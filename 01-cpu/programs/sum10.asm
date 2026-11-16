; 1 + 2 + ... + 10 = 55
; 内存布局：
;   mem[0x20] = 计数器 i
;   mem[0x21] = 累加和 sum
;   mem[0x22] = 常数 1
; 注意：程序占 0x00~0x1F，数据必须放在 0x20 之后，不能重叠！

        LDI 1          ; A = 1
        STA 0x22       ; mem[0x22] = 1
        LDI 0          ; A = 0
        STA 0x21       ; sum = 0
        LDI 10         ; A = 10
        STA 0x20       ; i = 10

loop:
        LDA 0x21       ; A = sum
        ADD 0x20       ; A = sum + i
        STA 0x21       ; sum = A
        LDA 0x20       ; A = i
        SUB 0x22       ; A = i - 1   （这一句会更新 Z 标志）
        STA 0x20       ; i = A
        JZ  done       ; 如果 i-1 == 0 → 跳出
        JMP loop

done:
        LDA 0x21       ; A = sum
        OUT            ; 输出 55
        HLT