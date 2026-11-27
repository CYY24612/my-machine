
H0:
        IN
        SUB C_AA
        JZ H1
        JMP H0

H1:
        IN
        SUB C_55
        JZ S2
        JMP H0

S2:
        IN
        STA TY
        STA CK

S3:
        IN
        STA LN
        ADD CK
        STA CK
        LDA LN
        STA CN

        LDA CN
        JZ  S5

S3A:
        IN
        STA AD
        ADD CK
        STA CK
        LDA CN
        DEC
        STA CN
        JZ S5

S4:
        IN
        STA T0
        ADD CK
        STA CK
        LDA T0
        STX AD
        LDA AD
        INC
        STA AD
        JZ H0

        LDA CN
        DEC
        STA CN
        JZ S5
        JMP S4

S5:     IN
        SUB CK              ; A = 收到的 CHK - 算出的 CK
        JZ  S5O
        JMP H0              ; 校验失败 → 丢整帧

S5O:    LDA TY
        SUB C_TPING
        JZ  PING

        LDA TY
        SUB C_TRUN
        JZ  RUN

        JMP H0              ; 其他类型（LOAD 成功后）→ 回去等下一帧

PING:   LDI 0xA5
        OUT
        JMP H0

RUN:    LDA AD
        STA SLOT
        JMPX SLOT           ; PC = mem[SLOT] = 入口地址

        ORG 0x70
C_AA:   DB 0xAA
C_55:   DB 0x55
C_TPING:   DB 0x06
C_TRUN:   DB 0x05
C_A5:   DB 0xA5

        ORG 0x78
TY:     DB 0
LN:     DB 0
CN:     DB 0
AD:     DB 0
CK:     DB 0
T0:     DB 0
SLOT:   DB 0