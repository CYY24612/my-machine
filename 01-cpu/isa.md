# 我的 CPU · 指令集（v0.1）

## 机器模型

- 8 位数据、8 位地址（256 字节内存）
- 一个累加器 A、一个零标志 Z
- 程序区 0x00~0x0F，数据区 0x10~0xFF
- 多周期：单字节指令 2 拍，带操作数指令 3 拍

## 指令表

| 助记符        | 编码 | 操作数 | 动作                                             | 拍数        |
| ------------- | ---- | ------ | ------------------------------------------------ | ----------- |
| NOP           | 0x00 | —     | 什么都不做                                       | 2           |
| LDA a         | 0x01 | addr   | A = mem[addr]；Z = (A==0)                        | 3           |
| STA a         | 0x02 | addr   | mem[addr] = A                                    | 3           |
| ADD a         | 0x03 | addr   | A = A + mem[addr]（8 位回绕）；Z 更新            | 3           |
| SUB a         | 0x04 | addr   | A = A - mem[addr]（8 位回绕）；Z 更新            | 3           |
| LDI v         | 0x05 | imm    | A = v；Z = (A==0)                                | 3           |
| JMP a         | 0x06 | addr   | PC = addr                                        | 3           |
| JZ a          | 0x07 | addr   | if Z: PC = addr else PC = PC+1                   | 3           |
| OUT           | 0x08 | —     | 输出 A 到 out_data，out_valid 拉高一拍           | 2           |
| **INC** | 0x09 | —     | `A = A + 1`；Z 更新                            | **2** |
| **DEC** | 0x0A | —     | `A = A - 1`；Z 更新                            | **2** |
| **LDX** | 0x0B | addr   | **间接读**：`A = mem[mem[addr]]`；Z 更新 | **3** |
| **STX** | 0x0C | addr   | **间接写**：`mem[mem[addr]] = A`         | **3** |
| HLT           | 0x0F | —     | 停机（halted=1）                                 | 2           |

## 状态机（RTL 用）

```
S_FETCH:  ir = mem[pc]; pc = pc+1        → S_EXEC
S_EXEC:   按 ir 分派
            · 单字节指令：执行 → S_FETCH
            · 带操作数指令：tmp = mem[pc]; pc = pc+1 → S_EXEC2
S_EXEC2:  用 tmp 执行 → S_FETCH
S_STOP:   halted 后停在这里
```

## 示例程序（3 + 5）

```
地址  编码   助记符      说明
00    05     LDI 3      A = 3
01    03
02    02     STA 0x10   mem[0x10] = 3
03    10
04    05     LDI 5      A = 5
05    05
06    03     ADD 0x10   A = 5 + 3 = 8
07    10
08    08     OUT        输出 8
09    0F     HLT        停机
```

期望：**OUT 输出 8，停机时 A = 8**。

---

## 间接寻址（LDX / STX）说明

`LDX ptr` 里的 `ptr` 是**一个地址**，那个地址里存的是**目标地址**：

```asm
ptr:    DB 0x30          ; ptr 里存着 0x30
...
        LDX ptr          ; 先读 mem[ptr] = 0x30，再读 mem[0x30]
```

**不是 6502 的 X 寄存器**，是"用变量当地址"（指针）。

**典型用途**：数组遍历

```asm
        LDI arr          ; A = 数组首地址 arr = 1 -> A = 1
        STA ptr          ; ptr = 首地址   ptr = 0x10 -> mem[0x10] = A = 1
loop:
        LDX ptr          ; A = 当前元素   ptr = 0x10 -> mem[0x10] = 1 mem[1]
        ...
        LDA ptr
        INC              ; 指针 +1
        STA ptr
```

> ⚠️ **综合注意**：`mem[mem[tmp]]` 是嵌套索引，仿真没问题，但部分综合器不喜欢。
> 若 Gowin 报错，改成先读地址到 `tmp2` 再访存（多一拍），语义不变。
