#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
radar.py —— 极坐标雷达图

数据格式（STM32 每 100ms 通过 USART1 发一行）:
    a=<角度 0..180> d=<距离 cm>      例如  a=45 d=32
    d=999 表示没等到回波；d=998 表示回波一直高 / 超时。两者都当无效点。

用法:
    python radar.py             # 默认 COM11
    python radar.py COM5        # 指定串口
    python radar.py COM5 300    # 指定串口 + 显示量程 300cm
"""
import sys
import re
import math

try:
    import serial
except ImportError:
    print("需要 pyserial:  python -m pip install pyserial")
    sys.exit(1)

import numpy as np
import matplotlib
import matplotlib.pyplot as plt

# ---- 中文字体：不设的话中文全渲染成方块 ----
matplotlib.rcParams["font.sans-serif"] = [
    "Microsoft YaHei", "SimHei", "SimSun",
    "Noto Sans CJK SC", "Source Han Sans SC", "DejaVu Sans",
]
matplotlib.rcParams["axes.unicode_minus"] = False

# ---------------- 参数 ----------------
PORT = sys.argv[1] if len(sys.argv) > 1 else "COM11"
BAUD = 115200
MAXD = int(sys.argv[2]) if len(sys.argv) > 2 else 200        # 显示量程 cm
MAXANG = 180
NBIN = MAXANG + 1                                            # 181 个角度格子

# ---------------- 状态 ----------------
dist = np.full(NBIN, np.nan)     # 每个角度上测到的距离
angle_now = 90                   # 最近收到的角度
dist_now = np.nan                # 最近收到的距离
n_total = 0                      # 总样本数
n_bad = 0                        # 无效样本数 (>=998)
a_min = 999                      # 收到过的角度最小/最大 —— 用来判断扫描是否在动
a_max = -1
buf = b""


def read_serial(s):
    """读走所有可用字节，更新全局状态"""
    global buf, angle_now, dist_now, n_total, n_bad, a_min, a_max
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
        n_total += 1

        if a < a_min:
            a_min = a
        if a > a_max:
            a_max = a

        if d >= 998:
            # 999 = Trig 没被接受（Echo 一直低）
            # 998 = 没收到回声（HC-SR04 会让 Echo 保持高约 38ms，超过我们 30ms 的超时）
            # 失败时【保留该角度上次的有效值】，不清空 —— 雷达图才能累积
            n_bad += 1
        else:
            dist[a] = d if d <= MAXD else np.nan

        got.append((a, d))

    return got


# ---------------- 画布 ----------------
fig = plt.figure(figsize=(8.0, 7.5))
try:
    fig.canvas.manager.set_window_title("我的机器会看 — 极坐标雷达")
except Exception:
    pass

ax = fig.add_subplot(111, projection="polar")
ax.set_thetamin(0)
ax.set_thetamax(MAXANG)
ax.set_theta_zero_location("E")       # 0° 指向右边
ax.set_theta_direction(1)             # 逆时针增大
ax.set_ylim(0, MAXD)

step = MAXD // 4 if MAXD >= 40 else 10
ax.set_yticks(np.arange(0, MAXD + 1, step))
ax.set_yticklabels([str(int(v)) for v in np.arange(0, MAXD + 1, step)],
                   fontsize=7, color="0.5")
ax.grid(True, alpha=0.3)
ax.set_title("极坐标雷达 —— 舵机扫描 + 超声波测距", pad=16, fontsize=13)

scat = ax.scatter([], [], s=20, c=[], cmap="viridis", vmin=0, vmax=MAXD,
                  edgecolors="none", alpha=0.9, zorder=3)
sweep, = ax.plot([], [], color="#e03030", lw=1.4, alpha=0.8, zorder=2)

info = fig.text(0.5, 0.045, "", ha="center", fontsize=11)
hint = fig.text(0.5, 0.015, "", ha="center", fontsize=9, color="0.45")

cbar = fig.colorbar(scat, ax=ax, pad=0.10, shrink=0.72)
cbar.set_label("距离 (cm)", fontsize=9)
cbar.ax.tick_params(labelsize=8)


def main():
    try:
        s = serial.Serial(PORT, BAUD, timeout=0)
    except Exception as e:
        print("打不开串口 %s: %s" % (PORT, e))
        print("可用串口： python -m serial.tools.list_ports")
        return

    print("已连接 %s @ %d" % (PORT, BAUD))
    print("等待数据… (关窗口或 Ctrl+C 退出)")

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

            dstr = "---" if math.isnan(dist_now) else "%d cm" % dist_now
            lo = a_min if a_min < 999 else 0
            hi = max(a_max, 0)
            rate = (100.0 * (n_total - n_bad) / n_total) if n_total else 0.0
            info.set_text(
                "角度 %3d°    距离 %-8s   有效点 %3d   样本 %5d   "
                "有效率 %4.1f%%   角度范围 %3d° ~ %3d°"
                % (angle_now, dstr, len(ok), n_total, rate, lo, hi)
            )

            # 诊断提示
            if n_total == 0:
                hint.set_text("没有数据：检查串口 / STM32 是否在运行")
            elif hi - lo < 5:
                hint.set_text("角度几乎不动 → CPU 没有在扫描？查 pin 26 -> PA3 这根线")
            elif rate < 5:
                hint.set_text("有效率极低 → 传感器前方没有反光物，或传感器没固定在舵机上")
            elif rate < 40:
                hint.set_text("有效率偏低 → 目标太软/太斜，试试硬纸板或纸箱")
            else:
                hint.set_text("")

            plt.pause(0.05)

    except KeyboardInterrupt:
        print("\n退出")
    finally:
        s.close()


if __name__ == "__main__":
    main()
