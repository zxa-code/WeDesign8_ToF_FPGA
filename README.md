# WeDesign8 - 基于FPGA的ToF激光测距数字系统

> 使用京微齐力**HR03PN0U81C7**（STEP-HR03-U81核心板）实现单路ToF激光测距的数据采集、显示、报警与上位机通信。
> 工程包含**FPGA RTL源码与福晞（Fuxi）工程**、**PC上位机（C# WinForms）**、**KiCad电路工程** 与 **可下载位流（ACF）** 四部分。

---

## 一、系统概览

```
       ToF 测距模块 (CN1)
            │  UART 921600 8N1
            ▼
 ┌──────────────────────────── FPGA (top_tof) ────────────────────────────┐
 │  uart_rx ─► tof1_parser(CRC16) ─► 距离 / 强度 / 环境光                  │
 │                │                                                       │
 │                ├─► bcd_conv ─► 2 位数码管 (74HC595)                     │
 │                ├─► disp_chargen + font8x8 ─► 1.12" 128x128 OLED (SPI)  │
 │                │                            └► 0.96" 128x64 OLED (I²C)  │
 │                ├─► alarm_ctrl ─► LED2 报警闪烁 / WS2812 灯效预览        │
 │                └─► 文本行组帧 ─► uart_tx ─► 上位机 (SDAM_Host_V2)       │
 │  输入：4 键 + 旋转编码器 + 拨码 SW0..3 + KEY_A/KEY_B                    │
 └─────────────────────────────────────────────────────────────────────────┘
```

- **主控**：HR03PN0U81C7，12MHz板载时钟，单时钟域设计。
- **数据链路**：ToF模块 → FPGA固定 **921600** 波特率；FPGA → PC的调试串口速率由拨码选择（9600 / 115200 / 230400 / 921600）。
- **本地显示**：SPI 128×128 OLED（SH1107）+ I²C 128×64 OLED（SSD1306）+ 2 位数码管。
- **交互**：板载4键、旋转编码器、扩展板KEY_A/KEY_B，可设置报警阈值、灯效与查看信息页。
- **报警**：距离低于阈值时LED2以2Hz闪烁；WS2812仅在设置页手动预览灯效。

---

## 二、目录结构

```
WeDesign8_ToF_FPGA/
├─ 01_fuxi projects/        FPGA 工程（Fuxi 2025.1）
│  ├─ top_tof.v             顶层：链路、串口、显示、LED、命令重发
│  ├─ tof1_parser.v         SDAM 帧解析 + CRC16 校验（自动重同步）
│  ├─ crc16_modbus.v        CRC16/Modbus 单字节递推（组合逻辑）
│  ├─ uart_rx.v / uart_tx.v 8N1 串口，8 倍过采样 / 累加器分频
│  ├─ bcd_conv.v            double-dabble 二进制→5 位 BCD
│  ├─ disp_chargen.v        46 行 × 16 列文本内容（纯组合）
│  ├─ font8x8.v             5×7 点阵字库（按列输出）
│  ├─ oled_sh1107.v         128×128 SPI OLED 驱动
│  ├─ oled_ssd1306.v        128×64 I²C OLED 驱动（共享字库）
│  ├─ seg7_595.v            2 位共阴数码管 + 74HC595 扫描
│  ├─ key_scan.v            5 通道 20 ms 消抖
│  ├─ rotary_enc.v          旋转编码器正交解码
│  ├─ ui_ctrl.v             单页菜单：ALARM / WARN DIST / LIGHT STYLE / INFO
│  ├─ alarm_ctrl.v          阈值报警 + 6 种灯效
│  ├─ ws2812_drv.v          两颗级联 WS2812 驱动
│  ├─ project.lpf           引脚约束（LPF）与 IO 电平
│  ├─ top_tof.aoc           Fuxi 工程 IO 约束
│  ├─ fuxi_run.sh           综合→布局布线→STA→位流生成流程
│  ├─ scripts/              cstool / cstimer 各阶段 TCL 脚本
│  └─ outputs/              综合、布局布线、STA 报告与网表
├─ 02_hostcpt_src/          PC 上位机（C# / .NET Framework 4.8）
│  ├─ exe/SDAM_Host_V2.exe  可直接运行
│  └─ src/                  源码、构建脚本、协议单元测试
├─ 03_Circuit/              KiCad 10 电路工程（由嘉立创 EDA 导入）
│  └─ kicanvas_fix/         网页端 KiCanvas 网络缺失修复脚本与上传包
└─ 04_downloadable acf/     生成的下载位流 top_tof_bin.acf
```

