#!/usr/bin/env python3
"""gen_monitor2_frames.py —— 为 monitor2 生成串口测试字节流

输出（给 tb/monitor2_tb.v 用，$readmemh 读）：
    programs/monitor2_frames.hex   第一字节 = 字节数，之后是要发给 CPU 的串口字节
    programs/monitor2_expect.hex   第一字节 = 字节数，之后是期望 CPU 从 OUT 回来的字节

场景（用统一帧协议 v1 封包，见 docs/协议-统一帧-v1.md）：
    A. LOAD 一段程序到 0x80 + RUN  —— 程序是 LDI 42; OUT; HLT
    B. PING                        —— CPU 应回 0xA5
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import proto


def load_and_run(addr, code):
    """LOAD 一帧 + RUN 一帧，拼成字节流"""
    return proto.load_frame(addr, code) + proto.run_frame(addr)


SCENARIOS = {
    # ---- A：装载 "LDI 42; OUT; HLT" 并运行，期望输出 0x2A ----
    "load_run": (
        load_and_run(0x80, bytes([0x05, 0x2A, 0x08, 0x0F])),
        bytes([0x2A]),
    ),
    # ---- B：PING，期望回 0xA5 ----
    "ping": (
        proto.ping_frame(),
        bytes([0xA5]),
    ),
    # ---- C：装载含 0xFF 的程序 "LDI 0xFF; OUT; HLT"，期望输出 0xFF ----
    "load_ff": (
        load_and_run(0x80, bytes([0x05, 0xFF, 0x08, 0x0F])),
        bytes([0xFF]),
    ),
}


def write_hexlist(path, data: bytes):
    """第一行 = 字节数，之后每行一个字节"""
    lines = [f"{len(data):02x}"] + [f"{b:02x}" for b in data]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in SCENARIOS:
        print("用法: python gen_monitor2_frames.py <场景>")
        for k, (fr, ex) in SCENARIOS.items():
            print(f"  {k:10s} 发送 {len(fr):3d} 字节，期望 {len(ex)} 字节")
        return 1

    name = sys.argv[1]
    frames, expect = SCENARIOS[name]

    out = Path(__file__).resolve().parent.parent / "01-cpu" / "programs"
    write_hexlist(out / "monitor2_frames.hex", frames)
    write_hexlist(out / "monitor2_expect.hex", expect)

    print(f"场景: {name}")
    print(f"  发送 {len(frames)} 字节:")
    print("    " + frames.hex(" ").upper())
    print(f"  期望 {len(expect)} 字节: " + expect.hex(" ").upper())
    print(f"  已写: {out / 'monitor2_frames.hex'}")
    print(f"        {out / 'monitor2_expect.hex'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())