// uart_rx.v —— 8N1 UART 接收器（纯 Verilog，无依赖）
//
// 用法：
//   rx 空闲为 1；检测到下降沿 = 起始位
//   在每位正中间采样（最稳）
//   收满 8 位 + 停止位后，rx_valid 拉高一拍，rx_data 有效
`timescale 1ns / 1ps

module uart_rx #(
    parameter integer CLKS_PER_BIT = 234
)(
    input wire       clk,
    input wire       rst,
    input wire       rx,
    output reg [7:0] rx_data,
    output reg       rx_valid
);

    localparam S_IDLE = 2'd0;
    localparam S_START = 2'd1;
    localparam S_DATA = 2'd2;
    localparam S_STOP = 2'd3;

    reg [1:0] state;
    reg [15:0] cnt;
    reg [2:0] bit_idx;
    reg [7:0] shreg;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            cnt <= 16'd0;
            bit_idx <= 3'd0;
            shreg <= 8'h00;
            rx_data <= 8'h00;
            rx_valid <= 1'b0;
        end else begin
            rx_valid <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (rx == 1'b0) begin
                        cnt <= 16'd0;
                        state <= S_START;
                    end
                end

                S_START: begin
                    if (cnt == CLKS_PER_BIT/2 - 1) begin
                        if (rx == 1'b0) begin
                            cnt <= 16'd0;
                            bit_idx <= 3'd0;
                            state <= S_DATA;
                        end else begin
                            state <= S_IDLE;
                        end
                    end else begin
                        cnt <= cnt + 16'd1;
                    end
                end

                S_DATA: begin
                    if (cnt == CLKS_PER_BIT - 1) begin
                        cnt <= 16'd0;
                        shreg[bit_idx] <= rx;
                        if (bit_idx == 3'd7) state <= S_STOP;
                        else                bit_idx <= bit_idx + 3'd1;
                    end else begin
                        cnt <= cnt + 16'd1;
                    end
                end

                S_STOP: begin
                    if (cnt == CLKS_PER_BIT - 1) begin
                        cnt <= 16'd0;
                        rx_data <= shreg;
                        rx_valid <= 1'b1;
                        state <= S_IDLE;
                    end else begin
                        cnt <= cnt + 16'd1;
                    end
                end
            endcase
        end
    end

endmodule