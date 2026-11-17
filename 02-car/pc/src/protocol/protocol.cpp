// protocol.cpp —— 遥控链路协议 v0.1 实现
#include "protocol/protocol.h"

namespace car {

// ============================================================ CRC-8/MAXIM
std::uint8_t crc8Maxim(const std::uint8_t *data, std::size_t len)
{
    // 反射实现：多项式 0x31 反射后是 0x8C，初值 0，无终异或
    std::uint8_t crc = 0x00;
    for (std::size_t i = 0; i < len; ++i) {
        crc ^= data[i];
        for (int b = 0; b < 8; ++b) {
            if (crc & 0x01)
                crc = static_cast<std::uint8_t>((crc >> 1) ^ 0x8C);
            else
                crc = static_cast<std::uint8_t>(crc >> 1);
        }
    }
    return crc;
}

// ============================================================ 小工具
void appendU16(Bytes &b, std::uint16_t v)
{
    b.push_back(static_cast<std::uint8_t>(v & 0xFF));        // 低字节在前
    b.push_back(static_cast<std::uint8_t>((v >> 8) & 0xFF));
}

std::uint16_t readU16(const Bytes &b, std::size_t off)
{
    if (off + 1 >= b.size()) return 0;
    return static_cast<std::uint16_t>(b[off] | (static_cast<std::uint16_t>(b[off + 1]) << 8));
}

// ============================================================ 编码
Bytes encodeFrame(std::uint8_t cmd, std::uint8_t seq, const Bytes &payload)
{
    Bytes out;
    out.reserve(3 + 2 + payload.size() + 1);

    out.push_back(kHead0);
    out.push_back(kHead1);

    const std::uint8_t len = static_cast<std::uint8_t>(2 + payload.size());
    out.push_back(len);
    out.push_back(cmd);
    out.push_back(seq);
    out.insert(out.end(), payload.begin(), payload.end());

    // CRC 覆盖 LEN..PAYLOAD，即 out[2] 起、共 1+len 字节
    out.push_back(crc8Maxim(out.data() + 2, static_cast<std::size_t>(1 + len)));
    return out;
}

Bytes encodeSetServo(std::uint8_t seq, std::uint16_t angleX10)
{
    Bytes p;
    appendU16(p, angleX10);
    return encodeFrame(CMD_SET_SERVO, seq, p);
}

Bytes encodeSetMode(std::uint8_t seq, std::uint8_t mode)
{
    return encodeFrame(CMD_SET_MODE, seq, Bytes{ mode });
}

Bytes encodeEstop(std::uint8_t seq)
{
    return encodeFrame(CMD_ESTOP, seq, Bytes{});
}

Bytes encodePing(std::uint8_t seq)
{
    return encodeFrame(CMD_PING, seq, Bytes{});
}

Bytes encodeStatus(std::uint8_t seq, const CarStatus &st)
{
    Bytes p;
    appendU16(p, st.servoX10);
    appendU16(p, st.distMm);
    p.push_back(st.errCode);
    return encodeFrame(CMD_STATUS, seq, p);
}

bool parseStatus(const Frame &f, CarStatus &out)
{
    if (f.cmd != CMD_STATUS) return false;
    if (f.payload.size() != 5) return false;
    out.servoX10 = readU16(f.payload, 0);
    out.distMm   = readU16(f.payload, 2);
    out.errCode  = f.payload[4];
    return true;
}

// ============================================================ 流式解析
void FrameParser::feed(const std::uint8_t *data, std::size_t len)
{
    if (data == nullptr || len == 0) return;
    m_buf.insert(m_buf.end(), data, data + len);

    // 兜底：万一一直解不出帧，别让缓冲无限长
    if (m_buf.size() > kBufSoftCap)
        m_buf.erase(m_buf.begin(), m_buf.end() - static_cast<std::ptrdiff_t>(kBufSoftCap / 2));
}

void FrameParser::feed(const Bytes &bytes)
{
    feed(bytes.data(), bytes.size());
}

bool FrameParser::nextFrame(Frame &out)
{
    for (;;) {
        // ---------- 1. 找帧头 ----------
        std::size_t head = static_cast<std::size_t>(-1);
        for (std::size_t i = 0; i + 1 < m_buf.size(); ++i) {
            if (m_buf[i] == kHead0 && m_buf[i + 1] == kHead1) { head = i; break; }
        }

        if (head == static_cast<std::size_t>(-1)) {
            // 没有帧头：只留最后 1 个字节（它可能是下一个帧头的前半）
            if (m_buf.size() > 1)
                m_buf.erase(m_buf.begin(), m_buf.end() - 1);
            return false;
        }
        if (head > 0)
            m_buf.erase(m_buf.begin(), m_buf.begin() + static_cast<std::ptrdiff_t>(head));

        // ---------- 2. 够读 LEN 吗 ----------
        if (m_buf.size() < 3) return false;

        const std::uint8_t len = m_buf[2];
        if (len < kLenMin || len > kLenMax) {
            // LEN 非法：这个"帧头"是假的，跳 1 字节重新找
            m_buf.erase(m_buf.begin());
            continue;
        }

        // ---------- 3. 够整帧吗 ----------
        const std::size_t total = 3 + len + 1;   // 头2 + LEN1 + 内容len + CRC1
        if (m_buf.size() < total) return false;

        // ---------- 4. 校验 ----------
        const std::uint8_t crcCalc = crc8Maxim(m_buf.data() + 2, static_cast<std::size_t>(1 + len));
        const std::uint8_t crcRecv = m_buf[total - 1];
        if (crcCalc != crcRecv) {
            // CRC 错：帧头可能只是数据里凑巧出现的，跳 1 字节重新同步
            m_buf.erase(m_buf.begin());
            continue;
        }

        // ---------- 5. 取出并消费 ----------
        out.cmd = m_buf[3];
        out.seq = m_buf[4];
        out.payload.assign(m_buf.begin() + 5, m_buf.begin() + static_cast<std::ptrdiff_t>(total - 1));
        m_buf.erase(m_buf.begin(), m_buf.begin() + static_cast<std::ptrdiff_t>(total));
        return true;
    }
}

} // namespace car