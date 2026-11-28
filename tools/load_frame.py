#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
load_frame.py —— 用「统一帧协议 v1」把机器码装进我的 CPU

和旧的 load_prog.py 的区别：
  旧：裸字节 + 0xFF 终止符
      - 程序里不能出现 0xFF
      - 串口打开瞬间的杂散字节会让 monitor 错位（11-26 踩过这个坑）
  新：AA 55 TYPE LEN PAYLOAD CHK
      - 长度由 LEN 决定，程序里可以有 0xFF
      - 帧头 AA 55 + 累加和校验，杂散字节会被自动丢弃并重新同步

流程（对应协议文档 §3）：
  LOAD 帧（TYPE=0x01）：PAYLOAD = ADDR + DATA，把 DATA 写到 0x80 起，不执行
  RUN  帧（TYPE=0x05）：PAYLOAD = ADDR，CPU 执行 JMPX 跳到 ADDR
  PING 帧（TYPE=0x06）：CPU 回一个 0xA5，用于链路自测

用法：
  python load_frame.py COM14 --ping
  python load_frame.py COM14 --text "Hi!"
  python load_frame.py COM14 --count 5
  python load_frame.py COM14 "05 2A 08 0F"
"""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

try:
    import serial
except ImportError:
    print("需要 pyserial: python -m pip install pyserial")
    sys.exit(1)

from proto import (                      # noqa: E402
    load_frame, run_frame, ping_frame,
    LOAD_ADDR_MIN, MAX_LOAD_DATA,
)

LOAD_ADDR = 0x80                          # 装载区起点


def text_to_code(text):
    """一段文本 -> 逐字打印的程序（LDI ch; OUT; ...; HLT）"""
    code = []
    for ch in text:
        b = ord(ch)
        if b > 255:
            raise ValueError("只能是单字节字符: %r" % ch)
        code += [0x05, b, 0x08]
    code += [0x0F]
    return code


def countdown_to_code(n):
    """n, n-1, ..., 1 倒计时（数据放 0x70）"""
    loop = 0x84
    hlt = 0x80 + 0x11
    return [
        0x05, n, 0x02, 0x70,
        0x01, 0x70, 0x08,
        0x01, 0x70, 0x0A, 0x02, 0x70,
        0x07, hlt,
        0x06, loop,
        0x0F, 0x0F,
    ]


def parse_hex_bytes(s):
    s = s.replace(",", " ").replace("0x", "").replace("0X", "")
    parts = s.split()
    if len(parts) == 1 and len(parts[0]) > 2:
        raw = parts[0]
        parts = [raw[i:i + 2] for i in range(0, len(raw), 2)]
    return [int(p, 16) for p in parts]


def hexs(b):
    return " ".join("%02X" % x for x in b)


def collect(s, wait=1.2, quiet=0.4):
    """读串口直到安静下来"""
    resp = b""
    deadline = time.time() + wait
    while time.time() < deadline:
        n = s.in_waiting
        if n:
            resp += s.read(n)
            deadline = time.time() + quiet
        else:
            time.sleep(0.02)
    return resp


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return

    port = args[0]
    rest = args[1:]
    if not rest:
        print(__doc__)
        return

    # ---- 解析要做什么 ----
    mode = None
    code = None
    desc = ""

    if rest[0] == "--ping":
        mode = "ping"
        desc = "PING 自测"
    elif rest[0] == "--text":
        code = text_to_code(" ".join(rest[1:]))
        mode = "loadrun"
        desc = "打印文本 %r" % " ".join(rest[1:])
    elif rest[0] == "--count":
        code = countdown_to_code(int(rest[1]))
        mode = "loadrun"
        desc = "倒计时 %d..1" % int(rest[1])
    else:
        code = parse_hex_bytes(" ".join(rest))
        mode = "loadrun"
        desc = "原始机器码"

    if code is not None and len(code) > MAX_LOAD_DATA:
        print("程序太长: %d 字节（单帧上限 %d）" % (len(code), MAX_LOAD_DATA))
        return

    print("=" * 62)
    print("目标串口 : %s" % port)
    print("动作     : %s" % desc)
    if code is not None:
        print("机器码   : %s" % hexs(code))
        print("字节数   : %d" % len(code))
    print("=" * 62)

    # ---- 开串口 ----
    try:
        s = serial.Serial(port, 115200, timeout=0.5)
    except Exception as e:
        print("打不开串口 %s: %s" % (port, e))
        print("可用串口: python -m serial.tools.list_ports")
        return

    try:
        s.dtr = False
        s.rts = False
    except Exception:
        pass
    time.sleep(0.2)
    s.reset_input_buffer()

    print()
    print(">>> 请按一下 FPGA 的复位键，然后在这里按回车 <<<")
    try:
        input()
    except EOFError:
        pass
    time.sleep(0.2)
    s.reset_input_buffer()

    # ---- PING ----
    if mode == "ping":
        f = ping_frame()
        print("发送 PING : %s" % hexs(f))
        s.write(f)
        s.flush()
        resp = collect(s, wait=1.0)
        print("收到      : %s" % (hexs(resp) if resp else "(无)"))
        if resp and resp[0] == 0xA5:
            print()
            print("[PASS] CPU 回了 0xA5 —— 帧协议链路通了")
        else:
            print()
            print("[FAIL] 没收到 0xA5")
            print("  检查: prog.hex 是不是 monitor2.hex？重新综合烧录了吗？")
        s.close()
        return

    # ---- LOAD + RUN ----
    lf = load_frame(LOAD_ADDR, bytes(code))
    rf = run_frame(LOAD_ADDR)
    print("发送 LOAD : %s" % hexs(lf))
    s.write(lf)
    s.flush()
    time.sleep(0.05)
    resp_load = collect(s, wait=0.4, quiet=0.2)
    if resp_load:
        print("LOAD 回显 : %s  (LOAD 本来不该有回显，有说明有问题)" % hexs(resp_load))

    print("发送 RUN  : %s" % hexs(rf))
    s.write(rf)
    s.flush()

    resp = collect(s, wait=1.5)
    s.close()

    print()
    if not resp:
        print("没有收到输出。")
        print("  1. prog.hex 是不是 monitor2.hex，有没有 Rerun All 重新综合")
        print("  2. 复位键按了吗（按了再回车）")
        print("  3. 程序里有 OUT 才会有回传")
        return

    print("收到 %d 字节：" % len(resp))
    print("  十六进制: %s" % hexs(resp))
    printable = "".join(chr(b) if 32 <= b < 127 else "." for b in resp)
    print("  文本视图: %r" % printable)
    print("  十进制  : %s" % " ".join(str(b) for b in resp))
    print()
    print("如果这就是程序该输出的东西 —— ")
    print("  统一帧协议在真实硬件上跑通了。")


if __name__ == "__main__":
    main()