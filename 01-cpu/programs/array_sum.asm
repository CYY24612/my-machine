; 数组求和：arr[0..4] = 1,2,3,4,5 → 15
; 用到 LDX（间接读）、INC、DEC

        LDI arr          ; A = 数组首地址
        STA ptr          ; ptr = 首地址
        LDI 0
        STA sum
        LDI 5
        STA cnt

loop:
        LDX ptr          ; A = mem[mem[ptr]] = 当前元素
        ADD sum          ; A = 元素 + 累加和
        STA sum
        LDA ptr
        INC              ; 指针 +1
        STA ptr
        LDA cnt
        DEC              ; 计数 -1
        STA cnt
        JZ  done
        JMP loop

done:
        LDA sum
        OUT
        HLT

        ORG 0x40
ptr:    DB 0
cnt:    DB 0
sum:    DB 0
        ORG 0x48
arr:    DB 1, 2, 3, 4, 5