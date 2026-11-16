# add.hex × cpu.v × 波形 · 逐拍印证

> 三个来源对照：
> - **add.hex**：机器码字节（程序）
> - **cpu.v**：行号（电路行为）
> - **cpu_tb.vcd**：实测波形（真实运行结果）
>
> 数据来自 `python3 scripts/vcd_table.py cpu_tb.vcd`。

---

## 0. 三个预备知识

### 0.1 拍号与时间

```
clk:  initial 0, 每 5ns 翻转  → 上升沿在 t = 5, 15, 25, ... ns
rst:  1 一直到 t = 12ns 才释放
所以第 1 个被计数的上升沿是 t = 15ns = 15000 ps = 第 1 拍
```

**第 n 拍的时刻 = (10n + 5) ns = (10000n + 5000) ps**

### 0.2 波形上的值 = 那一拍"执行完之后"的寄存器值

```
拍 n 的沿：状态机用【沿前的 state】决定做什么 → 做完后写寄存器 → 【沿后的 state】是下一步
所以：拍 n 显示的值 = 第 n 拍做完的结果
```

### 0.3 add.hex 的字节内容

| 地址 | 字节 | 含义 |
| --- | --- | --- |
| 0x00 | `05` | LDI |
| 0x01 | `03` | 立即数 3 |
| 0x02 | `02` | STA |
| 0x03 | `10` | 目标地址 0x10 |
| 0x04 | `05` | LDI |
| 0x05 | `05` | 立即数 5 |
| 0x06 | `03` | ADD |
| 0x07 | `10` | 目标地址 0x10 |
| 0x08 | `08` | OUT |
| 0x09 | `0F` | HLT |
| 0x10 | `00`→`03` | 数据区（被 STA 写入 3） |

---

## 1. 主表（16 个有效拍）

`state`: 0=FETCH 1=EXEC 2=EXEC2 3=STOP

| 拍 | t(ps) | 沿前 state | cpu.v 执行的行 | 动作 | 读写 | 波形实测 pc / ir / tmp / a |
| ---: | ---: | :---: | --- | --- | --- | --- |
| 1 | 15000 | 0 FETCH | **L67 L68 L70** | `ir<=mem[pc]`；`pc+1`；去 EXEC | 读 mem[0x00]=05 | 1 / 05 / 0 / 0 |
| 2 | 25000 | 1 EXEC | **L87 L88 L89** | 取操作数：`tmp<=mem[pc]`；`pc+1`；去 EXEC2 | 读 mem[0x01]=03 | 2 / 05 / 03 / 0 |
| 3 | 35000 | 2 EXEC2 | **L98 L99 L118** | LDI：`a<=tmp`；`z<=tmp==0`；回 FETCH | — | 2 / 05 / 03 / **3** |
| 4 | 45000 | 0 FETCH | L67 L68 L70 | 取 STA | 读 mem[0x02]=02 | 3 / 02 / 03 / 3 |
| 5 | 55000 | 1 EXEC | L87 L88 L89 | 取地址 0x10 | 读 mem[0x03]=10 | 4 / 02 / 10 / 3 |
| 6 | 65000 | 2 EXEC2 | **L105 L118** | STA：`mem[tmp]<=a` | **写 mem[0x10]=3** | 4 / 02 / 10 / 3 |
| 7 | 75000 | 0 FETCH | L67 L68 L70 | 取 LDI | 读 mem[0x04]=05 | 5 / 05 / 10 / 3 |
| 8 | 85000 | 1 EXEC | L87 L88 L89 | 取操作数 5 | 读 mem[0x05]=05 | 6 / 05 / 05 / 3 |
| 9 | 95000 | 2 EXEC2 | L98 L99 L118 | LDI：A = 5 | — | 6 / 05 / 05 / **5** |
| 10 | 105000 | 0 FETCH | L67 L68 L70 | 取 ADD | 读 mem[0x06]=03 | 7 / 03 / 05 / 5 |
| 11 | 115000 | 1 EXEC | L87 L88 L89 | 取地址 0x10 | 读 mem[0x07]=10 | 8 / 03 / 10 / 5 |
| 12 | 125000 | 2 EXEC2 | **L107 L108 L118** | ADD：`a<=a+mem[tmp]` = 5+3 | 读 mem[0x10]=3 | 8 / 03 / 10 / **8** |
| 13 | 135000 | 0 FETCH | L67 L68 L70 | 取 OUT | 读 mem[0x08]=08 | 9 / 08 / 10 / 8 |
| 14 | 145000 | 1 EXEC | **L78 L79 L80** | OUT：输出 a，`out_valid<=1` | — | 9 / 08 / 10 / 8（out_valid=1） |
| 15 | 155000 | 0 FETCH | L67 L68 **L69** L70 | 取 HLT；`out_valid<=0` | 读 mem[0x09]=0F | 10 / 0F / 10 / 8 |
| 16 | 165000 | 1 EXEC | **L83 L84** | HLT：`halted<=1`；去 STOP | — | 10 / 0F / 10 / 8（halted=1, state=3） |
| 17 | 175000 | 3 STOP | L121 | STOP 空转（TB 多等一拍） | — | 10 / 0F / 10 / 8 |

