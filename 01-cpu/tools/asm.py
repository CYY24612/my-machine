"""8 位 CPU 的汇编器（两遍扫描）。

用法：
    python asm.py programs/add.asm -o programs/add_out.hex -l programs/add.lst

支持的语法：
    ; 注释
    label:                定义标号（当前地址）
    ORG 0x20              把下一条指令/数据放到指定地址
    DB 1, 2, 0xFF         直接放字节（初始化数据用）
    NOP / OUT / HLT       无操作数
    LDA addr              addr 可以是数字（十进制或 0x 十六进制）或标号
    STA addr
    ADD addr
    SUB addr
    LDI imm
    JMP addr
    JZ  addr

输出的 hex 文件格式：每行一个字节；遇到地址跳变时输出 @XXXX（$readmemh 认识）。
"""

import re
import sys

OPCODES = {
    "NOP": 0x00, "LDA": 0x01, "STA": 0x02, "ADD": 0x03, "SUB": 0x04,
    "LDI": 0x05, "JMP": 0x06, "JZ": 0x07, "OUT": 0x08, "HLT": 0x0F,
}
HAS_OPERAND = {"LDA", "STA", "ADD", "SUB", "LDI", "JMP", "JZ"}


class AsmError(Exception):
    pass


def parse_int(tok):
    tok = tok.strip()
    if tok.lower().startswith("0x"):
        return int(tok, 16)
    return int(tok, 10)


def eval_expr(expr, labels):
    expr = expr.strip()
    if re.fullmatch(r"0[xX][0-9a-fA-F]+|\d+", expr):
        return parse_int(expr)
    if expr in labels:
        return labels[expr]
    raise AsmError(f"未知操作数: {expr}")


def read_lines(path):
    out = []
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for lineno, raw in enumerate(f, 1):
            text = raw.split(";")[0].rstrip()      # 去注释
            if text.strip():
                out.append((lineno, text.strip()))
    return out


def pass1(lines):
    """算每个标号的地址，顺便算出每行的地址与长度。"""
    labels = {}
    addr = 0
    layout = []           # [(lineno, addr, size, text)]
    for lineno, text in lines:
        m = re.match(r"^([A-Za-z_]\w*):\s*(.*)$", text)
        if m:
            labels[m.group(1)] = addr
            text = m.group(2).strip()
            if not text:
                continue
        parts = text.split(None, 1)
        mn = parts[0].upper()
        arg = parts[1].strip() if len(parts) > 1 else ""

        if mn == "ORG":
            addr = eval_expr(arg, labels)
            layout.append((lineno, addr, 0, text))
            continue
        if mn == "DB":
            n = len([x for x in arg.split(",") if x.strip()])
            layout.append((lineno, addr, n, text))
            addr += n
            continue
        if mn not in OPCODES:
            raise AsmError(f"第 {lineno} 行：未知指令 {mn}")
        size = 2 if mn in HAS_OPERAND else 1
        layout.append((lineno, addr, size, text))
        addr += size
    return labels, layout


def emit(labels, layout):
    """第二遍：生成 (addr, bytes, text) 列表。"""
    out = []
    for lineno, addr, size, text in layout:
        parts = text.split(None, 1)
        mn = parts[0].upper()
        arg = parts[1].strip() if len(parts) > 1 else ""

        if mn == "ORG":
            out.append((addr, [], text))
            continue
        if mn == "DB":
            vals = [eval_expr(x, labels) & 0xFF for x in arg.split(",") if x.strip()]
            out.append((addr, vals, text))
            continue

        code = OPCODES[mn]
        if mn in HAS_OPERAND:
            if not arg:
                raise AsmError(f"第 {lineno} 行：{mn} 需要操作数")
            val = eval_expr(arg, labels)
            if not (0 <= val <= 0xFF):
                raise AsmError(f"第 {lineno} 行：操作数越界 {val}")
            out.append((addr, [code, val], text))
        else:
            out.append((addr, [code], text))
    return out


def write_hex(path, items):
    lines = []
    expected = 0
    for addr, data, _ in items:
        if not data:
            continue
        if addr != expected:
            lines.append(f"@{addr:04x}")
        for b in data:
            lines.append(f"{b:02x}")
        expected = addr + len(data)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def write_listing(path, items, src):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("ADDR  BYTES        SOURCE\n")
        f.write("----  -----------  ----------------------------------\n")
        for addr, data, text in items:
            bs = " ".join(f"{b:02x}" for b in data) if data else "  "
            f.write(f"{addr:04x}  {bs:<11}  {text}\n")


def main(argv):
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    if len(argv) < 2:
        print(__doc__)
        return 1
    src = argv[1]
    out_hex = None
    out_lst = None
    if "-o" in argv:
        out_hex = argv[argv.index("-o") + 1]
    if "-l" in argv:
        out_lst = argv[argv.index("-l") + 1]
    if not out_hex:
        out_hex = src.rsplit(".", 1)[0] + ".hex"

    lines = read_lines(src)
    labels, layout = pass1(lines)
    items = emit(labels, layout)

    write_hex(out_hex, items)
    if out_lst:
        write_listing(out_lst, items, src)

    total = sum(len(d) for _, d, _ in items)
    print(f"汇编完成: {src}")
    print(f"  标号: {len(labels)} 个  ->  " + ", ".join(f"{k}=0x{v:02x}" for k, v in labels.items()))
    print(f"  字节: {total}")
    print(f"  输出: {out_hex}" + (f"  /  {out_lst}" if out_lst else ""))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except AsmError as e:
        print(f"错误: {e}")
        sys.exit(2)