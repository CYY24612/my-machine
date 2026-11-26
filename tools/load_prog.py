#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
load_prog.py —— 把机器码发给我的 CPU 执行

背景：FPGA 里跑的是 monitor.hex，它通过 UART 收机器码：
  - 收到的每个字节依次存到内存 0x80 起
  - 收到 0xFF 表示装载结束，然后 JMPX 跳到 0x80 执行
  - 装载的程序用 OUT 输出的字节，会从同一个串口发回来

所以：电脑发一串字节 -> 我的 CPU 执行 -> 结果发回来。

用法：
  python load_prog.py COM14 "05 2A 08 0F"       发原始机器码（LDI 42; OUT; HLT）
  python load_prog.py COM14 --text "Hi!"        自动生成打印文本的程序
  python load_prog.py COM14 --count 5           自动生成 5,4,3,2,1 倒计时

注意事项：
  - FPGA 里必须是 monitor.hex（prog.hex = monitor），且 top.v 里 RX_FROM_PC = 1
  - 一个程序执行完会停在 HLT，想装下一个必须先按一下 FPGA 上的复位键
  - 装载的机器码最多 127 字节（0x80..0xFE，0xFF 是终止符）
"""
import sys
import time

try:
    import serial
except ImportError:
    print("需要 pyserial:  python -m pip install pyserial")
    sys.exit(1)

MAX_BYTES = 127


def text_to_code(text):
    """把一段文本变成一个“逐字打印”的程序"""
    code = []
    for ch in text:
        b = ord(ch)
        if b > 255:
            raise ValueError("只能是单字节字符: %r" % ch)
        code += [0x05, b, 0x08]        # LDI b ; OUT
    code += [0x0F]                     # HLT
    return code


def countdown_to_code(n):
    """生成一个 n, n-1, ..., 1 的倒计时程序（数据放在 0x70）"""
    code = [
        0x05, n,        # 0x80 + 0: LDI n
        0x02, 0x70,     # LDA/STA 0x70
    ]
    # loop 在 0x80 + 4
    loop = 0x84
    hlt = 0x80 + 0x11
    code += [
        0x01, 0x70,     # 0x80+4: LDA 0x70
        0x08,           # 0x80+6: OUT
        0x01, 0x70,     # 0x80+7: LDA 0x70
        0x0A,           # 0x80+9: DEC
        0x02, 0x70,     # 0x80+A: STA 0x70
        0x07, hlt,      # 0x80+C: JZ hlt
        0x06, loop,     # 0x80+E: JMP loop
        0x0F,           # 0x80+10: filler
        0x0F,           # 0x80+11: HLT
    ]
    return code


def parse_hex_bytes(s):
    """解析 "05 2A 08" 或 "052A08" """
    s = s.replace(",", " ").replace("0x", "").replace("0X", "")
    parts = s.split()
    if len(parts) == 1 and len(parts[0]) > 2:
        raw = parts[0]
        parts = [raw[i:i + 2] for i in range(0, len(raw), 2)]
    return [int(p, 16) for p in parts]


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

    if rest[0] == "--text":
        code = text_to_code(" ".join(rest[1:]))
        desc = "打印文本 %r" % " ".join(rest[1:])
    elif rest[0] == "--count":
        n = int(rest[1])
        code = countdown_to_code(n)
        desc = "倒计时 %d..1" % n
    else:
        code = parse_hex_bytes(" ".join(rest))
        desc = "原始机器码"

    if len(code) > MAX_BYTES:
        print("程序太长: %d 字节（上限 %d）" % (len(code), MAX_BYTES))
        return

    payload = code + [0xFF]

    print("=" * 56)
    print("目标串口 : %s" % port)
    print("程序内容 : %s" % desc)
    print("机器码   : %s" % " ".join("%02X" % b for b in code))
    print("字节数   : %d  (+0xFF 终止符)" % len(code))
    print("=" * 56)

    try:
        s = serial.Serial(port, 115200, timeout=1.0)
    except Exception as e:
        print("打不开串口 %s: %s" % (port, e))
        print("可用串口: python -m serial.tools.list_ports")
        return

    time.sleep(0.1)
    s.reset_input_buffer()

    print("正在发送 …")
    for b in payload:
        s.write(bytes([b]))
        time.sleep(0.002)          # 每字节间隔 2ms，CPU 肯定跟得上
    s.flush()

    print("发送完成，等待 CPU 输出 …")
    time.sleep(0.8)

    n = s.in_waiting
    resp = s.read(n) if n else b""
    s.close()

    print()
    if not resp:
        print("没有收到任何输出。")
        print("  可能原因：")
        print("    1. FPGA 里的程序不是 monitor.hex（需要重新综合烧录）")
        print("    2. top.v 里 RX_FROM_PC 不是 1")
        print("    3. 串口选错了（FPGA 的 pin 17/18 对应的那个口）")
        print("    4. CPU 还停在上一个程序的 HLT 里 —— 按一下 FPGA 复位键再试")
        return

    print("收到 %d 字节：" % len(resp))
    print("  十六进制: %s" % " ".join("%02X" % b for b in resp))
    printable = "".join(chr(b) if 32 <= b < 127 else "." for b in resp)
    print("  文本视图: %r" % printable)
    print("  十进制  : %s" % " ".join(str(b) for b in resp))
    print()
    print("如果上面就是你的程序该输出的东西，那么 —— ")
    print("  我的 CPU 刚刚执行了我在电脑上现场输入的程序。")


if __name__ == "__main__":
    main()
