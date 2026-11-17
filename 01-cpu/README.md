# 我的机器 · 第 1 块砖：8 位 CPU

> 目标：**从零造一台能算数的计算机**（脑线第一步）。
> 这一块砖的终点：程序 `3 + 5` 跑出 `8`。

---

## 目录

```
01-cpu/
├── isa.md              指令集定义（先看这个）
├── cpu_ref.py          Python 参考模型（golden model，已跑通）
├── rtl/cpu.v           Verilog 实现（多周期，4 个状态）
├── tb/cpu_tb.v         纯 Verilog testbench（打印 PASS/FAIL）
├── programs/
│   ├── add.hex         机器码：3 + 5 = 8
│   └── add.asm         同一程序的汇编版（给人看）
└── README.md           本文件
```

---

## 第 0 步 · 跑参考模型（不需要任何 HDL 工具，已完成 ✅）

```powershell
cd E:\CYY\my_project\my-machine\01-cpu
python cpu_ref.py programs\add.hex
```

**期望输出**：

```
=== 运行 programs\add.hex ===
cyc=  3  pc=00  LDI  op=0x03  A=  3  Z=0  out=['-']
cyc=  6  pc=02  STA  op=0x10  A=  3  Z=0  out=['-']
cyc=  9  pc=04  LDI  op=0x05  A=  5  Z=0  out=['-']
cyc= 12  pc=06  ADD  op=0x10  A=  8  Z=0  out=['-']
cyc= 14  pc=08  OUT  op=--  A=  8  Z=0  out=[8]
cyc= 16  pc=09  HLT  op=--  A=  8  Z=0  out=[8]

停机: True   总拍数: 16   A=8   Z=0
OUT 序列: [8]

PASS: 3 + 5 = 8
```

> **为什么先做这个**：它定义了这颗 CPU 的**唯一正确语义**。等 RTL 写好了，两边结果必须一致——这就是"golden model 对照"，专业做法。

---

## 第 1 步 · 装 Verilator（在你的 Linux 侧）

Windows 上没装 Verilator，三个选择：

| 方案 | 怎么做 |
| --- | --- |
| **A. WSL（推荐）** | `wsl --install -d Ubuntu` → 进 Ubuntu → `sudo apt update && sudo apt install -y verilator` |
| **B. 麒麟虚拟机** | 在 VM 里 `sudo apt install -y verilator`（你已经有这个环境） |
| **C. iverilog（更轻）** | `sudo apt install -y iverilog gtkwave` |

装完验证：

```bash
verilator --version     # 期望 5.0 以上
# 或
iverilog -V
```

---

## 第 2 步 · 跑 RTL

### 用 Verilator（推荐，5.x）

```bash
cd 01-cpu
verilator --binary --timing -j 0 -Wall -Wno-fatal --top-module cpu_tb \
          -o cpu_tb rtl/cpu.v tb/cpu_tb.v
./obj_dir/cpu_tb
```

### 用 iverilog（更简单的替代）

```bash
cd 01-cpu
iverilog -o cpu_tb.vvp rtl/cpu.v tb/cpu_tb.v
vvp cpu_tb.vvp
```

**期望输出**：

```
[xxx] cyc=14  OUT = 8

halted = 1
cycles = 16
A      = 8 (0x08)
PASS: 3 + 5 = 8
```

> **cycle 数与 Python 模型差 1 属正常**：testbench 在 `posedge` 计数，边界上可能多算一拍。**关键看 `A = 8` 和 `PASS`。**

---

## 第 3 步 · 看波形（把"每一拍"看见）

```bash
# iverilog 路线（tb 里已带 $dumpfile）
gtkwave cpu_tb.vcd

# Verilator 路线需要加 --trace 重新编译
verilator --binary --timing --trace -j 0 --top-module cpu_tb -o cpu_tb rtl/cpu.v tb/cpu_tb.v
./obj_dir/cpu_tb
gtkwave cpu_tb.vcd
```

