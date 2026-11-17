// cpu.v —— 8 位多周期 CPU（v0.1）
//
// 内存布局：256 x 8，程序从 0x00 开始，数据区建议 0x10 起
// 指令：见 isa.md
// 每个带操作数的指令占 3 拍（取指 / 取操作数 / 执行），单字节指令占 2 拍
//
// 这是"能看懂"优先的写法：一个 always 块，一个 case，状态机只有 4 个状态。

`timescale 1ns / 1ps

module cpu (
    input  wire       clk,
    input  wire       rst,
    input  wire       out_ready,  // OUT 握手：1 = 外设空闲，可接收
    input  wire [7:0] in_data,
    input  wire       in_valid,
    // 对外输出
    output reg  [7:0] out_data,   // OUT 指令的数据
    output reg        out_valid,  // OUT 时拉高一拍
    output reg        in_ack,
    output reg        halted,     // HLT 后为 1
    // 调试观察
    output wire [7:0] dbg_pc,
    output wire [7:0] dbg_a,
    output wire [7:0] dbg_ir,
    output wire       dbg_z
);

    // ---- 指令编码 ----
    localparam OP_NOP = 8'h00, OP_LDA = 8'h01, OP_STA = 8'h02, OP_ADD = 8'h03,
               OP_SUB = 8'h04, OP_LDI = 8'h05, OP_JMP = 8'h06, OP_JZ  = 8'h07,
               OP_OUT = 8'h08, OP_HLT = 8'h0F,
               OP_INC = 8'h09, OP_DEC = 8'h0A, OP_LDX = 8'h0B, OP_STX = 8'h0C,
               OP_IN = 8'h0D;

    // ---- 状态 ----
    localparam S_FETCH = 2'd0, S_EXEC = 2'd1, S_EXEC2 = 2'd2, S_STOP = 2'd3;

    reg [7:0] mem [0:255];
    reg [7:0] pc, a, ir, tmp;
    reg       z;
    reg [1:0] state;

    assign dbg_pc = pc;
    assign dbg_a  = a;
    assign dbg_ir = ir;
    assign dbg_z  = z;

    // ---- 程序装载 ----
    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1)
            mem[i] = 8'h00;
        $readmemh("programs/prog.hex", mem);  // 由 run.sh 把要跑的程序拷成 prog.hex
    end

    // ---- 主状态机 ----
    always @(posedge clk) begin
        if (rst) begin
            pc        <= 8'h00;
            a         <= 8'h00;
            ir        <= 8'h00;
            tmp       <= 8'h00;
            z         <= 1'b0;
            state     <= S_FETCH;
            halted    <= 1'b0;
            out_valid <= 1'b0;
            in_ack    <= 1'b0;
            out_data  <= 8'h00;
        end else if (!halted) begin
            case (state)
                // 第 1 拍：取指令
                S_FETCH: begin
                    ir        <= mem[pc];
                    pc        <= pc + 8'd1;
                    out_valid <= 1'b0;          // OUT 只亮一拍
                    in_ack    <= 1'b0;
                    state     <= S_EXEC;
                end

                // 第 2 拍：单字节指令直接执行；带操作数的先取操作数
                S_EXEC: begin
                    case (ir)
                        OP_NOP:  state <= S_FETCH;
                        OP_OUT:  if (out_ready) begin   // 外设忙就停在这拍等
                                     out_data  <= a;
                                     out_valid <= 1'b1;
                                     state     <= S_FETCH;
                                 end
                        OP_HLT:  begin
                                     halted <= 1'b1;
                                     state  <= S_STOP;
                                 end
                        OP_INC:  begin
                                     a <= a + 8'd1;
                                     z <= ((a + 8'd1) == 8'h00);
                                     state <= S_FETCH;
                                 end
                        OP_DEC:  begin
                                     a <= a - 8'd1;
                                     z <= ((a - 8'd1) == 8'h00);
                                     state <= S_FETCH;
                                 end
                        OP_IN:  if (in_valid) begin
                                     a <= in_data;
                                     z <= (in_data == 8'h00);
                                     in_ack <= 1'b1;
                                     state <= S_FETCH;
                                 end
                        default: begin              // 带操作数的指令
                                     tmp   <= mem[pc];
                                     pc    <= pc + 8'd1;
                                     state <= S_EXEC2;
                                 end
                    endcase
                end

                // 第 3 拍：用 tmp（操作数）执行
                S_EXEC2: begin
                    case (ir)
                        OP_LDI: begin
                                    a <= tmp;
                                    z <= (tmp == 8'h00);
                                end
                        OP_LDA: begin
                                    a <= mem[tmp];
                                    z <= (mem[tmp] == 8'h00);
                                end
                        OP_STA: mem[tmp] <= a;
                        OP_ADD: begin
                                    a <= a + mem[tmp];
                                    z <= ((a + mem[tmp]) == 8'h00);
                                end
                        OP_SUB: begin
                                    a <= a - mem[tmp];
                                    z <= ((a - mem[tmp]) == 8'h00);
                                end
                        OP_LDX: begin                       // 间接读：A = mem[mem[tmp]]
                                    a <= mem[mem[tmp]];
                                    z <= (mem[mem[tmp]] == 8'h00);
                                end
                        OP_STX: mem[mem[tmp]] <= a;         // 间接写
                        OP_JMP: pc <= tmp;
                        OP_JZ:  if (z) pc <= tmp;
                        default: ;                 // 非法指令：当 NOP
                    endcase
                    state <= S_FETCH;
                end

                S_STOP: state <= S_STOP;
            endcase
        end
    end

endmodule