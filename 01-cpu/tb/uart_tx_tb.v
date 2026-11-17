// uart_tx_tb.v —— UART 发送器自测（自带接收解码，直接打印字符）
// 期望在终端看到：  Hi
//                   UART PASS
`timescale 1ns / 1ps

module uart_tx_tb;

    localparam integer CLKS_PER_BIT = 234;   // 27 MHz / 115200

    reg        clk, rst, tx_start;
    reg  [7:0] tx_data;
    wire       tx, tx_busy;

    integer errors;
    reg [7:0] got;

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) dut (
        .clk(clk), .rst(rst),
        .tx_start(tx_start), .tx_data(tx_data),
        .tx(tx), .tx_busy(tx_busy)
    );

    // 27 MHz → 周期 37.037 ns
    initial clk = 1'b0;
    always #18.518 clk = ~clk;

    // 接收一个字节（8N1，低位先）
    task recv_byte(output [7:0] b);
        integer i;
        begin
            @(negedge tx);                                    // 起始位下降沿
            repeat (CLKS_PER_BIT + CLKS_PER_BIT/2) @(posedge clk);  // 移到 bit0 中心
            for (i = 0; i < 8; i = i + 1) begin
                b[i] = tx;
                repeat (CLKS_PER_BIT) @(posedge clk);
            end
            repeat (CLKS_PER_BIT/2) @(posedge clk);            // 走到停止位中心
        end
    endtask

    // 发一个字节并自校验
    task send(input [7:0] d);
        begin
            while (tx_busy) @(posedge clk);
            @(posedge clk); #1;
            tx_data = d;
            tx_start = 1'b1;
            @(posedge clk); #1;
            tx_start = 1'b0;

            recv_byte(got);
            if (got !== d) begin
                $display("  FAIL: 期望 0x%02h 收到 0x%02h", d, got);
                errors = errors + 1;
            end else begin
                $write("%c", got);          // 打印解出来的字符
                $fflush();
            end
        end
    endtask

    initial begin
        errors   = 0;
        rst      = 1'b1;
        tx_start = 1'b0;
        tx_data  = 8'h00;

        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (5) @(posedge clk);

        // 检测空闲电平
        if (tx !== 1'b1) begin
            $display("  FAIL: 空闲时 tx 应为 1，实际 %b", tx);
            errors = errors + 1;
        end

        // 发送 "Hi\n"
        send(8'h48);   // 'H'
        send(8'h69);   // 'i'
        send(8'h0A);   // 换行

        $display("");
        if (errors == 0) $display("  UART PASS");
        else             $display("  UART FAIL （%0d 处错误）", errors);
        $finish;
    end

endmodule