---

## 2. 三个状态各自在干什么

### FETCH（L66~L71）

```verilog
S_FETCH: begin
    ir        <= mem[pc];     // L67  取指令
    pc        <= pc + 8'd1;   // L68  地址 +1
    out_valid <= 1'b0;        // L69  OUT 只亮一拍
    state     <= S_EXEC;      // L70
end
```

**波形上验证**：每 2~3 拍 `pc` 会 +1（不是每拍），`ir` 变成新指令的 opcode。

### EXEC（L74~L92）：分流

```verilog
case (ir)
    OP_NOP:  state <= S_FETCH;      // L76
    OP_OUT:  begin                  // L77
                 out_data  <= a;    // L78
                 out_valid <= 1'b1; // L79
                 state     <= S_FETCH; // L80
             end
    OP_HLT:  begin                  // L82
                 halted <= 1'b1;    // L83
                 state  <= S_STOP;  // L84
             end
    default: begin                  // L86  ★ 带操作数的指令走这里
                 tmp   <= mem[pc];  // L87
                 pc    <= pc + 8'd1;// L88
                 state <= S_EXEC2;  // L89
             end
endcase
```

**关键**：`tmp` 只有在这个 `default` 分支才会被赋值。
所以波形上 `tmp` 从第 2 拍开始一直是 `0x10`（最后一次赋的值），**它不会自动清零**。

### EXEC2（L95~L119）：真正执行

```verilog
case (ir)
    OP_LDI: a <= tmp;                    // L98
    OP_LDA: a <= mem[tmp];               // L102
    OP_STA: mem[tmp] <= a;               // L105
    OP_ADD: a <= a + mem[tmp];           // L107  ★ 注意 mem[]
    OP_SUB: a <= a - mem[tmp];           // L111
    OP_JMP: pc <= tmp;                   // L114
    OP_JZ:  if (z) pc <= tmp;            // L115
    state <= S_FETCH;                    // L118
endcase
```

---

## 3. 波形如何证明 ADD 的 bug（21 vs 8）

### 错误版本（`a <= a + tmp`）

```
拍 11：tmp <= mem[0x07] = 0x10      ← 这是【地址】
拍 12：a  <= a + tmp = 5 + 0x10 = 21
```

**波形上会看到**：`tmp = 0x10`，`a` 从 5 跳到 **21（0x15）**。

### 正确版本（`a <= a + mem[tmp]`）

```
拍 11：tmp <= mem[0x07] = 0x10      ← 地址
拍 12：a  <= a + mem[0x10] = 5 + 3 = 8    ← 多读了一次内存
```

**波形上会看到**：`tmp = 0x10` 不变，`a` 从 5 跳到 **8**。

> **判别方法**：看 `a` 跳到了多少。
> `21 = 5 + 0x10` → 用了地址；`8 = 5 + mem[0x10]` → 用了地址里的值。

---

## 4. 波形里看不到的东西：mem 的内容

**`mem` 是数组，VCD 默认不会导出**（波形里只有 `state/pc/ir/tmp/a/z/out_valid/halted`）。

所以"STA 到底写没写进去"，只能**间接验证**：

| 想验证 | 间接方法 |
| --- | --- |
| STA 写成功了吗 | 看第 12 拍 ADD 的结果是不是 8（如果 mem[0x10] 没写进去，会是 5+0=5） |
| LDA 读对了吗 | 看 `a` 是否等于预期 |

**想直接看 mem**，在 `tb/cpu_tb.v` 里加一行：

```verilog
$dumpvars(0, cpu_tb.dut.mem);      // 会多出 256 个信号，慎用
```

或者临时只 dump 几个：

```verilog
$dumpvars(0, cpu_tb.dut.mem[16]);  // mem[0x10]
```

---

## 5. 自己复现这张表

```bash
cp programs/add.hex programs/prog.hex
iverilog -o cpu_tb.vvp rtl/cpu.v tb/cpu_tb.v
vvp cpu_tb.vvp +EXPECT=8
python3 scripts/vcd_table.py cpu_tb.vcd
```

想只看关键信号：

```bash
python3 scripts/vcd_table.py cpu_tb.vcd --signals state,pc,ir,tmp,a
```

---

## 6. 一句话总结

> **`pc` 告诉你"程序走到哪"，`ir` 告诉你"这是什么指令"，`tmp` 告诉你"操作数是地址还是值"，`a` 告诉你"算出来什么"。**
> **四者对上 `cpu.v` 的行，就说明"代码 → 电路 → 行为"三边一致。**