// monitor2_tb.v —— 喂统一帧协议的字节流给 monitor2，检查 CPU 的输出
//
// 字节流与期望输出来自 programs/monitor2_{frames,expect}.hex
// 由 tools/gen_monitor2_frames.py 生成（场景: load_run / ping / load_ff）
//
// 用法（kylin）：
//   iverilog -o /tmp/m2.vvp rtl/cpu.v rtl/uart_rx.v rtl/uart_tx.v rtl/in_buf.v tb/monitor2_tb.v
//   vvp /tmp/m2.vvp
`timescale 1ns / 1ps

module monitor2_tb;

    localparam integer CLKS_PER_BIT = 234;   // 27 MHz / 115200

    reg  clk, rst;
    reg  rx_line;                    // TB 发给 CPU

    wire [7:0] rx_data;
    wire       rx_valid;
    wire [7:0] in_data;
    wire       in_valid, in_ack;
    wire [7:0] out_data;
    wire       out_valid, halted;
    wire [7:0] dbg_pc, dbg_a, dbg_ir;
    wire       dbg_z;
    wire       tx_line, tx_busy;     // CPU 发回来

    cpu dut (
        .clk(clk), .rst(rst), .out_ready(~tx_busy),
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

    // ---- 测试向量 ----
    reg [7:0] fr [0:255];
    reg [7:0] ex [0:31];
    integer   n_frame, n_expect;
    integer   i, errors;
    reg [7:0] got;

    task send_byte(input [7:0] d);
        integer k;
        begin
            rx_line = 1'b0;                          // 起始位
            repeat (CLKS_PER_BIT) @(posedge clk);
            for (k = 0; k < 8; k = k + 1) begin
                rx_line = d[k];                      // 低位先
                repeat (CLKS_PER_BIT) @(posedge clk);
            end
            rx_line = 1'b1;                          // 停止位
            repeat (CLKS_PER_BIT) @(posedge clk);
        end
    endtask

    task recv_byte(output [7:0] b);
        integer k;
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

    integer si, ri;

    initial begin
        errors = 0;

        $readmemh("programs/monitor2_frames.hex", fr);
        $readmemh("programs/monitor2_expect.hex", ex);
        n_frame  = fr[0];
        n_expect = ex[0];

        $display("");
        $display("  发送 %0d 字节，期望 %0d 字节", n_frame, n_expect);

        rst     = 1'b1;
        rx_line = 1'b1;
        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (5) @(posedge clk);

        // ⚠️ 收发必须并发：
        //   CPU 处理一帧只要 1.5 µs，而 TB 发完最后一个字节要 87 µs，
        //   顺序"先发后收"会错过起始位（采样点错位 → 解出乱码）。
        fork
            // ---- 1) 发送整段字节流 ----
            begin
                for (si = 0; si < n_frame; si = si + 1)
                    send_byte(fr[1+si]);
            end

            // ---- 2) 同时等待 CPU 的输出 ----
            begin
                for (ri = 0; ri < n_expect; ri = ri + 1) begin
                    recv_byte(got);
                    if (got !== ex[1+ri]) begin
                        $display("  FAIL[%0d]: 期望 %02h，收到 %02h", ri, ex[1+ri], got);
                        errors = errors + 1;
                    end else begin
                        $display("  OK  [%0d]: %02h", ri, got);
                    end
                end
            end
        join

        $display("");
        if (errors == 0) $display("  MONITOR2 PASS");
        else             $display("  MONITOR2 FAIL（%0d 处错误）", errors);
        $finish;
    end

    // ---- 超时保护：8 ms（16 字节 ≈ 1.4 ms + 执行，留足余量）----
    initial begin
        #8000000;
        $display("");
        $display("  MONITOR2 TIMEOUT（等不到 CPU 输出）");
        $finish;
    end

endmodule