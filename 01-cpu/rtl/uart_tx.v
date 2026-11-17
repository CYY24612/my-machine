// uart_tx.v —— 8N1 UART 发送器（纯 Verilog，无依赖）
//
// 用法：
//   tx_start 拉高一拍 → 把 tx_data 按 8N1 发出去（低位先发）
//   tx_busy 期间不要再发（否则丢字节）
//
// 波特率：CLKS_PER_BIT = f_clk / baud
//   27 MHz / 115200 = 234.375 → 取 234（误差 0.16%，可接受）
`timescale 1ns / 1ps

module uart_tx #(
    parameter integer CLKS_PER_BIT = 234
)(
    input  wire       clk,
    input  wire       rst,        // 高有效，异步复位不对（同步即可）
    input  wire       tx_start,   // 单拍脉冲
    input  wire [7:0] tx_data,
    output reg        tx,         // 空闲为 1；起始位 0；停止位 1
    output reg        tx_busy
);

    localparam S_IDLE  = 2'd0;
    localparam S_START = 2'd1;
    localparam S_DATA  = 2'd2;
    localparam S_STOP  = 2'd3;

    reg [1:0]  state;
    reg [15:0] cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  shreg;

    always @(posedge clk) begin
        if (rst) begin
            state   <= S_IDLE;
            tx      <= 1'b1;
            tx_busy <= 1'b0;
            cnt     <= 16'd0;
            bit_idx <= 3'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    tx <= 1'b1;
                    if (tx_start) begin
                        shreg   <= tx_data;
                        tx_busy <= 1'b1;
                        cnt     <= 16'd0;
                        state   <= S_START;
                    end
                end

                S_START: begin
                    tx <= 1'b0;                       // 起始位
                    if (cnt == CLKS_PER_BIT - 1) begin
                        cnt     <= 16'd0;
                        bit_idx <= 3'd0;
                        state   <= S_DATA;
                    end else begin
                        cnt <= cnt + 16'd1;
                    end
                end

                S_DATA: begin
                    tx <= shreg[bit_idx];             // 低位先发
                    if (cnt == CLKS_PER_BIT - 1) begin
                        cnt <= 16'd0;
                        if (bit_idx == 3'd7) state <= S_STOP;
                        else                 bit_idx <= bit_idx + 3'd1;
                    end else begin
                        cnt <= cnt + 16'd1;
                    end
                end

                S_STOP: begin
                    tx <= 1'b1;                       // 停止位
                    if (cnt == CLKS_PER_BIT - 1) begin
                        cnt     <= 16'd0;
                        state   <= S_IDLE;
                        tx_busy <= 1'b0;
                    end else begin
                        cnt <= cnt + 16'd1;
                    end
                end
            endcase
        end
    end

endmodule