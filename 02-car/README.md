# 02-car —— 我的车，我的遥控器（交汇点 ①）

> 目标：一个上位机（Qt）通过串口控制下位机（STM32）的舵机、读回超声波距离。
> 起点不是小车，是**舵机 + 超声波**（零采购）；底盘/电机等到交汇点 ③ 之前再买。
> 建立：2026-11-14　**B1 打通：2026-11-16**

---

## 一、目录

```
02-car/
├── pc/                         Qt 上位机（A 阶段已可运行）
│   ├── CMakeLists.txt
│   ├── build.ps1               一键编译
│   ├── run.ps1                 一键运行 / -Test 跑单测
│   ├── src/
│   │   ├── main.cpp
│   │   ├── protocol/           协议层（零 Qt 依赖，可单测）
│   │   ├── source/             数据源层（ICarSource / FakeCar / SerialCar）
│   │   ├── app/                应用层（CarController，状态机）
│   │   └── ui/                 界面层（MainWindow）
│   └── tests/test_protocol.cpp 协议单测（68 条断言）
└── mcu/
    └── car_mcu/                STM32 固件（CubeMX + Keil）
        ├── Core/Src/main.c     ← B1 代码在这四个 USER CODE 块里
        ├── Core/Src/tim.c      TIM2 配置（PSC=7199, ARR=999）
        ├── Core/Src/usart.c    USART1 配置（115200 8N1, PA9/PA10）
        └── MDK-ARM/car_mcu.uvprojx
```

**依赖方向（单向，不许反向）**：

```
ui → app → source → protocol
```

自检：`protocol.cpp` 里应出现 **0 个** `#include <Q...>`；`ui/` 里应出现 **0 个** `#include "SerialCar.h"`。

---

## 二、协议 v0.1

### 帧格式

```
AA 55 | LEN | CMD | SEQ | PAYLOAD(N) | CRC8
 2B     1B    1B    1B      N B         1B
```

- `LEN` = 1(CMD) + 1(SEQ) + N（不含帧头、不含 CRC）
- `CRC8` = **CRC-8/MAXIM**，覆盖 `LEN..PAYLOAD`
  - poly=0x31 init=0x00 refin=true refout=true xorout=0x00
  - **自检值：`crc("123456789") == 0xA1`**
- 多字节字段一律**小端**

### 命令表

| 方向 | CMD | 名称 | 负载 |
|---|---|---|---|
| 下行 | `0x01` | `SET_SERVO` | `uint16 angle_x10`（0..1800） |
| 下行 | `0x02` | `SET_MODE` | `uint8 mode`（0 待机 / 1 遥控 / 2 扫描） |
| 下行 | `0x0F` | `ESTOP` | 空 |
| 下行 | `0x10` | `PING` | 空 |
| 上行 | `0x81` | `STATUS` | `uint16 servo_x10` + `uint16 dist_mm` + `uint8 err` |
| 上行 | `0x8F` | `EVENT` | `uint8 code`（1 失联停机 / 2 急停 / 3 堵转） |

### 三条设计约定

1. **不做请求-应答（无 ACK）**。遥控链路要的是低延迟，不是可靠性确认。
2. **失联保护在车端**：超过 **300 ms** 没收到合法下行帧 → 自动停机 + 发 `EVENT(1)`。
3. **急停是独立命令**（`0x0F`，零负载），收到即锁死，需重连才解除。

---

## 三、构建与运行

```powershell
cd E:\myProject\my-machine\02-car\pc

.\build.ps1          # 配置 + 编译（已配置则跳过配置）
.\build.ps1 -Clean   # 删 build 彻底重来（AUTOMOC 缓存异常时用）
.\run.ps1            # 跑界面
.\run.ps1 -Test      # 跑协议单测
```

**环境**：Qt 5.12.9 + 自带 MinGW 7.3.0 64-bit
- Qt：`E:\SoftWare\QT\Qt5.12.9\5.12.9\mingw73_64`
- MinGW：`E:\SoftWare\QT\Qt5.12.9\Tools\mingw730_64\bin`

---

## 四、STM32 硬件的实际配置（B1 验证过）

| 项 | 值 |
|---|---|
| 芯片 | STM32F103C8T6（Blue Pill，64KB Flash / 20KB RAM） |
| 时钟 | HSE 8MHz → PLL ×9 → **SYSCLK 72MHz**；APB1 Timer clocks **72MHz** |
| 定时器 | **TIM2**：PSC=**7199**、ARR=**999** → 10Hz = **100ms**；**NVIC 已使能** |
| 串口 | **USART1**：115200 / 8N1 / **PA9=TX** / **PA10=RX** |
| 代码量 | Code 4304B（6.6%）/ RAM 1776B（8.7%） |
| 烧录 | ST-Link V2（SWD），`Verify OK` |
| 通信 | **CP2102 模块 → COM11** |

### 接线（实测能通）

```
CP2102 RXD  →  Blue Pill A9  (PA9, USART1_TX)
CP2102 TXD  →  Blue Pill A10 (PA10, USART1_RX)
CP2102 GND  →  Blue Pill G
CP2102 VCC  →  不接（CP2102 由 USB 供电；Blue Pill 由 ST-Link 3.3V 供电）

ST-Link 3.3V/SWDIO/SWCLK/GND → Blue Pill 4 针排针 3.3/DIO/CLK/GND
```

⚠️ **只用一个电源**：ST-Link 的 3.3V 给 Blue Pill，CP2102 的 VCC **悬空**，否则两个电源对灌。

---

## 五、阶段进度

