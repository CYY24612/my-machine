// uart_rx_tb.v —— UART 接收器自测
// testbench 自己按 UART 时序发字节，检查 rx 收得对不对
`timescale 1ns / 1ps

module uart_rx_tb;

    localparam integer CLKS_PER_BIT = 234;

    reg clk, rst, rx;
    wire [7:0] rx_data;
    wire rx_valid;

    integer errors, i;
    reg [7:0] cap;
    reg cap_flag;

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) dut (
        .clk(clk), .rst(rst), .rx(rx),
        .rx_data(rx_data), .rx_valid(rx_valid)
    );

    initial clk = 1'b0;
    always #18.518 clk = ~clk;

    always @(posedge clk) begin
        if (rx_valid) begin
            cap <= rx_data;
            cap_flag <= 1'b1;
        end
    end

    task send_byte(input [7:0] d);
        begin
            rx = 1'b0;
            repeat (CLKS_PER_BIT) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                rx = d[i];
                repeat (CLKS_PER_BIT) @(posedge clk);
            end
            rx = 1'b1;
            repeat (CLKS_PER_BIT) @(posedge clk);
        end
    endtask

    // 发一个字节并校验
    task check(input [7:0] d);
        begin
            cap_flag = 1'b0;
            send_byte(d);
            repeat (3) @(posedge clk);                   // 等一拍让 valid 落地
            if (cap_flag !== 1'b1) begin
                $display("  FAIL: 没收到 rx_valid（发的是 0x%02h）", d);
                errors = errors + 1;
            end else if (cap !== d) begin
                $display("  FAIL: 期望 0x%02h 收到 0x%02h", d, cap);
                errors = errors + 1;
            end else begin
                $display("  OK: 0x%02h  '%c'", cap, cap);
            end
        end
    endtask

    initial begin
        errors   = 0;
        cap_flag = 1'b0;
        cap      = 8'h00;
        rx       = 1'b1;
        rst      = 1'b1;

        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (5) @(posedge clk);

        check(8'h48);   // 'H'
        check(8'h69);   // 'i'
        check(8'h0A);   // 换行
        check(8'h55);   // 'U'

        $display("");
        if (errors == 0) $display("  UART-RX PASS");
        else             $display("  UART-RX FAIL （%0d 处错误）", errors);
        $finish;
    end

endmodule