**看这几个信号**：`state`、`pc`、`ir`、`a`、`z`、`out_valid`。

---

## 每一拍在干什么（对照表）

| 拍 | state | 发生什么 |
| --- | --- | --- |
| 1 | S_FETCH | `ir = mem[pc]`，`pc++` |
| 2 | S_EXEC | 单字节指令（NOP/OUT/HLT）直接执行；其余取操作数 `tmp = mem[pc]`，`pc++` |
| 3 | S_EXEC2 | 用 `tmp` 执行（LDI/LDA/STA/ADD/SUB/JMP/JZ） |

**逐指令拍数**：

| 指令 | 拍数 | 过程 |
| --- | --- | --- |
| NOP / OUT / HLT | 2 | FETCH → EXEC |
| LDI / LDA / STA / ADD / SUB / JMP / JZ | 3 | FETCH → EXEC(取操作数) → EXEC2(执行) |

**`add.hex` 的 16 拍**：

```
LDI 3    : 3 拍
STA 0x10 : 3 拍
LDI 5    : 3 拍
ADD 0x10 : 3 拍
OUT      : 2 拍
HLT      : 2 拍
────────────────
合计      16 拍
```

---

## 写程序：用汇编器，不再手数地址

```bash
# 汇编（自动算标号地址、自动生成 listing）
python3 tools/asm.py programs/mul.asm -o programs/mul.hex -l programs/mul.lst

# 看地址表（listing）
cat programs/mul.lst
```

**支持的语法**：

```asm
; 注释
label:                标号
ORG 0x20              把数据放到 0x20（程序之后）
DB 0, 7, 1           直接放字节（初始化数据）
LDA addr / STA addr / ADD addr / SUB addr
LDI imm
JMP addr / JZ addr
NOP / OUT / HLT
```

**它做的事（两遍扫描）**：

1. **第一遍**：走一遍源码，算出每个标号的地址、每条指令的字节数
2. **第二遍**：把标号地址填回去，生成机器码

**输出**：

| 文件 | 内容 |
| --- | --- |
| `.hex` | 机器码，遇到地址跳变输出 `@XXXX`（`$readmemh` 认识） |
| `.lst` | 地址 + 字节 + 源码，一眼看"这行在哪" |

> **数据区一定要 `ORG` 到程序之后**（`mul` 用 0x20），否则数据会覆盖指令。

---
## 加测试只需要两步（回归框架已就绪）

**现在跑一次 `./run.sh`，会依次跑两个程序并自动判分：**

| 程序 | 测什么 | 期望 A |
| --- | --- | ---: |
| `add` | 加法 + 存储 | 8 |
| `sum10` | **用 JZ 写循环**（1+2+…+10） | 55 |

**加新程序**：

```bash
# 1. 写 programs/xxx.asm，手工汇编成 programs/xxx.hex
# 2. 把 "xxx:期望值" 加进 run.sh 的 TESTS 列表
TESTS="add:8 sum10:55 xxx:期望值"
```

**程序怎么被加载**：`run.sh` 把要跑的那个拷成 `programs/prog.hex`，`cpu.v` 固定读这个文件。
**期望值怎么传进仿真**：`vvp cpu_tb.vvp +EXPECT=55`，testbench 用 `$value$plusargs` 读取。

> 内存布局提醒：程序从 0x00 开始，**数据必须放在程序之后**（`sum10` 用 0x20 以后），否则数据会覆盖指令。

---
## 第 4 步 · 改点什么（真正学会的地方）

按难度递增，改完都要**先改 Python 模型验证，再改 RTL**：

