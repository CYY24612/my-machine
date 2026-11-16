// cpu_tb.v —— 纯 Verilog testbench
// 用法：vvp cpu_tb.vvp +EXPECT=8
//   程序由 programs/prog.hex 提供（run.sh 负责把要跑的程序拷过去）
`timescale 1ns / 1ps

module cpu_tb;

    reg clk, rst;
    wire [7:0] out_data;
    wire       out_valid, halted;
    wire [7:0] dbg_pc, dbg_a, dbg_ir;
    wire       dbg_z;

    cpu dut (
        .clk(clk), .rst(rst),
        .out_data(out_data), .out_valid(out_valid), .halted(halted),
        .dbg_pc(dbg_pc), .dbg_a(dbg_a), .dbg_ir(dbg_ir), .dbg_z(dbg_z)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer cycles;
    integer expect;

    initial begin
        // 期望值：默认 8（3+5），可用 +EXPECT=55 覆盖
        if (!$value$plusargs("EXPECT=%d", expect))
            expect = 8;

        cycles = 0;
        rst = 1;
        #12 rst = 0;

        while (!halted && cycles < 2000) begin
            @(posedge clk);
            cycles = cycles + 1;
            if (out_valid)
                $display("  OUT = %0d", out_data);
        end

        $display("");
        $display("  halted = %0d   cycles = %0d", halted, cycles);
        $display("  A      = %0d (0x%02h)   expect = %0d", dbg_a, dbg_a, expect);

        if (halted && dbg_a == expect[7:0])
            $display("  PASS");
        else
            $display("  FAIL");

        $finish;
    end

    initial begin
        $dumpfile("cpu_tb.vcd");
        $dumpvars(0, cpu_tb);
    end

endmodule