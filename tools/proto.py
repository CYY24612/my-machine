#!/usr/bin/env python3
"""proto.py —— 统一帧协议 v1 的参考实现（"可执行规范"）

文档：docs/协议-统一帧-v1.md

为什么写成这样：
    CPU（8 位、15 条指令、无栈）也要实现同一套解析状态机。
    所以 Parser 刻意写成「逐字节 + 显式状态 + 统计计数器」的形式，
    方便逐行对照汇编实现（每个状态 = 汇编里的一个分支）。

帧格式：
    AA 55 | TYPE | LEN | PAYLOAD[LEN] | CHK
    CHK = (TYPE + LEN + PAYLOAD 逐字节和) & 0xFF
"""

from __future__ import annotations

MAGIC0 = 0xAA
MAGIC1 = 0x55

MAX_LEN = 250          # 协议上限（整帧 ≤ 255 字节）
MAX_LOAD_DATA = 126    # 装载帧 PAYLOAD = 1 字节地址 + 数据，装载区 0x80~0xFE 共 127 字节
LOAD_ADDR_MIN = 0x80   # 装载区下界（0x00~0x7F 被 monitor 代码/变量占用）
LOAD_ADDR_MAX = 0xFE   # 装载区上界（0xFF 保留）

# ---- TYPE ----
T_LOAD      = 0x01     # PC  -> CPU    ADDR + DATA(N)
T_SET_ANGLE = 0x02     # CPU -> STM32  ANGLE
T_DIST      = 0x03     # STM32 -> CPU  DIST
T_ESTOP     = 0x04     # 任意          (空)
T_RUN       = 0x05     # PC  -> CPU    ADDR
T_PING      = 0x06     # PC  -> CPU    (空，CPU 回 OUT 0xA5)
T_STATUS    = 0x10     # STM32 -> PC   ANGLE + DIST_LO + DIST_HI + ERR

TYPE_NAMES = {
    T_LOAD: "LOAD", T_SET_ANGLE: "SET_ANGLE", T_DIST: "DIST",
    T_ESTOP: "ESTOP", T_RUN: "RUN", T_PING: "PING", T_STATUS: "STATUS",
}

# 距离错误码（PAYLOAD 里的 DIST 字段）
DIST_OK_MIN = 0
DIST_OK_MAX = 250
DIST_NO_ECHO = 999     # 仅在调试上报里出现，DIST 帧里用 251 表示无效
DIST_INVALID = 251


# --------------------------------------------------------------------------
# 校验
# --------------------------------------------------------------------------
def checksum(typ: int, payload: bytes) -> int:
    """CHK = (TYPE + LEN + 各 PAYLOAD 字节) & 0xFF"""
    return (typ + len(payload) + sum(payload)) & 0xFF


# --------------------------------------------------------------------------
# 编码
# --------------------------------------------------------------------------
def encode(typ: int, payload: bytes = b"") -> bytes:
    """把 TYPE + PAYLOAD 封成一帧"""
    payload = bytes(payload)
    if len(payload) > MAX_LEN:
        raise ValueError(f"payload too long: {len(payload)} > {MAX_LEN}")
    return bytes([MAGIC0, MAGIC1, typ, len(payload)]) + payload + bytes([checksum(typ, payload)])


def load_frame(addr: int, data: bytes) -> bytes:
    """LOAD：把 data 依次写到 addr 起"""
    data = bytes(data)
    if not (LOAD_ADDR_MIN <= addr <= LOAD_ADDR_MAX):
        raise ValueError(
            f"load addr 0x{addr:02X} out of region "
            f"0x{LOAD_ADDR_MIN:02X}~0x{LOAD_ADDR_MAX:02X}")
    if len(data) > MAX_LOAD_DATA:
        raise ValueError(f"load data too long: {len(data)} > {MAX_LOAD_DATA}")
    if addr + len(data) > LOAD_ADDR_MAX + 1:
        raise ValueError(
            f"load 0x{addr:02X}+{len(data)} crosses the load region end")
    return encode(T_LOAD, bytes([addr]) + data)


def run_frame(addr: int) -> bytes:
    return encode(T_RUN, bytes([addr & 0xFF]))


def angle_frame(deg: int) -> bytes:
    return encode(T_SET_ANGLE, bytes([max(0, min(180, int(deg)))]))


def dist_frame(cm: int) -> bytes:
    return encode(T_DIST, bytes([max(0, min(255, int(cm)))]))


def estop_frame() -> bytes:
    return encode(T_ESTOP)


def ping_frame() -> bytes:
    return encode(T_PING)