| 练习 | 要改什么 | 验证方法 |
| --- | --- | --- |
| 1. 改成立 7 + 9 | 只改 `programs/add.hex` 里的立即数 | `A` 应为 16（0x10） |
| 2. 溢出测试：200 + 100 | 改立即数 | `A` 应为 44（8 位回绕） |
| 3. 加一个 `DEC`（减一）指令 | 编码 0x09，改 `isa.md` + 两处代码 | 写程序试 |
| 4. 用 JZ 写循环：算 1+2+...+10 | 只用现有指令写程序 | `A` 应为 55 |
| 5. 加一条 `LDX`（间接寻址） | 编码 0x0A，`a = mem[mem[x]]` | 需要先加 X 寄存器 |

> **循环那个（第 4 项）最有价值**：只用现有 9 条指令就能写出有控制流的程序，说明指令集是"图灵完备"的雏形。

---

## 常见错误

| 现象 | 原因 | 解法 |
| --- | --- | --- |
| `$readmemh: file not found` | 工作目录不对 | 一定要在 `01-cpu/` 根目录跑 |
| `A` 一直是 0 | `rst` 时序问题 | 检查 testbench 的复位宽度 |
| 一直不 HLT | 程序没跑对 | 先用 Python 模型跑同一个 hex，比对 |
| 拍数比预期多 | `S_EXEC2` 多走了一拍 | 正常，看 `A` 对不对 |
| Verilator 报 `--timing` 不支持 | 版本低于 5.0 | 升级，或改用 iverilog |

---

## 下一步（这块砖之后）

1. **加内存读写指令**（`LDX`/`STX`），能操作数组
2. **加 CALL/RET**，能写子程序
3. **加 UART 输出**，让 CPU 能打印字符（这就是"跑程序"的开始）
4. **上 FPGA 板**（Tang Nano 9K，约 100 元），LED 显示结果
5. **写一个汇编器**（Python，200 行），不再手写机器码

---

## 这个项目在整体计划里的位置

见 [[长期目标 · 我的机器]] 的**脑线**，对应交汇点 ②（我的 CPU，能算加法）。

**它是"电脑到底怎么组成的"这个问题的第一个答案**：你现在有一台（在模型里）能执行程序的机器，而且每一拍你都知道它在干什么。

---

## 14 条指令（2026-11-17 新增 4 条）

| 指令 | 编码 | 拍数 | 语义 | 用途 |
| --- | --- | ---: | --- | --- |
| NOP | 0x00 | 2 | 空操作 | — |
| LDA addr | 0x01 | 3 | `A = mem[addr]` | 直接读 |
| STA addr | 0x02 | 3 | `mem[addr] = A` | 直接写 |
| ADD addr | 0x03 | 3 | `A += mem[addr]` | — |
| SUB addr | 0x04 | 3 | `A -= mem[addr]` | — |
| LDI imm | 0x05 | 3 | `A = imm` | 立即数 |
| JMP addr | 0x06 | 3 | `PC = addr` | 无条件跳 |
| JZ addr | 0x07 | 3 | `if Z: PC = addr` | 条件跳 |
| OUT | 0x08 | 2 | 输出 A | — |
| **INC** | 0x09 | **2** | `A += 1`（更新 Z） | 指针/计数器 +1 |
| **DEC** | 0x0A | **2** | `A -= 1`（更新 Z） | 指针/计数器 -1 |
| **LDX addr** | 0x0B | **3** | `A = mem[mem[addr]]` | **间接读（数组/指针）** |
| **STX addr** | 0x0C | **3** | `mem[mem[addr]] = A` | **间接写** |
| HLT | 0x0F | 2 | 停机 | — |

### 新增两个测试程序

| 程序 | 测什么 | 期望 A | 拍数 |
| --- | --- | ---: | ---: |
| `array_sum` | 用 **LDX** 遍历数组求和（1+2+3+4+5） | **15** | 178 |
| `array_fill` | 用 **STX** 批量写入 9，再读回验证 | **9** | 135 |

```bash
python tools/asm.py programs/array_sum.asm -o programs/array_sum.hex -l programs/array_sum.lst
python cpu_ref.py programs/array_sum.hex --expect 15
```

### 汇编器的两道自检（防静默失败）

