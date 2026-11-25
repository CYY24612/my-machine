// in_buf.v —— 串口接收缓冲
// 作用：uart_rx 的 rx_valid 只亮一拍，CPU 可能来不及取（它可能正在执行别的指令）
//       这里把数据"挂住"，直到 CPU 用 in_ack 取走
`timescale 1ns / 1ps

module in_buf (
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] src_data,    // 来自 uart_rx
    input  wire       src_valid,   // 单拍脉冲
    output reg  [7:0] out_data,    // 给 CPU
    output reg        out_valid,   // 保持高，直到 ack
    input  wire       out_ack      // CPU 的 in_ack
);

    always @(posedge clk) begin
        if (rst) begin
            out_data  <= 8'h00;
            out_valid <= 1'b0;
        end else if (src_valid) begin
            out_data  <= src_data;
            out_valid <= 1'b1;
        end else if (out_ack) begin
            out_valid <= 1'b0;
        end
    end

endmodule