| 阶段 | 内容 | 状态 |
|---|---|---|
| **A** | `ICarSource` + `FakeCar` + 界面 | ✅ **2026-11-14** |
| **B1** | STM32 发固定字节 → PC 收到 | ✅ **2026-11-16** |
| B2 | STM32 发**真帧**（LEN + payload + CRC） | ⬜ 下一步 |
| B3 | PC 侧 `SerialCar`（`QSerialPort` + `FrameParser`） | ⬜ |
| B4 | 界面显示真实数据 | ⬜ |
| B5 | 拔插稳定性测试 | ⬜ |
| C | 舵机接入（滑块 → 真实角度） | ⬜ |
| D | 超声波接入（手挡 → 距离变小） | ⬜ |
| E | 扫描 + 极坐标雷达图 | ⬜ |

**A 阶段验收**：界面连续跑 30 分钟不崩；假数据按虚拟墙模型变化（40°~70° 距离掉到约 300mm）；断开时状态灯变红且不崩。

**B1 阶段验收**：每 100ms 收到 8 个字节 `AA 55 06 81 01 0E 03 00`，连续不断。

---

## 六、踩过的坑（别重复踩）

### PC 侧

| 坑 | 现象 | 原因 / 修法 |
|---|---|---|
| **AUTOMOC 孤儿头文件** | 链接期 `undefined reference to vtable for ICarSource` / `staticMetaObject` | 纯接口头文件（只有 .h 没 .cpp）带 `Q_OBJECT`，**必须显式列进 `add_executable` 的 sources** |
| **PowerShell 调外部程序** | `-std=c++17` 报"意外的标记" | 引号包起来的路径开头必须加 **`&`** |
| **控制台中文乱码** | `鍗忚灞傚崟娴` | `chcp 65001` **不够**，还要 `[Console]::OutputEncoding = UTF8`（脚本已内置） |
| **`m_ctrl` 初始化顺序** | 急停按钮没反应，**无任何报错** | `buildUi()` 里要连 `m_ctrl`，控制器必须先建 |
| **`.ps1` 编码** | 中文乱码 → 引号被吃 → 语法错误 | **`.ps1` 必须 UTF-8 带 BOM**（Markdown/C++ 相反，要无 BOM） |

### STM32 / 工具链侧

| 坑 | 现象 | 原因 / 修法 |
|---|---|---|
| **Keil 工具链路径失效** | `*** Error: CreateProcess failed, Command: ArmAsm/ArmCC` | `TOOLS.INI` 里 `PATH="E:\Keil_v5\ARM\"`，实际在 `E:\SoftWare\Keil_v5\ARM\`。改 INI（GBK 编码，字节级替换） |
| **只插 USB_TTL 不供电** | 板子灯亮但串口 0 字节 | 分清楚「板子供电」和「串口模块供电」 |
| **BOOT0 跳线在 1** | 程序烧进去了但**根本不执行** | BOOT0 必须在 **0**（或拔掉跳线帽，有下拉） |
| **烧录成功 ≠ 程序在跑** | Keil 报 `Verify OK`，串口 0 字节 | 烧完程序停在复位状态，**要按一次 RESET**。修法：Debug→Settings→Flash Download 勾 **`Reset and Run`** |
| **TIM2 中断没使能** | 回调永不调用 → 一帧不发 | CubeMX 里 `NVIC Settings` 必须勾 **`TIM2 global interrupt`** |
| **`HAL_TIM_Base_Start_IT` 忘了** | 定时器不跑 | `MX_TIM2_Init()` 只配置不启动 |
| **回调函数名拼错** | 不报错但永不调用 | 必须 `HAL_TIM_PeriodElapsedCallback` |
| **`volatile` 缺失** | 主循环看不到中断里的标志 | 中断写的全局变量必须 `volatile` |
| **HSI 跑串口会误码** | 偶尔乱码 | 必须用 **HSE 外部晶振**（HSI ±1% vs HSE ±20ppm） |
| **串口口"存在"≠"空闲"** | `Access to the port 'COMx' is denied` | 一次只能一个程序打开；蓝牙虚拟串口会混在列表里 |

### 串口调试侧

| 坑 | 现象 | 说明 |
|---|---|---|
| **字节流边界 ≠ 帧边界** | 日志里 `AA` 单独一行 | 正常。`BytesToRead` 每次读到的量不定。**这正是 `FrameParser` 存在的理由** —— 它按 `AA 55` 重新对齐，跨块也能拼 |
| **CP2102 换 USB 口 COM 号可能变** | 打不开原 COM 号 | 用 `GetPortNames()` + 注册表 `HKLM\SYSTEM\CurrentControlSet\Enum\USB` 查真实分配 |

---

## 七、下一步（B2 → B4）

### B2：STM32 侧发真帧

把 `kDummy` 换成一个真正的 `STATUS` 帧：

```
AA 55 07 81 01 <servo_lo> <servo_hi> <dist_lo> <dist_hi> <err> <crc>
```

- `LEN = 0x07`（CMD 1 + SEQ 1 + payload 5）
- 总长 **11 字节**
- CRC-8/MAXIM 覆盖 `LEN..PAYLOAD`
- **必须先实现与 PC 侧 `protocol.cpp` 输出逐字节一致的 CRC 和编码**

**推荐做法**：写 `mcu/protocol_c.c`（纯 C，无 HAL 依赖），用 PC 上的 g++ 编译成测试程序，和 `protocol.cpp` 对拍同一组输入，**输出必须完全一致**。

### B3：PC 侧 `SerialCar`

1. `CMakeLists.txt` 打开 `SerialPort` 组件
2. `source/SerialCar.h/.cpp` 实现 `ICarSource`，内部用 `QSerialPort` + `FrameParser`
3. `MainWindow.cpp` 那一行 `m_ctrl->attach(new FakeCar(this));` 换成 `SerialCar`

### B4：验收

**界面上的角度/距离变成 STM32 发来的真实数字** → 交汇点 ① 完成。