---

## 三、FPGA 设计要点

### 1. 复位策略
HR02/HR03内部配置寄存器上电默认输出为 1，单计数器POR可能上电首拍即判完成。顶层采用 **升计数饱和 + 降计数归零** 双计数器（`por_up` / `por_dn`），保证无论初值如何都得到约 **5.46 ms** 的确定性复位窗口；`KEY_B` 可随时拉低复位。

### 2. ToF 通信与帧格式
- 上电复位后先**等待约1.4s**，再发送一条9字节启动流命令：

  ```
  A5 03 20 01 00 00 00 02 6E
  ```

- 一次“尝试”只发这一帧，随后静默1.4s等待模块推流；未锁定则按1.4s周期重发，`KEY_A` 可立即补发，收到合法帧后停止打扰。
- 上行帧格式：

  ```
  A5 03 20 CMD RSV LEN_H LEN_L + 14 B data + CRC_H CRC_L
  ```

  data 为小端：主目标距离（mm）、主目标强度、环境光。CRC为**CRC16/Modbus**（初值0xFFFF、反射、poly 0xA001），同时兼容高低字节交换的写法。
- 解析器支持帧头重同步，任意字节丢失后可自动恢复。

### 3. 本地显示
| 外设 | 接口 | 说明 |
| --- | --- | --- |
| 1.12" 128×128 OLED | 4 线 SPI（3 MHz，CS 接地） | 16行 × 16字符，显示距离/强度/环境光/计数/链路/命令次数等 |
| 0.96" 128×64 OLED | I²C（0x3C，SCL=IO31，SDA=IO32 开漏） | 单页菜单 + 3 个子页，与小屏共享 `disp_chargen` 和 `font8x8` |
| 2 位数码管 | 74HC595 串行 | 按 `<1 m` 显示厘米、`1~9.99 m` 显示米.分米、`≥10 m` 显示十米/米 |

两块 OLED 共享一份字库与字符源，顶层在 SPI 屏 `S_LOAD` 拍仲裁，节省 LUT。

### 4. 交互与报警
- `key_scan`：1 kHz 采样、20 ms 消抖；`rotary_enc`：4 状态正交解码，每档一个 step。
- `ui_ctrl`：主页 4 项（ALARM 开关 / WARN DIST / LIGHT STYLE / INFO），旋转选择、按键确认；WARN 阈值 0.10–20.00 m，精度 0.01 m（BCD `{十米,米,分米,厘米}` 避免除法），默认 5.00 m。
- `alarm_ctrl`：判据 `alarm_en && link_ok && 距离有效且 ≤ alarm_mm`，带 200 ms 超阈值清除与 1 s 失链清除；报警由 **LED2 2 Hz 闪烁** 指示。6 种灯效（红闪 / 黄闪 / 绿常亮 / 警灯 / 呼吸 / 彩虹）仅在 LIGHT STYLE 子页预览。

### 5. LED 与拨码语义
| 拨码 | 含义 |
| --- | --- |
| 恰好 1 个 ON | 打开上位机串口：SW0=9600，SW1=115200，SW2=230400，SW3=921600 |
| 0 个 ON | 关闭上位机串口，OLED 显示 `OFF` |
| 多个 ON | 非法，串口关闭，OLED 显示 `ERROR` |

拨码只影响 **FPGA→PC** 的调试串口；ToF 侧固定 921600，测距、OLED、数码管不受影响。

LED（核心板低电平点亮，代码中统一取反）：
`LED1` 心跳 / `LED2` 距离报警 2 Hz / `LED3` 链路 OK / `LED4` 上位机串口已开 / `LED5..8` 四档位指示。

### 6. 资源占用（Fuxi 2025.1，2026-11-14 综合）
- 综合状态：**Successful**，0 error / 6 warning。
- 寄存器 1164 / 2048，IO 37 / 66，未使用 EMB 与 PLL。
- 布局布线、时序分析（agtc 85 ℃ / 0.81 V）与位流生成均已跑通，产物见 `outputs/` 与 `04_downloadable acf/`。

