// cpu_uart_tb.v —— CPU 通过 OUT 指令驱动 UART，把字符打印出来
// 期望终端看到：  Hi
//                 CPU→UART PASS（CPU 打印出了 Hi）
`timescale 1ns / 1ps

module cpu_uart_tb;

    localparam integer CLKS_PER_BIT = 234;   // 27 MHz / 115200

    reg        clk, rst;
    wire [7:0] out_data;
    wire       out_valid, halted;
    wire [7:0] dbg_pc, dbg_a, dbg_ir;
    wire       dbg_z;

    wire tx, tx_busy;
    wire out_ready = ~tx_busy;               // 握手：UART 空闲才能发

    cpu dut (
        .clk(clk), .rst(rst), .out_ready(out_ready),
        .out_data(out_data), .out_valid(out_valid), .halted(halted),
        .dbg_pc(dbg_pc), .dbg_a(dbg_a), .dbg_ir(dbg_ir), .dbg_z(dbg_z)
    );

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk(clk), .rst(rst),
        .tx_start(out_valid), .tx_data(out_data),
        .tx(tx), .tx_busy(tx_busy)
    );

    initial clk = 1'b0;
    always #18.518 clk = ~clk;

    integer   errors, nrecv;
    reg [7:0] ch;
    reg [7:0] expect_str [0:2];

    task recv_byte(output [7:0] b);
        integer i;
        begin
            @(negedge tx);
            repeat (CLKS_PER_BIT + CLKS_PER_BIT/2) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                b[i] = tx;
                repeat (CLKS_PER_BIT) @(posedge clk);
            end
            repeat (CLKS_PER_BIT/2) @(posedge clk);
        end
    endtask

    initial begin
        errors = 0; nrecv = 0;
        expect_str[0] = 8'h48;   // 'H'
        expect_str[1] = 8'h69;   // 'i'
        expect_str[2] = 8'h0A;   // 换行

        rst = 1'b1;
        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (5) @(posedge clk);

        repeat (3) begin
            recv_byte(ch);
            $write("%c", ch);
            $fflush();
            if (ch !== expect_str[nrecv]) begin
                $display("");
                $display("  FAIL: 第 %0d 个字节 期望 0x%02h 收到 0x%02h", nrecv, expect_str[nrecv], ch);
                errors = errors + 1;
            end
            nrecv = nrecv + 1;
        end

        if (errors == 0) $display("  CPU→UART PASS（CPU 打印出了 Hi）");
        else             $display("  CPU→UART FAIL（%0d 处错误）", errors);
        $finish;
    end

endmodule