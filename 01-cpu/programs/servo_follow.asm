; servo_follow.asm —— 我的 CPU 根据超声波距离控制舵机角度
;
; 行为：角度 = 180 - 距离
;   手远(60cm) -> 角度 120
;   手近(20cm) -> 角度 160
;
; 数据地址 0xF0 避开程序区（程序只占 0x00~0x09）

        ORG 0

loop:
        IN                ; A = 从 STM32 收到的距离（cm）
        STA 0xF0          ; 存起来
        LDI 180           ; A = 180
        SUB 0xF0          ; A = 180 - 距离 = 舵机角度
        OUT               ; 发给 STM32 -> TIM4_CH4 PWM -> 舵机
        JMP loop