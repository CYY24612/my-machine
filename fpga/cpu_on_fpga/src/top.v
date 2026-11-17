// top.v —— 板级顶层：CPU + 两路 UART
//
// 目标（③ 的第一步）：我的 CPU 向 STM32 发字符，点亮 STM32 的灯
//
// 双路 UART 设计：
//   uart_tx_A -> pin 17 -> 板载 USB-UART -> 电脑（调试观察）
//   uart_tx_B -> pin 26 -> 排针 -> STM32 PA10（控制）
//   两路发同样的字节。
//
//   好处：COM14 有输出但 STM32 没反应 => 问题在接线/STM32 侧，不是 CPU。
`timescale 1ns / 1ps

module top (
    input  wire       sys_clk,     // 27 MHz，pin 52
    input  wire       btn_rst_n,   // 按键，pin 4，按下为 0
    output wire [5:0] led,         // pin 10/11/13/14/15/16（低电平点亮）
    output wire       uart_dbg,    // pin 17 -> 板载 USB-UART -> 电脑
    output wire       uart_car     // pin 26 -> 排针 -> STM32
);

    localparam integer CLKS_PER_BIT = 234;   // 27MHz / 115200

    // ---- 复位 ----
    reg [1:0] rst_sync = 2'b11;
    always @(posedge sys_clk)
        rst_sync <= {rst_sync[0], ~btn_rst_n};
    wire cpu_rst = rst_sync[1];

    // ---- CPU ----
    wire [7:0] out_data, dbg_pc, dbg_a, dbg_ir;
    wire       out_valid, halted, in_ack, dbg_z;

    // ---- 两路 UART ----
    wire tx_a, busy_a;
    wire tx_b, busy_b;

    // 两路都空闲才能发下一个字节
    wire out_ready = ~busy_a & ~busy_b;

    cpu u_cpu (
        .clk       (sys_clk),
        .rst       (cpu_rst),
        .out_ready (out_ready),
        .in_data   (8'h00),
        .in_valid  (1'b0),
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

    // ---- LED：显示 A 的低 6 位（诊断）----
    // 程序是死循环，A 恒为 72 = 0x48 -> led[5:0] = 001000（只有 led[3] 输出 1 = 灭）
    assign led = dbg_a[5:0];

endmodule