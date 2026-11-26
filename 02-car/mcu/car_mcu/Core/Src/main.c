/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file           : main.c
  * @brief          : Main program body
  ******************************************************************************
  * @attention
  *
  * Copyright (c) 2026 STMicroelectronics.
  * All rights reserved.
  *
  * This software is licensed under terms that can be found in the LICENSE file
  * in the root directory of this software component.
  * If no LICENSE file comes with this software, it is provided AS-IS.
  *
  ******************************************************************************
  */
/* USER CODE END Header */
/* Includes ------------------------------------------------------------------*/
#include "main.h"
#include "tim.h"
#include "usart.h"
#include "gpio.h"

/* Private includes ----------------------------------------------------------*/
/* USER CODE BEGIN Includes */
#include <stdio.h>

/* USER CODE END Includes */

/* Private typedef -----------------------------------------------------------*/
/* USER CODE BEGIN PTD */

/* USER CODE END PTD */

/* Private define ------------------------------------------------------------*/
/* USER CODE BEGIN PD */

/* USER CODE END PD */

/* Private macro -------------------------------------------------------------*/
/* USER CODE BEGIN PM */

/* USER CODE END PM */

/* Private variables ---------------------------------------------------------*/

/* USER CODE BEGIN PV */
static const uint8_t kDummy[8] = { 0xAA, 0x55, 0x06, 0x81, 0x01, 0x0E, 0x03, 0x00 };
volatile uint8_t g_tick_100ms= 0;
volatile uint8_t g_loss_cnt = 0;

uint8_t g_rx2 = 0;
uint8_t g_tx_cnt = 0;

volatile uint32_t g_dist_cm = 0;
volatile uint32_t g_raw_us = 0;

/* ---- 距离滤波：最近 3 次有效值 + 中值 ---- */
uint16_t g_dbuf[3] = { 0, 0, 0 };
uint8_t  g_didx = 0;
uint8_t  g_dcount = 0;
int16_t  g_last_sent = -100;        /* 上次发给 CPU 的距离，-100 = 还没发过 */

uint16_t g_servo_ang = 0;
uint8_t g_servo_dir = 1;
/* USER CODE END PV */

/* Private function prototypes -----------------------------------------------*/
void SystemClock_Config(void);
/* USER CODE BEGIN PFP */

/* USER CODE END PFP */

/* Private user code ---------------------------------------------------------*/
/* USER CODE BEGIN 0 */

/* 三个数取中值：天然抗离群值（比平均值好，不会被单个坏值带偏） */
static uint16_t median3(uint16_t a, uint16_t b, uint16_t c)
{
    if ((a <= b) && (b <= c)) return b;
    if ((c <= b) && (b <= a)) return b;
    if ((b <= a) && (a <= c)) return a;
    if ((c <= a) && (a <= b)) return a;
    return c;
}
static uint32_t hcsr04_read_cm(void)
{
    uint32_t t0, t1;

    HAL_GPIO_WritePin(TRIG_GPIO_Port, TRIG_Pin, GPIO_PIN_SET);
    t0 = __HAL_TIM_GET_COUNTER(&htim3);
    while (__HAL_TIM_GET_COUNTER(&htim3) - t0 < 15) {
        /* 等待 10us */
    }
    HAL_GPIO_WritePin(TRIG_GPIO_Port, TRIG_Pin, GPIO_PIN_RESET);

    t0 = __HAL_TIM_GET_COUNTER(&htim3);
    while (HAL_GPIO_ReadPin(ECHO_GPIO_Port, ECHO_Pin) == GPIO_PIN_RESET) {
        if ((__HAL_TIM_GET_COUNTER(&htim3) - t0) > 5000) return 999;
    }

    t0 = __HAL_TIM_GET_COUNTER(&htim3);
    while (HAL_GPIO_ReadPin(ECHO_GPIO_Port, ECHO_Pin) == GPIO_PIN_SET) {
        if ((__HAL_TIM_GET_COUNTER(&htim3) - t0) > 30000) return 998;
    }

    t1 = __HAL_TIM_GET_COUNTER(&htim3);
    g_raw_us = t1 - t0;
    return g_raw_us / 58;  /* cm */
}
/* USER CODE END 0 */

