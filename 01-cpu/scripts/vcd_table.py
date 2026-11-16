"""把 VCD 转成"每个时钟上升沿一行"的表。

用法：
    python vcd_table.py cpu_tb.vcd
    python vcd_table.py cpu_tb.vcd --signals state,pc,ir,tmp,a,z,out_valid,halted
"""

import sys
import re

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

DEFAULT_SIGNALS = ["state", "pc", "ir", "tmp", "a", "z", "out_valid", "halted"]


def parse_vcd(path):
    """返回 (signal_names, changes)

    signal_names: 完整名 -> (id, width)
    changes: [(time, id, value)] 按时间顺序
    """
    names = {}           # full_name -> (id, width)
    changes = []
    scope = []
    cur_time = 0

    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for raw in f:
            line = raw.strip()
            if not line:
                continue

            if line.startswith("$scope"):
                parts = line.split()
                scope.append(parts[2])
                continue
            if line.startswith("$upscope"):
                if scope:
                    scope.pop()
                continue
            if line.startswith("$var"):
                parts = line.split()
                width = int(parts[2])
                ident = parts[3]
                name = parts[4]
                full = ".".join(scope + [name])
                names[full] = (ident, width)
                continue
            if line.startswith("$end"):
                continue
            if line.startswith("#"):
                cur_time = int(line[1:])
                continue
            if line.startswith("$"):
                continue

            # 值变化
            if line[0] in "01xXzZ" and len(line) > 1:
                changes.append((cur_time, line[1:], line[0]))
            elif line[0] in "bB":
                body = line[1:]
                if " " in body:
                    bits, ident = body.split(" ", 1)
                    changes.append((cur_time, ident.strip(), bits))
            continue

    return names, changes


def find(names, short):
    """按短名找信号，优先 dut.*，其次 cpu_tb.*"""
    candidates = [n for n in names if n.split(".")[-1] == short]
    for pref in (".dut.", ".cpu_tb."):
        for n in candidates:
            if pref in n + ".":
                return n
    return candidates[0] if candidates else None


def value_of(bits, width):
    if isinstance(bits, str) and bits and bits[0] in "xXzZ":
        return "x"
    if isinstance(bits, str) and all(c in "xXzZ" for c in bits):
        return "x"
    try:
        return int(bits, 2)
    except ValueError:
        return "x"


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    path = sys.argv[1]
    signals = DEFAULT_SIGNALS
    if "--signals" in sys.argv:
        signals = sys.argv[sys.argv.index("--signals") + 1].split(",")

    names, changes = parse_vcd(path)

    # 找到所有需要的信号
    picked = {}
    for s in signals:
        full = find(names, s)
        if full:
            picked[full] = names[full]
    cyc_full = find(names, "cycles")

    # 按时间聚合
    by_time = {}
    for t, ident, bits in changes:
        by_time.setdefault(t, []).append((ident, bits))

    # 当前值
    cur = {full: 0 for full in names}
    id2full = {}
    for full, (ident, width) in names.items():
        id2full.setdefault(ident, []).append((full, width))

    rows = []
    clk_full = find(names, "clk")
    prev_clk = 0

    for t in sorted(by_time):
        # 先应用这个时间点的所有变化
        for ident, bits in by_time[t]:
            for full, width in id2full.get(ident, []):
                if bits in ("0", "1"):
                    cur[full] = bits
                else:
                    cur[full] = bits
        # 判断 clk 是否上升沿
        clk_bits = cur.get(clk_full) if clk_full else None
        if clk_bits == "1" and prev_clk != "1":
            row = {"t": t}
            if cyc_full:
                row["cycle"] = value_of(cur.get(cyc_full, "0"), 32)
            for full in picked:
                row[full.split(".")[-1]] = value_of(cur.get(full, "0"), 8)
            rows.append(row)
        prev_clk = clk_bits

    # 打印
    cols = (["cycle"] if cyc_full else []) + [s for s in signals if any(s in r for r in rows)]
    print(f"文件: {path}    总上升沿: {len(rows)}")
    print()
    header = "| " + " | ".join(["t(ps)"] + cols) + " |"
    print(header)
    print("|" + "---:|" * (len(cols) + 1))
    for r in rows:
        cells = [str(r["t"])]
        for c in cols:
            v = r.get(c, "-")
            cells.append(str(v))
        print("| " + " | ".join(cells) + " |")
    return 0


if __name__ == "__main__":
    sys.exit(main())