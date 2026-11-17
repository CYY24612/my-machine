// top.v —— 板级顶层：把 cpu.v + uart_tx.v 包起来，不改 cpu.v 一个字
//
// 目标：hello 程序通过 OUT 指令驱动 UART，在串口上打印 "Hi"
// 板：Tang Nano 9K（GW1NR-9C，27MHz）
//
// 关键设计：
//   out_ready = ~tx_busy  ← 握手。CPU 一个 OUT 只花 2 拍，
//                            而 UART 发一个字节要 2340 拍，不握手会丢字节。
`timescale 1ns / 1ps

module top (
    input  wire       sys_clk,     // 27 MHz，pin 52
    input  wire       btn_rst_n,   // 按键，pin 4，按下为 0
    output wire [5:0] led,         // pin 10/11/13/14/15/16（低电平点亮）
    output wire       uart_tx      // pin 17 -> 板载 USB-UART
);

    localparam integer CLKS_PER_BIT = 234;   // 27MHz / 115200 = 234.375 -> 234

    // ---- 复位：按键低有效，cpu 的 rst 是高有效 ----
    // 上电先保持 2 拍复位，避免寄存器初值不确定
    reg [1:0] rst_sync = 2'b11;
    always @(posedge sys_clk)
        rst_sync <= {rst_sync[0], ~btn_rst_n};
    wire cpu_rst = rst_sync[1];

    // ---- CPU ----
    wire [7:0] out_data, dbg_pc, dbg_a, dbg_ir;
    wire       out_valid, halted, in_ack, dbg_z;

    // ---- UART ----
    wire tx, tx_busy;
    wire out_ready = ~tx_busy;      // UART 空闲才能发

    cpu u_cpu (
        .clk       (sys_clk),
        .rst       (cpu_rst),
        .out_ready (out_ready),
        .in_data   (8'h00),         // 本轮不做接收，固定 0
        .in_valid  (1'b0),          // 永远没有输入数据
        .out_data  (out_data),
        .out_valid (out_valid),
        .in_ack    (in_ack),
        .halted    (halted),
        .dbg_pc    (dbg_pc),
        .dbg_a     (dbg_a),
        .dbg_ir    (dbg_ir),
        .dbg_z     (dbg_z)
    );

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk      (sys_clk),
        .rst      (cpu_rst),
        .tx_start (out_valid),
        .tx_data  (out_data),
        .tx       (tx),
        .tx_busy  (tx_busy)
    );

    assign uart_tx = tx;

    // ---- LED 显示累加器 A 的低 6 位（低电平点亮）----
    // hello 跑完 A = 0x0A = 10 -> led[5:0] = 001010
    // 这是一个诊断值：LED 显示 10 说明 CPU 跑完了，问题只在 UART
    assign led = dbg_a[5:0];

endmodule