/**
  * @brief  The application entry point.
  * @retval int
  */
int main(void)
{

  /* USER CODE BEGIN 1 */

  /* USER CODE END 1 */

  /* MCU Configuration--------------------------------------------------------*/

  /* Reset of all peripherals, Initializes the Flash interface and the Systick. */
  HAL_Init();

  /* USER CODE BEGIN Init */

  /* USER CODE END Init */

  /* Configure the system clock */
  SystemClock_Config();

  /* USER CODE BEGIN SysInit */

  /* USER CODE END SysInit */

  /* Initialize all configured peripherals */
  MX_GPIO_Init();
  MX_TIM2_Init();
  MX_USART1_UART_Init();
  MX_USART2_UART_Init();
  MX_TIM4_Init();
  MX_TIM3_Init();
  /* USER CODE BEGIN 2 */
  HAL_TIM_Base_Start_IT(&htim2);
  HAL_UART_Receive_IT(&huart2, &g_rx2, 1);
  HAL_GPIO_WritePin(GPIOC, GPIO_PIN_13, GPIO_PIN_SET);
  
  HAL_TIM_PWM_Start(&htim4, TIM_CHANNEL_4);
  __HAL_TIM_SET_COMPARE(&htim4, TIM_CHANNEL_4, 1500);

  HAL_TIM_Base_Start(&htim3);  /* 用于测距的定时器 */
  /* USER CODE END 2 */

  /* Infinite loop */
  /* USER CODE BEGIN WHILE */
  while (1)
  {
    /* USER CODE END WHILE */

    /* USER CODE BEGIN 3 */
    if (g_tick_100ms) {
        g_tick_100ms = 0;

        /* ---- 1. 测距 ---- */
        g_dist_cm = hcsr04_read_cm();

        /* ---- 2. 调试输出（原始值）---- */
        char buf[40];
        int n = snprintf(buf, sizeof(buf), "d=%lu w=%lu\r\n",
                         (unsigned long)g_dist_cm,
                         (unsigned long)g_raw_us);
        if (n > 0) HAL_UART_Transmit(&huart1, (uint8_t *)buf, n, 100);

        /* ---- 3. 只处理有效测量（失败就不发，舵机保持原位）---- */
        if (g_dist_cm < 998) {

            /* 3.1 进环形缓冲 */
            g_dbuf[g_didx] = (uint16_t)g_dist_cm;
            g_didx = (uint8_t)((g_didx + 1) % 3);
            if (g_dcount < 3) g_dcount++;

            /* 3.2 攒满 3 个取中值 */
            if (g_dcount >= 3) {
                uint16_t med = median3(g_dbuf[0], g_dbuf[1], g_dbuf[2]);
                uint8_t  d   = (med > 180) ? 180 : (uint8_t)med;

                /* 3.3 死区：变化 >= 3cm 才发，减少抖动 */
                int16_t diff = (int16_t)d - g_last_sent;
                if (diff < 0) diff = (int16_t)(-diff);

                if (g_last_sent < 0 || diff >= 3) {
                    g_last_sent = (int16_t)d;
                    HAL_UART_Transmit(&huart2, &d, 1, 10);
                }
            }
        }
    }
  }
    /* USER CODE END 3 */
}

/**
  * @brief System Clock Configuration
  * @retval None
  */
