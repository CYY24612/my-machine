; 6 × 7 = 42   （用重复加法实现）
; 演示：标号 + ORG 数据区 + DB 初始化

        LDI 0
        STA result      ; result = 0
        LDI 6
        STA cnt         ; cnt = 6

loop:
        LDA result
        ADD seven       ; result += 7
        STA result
        LDA cnt
        SUB one         ; cnt -= 1
        STA cnt
        JZ  done        ; 如果 cnt-1 == 0 就跳出
        JMP loop

done:
        LDA result
        OUT             ; 输出 42
        HLT

; ---- 数据区放在程序之后，避免覆盖指令 ----
        ORG 0x20
cnt:    DB 0
result: DB 0
seven:  DB 7
one:    DB 1