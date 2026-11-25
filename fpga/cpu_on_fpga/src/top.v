// top.v —— 板级顶层：CPU + 双路 UART 发 + 一路 UART 收
//
// 目标（③ 的感知通道）：STM32 通过 UART 发数据给 CPU
//
// 发送：
//   uart_tx_A -> pin 17 -> 板载 USB-UART -> 电脑（调试观察）
//   uart_tx_B -> pin 26 -> 排针 -> STM32 PA3（控制）
//
// 接收：
//   pin 27 <- STM32 PA2 -> uart_rx -> in_buf -> CPU(in_data/in_valid/in_ack)
//
// 为什么要有 in_buf：
//   uart_rx 的 rx_valid 只亮一拍（37ns），CPU 可能正在执行别的指令来不及取。
//   in_buf 把数据"挂住"，直到 CPU 用 in_ack 取走。
`timescale 1ns / 1ps

module top (
    input  wire       sys_clk,       // 27 MHz，pin 52
    input  wire       btn_rst_n,     // 按键，pin 4，按下为 0
    input  wire       uart_rx_pin,   // pin 27 <- 排针 <- STM32 PA2 (USART2_TX)
    output wire [5:0] led,           // pin 10/11/13/14/15/16（低电平点亮）
    output wire       uart_dbg,      // pin 17 -> 板载 USB-UART -> 电脑
    output wire       uart_car       // pin 26 -> 排针 -> STM32 PA3 (USART2_RX)
);

    localparam integer CLKS_PER_BIT = 234;   // 27MHz / 115200

    // ---- 复位 ----
    reg [1:0] rst_sync = 2'b11;
    always @(posedge sys_clk)
        rst_sync <= {rst_sync[0], ~btn_rst_n};
    wire cpu_rst = rst_sync[1];

    // ---- CPU 接口 ----
    wire [7:0] out_data, dbg_pc, dbg_a, dbg_ir;
    wire       out_valid, halted, in_ack, dbg_z;

    // ---- 接收链路 ----
    wire [7:0] rx_byte;
    wire       rx_valid;
    wire [7:0] in_data_w;
    wire       in_valid_w;

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .clk      (sys_clk),
        .rst      (cpu_rst),
        .rx       (uart_rx_pin),
        .rx_data  (rx_byte),
        .rx_valid (rx_valid)
    );

    in_buf u_inbuf (
        .clk       (sys_clk),
        .rst       (cpu_rst),
        .src_data  (rx_byte),
        .src_valid (rx_valid),
        .out_data  (in_data_w),
        .out_valid (in_valid_w),
        .out_ack   (in_ack)
    );

    // ---- 发送链路（两路同数据）----
    wire tx_a, busy_a;
    wire tx_b, busy_b;
    wire out_ready = ~busy_a & ~busy_b;

    // ---- CPU ----
    cpu u_cpu (
        .clk       (sys_clk),
        .rst       (cpu_rst),
        .out_ready (out_ready),
        .in_data   (in_data_w),
        .in_valid  (in_valid_w),
        .out_data  (out_data),
        .out_valid (out_valid),
        .in_ack    (in_ack),
        .halted    (halted),
        .dbg_pc    (dbg_pc),
        .dbg_a     (dbg_a),
        .dbg_ir    (dbg_ir),
        .dbg_z     (dbg_z)
    );

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx_dbg (
        .clk      (sys_clk),
        .rst      (cpu_rst),
        .tx_start (out_valid),
        .tx_data  (out_data),
        .tx       (tx_a),
        .tx_busy  (busy_a)
    );

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx_car (
        .clk      (sys_clk),
        .rst      (cpu_rst),
        .tx_start (out_valid),
        .tx_data  (out_data),
        .tx       (tx_b),
        .tx_busy  (busy_b)
    );

    assign uart_dbg = tx_a;
    assign uart_car = tx_b;

    // ---- LED：显示 A 的低 6 位 ----
    // 程序是 IN; JMP 0 => A = 最后收到的字节 => LED 直接显示它
    assign led = dbg_a[5:0];

endmodule