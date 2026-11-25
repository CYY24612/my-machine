#!/usr/bin/env bash
# 一键回归：把每个测试程序交给「参考模型」和「RTL 仿真」各跑一遍，比对期望值。
# 加新程序：把它加进下面的 TESTS 列表，格式 名字:期望A
#
# 注意：每次都从 .asm 重新汇编出 .hex。
# 签入的 .hex 可能过期（曾因此白查半小时），.asm 才是唯一真相。
set -uo pipefail
cd "$(dirname "$0")"

TESTS="add:8 sum10:55 mul:42 array_sum:15 array_fill:9 jumpx_test:42"
fail=0
pass=0

asm() {   # asm <名字>
    local name="$1"
    if [ ! -f "programs/$name.asm" ]; then
        echo "  找不到 programs/$name.asm"; return 1
    fi
    if command -v python3 >/dev/null 2>&1; then
        if ! python3 tools/asm.py "programs/$name.asm" \
                -o "programs/$name.hex" -l "programs/$name.lst" >/dev/null; then
            echo "  汇编失败"; return 1
        fi
    elif [ ! -f "programs/$name.hex" ]; then
        echo "  既没有 python3 也没有现成的 programs/$name.hex"; return 1
    fi
    return 0
}

for t in $TESTS; do
    name=${t%%:*}
    expect=${t##*:}

    echo "=============================================="
    echo " 程序: $name    期望 A = $expect"
    echo "=============================================="

    asm "$name" || { fail=$((fail+1)); continue; }
    cp "programs/$name.hex" programs/prog.hex

    # ---------- 参考模型 ----------
    echo "-- 1/2 Python 参考模型 --"
    if command -v python3 >/dev/null 2>&1; then
        if python3 cpu_ref.py programs/prog.hex --expect "$expect" >/dev/null 2>&1; then
            echo "   PASS"
        else
            echo "   FAIL （参考模型自己就不对，先修它）"
            python3 cpu_ref.py programs/prog.hex --expect "$expect" 2>&1 | tail -4 | sed 's/^/     /'
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

# ---------------- CPU → UART ----------------
echo "=============================================="
echo " CPU → UART ：hello 程序打印 Hi"
echo "=============================================="
if command -v iverilog >/dev/null 2>&1; then
    if asm hello; then
        cp programs/hello.hex programs/prog.hex
        if iverilog -o cpu_uart.vvp rtl/cpu.v rtl/uart_tx.v tb/cpu_uart_tb.v; then
            uout=$(vvp cpu_uart.vvp)
            echo "$uout" | grep -E 'PASS|FAIL' | sed 's/^/   /'
            if echo "$uout" | grep -q 'CPU→UART PASS'; then
                pass=$((pass+1))
            else
                fail=$((fail+1))
            fi
        else
            echo "   编译失败"; fail=$((fail+1))
        fi
    else
        fail=$((fail+1))
    fi
fi
echo ""

# ---------------- IN 指令 ----------------
echo "=============================================="
echo " IN 指令：喂 11 22 33，A 应为 0x33"
echo "=============================================="
if command -v iverilog >/dev/null 2>&1; then
    if asm cnt_in; then
        cp programs/cnt_in.hex programs/prog.hex
        if iverilog -o cpu_in.vvp rtl/cpu.v tb/cpu_in_tb.v; then
            iout=$(vvp cpu_in.vvp)
            echo "$iout" | grep -E 'IN-PASS|IN-FAIL' | sed 's/^/   /'
            if echo "$iout" | grep -q 'IN-PASS'; then pass=$((pass+1)); else fail=$((fail+1)); fi
        else
            echo "   编译失败"; fail=$((fail+1))
        fi
    else
        fail=$((fail+1))
    fi
fi
echo ""

# ---------------- 串口回环（CPU 收 → 发）----------------
echo "=============================================="
echo " 串口回环：发 ABC，CPU 应原样回 ABC"
echo "=============================================="
if command -v iverilog >/dev/null 2>&1; then
    if asm echo_loop; then
        cp programs/echo_loop.hex programs/prog.hex
        if iverilog -o cpu_echo.vvp rtl/cpu.v rtl/uart_rx.v rtl/uart_tx.v rtl/in_buf.v tb/cpu_uart_echo_tb.v; then
            eout=$(vvp cpu_echo.vvp)
            echo "$eout" | grep -E 'ECHO PASS|ECHO FAIL' | sed 's/^/   /'
            if echo "$eout" | grep -q 'ECHO PASS'; then pass=$((pass+1)); else fail=$((fail+1)); fi
        else
            echo "   编译失败"; fail=$((fail+1))
        fi
    else
        fail=$((fail+1))
    fi
fi
echo ""

# ---------------- 监控程序（串口装载 → 执行）----------------
echo "=============================================="
echo " 监控程序：串口送 05 2A 08 0F FF，应执行并回 0x2A"
echo "=============================================="
if command -v iverilog >/dev/null 2>&1; then
    if asm monitor; then
        cp programs/monitor.hex programs/prog.hex
        if iverilog -o cpu_mon.vvp rtl/cpu.v rtl/uart_rx.v rtl/uart_tx.v rtl/in_buf.v tb/monitor_tb.v; then
            mout=$(vvp cpu_mon.vvp)
            echo "$mout" | grep -E 'MONITOR PASS|MONITOR FAIL' | sed 's/^/   /'
            if echo "$mout" | grep -q 'MONITOR PASS'; then pass=$((pass+1)); else fail=$((fail+1)); fi
        else
            echo "   编译失败"; fail=$((fail+1))
        fi
    else
        fail=$((fail+1))
    fi
fi
echo ""
echo "=============================================="
echo " 结果：通过 $pass 个，失败 $fail 个"
echo "=============================================="
[ "$fail" -eq 0 ] && exit 0 || exit 1