| 检查 | 触发条件 | 为什么要 |
| --- | --- | --- |
| **hex 内容检查** | 出现非 `xx` / `@xxxx` 的行 | Gowin `$readmemh` 遇到注释**静默失败** |
| **地址重叠检查** | `ORG` 回头覆盖已生成的字节 | 数据压到代码上 → 跑飞（本次实测踩到） |

---

## CPU 会说话了：OUT → UART（P3，2026-11-17）

```
cpu ──out_data[7:0]──▶ uart_tx ──tx──▶ 串口线
    ──out_valid(1拍)──▶ tx_start
    ◀──out_ready──────  ~tx_busy      ← 握手：外设忙，CPU 停在 OUT 上等
```

### 关键改动：`out_ready` 握手

CPU 一个 OUT 只花 2 拍，而发一个字节要 **2340 拍**（234 拍/bit × 10 bit）。
如果不握手，CPU 会连着 OUT 好几个字节，串口只会发出去第一个。

所以 `cpu.v` 新增输入 `out_ready`：

```verilog
OP_OUT:  if (out_ready) begin      // 外设忙就停在这拍等
             out_data  <= a;
             out_valid <= 1'b1;
             state     <= S_FETCH;
         end
```

**纯计算测试不受影响**：`cpu_tb.v` 里接 `.out_ready(1'b1)`。

> ⚠️ **`fpga/top.v` 必须同步改**：没有 UART 时接 `1'b1`，
> 有 UART 时接 `~tx_busy`。否则综合报端口不匹配。

### 波特率

```verilog
uart_tx #(.CLKS_PER_BIT(234)) u_tx(...)   // 27MHz / 115200 = 234.375 → 234（误差 0.16%）
```

| 时钟 | 波特率 | CLKS_PER_BIT |
| --- | --- | ---: |
| 27 MHz | 115200 | 234 |
| 27 MHz | 9600 | 2812 |

### 两个 testbench

| testbench | 测什么 | 命令 |
| --- | --- | --- |
| `tb/uart_tx_tb.v` | UART 模块**单独**可用（自带解码，打印 `Hi`） | `iverilog -o u.vvp rtl/uart_tx.v tb/uart_tx_tb.v && vvp u.vvp` |
| `tb/cpu_uart_tb.v` | **CPU 驱动** UART 打印 `Hi` | `iverilog -o c.vvp rtl/cpu.v rtl/uart_tx.v tb/cpu_uart_tb.v && vvp c.vvp` |

### hello.asm

```asm
        LDI 72          ; 'H'
        OUT
        LDI 105         ; 'i'
        OUT
        LDI 10          ; 换行
        OUT
        HLT
```

### ⚠️ 一个教训：签入的 `.hex` 会过期

本次踩坑：`array_sum.hex` 是旧的，参考模型跑出错误结果，排查了半小时。
**现在 `run.sh` 每次都从 `.asm` 重新汇编**——`.asm` 是唯一真相，`.hex` 只是产物。

> 同类问题：`.lst` 也一样。改完 `.asm` 一定要重新跑 `run.sh`。

### IN 指令（2026-11-17 加，第 15 条）

```verilog
IN ：如果 in_valid=1 → A = in_data，给 in_ack 脉冲，回取指
     如果 in_valid=0 → 停在这拍等（和 OUT 的 out_ready 对称）
```

| 端口 | 方向 | 作用 |
| --- | --- | --- |
| `in_data[7:0]` | 输入 | 外部数据 |
| `in_valid` | 输入 | 有数据待取 |
| `in_ack` | 输出 | 取走了（单拍脉冲） |

**编码 0x0D，2 拍 + 等待。**

测试：`programs/cnt_in.asm` 读 3 个字节，第 3 个留在 A → 喂 `11 22 33` 得 `0x33`。

```bash
python cpu_ref.py programs/cnt_in.hex --input "11 22 33" --expect 51
iverilog -o in.vvp rtl/cpu.v tb/cpu_in_tb.v && vvp in.vvp
```