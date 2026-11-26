#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
radar.py —— 极坐标雷达图

数据格式（STM32 每 100ms 通过 USART1 发一行）:
    a=<角度 0..180> d=<距离 cm>      例如  a=45 d=32
    d=999 表示没等到回波；d=998 表示回波超时/超量程。两者都当无效点。

用法:
    python radar.py            # 自动找 COM11
    python radar.py COM5       # 指定串口
    python radar.py COM5 300   # 指定串口 + 显示量程 300cm
"""
import sys
import re
import time
import math

try:
    import serial
except ImportError:
    print("需要 pyserial:  python -m pip install pyserial")
    sys.exit(1)

import numpy as np
import matplotlib
import matplotlib.pyplot as plt

# ---------------- 参数 ----------------
PORT = sys.argv[1] if len(sys.argv) > 1 else "COM11"
BAUD = 115200
MAXD = int(sys.argv[2]) if len(sys.argv) > 2 else 200        # 显示量程 (cm)
MAXANG = 180
NBIN = MAXANG + 1                                            # 181 个角度格子

# ---------------- 数据 ----------------
dist = np.full(NBIN, np.nan)          # 每个角度上测到的距离
angle_now = 90
dist_now = np.nan
update_count = 0

# ---------------- 串口 ----------------
buf = b""
def read_serial(s):
    """读走所有可用字节，返回本次新增的 (角度, 距离) 列表"""
    global buf, angle_now, dist_now, update_count
    got = []
    n = s.in_waiting
    if n:
        buf += s.read(n)
    while b"\n" in buf:
        line, buf = buf.split(b"\n", 1)
        m = re.search(rb"a=(\d+)\s+d=(\d+)", line)
        if not m:
            continue
        a = int(m.group(1))
        d = int(m.group(2))
        if not (0 <= a <= MAXANG):
            continue
        angle_now = a
        dist_now = d
        update_count += 1
        if d >= 998:                 # 999 = 无回波, 998 = 超时/超量程
            dist[a] = np.nan
        else:
            dist[a] = d if d <= MAXD else np.nan
        got.append((a, d))
    return got

# ---------------- 画布 ----------------
fig = plt.figure(figsize=(7.5, 7.5))
fig.canvas.manager.set_window_title("我的机器会看 — 极坐标雷达")

ax = fig.add_subplot(111, projection="polar")
ax.set_thetamin(0)
ax.set_thetamax(MAXANG)
ax.set_theta_zero_location("E")       # 0° 指向右边
ax.set_theta_direction(1)             # 逆时针增大
ax.set_ylim(0, MAXD)
ax.set_yticks(np.arange(0, MAXD + 1, MAXD // 4 if MAXD >= 40 else 10))
ax.set_yticklabels([str(int(v)) for v in ax.get_yticks()], fontsize=7, color="0.5")
ax.grid(True, alpha=0.3)
ax.set_title("极坐标雷达  (舵机扫描 + HC-SR04 测距)", pad=18, fontsize=11)

scat = ax.scatter([], [], s=18, c=[], cmap="viridis", vmin=0, vmax=MAXD,
                  edgecolors="none", alpha=0.9, zorder=3)
sweep, = ax.plot([], [], color="#e03030", lw=1.2, alpha=0.75, zorder=2)
info = ax.text(0.5, -0.08, "", transform=ax.transAxes, ha="center",
               fontsize=10, family="monospace")

cbar = fig.colorbar(scat, ax=ax, pad=0.10, shrink=0.75)
cbar.set_label("距离 (cm)", fontsize=8)
cbar.ax.tick_params(labelsize=7)

# ---------------- 主循环 ----------------
def main():
    try:
        s = serial.Serial(PORT, BAUD, timeout=0)
    except Exception as e:
        print("打不开串口 %s: %s" % (PORT, e))
        print("可用串口:  python -m serial.tools.list_ports")
        return

    print("已连接 %s @ %d" % (PORT, BAUD))
    print("等待数据… (Ctrl+C 退出)")

    try:
        while plt.fignum_exists(fig.number):
            read_serial(s)

            ok = np.where(~np.isnan(dist))[0]
            if len(ok):
                th = np.deg2rad(ok.astype(float))
                rr = dist[ok]
                scat.set_offsets(np.column_stack([th, rr]))
                scat.set_array(rr)
            else:
                scat.set_offsets(np.empty((0, 2)))

            sw = math.radians(angle_now)
            sweep.set_data([sw, sw], [0, MAXD])

            dstr = "---" if np.isnan(dist_now) else "%d cm" % dist_now
            info.set_text("角度 %3d°   距离 %-7s   有效点 %3d   样本 %5d"
                          % (angle_now, dstr, len(ok), update_count))

            plt.pause(0.05)
    except KeyboardInterrupt:
        print("\n退出")
    finally:
        s.close()

if __name__ == "__main__":
    main()