def status_frame(angle: int, dist: int, err: int = 0) -> bytes:
    """STATUS：ANGLE + DIST(小端 16 位) + ERR"""
    d = int(dist) & 0xFFFF
    return encode(T_STATUS, bytes([angle & 0xFF, d & 0xFF, (d >> 8) & 0xFF, err & 0xFF]))


# --------------------------------------------------------------------------
# 解析
# --------------------------------------------------------------------------
S_HUNT  = "HUNT"    # 找 0xAA
S_HUNT2 = "HUNT2"   # 找 0x55
S_TYPE  = "TYPE"
S_LEN   = "LEN"
S_DATA  = "DATA"
S_CHK   = "CHK"


class Frame:
    __slots__ = ("typ", "payload")

    def __init__(self, typ: int, payload: bytes):
        self.typ = typ
        self.payload = payload

    def __repr__(self):
        return f"Frame(0x{self.typ:02X} {TYPE_NAMES.get(self.typ, '?')}, {self.payload.hex(' ')})"

    def __eq__(self, other):
        return isinstance(other, Frame) and self.typ == other.typ and self.payload == other.payload


class Parser:
    """逐字节状态机，和 CPU 侧汇编实现一一对应。

    统计计数器（stats）用于诊断：
        ok        成功解出的帧数
        bad_chk   校验失败
        bad_len   LEN 超限
        resync    中途丢弃（帧头不完整/超时）
        timeouts  调用 feed_gap() 造成的重置
    """

    def __init__(self):
        self.reset_full()

    # ---- 状态复位 ----
    def reset_frame(self):
        self.state = S_HUNT
        self.typ = 0
        self.len = 0
        self.idx = 0
        self.payload = bytearray()
        self.chk = 0

    def reset_full(self):
        self.reset_frame()
        self.stats = {"ok": 0, "bad_chk": 0, "bad_len": 0, "resync": 0, "timeouts": 0}

    # ---- 超时：帧内字节间隔 > 50 ms ----
    def feed_gap(self):
        if self.state != S_HUNT:
            self.stats["resync"] += 1
        self.stats["timeouts"] += 1
        self.reset_frame()

    # ---- 主入口 ----
    def feed(self, data: bytes):
        """喂入任意长度的字节，返回本次解出的 Frame 列表"""
        out = []
        for b in bytes(data):
            f = self._step(b)
            if f is not None:
                out.append(f)
        return out

    def _step(self, b: int):
        if self.state == S_HUNT:
            if b == MAGIC0:
                self.state = S_HUNT2
            # 否则继续 HUNT

        elif self.state == S_HUNT2:
            if b == MAGIC1:
                self.state = S_TYPE
            elif b == MAGIC0:
                self.state = S_HUNT2      # AA AA 55：第二个 AA 是新候选
            else:
                self.state = S_HUNT          # 假帧头

        elif self.state == S_TYPE:
            self.typ = b
            self.chk = b
            self.state = S_LEN

        elif self.state == S_LEN:
            self.len = b
            if b > MAX_LEN:
                self.stats["bad_len"] += 1
                self.reset_frame()
                return None
            self.chk = (self.chk + b) & 0xFF
            self.payload = bytearray()
            self.idx = 0
            self.state = S_DATA if self.len > 0 else S_CHK

        elif self.state == S_DATA:
            self.payload.append(b)
            self.chk = (self.chk + b) & 0xFF
            self.idx += 1
            if self.idx >= self.len:
                self.state = S_CHK

        elif self.state == S_CHK:
            ok = (b == self.chk)
            frame = Frame(self.typ, bytes(self.payload)) if ok else None
            if ok:
                self.stats["ok"] += 1
            else:
                self.stats["bad_chk"] += 1
            self.reset_frame()
            return frame

        return None

    @property
    def busy(self):
        return self.state != S_HUNT


# --------------------------------------------------------------------------
# 自检：打印协议文档里的 7 条示例帧
# --------------------------------------------------------------------------
if __name__ == "__main__":
    samples = [
        ("PING", ping_frame()),
        ("ESTOP", estop_frame()),
        ("SET_ANGLE 90", angle_frame(90)),
        ("DIST 40", dist_frame(40)),
        ("RUN 0x80", run_frame(0x80)),
        ("LOAD 0x80 (含 0xFF)", load_frame(0x80, bytes([0x05, 0x2A, 0x08, 0x0F, 0xFF]))),
        ("STATUS", status_frame(90, 100, 0)),
    ]
    print("协议文档 §5 的示例帧：")
    for name, fr in samples:
        print(f"  {name:22s} {fr.hex(' ').upper()}")

    print("\n回环解析：")
    p = Parser()
    for name, fr in samples:
        for got in p.feed(fr):
            print(f"  {name:22s} -> {got}")
    print(f"\n统计：{p.stats}")