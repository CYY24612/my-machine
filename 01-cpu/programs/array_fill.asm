; 数组填充：把 4 个元素都写成 9，再读回第 0 个验证 → 9
; 用到 STX（间接写）、INC、DEC

        LDI arr
        STA ptr
        LDI 4
        STA cnt

loop:
        LDI 9
        STX ptr          ; mem[mem[ptr]] = 9
        LDA ptr
        INC
        STA ptr
        LDA cnt
        DEC
        STA cnt
        JZ  done
        JMP loop

done:
        LDI arr
        STA ptr
        LDX ptr          ; 读回第一个元素
        OUT
        HLT

        ORG 0x40
ptr:    DB 0
cnt:    DB 0
        ORG 0x48
arr:    DB 0, 0, 0, 0