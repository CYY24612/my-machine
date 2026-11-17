; hello.asm —— CPU 通过 OUT 打印 "Hi"

        LDI 72          ; 'H'
        OUT
        LDI 105         ; 'i'
        OUT
        LDI 10          ; 换行
        OUT
        HLT