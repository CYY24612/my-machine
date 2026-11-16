; 3 + 5 = 8
; 汇编好之后手动换成机器码，见 add.hex

    LDI 3        ; A = 3
    STA 0x10     ; mem[0x10] = 3
    LDI 5        ; A = 5
    ADD 0x10     ; A = 5 + 3 = 8
    OUT          ; 输出 8
    HLT          ; 停机