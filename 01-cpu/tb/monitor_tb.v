// monitor_tb.v —— 监控程序自测：串口送机器码，CPU 执行后把结果 OUT 回来
//
// 送的字节：05 2A 08 0F FF
//   = LDI 42 ; OUT ; HLT ; 终止符
// 期望收到：2A（=42）
`timescale 1ns / 1ps

module monitor_tb;

    localparam integer CLKS_PER_BIT = 234;

    reg  clk, rst;
    reg  rx_line;

    wire [7:0] rx_data;
    wire       rx_valid;
    wire [7:0] in_data;
    wire       in_valid, in_ack;
    wire [7:0] out_data;
    wire       out_valid, halted;
    wire [7:0] dbg_pc, dbg_a, dbg_ir;
    wire       dbg_z;
    wire tx_line, tx_busy;

    cpu dut (
        .clk(clk), .rst(rst),
        .out_ready(~tx_busy),
        .in_data(in_data), .in_valid(in_valid), .in_ack(in_ack),
        .out_data(out_data), .out_valid(out_valid), .halted(halted),
        .dbg_pc(dbg_pc), .dbg_a(dbg_a), .dbg_ir(dbg_ir), .dbg_z(dbg_z)
    );

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .clk(clk), .rst(rst), .rx(rx_line),
        .rx_data(rx_data), .rx_valid(rx_valid)
    );

    in_buf u_buf (
        .clk(clk), .rst(rst),
        .src_data(rx_data), .src_valid(rx_valid),
        .out_data(in_data), .out_valid(in_valid), .out_ack(in_ack)
    );

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk(clk), .rst(rst),
        .tx_start(out_valid), .tx_data(out_data),
        .tx(tx_line), .tx_busy(tx_busy)
    );

    initial clk = 1'b0;
    always #18.518 clk = ~clk;

    integer   i, k, errors;
    reg [7:0] got;

    task send_byte(input [7:0] d);
        begin
            rx_line = 1'b0;
            repeat (CLKS_PER_BIT) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                rx_line = d[i];
                repeat (CLKS_PER_BIT) @(posedge clk);
            end
            rx_line = 1'b1;
            repeat (CLKS_PER_BIT) @(posedge clk);
        end
    endtask

    task recv_byte(output [7:0] b);
        begin
            @(negedge tx_line);
            repeat (CLKS_PER_BIT + CLKS_PER_BIT/2) @(posedge clk);
            for (k = 0; k < 8; k = k + 1) begin
                b[k] = tx_line;
                repeat (CLKS_PER_BIT) @(posedge clk);
            end
            repeat (CLKS_PER_BIT/2) @(posedge clk);
        end
    endtask

    initial begin
        errors  = 0;
        rst     = 1'b1;
        rx_line = 1'b1;

        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (5) @(posedge clk);

        // 装载用户程序：LDI 42 ; OUT ; HLT
        send_byte(8'h05);
        send_byte(8'h2A);
        send_byte(8'h08);
        send_byte(8'h0F);

        // 最后一个字节 + 等结果并行
        fork
            send_byte(8'hFF);
            recv_byte(got);
        join

        if (got !== 8'h2A) begin
            $display("  FAIL: 期望 0x2A 收到 0x%02h", got);
            errors = errors + 1;
        end else begin
            $display("  OK: 收到 0x2A（用户程序被执行了）");
        end

        $display("");
        if (errors == 0) $display("  MONITOR PASS（串口装载机器码 → CPU 执行）");
        else             $display("  MONITOR FAIL");
        $finish;
    end

endmodule