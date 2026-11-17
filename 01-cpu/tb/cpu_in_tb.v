// cpu_in_tb.v —— 给 CPU 喂 3 个字节，检验 IN 指令
`timescale 1ns / 1ps

module cpu_in_tb;

    reg clk, rst;
    wire [7:0] out_data;
    wire       out_valid, halted;
    wire [7:0] dbg_pc, dbg_a, dbg_ir;
    wire       dbg_z;
    wire       in_ack;

    // 要喂的三个字节
    reg [7:0] q0, q1, q2;
    integer   idx;
    wire [7:0] in_data  = (idx == 0) ? q0 :
                          (idx == 1) ? q1 :
                          (idx == 2) ? q2 : 8'h00;
    wire       in_valid = (idx < 3);

    cpu dut (
        .clk(clk), .rst(rst), .out_ready(1'b1),
        .in_data(in_data), .in_valid(in_valid), .in_ack(in_ack),
        .out_data(out_data), .out_valid(out_valid), .halted(halted),
        .dbg_pc(dbg_pc), .dbg_a(dbg_a), .dbg_ir(dbg_ir), .dbg_z(dbg_z)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // CPU 每 ack 一次，指针 +1（换下一个字节）
    always @(posedge clk) begin
        if (in_ack) idx <= idx + 1;
    end

    integer cycles;
    initial begin
        q0 = 8'h11; q1 = 8'h22; q2 = 8'h33;
        idx = 0; cycles = 0;
        rst = 1'b1;
        #12 rst = 1'b0;

        while (!halted && cycles < 300) begin
            @(posedge clk);
            cycles = cycles + 1;
        end

        $display("");
        $display("  halted=%0d  cycles=%0d  A=0x%02h（期望 0x33）", halted, cycles, dbg_a);
        if (halted && dbg_a == 8'h33) $display("  IN-PASS");
        else                          $display("  IN-FAIL");
        $finish;
    end

endmodule