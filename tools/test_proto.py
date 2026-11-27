#!/usr/bin/env python3
"""test_proto.py —— 统一帧协议的测试向量（不依赖 pytest，直接 python 跑）

覆盖：
    正常帧、含 0xFF 的数据、逐字节喂、垃圾前缀、AA AA 55、
    校验失败、LEN 超限、一包多帧、跨包拆分、超时复位、边界拒绝
"""

import sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

import proto
from proto import (
    Parser, Frame, encode, checksum, load_frame, run_frame, angle_frame,
    dist_frame, estop_frame, ping_frame, status_frame,
    T_LOAD, T_RUN, T_PING, T_ESTOP, T_STATUS, T_SET_ANGLE, T_DIST,
    MAX_LEN, MAX_LOAD_DATA,
)


# ---------------------------------------------------------------- 正常帧
def test_doc_sample_frames():
    """文档 §5 的 7 条示例帧，字节必须完全一致"""
    cases = [
        (ping_frame(),                    "AA 55 06 00 06"),
        (estop_frame(),                   "AA 55 04 00 04"),
        (angle_frame(90),                 "AA 55 02 01 5A 5D"),
        (dist_frame(40),                  "AA 55 03 01 28 2C"),
        (run_frame(0x80),                 "AA 55 05 01 80 86"),
        (load_frame(0x80, bytes([0x05, 0x2A, 0x08, 0x0F, 0xFF])),
                                          "AA 55 01 06 80 05 2A 08 0F FF CC"),
        (status_frame(90, 100, 0),        "AA 55 10 04 5A 64 00 00 D2"),
    ]
    for got, want in cases:
        assert got.hex(" ").upper() == want, f"got {got.hex(' ').upper()} want {want}"
    assert len(cases) == 7


def test_roundtrip_all_types():
    p = Parser()
    for fr in (ping_frame(), estop_frame(), angle_frame(180), dist_frame(250),
               run_frame(0x80), load_frame(0x90, b"\x00\xFF\x55\xAA"), status_frame(1, 2, 3)):
        out = p.feed(fr)
        assert len(out) == 1, f"应解出 1 帧，实际 {len(out)}"
        assert out[0].typ == fr[2]


def test_load_payload_may_contain_ff():
    """新协议最大的收益：数据里可以有 0xFF（旧协议用 0xFF 作终止符，发不出去）"""
    data = bytes([0xFF, 0xFF, 0x00, 0xFF])
    fr = load_frame(0x80, data)
    out = Parser().feed(fr)
    assert len(out) == 1
    assert out[0].payload == bytes([0x80]) + data


def test_empty_payload_types():
    for fr, typ in ((ping_frame(), T_PING), (estop_frame(), T_ESTOP)):
        assert fr[3] == 0, "LEN 应为 0"
        out = Parser().feed(fr)
        assert out[0].payload == b""


# ---------------------------------------------------------------- 解析健壮性
def test_byte_by_byte():
    """逐字节喂入（模拟串口每 87µs 来一个字节）"""
    fr = angle_frame(45)
    p = Parser()
    got = []
    for b in fr:
        got += p.feed(bytes([b]))
    assert len(got) == 1 and got[0].payload == bytes([45])


def test_garbage_before_header():
    p = Parser()
    out = p.feed(b"\x01\x02\x03\xAA\xFF" + angle_frame(10))
    assert len(out) == 1, "垃圾前缀后应正常解出"
    assert out[0].payload == bytes([10])


def test_aa_aa_55():
    """AA AA 55 —— 第二个 AA 是新候选，不能丢弃"""
    p = Parser()
    out = p.feed(b"\xAA\xAA\x55" + bytes([T_PING, 0, checksum(T_PING, b"")]))
    assert len(out) == 1


def test_aa_then_wrong_byte_resync():
    p = Parser()
    # AA 然后不是 55 → 回 HUNT；后面跟一个完整 PING
    out = p.feed(b"\xAA\x12" + ping_frame())
    assert len(out) == 1


def test_bad_checksum_dropped():
    fr = bytearray(angle_frame(90))
    fr[-1] ^= 0xFF                      # 弄坏校验
    p = Parser()
    out = p.feed(bytes(fr))
    assert out == [], "校验错的帧必须丢弃"
    assert p.stats["bad_chk"] == 1


