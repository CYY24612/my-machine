; servo_sweep.asm —— 我的 CPU 扫描舵机角度
;
; 行为：发角度 0 -> 180 -> 0 -> ... 循环，每步约 19ms
;
; ⚠️ 内存布局（必须避开程序区！程序占 0x00~0x46）
;   0xF0  当前角度
;   0xF1  方向（0=向上，1=向下）
;   0xF2  延时外层计数
;   0xF3  比较常量 181

        ORG 0

        ; ---- 初始化 ----
        LDI 0
        STA 0xF0          ; 角度 = 0
        STA 0xF1          ; 方向 = 0（向上）
        LDI 181
        STA 0xF3          ; 上界常量

main:
        LDA 0xF0          ; A = 当前角度
        OUT               ; 发送给 STM32

        ; ---- 延时约 19ms（两层嵌套）----
        LDI 255
d_outer:
        STA 0xF2
        LDI 255
d_inner:
        DEC
        JZ  d_inner_done
        JMP d_inner
d_inner_done:
        LDA 0xF2
        DEC
        JZ  d_outer_done
        JMP d_outer
d_outer_done:

        ; ---- 方向判断 ----
        LDA 0xF1
        JZ  step_up       ; 方向 == 0 -> 向上

        ; ===== 向下 =====
        LDA 0xF0
        DEC
        STA 0xF0
        JZ  at_zero
        JMP main

at_zero:
        LDI 0
        STA 0xF1          ; 方向改为向上
        JMP main

        ; ===== 向上 =====
step_up:
        LDA 0xF0
        INC
        STA 0xF0
        SUB 0xF3          ; A = (角度) - 181
        JZ  at_max
        JMP main

at_max:
        LDI 180
        STA 0xF0          ; 角度回到 180
        LDI 1
        STA 0xF1          ; 方向改为向下
        JMP main