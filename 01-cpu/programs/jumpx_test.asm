; jumpx_test.asm —— 验证间接跳转 JMPX
; 期望：跳到 0x40 执行 → A = 42，OUT 42

        LDI 0x40
        STA entry
        JMPX entry       ; PC = mem[entry] = 0x40

        LDI 0xEE         ; 不该走到这里
        OUT
        HLT

        ORG 0x40
target:
        LDI 42
        OUT
        HLT

        ORG 0x60
entry:  DB 0