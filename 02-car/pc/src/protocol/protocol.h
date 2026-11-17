// protocol.h —— 遥控链路协议 v0.1（纯 C++，零 Qt 依赖）
// -----------------------------------------------------------------------------
// 帧格式：
//   AA 55 | LEN | CMD | SEQ | PAYLOAD(N) | CRC8
//    2B     1B    1B    1B      N B         1B
//
//   LEN  = 1(CMD) + 1(SEQ) + N        —— 不含帧头，不含 CRC
//   CRC8 = CRC-8/MAXIM，覆盖 LEN..PAYLOAD 全部字节
//          参数 poly=0x31 init=0x00 refin=true refout=true xorout=0x00
//          自检：对字符串 "123456789" 计算结果必须是 0xA1
//
// 多字节字段一律小端（x86 和 STM32 都是小端，memcpy 即可）。
// -----------------------------------------------------------------------------
#ifndef CAR_PROTOCOL_H
#define CAR_PROTOCOL_H

#include <cstddef>
#include <cstdint>
#include <vector>

namespace car {

using Bytes = std::vector<std::uint8_t>;

// ---- 帧头 ----
constexpr std::uint8_t kHead0 = 0xAA;
constexpr std::uint8_t kHead1 = 0x55;

// ---- 下行：遥控器 -> STM32 ----
constexpr std::uint8_t CMD_SET_SERVO = 0x01;  // 负载 uint16 angle_x10 (0..1800)
constexpr std::uint8_t CMD_SET_MODE  = 0x02;  // 负载 uint8  mode (0 待机/1 遥控/2 扫描)
constexpr std::uint8_t CMD_ESTOP     = 0x0F;  // 空负载，急停
constexpr std::uint8_t CMD_PING      = 0x10;  // 空负载

// ---- 上行：STM32 -> 遥控器 ----
constexpr std::uint8_t CMD_STATUS    = 0x81;  // uint16 servo_x10, uint16 dist_mm, uint8 err
constexpr std::uint8_t CMD_EVENT     = 0x8F;  // uint8 code

// ---- 防御常数 ----
constexpr std::uint8_t  kLenMin      = 2;     // CMD + SEQ
constexpr std::uint8_t  kLenMax      = 64;    // 超过就当垃圾
constexpr std::size_t   kBufSoftCap  = 1024;  // 缓冲上限，防止无穷增长

struct Frame {
    std::uint8_t cmd = 0;
    std::uint8_t seq = 0;
    Bytes        payload;
};

// ---- 校验 ----
std::uint8_t crc8Maxim(const std::uint8_t *data, std::size_t len);

// ---- 编码 ----
Bytes encodeFrame(std::uint8_t cmd, std::uint8_t seq, const Bytes &payload);

Bytes encodeSetServo(std::uint8_t seq, std::uint16_t angleX10);
Bytes encodeSetMode (std::uint8_t seq, std::uint8_t  mode);
Bytes encodeEstop   (std::uint8_t seq);
Bytes encodePing    (std::uint8_t seq);

Bytes encodeStatus  (std::uint8_t seq, const struct CarStatus &st);

// ---- 流式解码 ----
// 串口是字节流：一次 feed 可能只有半帧、可能有两帧、也可能是垃圾。
// 只能靠"喂字节 + 取完整帧"这个模式，不能假设"一次读收到一帧"。
class FrameParser {
public:
    void feed(const std::uint8_t *data, std::size_t len);
    void feed(const Bytes &bytes);

    // 取出一帧（CRC 已校验通过）。返回 false = 当前缓冲里没有完整可用帧。
    bool nextFrame(Frame &out);

    void        reset()          { m_buf.clear(); }
    std::size_t pending()  const { return m_buf.size(); }

private:
    Bytes m_buf;
};

// ---- 状态负载 ----
struct CarStatus {
    std::uint16_t servoX10 = 0;
    std::uint16_t distMm   = 0;
    std::uint8_t  errCode  = 0;
};

bool parseStatus(const Frame &f, CarStatus &out);

// ---- 小工具 ----
void          appendU16(Bytes &b, std::uint16_t v);
std::uint16_t readU16  (const Bytes &b, std::size_t off);

} // namespace car

#endif // CAR_PROTOCOL_H