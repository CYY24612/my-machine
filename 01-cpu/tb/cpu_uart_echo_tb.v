// cpu_uart_echo_tb.v —— 完整回环：TB 发 ABC，CPU 应原样发回 ABC
`timescale 1ns / 1ps

module cpu_uart_echo_tb;

    localparam integer CLKS_PER_BIT = 234;   // 27 MHz / 115200

    reg  clk, rst;
    reg  rx_line;                            // TB 发数据用这条线

    wire [7:0] rx_data;
    wire       rx_valid;

    wire [7:0] in_data;
    wire       in_valid, in_ack;

    wire [7:0] out_data;
    wire       out_valid, halted;
    wire [7:0] dbg_pc, dbg_a, dbg_ir;
    wire       dbg_z;

    wire tx_line, tx_busy;

    // ---- CPU ----
    cpu dut (
        .clk(clk), .rst(rst),
        .out_ready(~tx_busy),
        .in_data(in_data), .in_valid(in_valid), .in_ack(in_ack),
        .out_data(out_data), .out_valid(out_valid), .halted(halted),
        .dbg_pc(dbg_pc), .dbg_a(dbg_a), .dbg_ir(dbg_ir), .dbg_z(dbg_z)
    );

    // ---- 接收器 ----
    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .clk(clk), .rst(rst), .rx(rx_line),
        .rx_data(rx_data), .rx_valid(rx_valid)
    );

    // ---- 缓冲 ----
    in_buf u_buf (
        .clk(clk), .rst(rst),
        .src_data(rx_data), .src_valid(rx_valid),
        .out_data(in_data), .out_valid(in_valid), .out_ack(in_ack)
    );

    // ---- 发送器 ----
    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk(clk), .rst(rst),
        .tx_start(out_valid), .tx_data(out_data),
        .tx(tx_line), .tx_busy(tx_busy)
    );

    initial clk = 1'b0;
    always #18.518 clk = ~clk;

    integer   i, k, errors;
    reg [7:0] got;

    // ---- TB 发一个字节到 rx_line ----
    task send_byte(input [7:0] d);
        begin
            rx_line = 1'b0;                              // 起始位
            repeat (CLKS_PER_BIT) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                rx_line = d[i];                          // 数据位，低位先
                repeat (CLKS_PER_BIT) @(posedge clk);
            end
            rx_line = 1'b1;                              // 停止位
            repeat (CLKS_PER_BIT) @(posedge clk);
        end
    endtask

    // ---- TB 从 tx_line 解一个字节 ----
    task recv_byte(output [7:0] b);
        begin
            @(negedge tx_line);                          // 等起始位
            repeat (CLKS_PER_BIT + CLKS_PER_BIT/2) @(posedge clk);
            for (k = 0; k < 8; k = k + 1) begin
                b[k] = tx_line;
                repeat (CLKS_PER_BIT) @(posedge clk);
            end
            repeat (CLKS_PER_BIT/2) @(posedge clk);
        end
    endtask

    // ---- 发一个、收一个、比对 ----
    task test_byte(input [7:0] d);
        begin
            fork
                send_byte(d);
                recv_byte(got);
            join
            if (got !== d) begin
                $display("  FAIL: 期望 0x%02h 收到 0x%02h", d, got);
                errors = errors + 1;
            end else begin
                $display("  OK: 0x%02h  '%c'", got, got);
            end
        end
    endtask

    initial begin
        errors  = 0;
        rst     = 1'b1;
        rx_line = 1'b1;

        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (5) @(posedge clk);

        test_byte(8'h41);   // 'A'
        test_byte(8'h42);   // 'B'
        test_byte(8'h5A);   // 'Z'

        $display("");
        if (errors == 0) $display("  ECHO PASS（CPU 收到什么就发回了什么）");
        else             $display("  ECHO FAIL（%0d 处错误）", errors);
        $finish;
    end

endmodule