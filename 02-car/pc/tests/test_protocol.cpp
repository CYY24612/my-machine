// test_protocol.cpp —— 协议层单测（零依赖，只用标准库）
// 编译：g++ -std=c++17 -I src src\protocol\protocol.cpp tests\test_protocol.cpp -o test_protocol.exe
#include "protocol/protocol.h"

#include <cstdio>
#include <cstring>

using namespace car;

static int g_pass = 0;
static int g_fail = 0;

#define CHECK(cond)                                                        \
    do {                                                                   \
        if (cond) { ++g_pass; }                                            \
        else {                                                             \
            ++g_fail;                                                      \
            std::printf("  FAIL  line %d : %s\n", __LINE__, #cond);        \
        }                                                                  \
    } while (0)

#define CHECK_EQ(a, b)                                                     \
    do {                                                                   \
        const long long _a = static_cast<long long>(a);                    \
        const long long _b = static_cast<long long>(b);                    \
        if (_a == _b) { ++g_pass; }                                        \
        else {                                                             \
            ++g_fail;                                                      \
            std::printf("  FAIL  line %d : %s == %s  (%lld vs %lld)\n",    \
                        __LINE__, #a, #b, _a, _b);                         \
        }                                                                  \
    } while (0)

// ---------------------------------------------------------------- T1 CRC 自检
static void test_crc_check_value()
{
    std::printf("[T1] CRC-8/MAXIM 标准自检值\n");
    const char *s = "123456789";
    const std::uint8_t crc = crc8Maxim(reinterpret_cast<const std::uint8_t *>(s), 9);
    std::printf("     crc(\"123456789\") = 0x%02X （标准值 0xA1）\n", crc);
    CHECK_EQ(crc, 0xA1);
}

// ---------------------------------------------------------------- T2 编解码往返
static void test_roundtrip()
{
    std::printf("[T2] 编码 -> 解析 往返\n");

    struct Case { const char *name; Bytes raw; };
    std::vector<Case> cases = {
        { "SET_SERVO(90.0deg)", encodeSetServo(1, 900) },
        { "SET_MODE(1)",        encodeSetMode(2, 1)    },
        { "ESTOP",              encodeEstop(3)         },
        { "PING",               encodePing(4)          },
    };

    for (const auto &c : cases) {
        FrameParser p;
        p.feed(c.raw);
        Frame f;
        const bool ok = p.nextFrame(f);
        if (!ok) { ++g_fail; std::printf("  FAIL  %s 解不出帧\n", c.name); continue; }
        ++g_pass;

        // 帧结构：头2 + LEN + (LEN 字节) + CRC = 4 + LEN
        CHECK_EQ(c.raw.size(), 4u + static_cast<std::size_t>(c.raw[2]));
        CHECK_EQ(f.cmd, c.raw[3]);
        CHECK_EQ(f.seq, c.raw[4]);
        CHECK_EQ(f.payload.size(), static_cast<std::size_t>(c.raw[2]) - 2);
        CHECK_EQ(p.pending(), 0u);   // 帧被完整消费
    }
}

// ---------------------------------------------------------------- T3 一字节一字节喂
static void test_feed_byte_by_byte()
{
    std::printf("[T3] 逐字节喂（模拟串口碎片）\n");
    const Bytes raw = encodeSetServo(7, 1800);

    FrameParser p;
    int frames = 0;
    for (std::size_t i = 0; i < raw.size(); ++i) {
        p.feed(raw.data() + i, 1);
        Frame f;
        while (p.nextFrame(f)) ++frames;
    }
    CHECK_EQ(frames, 1);
    CHECK_EQ(p.pending(), 0u);
}

// ---------------------------------------------------------------- T4 帧前垃圾
static void test_garbage_prefix()
{
    std::printf("[T4] 帧头前有垃圾字节\n");
    Bytes raw = { 0x00, 0xFF, 0x12, 0x34 };
    const Bytes f = encodePing(9);
    raw.insert(raw.end(), f.begin(), f.end());

    FrameParser p;
    p.feed(raw);
    Frame out;
    CHECK(p.nextFrame(out));
    CHECK_EQ(out.cmd, CMD_PING);
    CHECK_EQ(p.pending(), 0u);
}

// ---------------------------------------------------------------- T5 一次收到两帧
static void test_two_frames_one_feed()
{
    std::printf("[T5] 一次 feed 里有两帧\n");
    Bytes raw = encodePing(1);
    const Bytes f2 = encodeEstop(2);
    raw.insert(raw.end(), f2.begin(), f2.end());

    FrameParser p;
    p.feed(raw);
    Frame a, b;
    CHECK(p.nextFrame(a));
    CHECK(p.nextFrame(b));
    CHECK_EQ(a.cmd, CMD_PING);
    CHECK_EQ(b.cmd, CMD_ESTOP);
    CHECK_EQ(p.pending(), 0u);
    Frame c;
    CHECK(!p.nextFrame(c));      // 没有第三帧
}

// ---------------------------------------------------------------- T6 半帧等下一半
static void test_split_frame()
{
    std::printf("[T6] 先来半帧，再来剩下的\n");
    const Bytes raw = encodeSetMode(5, 2);
    const std::size_t cut = raw.size() / 2;

    FrameParser p;
    p.feed(raw.data(), cut);
    Frame f;
    CHECK(!p.nextFrame(f));      // 还不完整
    CHECK_EQ(p.pending(), cut);  // 数据没被丢

    p.feed(raw.data() + cut, raw.size() - cut);
    CHECK(p.nextFrame(f));
    CHECK_EQ(f.cmd, CMD_SET_MODE);
    CHECK_EQ(static_cast<int>(f.payload.at(0)), 2);
}

// ---------------------------------------------------------------- T7 CRC 坏掉后重同步
static void test_crc_error_resync()
{
    std::printf("[T7] 第一帧 CRC 坏，要能跳过并接住第二帧\n");
    Bytes bad = encodePing(1);
    bad[bad.size() - 1] ^= 0xFF;          // 把 CRC 打坏
    const Bytes good = encodeEstop(2);

    Bytes raw = bad;
    raw.insert(raw.end(), good.begin(), good.end());

    FrameParser p;
    p.feed(raw);
    Frame f;
    bool got = p.nextFrame(f);
    CHECK(got);
    CHECK_EQ(f.cmd, CMD_ESTOP);           // 拿到的是第二帧，不是坏帧
}

// ---------------------------------------------------------------- T8 LEN 非法
static void test_bad_len()
{
    std::printf("[T8] LEN 越界要被拒绝\n");
    Bytes raw;
    raw.push_back(kHead0); raw.push_back(kHead1);
    raw.push_back(200);                   // > kLenMax
    for (int i = 0; i < 8; ++i) raw.push_back(0x00);

    FrameParser p;
    p.feed(raw);
    Frame f;
    CHECK(!p.nextFrame(f));
}

// ---------------------------------------------------------------- T9 边界值
static void test_servo_boundary()
{
    std::printf("[T9] 舵机角度的边界值\n");
    const std::uint16_t vals[] = { 0, 1, 900, 1799, 1800, 65535 };
    for (std::uint16_t v : vals) {
        FrameParser p;
        p.feed(encodeSetServo(0, v));
        Frame f;
        CHECK(p.nextFrame(f));
        CHECK_EQ(f.cmd, CMD_SET_SERVO);
        CHECK_EQ(readU16(f.payload, 0), v);
    }
}

// ---------------------------------------------------------------- T10 STATUS
static void test_status()
{
    std::printf("[T10] STATUS 帧编码/解析\n");
    CarStatus st;
    st.servoX10 = 900;
    st.distMm   = 1234;
    st.errCode  = 0;

    FrameParser p;
    p.feed(encodeStatus(11, st));
    Frame f;
    CHECK(p.nextFrame(f));

    CarStatus out;
    CHECK(parseStatus(f, out));
    CHECK_EQ(out.servoX10, 900);
    CHECK_EQ(out.distMm, 1234);
    CHECK_EQ(out.errCode, 0);

    // 不是 STATUS 的帧必须拒绝
    Frame notStatus;
    notStatus.cmd = CMD_PING;
    notStatus.payload = { 0, 0, 0, 0, 0 };
    CHECK(!parseStatus(notStatus, out));
}

// ---------------------------------------------------------------- main
int main()
{
    std::printf("==== 协议层单测 v0.1 ====\n\n");
    test_crc_check_value();
    test_roundtrip();
    test_feed_byte_by_byte();
    test_garbage_prefix();
    test_two_frames_one_feed();
    test_split_frame();
    test_crc_error_resync();
    test_bad_len();
    test_servo_boundary();
    test_status();

    std::printf("\n==== 结果：通过 %d，失败 %d ====\n", g_pass, g_fail);
    return g_fail == 0 ? 0 : 1;
}