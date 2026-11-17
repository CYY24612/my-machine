// top.v —— 板级顶层：把 cpu.v 原样包起来，不改 cpu.v 一个字
// 目标：add 程序跑完后，6 个 LED 显示 A 的值（3+5=8 → 001000）
`timescale 1ns / 1ps

module top (
    input  wire       sys_clk,     // 27 MHz，pin 52
    input  wire       btn_rst_n,   // 按键 S1，pin 4，按下为 0
    output wire [5:0] led          // pin 10/11/13/14/15/16
);

    // ---- 复位：按键低有效，cpu 的 rst 是高有效，所以要取反 ----
    // 上电先保持 2 拍复位，避免寄存器初值不确定
    reg [1:0] rst_sync = 2'b11;
    always @(posedge sys_clk)
        rst_sync <= {rst_sync[0], ~btn_rst_n};

    wire cpu_rst = rst_sync[1];

    // ---- CPU 实例 ----
    wire [7:0] dbg_pc, dbg_a, dbg_ir;
    wire       dbg_z, out_valid, halted;
    wire [7:0] out_data;

    cpu u_cpu (
        .clk       (sys_clk),
        .rst       (cpu_rst),
        .out_data  (out_data),
        .out_valid (out_valid),
        .halted    (halted),
        .dbg_pc    (dbg_pc),
        .dbg_a     (dbg_a),
        .dbg_ir    (dbg_ir),
        .dbg_z     (dbg_z)
    );

    // ---- LED 显示累加器 A 的低 6 位 ----
    assign led = dbg_a[5:0];

endmodule