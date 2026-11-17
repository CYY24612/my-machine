; cnt_in.asm —— 读 3 个字节，第 3 个留在 A 里
; 预期：喂 11 22 33 → A = 0x33 = 51

        IN
        IN
        STA tmp
        IN
        HLT

        ORG 0x40
tmp:    DB 0