---

## 四、上位机（SDAM Host V2）

- 语言/框架：C# WinForms，.NET Framework 4.8（Windows 10/11 自带，无需额外安装）。
- **纯接收设计**：只解析 FPGA 上行的 ASCII 文本行，不向串口写任何字节。
- 数据格式（约 49 B，`\r\n` 结尾）：

  ```
  D=0843 I=0924 A=0012 C=00 F=0000 U=3 B=0000 L=1
  ```

  | 字段 | 含义 |
  | --- | --- |
  | `D=` | 主目标距离，1 mm/LSB（4 位十六进制） |
  | `I=` | 回波强度（4 位十六进制） |
  | `A=` | 环境光基底（4 位十六进制） |
  | `C=` | CRC 错误帧计数（2 位十六进制） |
  | `F=` | 合法帧计数（4 位十六进制） |
  | `U=` | 上位机串口档位 0..3 |
  | `B=` | 累计接收字节数 mod 65536（4 位十六进制） |
  | `L=` | 链路状态（1=1.4 s 内有合法帧） |

- 功能：三路实时曲线（10/30/60/300 s）、链路统计、日志、CSV 导出、曲线 PNG 导出。
- 构建与测试：
  ```bat
  cd 02_hostcpt_src\src
  build.bat            :: 使用系统自带 csc.exe，无需 VS
  cd tests
  run_tests.bat        :: 协议解析单元测试，77 项断言
  ```

---

## 五、电路工程

- `03_Circuit/` 为 KiCad 10 工程（由嘉立创 EDA 专业版导入），含原理图、PCB、封装库与符号库。
- 电子森林网页端使用旧版 KiCanvas 解析器，无法识别 KiCad 10 的“仅网络名”格式，且 polygon 内嵌 `arc` 会导致白屏。`kicanvas_fix/convert_kicad10_to_kicanvas.py` 会：
  1. 将 `(arc ...)` 按 12° 采样展开为折线；
  2. 插入顶层网络表并把 pad/segment/via/zone 的 net 引用改为旧格式。
- 修复后：KiCad 10 可正常打开（47 nets / 219 tracks），网页端 Nets 面板可显示 47 个网络并高亮走线。
- 上传包：`03_Circuit/kicanvas_fix/WeDesign8_ToF_FPGA_kicanvas_upload.zip`。
- **注意**：不要用 KiCad 10 打开修复版再保存，否则会写回新格式；改板请修改原工程后重新转换。

---

## 六、复现与下载

1. 用福晞（Fuxi 2025.1）打开 `01_fuxi projects/top_tof.hpr`（或对应工程），综合→布局布线→生成位流；
   也可按 `fuxi_run.sh` 依次调用 `cstool` / `agtc` / `cstimer` / `abcgen` / `acfgen`。
2. 位流输出为 `04_downloadable acf/top_tof_bin.acf`，使用官方下载工具烧录至 HR03PN0U81C7。
3. 按原理图连接 ToF 模块（CN1）、两块 OLED、数码管与 WS2812，上电后约 0.7 s 全亮自检，随后正常显示。
4. PC端运行`02_hostcpt_src/exe/SDAM_Host_V2.exe`，选择串口与拨码对应的波特率即可接收。

---

## 七、版本说明

顶层当前版本为**V3.0-P4.1**（2026-11-14）。近几次主要迭代：

- **V2.0**：拨码语义由“ToF速率”改为“上位机串口速率”，ToF固定921600的通信波特率；LED改正逻辑；放弃第二路ToF。
- **V3.0-P1~P2**：新增4个板载可交互按键、旋转编码器与I²C 128×64 OLED 驱动。
- **V3.0-P3~P3d**：加入菜单/子页UI，两屏共享一份字库与字符源以节省LUT。
- **V3.0-P4~P4.1**：距离报警（ALARM / WARN DIST）与 6 种 WS2812 灯效；报警改由 LED2 指示，WS2812 仅手动预览。

---

## 八、说明

- 本工程为综合课程设计项目，代码中保留了较详细的中文注释与版本修订记录，便于继续维护。
- 各模块的设计背景、调试过程中遇到的问题及取舍，详见源码文件头注释。