def test_len_too_big_rejected():
    p = Parser()
    out = p.feed(bytes([0xAA, 0x55, T_PING, MAX_LEN + 1]))
    assert out == []
    assert p.stats["bad_len"] == 1


def test_two_frames_one_feed():
    p = Parser()
    out = p.feed(ping_frame() + angle_frame(7) + dist_frame(8))
    assert len(out) == 3
    assert [f.typ for f in out] == [T_PING, T_SET_ANGLE, T_DIST]


def test_frame_split_across_feeds():
    fr = load_frame(0x80, b"\x01\x02\x03\x04")
    cut = 5
    p = Parser()
    out = p.feed(fr[:cut]) + p.feed(fr[cut:])
    assert len(out) == 1 and out[0].payload == b"\x80\x01\x02\x03\x04"


def test_timeout_resets_partial_frame():
    fr = angle_frame(90)
    p = Parser()
    p.feed(fr[:3])                      # 收到 AA 55 02 就中断
    assert p.busy
    p.feed_gap()                        # 模拟间隔 > 50ms
    assert not p.busy
    assert p.stats["timeouts"] == 1
    # 之后还能正常收
    out = p.feed(fr)
    assert len(out) == 1


def test_parser_busy_flags():
    p = Parser()
    assert not p.busy
    p.feed(b"\xAA")
    assert p.busy
    p.feed(b"\x55\x06\x00\x06")
    assert not p.busy


# ---------------------------------------------------------------- 编码校验
def test_encode_rejects_too_long():
    try:
        encode(T_PING, b"\x00" * (MAX_LEN + 1))
    except ValueError:
        pass
    else:
        raise AssertionError("超长 payload 应抛 ValueError")


def test_load_bounds():
    # 数据太长
    try:
        load_frame(0x80, b"\x00" * (MAX_LOAD_DATA + 1))
    except ValueError:
        pass
    else:
        raise AssertionError("装载数据 > 126 应抛错")

    # 地址 + 长度越界（0xFE + 2 会写到 0xFF，装载区上界是 0xFE）
    try:
        load_frame(0xFE, b"\x00\x00")
    except ValueError:
        pass
    else:
        raise AssertionError("装载跨越装载区上界应抛错")

    # 地址低于装载区（会覆盖 monitor 代码）
    try:
        load_frame(0x70, b"\x00")
    except ValueError:
        pass
    else:
        raise AssertionError("装载到 0x70 应抛错（会覆盖 monitor）")

    # 边界刚好：0x80 + 126 字节，最后一个字节落在 0xFD
    assert len(load_frame(0x80, b"\x00" * MAX_LOAD_DATA)) == 1 + MAX_LOAD_DATA + 5
    # 上界刚好：0xFE 单字节
    assert len(load_frame(0xFE, b"\x00")) == 7


def test_clamps():
    assert angle_frame(200)[4] == 180
    assert angle_frame(-5)[4] == 0
    assert dist_frame(300)[4] == 255


def test_status_little_endian():
    fr = status_frame(45, 0x1234, 1)
    # 帧结构：[0]=AA [1]=55 [2]=TYPE [3]=LEN，payload 从 [4] 开始
    assert fr[4] == 45           # angle
    assert fr[5] == 0x34         # dist low
    assert fr[6] == 0x12         # dist high
    assert fr[7] == 1            # err


def test_checksum_covers_type_and_len():
    """校验必须覆盖 TYPE 和 LEN —— 改任何一个都应导致解帧失败"""
    fr = bytearray(ping_frame())
    fr[2] ^= 0x01                # 改 TYPE
    assert Parser().feed(bytes(fr)) == []

    fr2 = bytearray(angle_frame(90))
    fr2[3] = 0x00                # 把 LEN 改成 0（会导致数据错位）
    p = Parser()
    out = p.feed(bytes(fr2))
    assert out == []


# ---------------------------------------------------------------- 运行器
def main():
    tests = [(k, v) for k, v in sorted(globals().items())
             if k.startswith("test_") and callable(v)]
    passed = failed = 0
    print("=" * 62)
    for name, fn in tests:
        try:
            fn()
            print(f"  PASS  {name}")
            passed += 1
        except AssertionError as e:
            print(f"  FAIL  {name}: {e}")
            failed += 1
        except Exception as e:
            print(f"  ERROR {name}: {type(e).__name__}: {e}")
            failed += 1
    print("=" * 62)
    print(f"  通过 {passed}，失败 {failed}")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())