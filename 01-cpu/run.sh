#!/usr/bin/env bash
# 一键回归：把每个测试程序交给「参考模型」和「RTL 仿真」各跑一遍，比对期望值。
# 加新程序：把它加进下面的 TESTS 列表，格式 名字:期望A
set -uo pipefail
cd "$(dirname "$0")"

TESTS="add:8 sum10:55 mul:42 array_sum:15 array_fill:9"
fail=0
pass=0

for t in $TESTS; do
    name=${t%%:*}
    expect=${t##*:}

    echo "=============================================="
    echo " 程序: $name    期望 A = $expect"
    echo "=============================================="

    if [ ! -f "programs/$name.hex" ]; then
        echo "  找不到 programs/$name.hex"
        fail=$((fail+1)); continue
    fi
    cp "programs/$name.hex" programs/prog.hex

    # ---------- 参考模型 ----------
    echo "-- 1/2 Python 参考模型 --"
    if command -v python3 >/dev/null 2>&1; then
        if python3 cpu_ref.py programs/prog.hex --expect "$expect" >/dev/null 2>&1; then
            echo "   PASS"
        else
            echo "   FAIL （参考模型自己就不对，先修它）"
            fail=$((fail+1)); continue
        fi
    else
        echo "   （没有 python3，跳过）"
    fi

    # ---------- RTL ----------
    echo "-- 2/2 RTL 仿真 --"
    if command -v iverilog >/dev/null 2>&1; then
        if ! iverilog -o cpu_tb.vvp rtl/cpu.v tb/cpu_tb.v; then
            echo "   编译失败"; fail=$((fail+1)); continue
        fi
        out=$(vvp cpu_tb.vvp +EXPECT="$expect")
        echo "$out" | grep -E 'OUT =|halted =|A      =|expect =|PASS|FAIL' | sed 's/^/   /'
        if echo "$out" | grep -q '  PASS'; then
            pass=$((pass+1))
        else
            fail=$((fail+1))
        fi
    elif command -v verilator >/dev/null 2>&1; then
        echo "   只有 verilator，且版本低于 5 不支持 --timing，请装 iverilog："
        echo "   sudo apt install -y iverilog"
        fail=$((fail+1))
    else
        echo "   没装 iverilog： sudo apt install -y iverilog"
        fail=$((fail+1))
    fi
    echo ""
done

echo "=============================================="
echo " 结果：通过 $pass 个，失败 $fail 个"
echo "=============================================="
[ "$fail" -eq 0 ] && exit 0 || exit 1