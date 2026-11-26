#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
rx_test.py —— 走马灯测试：确认 PC -> CPU 的接收通路

FPGA 里必须烧 rx_display.hex（IN; JMP 0），它会把收到的字节直接显示在 LED 上。

本脚本依次发送 0x01 0x02 0x04 0x08 0x10 0x20 0x00，
每个字节间隔 1.5 秒 —— 你应该看到 6 个 LED 依次只亮一颗：
  0x01 -> 只有 led[0] 亮
  0x02 -> 只有 led[1] 亮
  0x04 -> 只有 led[2] 亮
  0x08 -> 只有 led[3] 亮
  0x10 -> 只有 led[4] 亮
  0x20 -> 只有 led[5] 亮
  0x00 -> 全亮

用法: python rx_test.py COM14
"""
import sys
import time

try:
    import serial
except ImportError:
    print("需要 pyserial: python -m pip install pyserial")
    sys.exit(1)

PORT = sys.argv[1] if len(sys.argv) > 1 else "COM14"
BAUD = 115200

pattern = [0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x00]

try:
    s = serial.Serial(PORT, BAUD, timeout=0.5)
except Exception as e:
    print("打不开串口 %s: %s" % (PORT, e))
    sys.exit(1)

print("已连接 %s @ %d" % (PORT, BAUD))
print()
print("将要发送（每 1.5 秒一个），请看 FPGA 的 6 个 LED：")
for b in pattern:
    if b == 0:
        print("  0x00  ->  全部 6 颗亮（A=0）")
    else:
        idx = 0
        for i in range(6):
            if b & (1 << i):
                idx = i
        print("  0x%02X  ->  只有 led[%d] 亮" % (b, idx))
print()

for b in pattern:
    print("  send 0x%02X ..." % b, end="", flush=True)
    s.write(bytes([b]))
    s.flush()
    time.sleep(1.5)
    print(" ok")

print()
print("发送完毕。请告诉我 LED 的实际表现。")
s.close()