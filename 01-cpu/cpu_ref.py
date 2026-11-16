"""CPU 参考模型（golden model）。

这个模型不是"模拟器玩具"：它定义了我们这颗 CPU 的**唯一正确语义**。
将来 RTL 写出来后，用同一个程序跑，两边结果必须一致。

用法：
    python cpu_ref.py programs\add.hex
"""

import sys
from pathlib import Path

# Windows 控制台默认 cp936，统一成 utf-8 避免中文乱码
try:
    sys.stdout.reconfigure(encoding='utf-8')
except Exception:
    pass

# ---- 指令编码 ----
NOP = 0x00
LDA = 0x01
STA = 0x02
ADD = 0x03
SUB = 0x04
LDI = 0x05
JMP = 0x06
JZ  = 0x07
OUT = 0x08
HLT = 0x0F

HAS_OPERAND = {LDA, STA, ADD, SUB, LDI, JMP, JZ}
NAMES = {NOP: "NOP", LDA: "LDA", STA: "STA", ADD: "ADD", SUB: "SUB",
         LDI: "LDI", JMP: "JMP", JZ: "JZ", OUT: "OUT", HLT: "HLT"}


class CPU:
    def __init__(self, mem=None, trace=True):
        self.mem = list(mem) if mem else [0] * 256
        self.pc = 0
        self.a = 0
        self.z = 0
        self.halted = False
        self.cycles = 0
        self.outputs = []
        self.trace = trace
        self.log = []

    def _fetch(self):
        ir = self.mem[self.pc]
        self.pc = (self.pc + 1) & 0xFF
        self.cycles += 1
        return ir

    def _operand(self):
        v = self.mem[self.pc]
        self.pc = (self.pc + 1) & 0xFF
        self.cycles += 1
        return v

    def step(self):
        """执行一条指令，返回是否继续运行。"""
        if self.halted:
            return False

        ir = self._fetch()                      # S_FETCH
        pc_before = self.pc
        operand = None
        if ir in HAS_OPERAND:                   # S_EXEC (取操作数)
            operand = self._operand()
        self.cycles += 1                        # S_EXEC / S_EXEC2 的执行拍

        if ir == NOP:
            pass
        elif ir == LDI:
            self.a = operand
            self.z = int(self.a == 0)
        elif ir == LDA:
            self.a = self.mem[operand]
            self.z = int(self.a == 0)
        elif ir == STA:
            self.mem[operand] = self.a
        elif ir == ADD:
            self.a = (self.a + self.mem[operand]) & 0xFF
            self.z = int(self.a == 0)
        elif ir == SUB:
            self.a = (self.a - self.mem[operand]) & 0xFF
            self.z = int(self.a == 0)
        elif ir == JMP:
            self.pc = operand
        elif ir == JZ:
            if self.z:
                self.pc = operand
        elif ir == OUT:
            self.outputs.append(self.a)
        elif ir == HLT:
            self.halted = True
        else:
            raise ValueError(f"非法指令 0x{ir:02X} @ pc=0x{pc_before - 1:02X}")

        line = (f"cyc={self.cycles:3d}  pc={pc_before - 1:02X}  {NAMES.get(ir, '??'):3s}"
                f"  op={('--' if operand is None else f'0x{operand:02X}')}"
                f"  A={self.a:3d}  Z={self.z}  out={self.outputs[-1:] or ['-']}")
        self.log.append(line)
        if self.trace:
            print(line)
        return not self.halted


def load_hex(path):
    mem = [0] * 256
    text = Path(path).read_text(encoding="utf-8")
    i = 0
    for line in text.splitlines():
        line = line.split("//")[0].strip()
        if not line:
            continue
        for tok in line.split():
            if tok.startswith("@"):
                i = int(tok[1:], 16)
            else:
                mem[i] = int(tok, 16) & 0xFF
                i += 1
    return mem


def run(path, max_cycles=1000):
    cpu = CPU(load_hex(path))
    print(f"=== 运行 {path} ===")
    while cpu.step() and cpu.cycles < max_cycles:
        pass
    print()
    print(f"停机: {cpu.halted}   总拍数: {cpu.cycles}   A={cpu.a}   Z={cpu.z}")
    print(f"OUT 序列: {cpu.outputs}")
    return cpu


if __name__ == "__main__":
    args = sys.argv[1:]
    target = "programs/prog.hex"
    expect = None
    positional = [a for a in args if not a.startswith("--")]
    if positional:
        target = positional[0]
    if "--expect" in args:
        expect = int(args[args.index("--expect") + 1])

    cpu = run(target)
    ok = cpu.halted and (expect is None or cpu.a == expect)
    print()
    if expect is not None:
        print(f"  期望 A = {expect}，实际 A = {cpu.a}")
    print("PASS" if ok else "FAIL")
    sys.exit(0 if ok else 1)