void SystemClock_Config(void)
{
  RCC_OscInitTypeDef RCC_OscInitStruct = {0};
  RCC_ClkInitTypeDef RCC_ClkInitStruct = {0};

  /** Initializes the RCC Oscillators according to the specified parameters
  * in the RCC_OscInitTypeDef structure.
  */
  RCC_OscInitStruct.OscillatorType = RCC_OSCILLATORTYPE_HSE;
  RCC_OscInitStruct.HSEState = RCC_HSE_ON;
  RCC_OscInitStruct.HSEPredivValue = RCC_HSE_PREDIV_DIV1;
  RCC_OscInitStruct.HSIState = RCC_HSI_ON;
  RCC_OscInitStruct.PLL.PLLState = RCC_PLL_ON;
  RCC_OscInitStruct.PLL.PLLSource = RCC_PLLSOURCE_HSE;
  RCC_OscInitStruct.PLL.PLLMUL = RCC_PLL_MUL9;
  if (HAL_RCC_OscConfig(&RCC_OscInitStruct) != HAL_OK)
  {
    Error_Handler();
  }

  /** Initializes the CPU, AHB and APB buses clocks
  */
  RCC_ClkInitStruct.ClockType = RCC_CLOCKTYPE_HCLK|RCC_CLOCKTYPE_SYSCLK
                              |RCC_CLOCKTYPE_PCLK1|RCC_CLOCKTYPE_PCLK2;
  RCC_ClkInitStruct.SYSCLKSource = RCC_SYSCLKSOURCE_PLLCLK;
  RCC_ClkInitStruct.AHBCLKDivider = RCC_SYSCLK_DIV1;
  RCC_ClkInitStruct.APB1CLKDivider = RCC_HCLK_DIV2;
  RCC_ClkInitStruct.APB2CLKDivider = RCC_HCLK_DIV1;

  if (HAL_RCC_ClockConfig(&RCC_ClkInitStruct, FLASH_LATENCY_2) != HAL_OK)
  {
    Error_Handler();
  }
}

/* USER CODE BEGIN 4 */
void HAL_TIM_PeriodElapsedCallback(TIM_HandleTypeDef *htim)
{
  if (htim->Instance == TIM2) {
    g_tick_100ms = 1;
  
    /* ---- 失联保护：300ms 没收到新角度就关脉宽 ---- */
    if (g_loss_cnt < 255) {
      g_loss_cnt++;
    } 
    if (g_loss_cnt >= 20)   /* 2 秒（有死区，故意不发是正常的） */ {
      __HAL_TIM_SET_COMPARE(&htim4, TIM_CHANNEL_4, 0);
    }
  }
}

void HAL_UART_RxCpltCallback(UART_HandleTypeDef *huart)
{
    if (huart->Instance == USART2) {
      static uint8_t n = 0;

      g_loss_cnt = 0;
      uint32_t ang = g_rx2;
      if (ang > 180) ang = 180;
      __HAL_TIM_SET_COMPARE(&htim4, TIM_CHANNEL_4, 500 + (ang * 2000) / 180);

      if (++n >= 20) { n = 0; HAL_GPIO_TogglePin(GPIOC, GPIO_PIN_13); }
      
      g_rx2 = 0;
      HAL_UART_Receive_IT(&huart2, &g_rx2, 1);
    }
}
/* USER CODE END 4 */

/**
  * @brief  This function is executed in case of error occurrence.
  * @retval None
  */
void Error_Handler(void)
{
  /* USER CODE BEGIN Error_Handler_Debug */
  /* User can add his own implementation to report the HAL error return state */
  __disable_irq();
  while (1)
  {
  }
  /* USER CODE END Error_Handler_Debug */
}
#ifdef USE_FULL_ASSERT
/**
  * @brief  Reports the name of the source file and the source line number
  *         where the assert_param error has occurred.
  * @param  file: pointer to the source file name
  * @param  line: assert_param error line source number
  * @retval None
  */
void assert_failed(uint8_t *file, uint32_t line)
{
  /* USER CODE BEGIN 6 */
  /* User can add his own implementation to report the file name and line number,
     ex: printf("Wrong parameters value: file %s on line %d\r\n", file, line) */
  /* USER CODE END 6 */
}
#endif /* USE_FULL_ASSERT */
