; monitor.asm —— 极简监控程序（串口装载机器码 → 执行）
;
; 协议（极简）：
;   收到的每个字节依次存到 0x80 起
;   收到 0xFF 表示"装载结束" → 跳到 0x80 执行
;
; 用法示例：想跑 "LDI 42; OUT; HLT"，就依次发 05 2A 08 0F FF

        LDI 0x80
        STA ptr          ; ptr = 装载地址
        STA entry        ; entry = 入口地址
        LDI 0xFF
        STA term         ; term = 终止符

recv:
        IN               ; 等一个字节 → A
        STX ptr          ; mem[mem[ptr]] = A  （存到 0x80 + k）
        SUB term         ; A = 字节 - 0xFF
        JZ  run          ; 是终止符 → 去执行
        LDA ptr
        INC
        STA ptr          ; 装载地址 + 1
        JMP recv

run:
        JMPX entry       ; PC = mem[entry] = 0x80

        ORG 0x60
ptr:    DB 0
entry:  DB 0
term:   DB 0