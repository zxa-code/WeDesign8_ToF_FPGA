# ToF激光测距上位机（FPGA 数据采集与可视化）

配合「基于 FPGA 的 ToF 激光测距数字系统」（STEP-HR03-U81 / 京微齐力 HR03PN0U81C7）使用的 PC 端上位机。
纯接收 FPGA 通过串口上行的 ASCII 文本行，实时解析并显示距离、强度、环境光、帧计数、CRC 错误计数、链路状态等，
提供三路实时曲线、链路统计、日志与数据导出。**本程序只接收、不向串口写入任何字节。**

## 目录结构

```
02_hostcpt_src与exe\
├─ README.md                      本说明
├─ exe\
│  └─ SDAM_Host_V2.exe            可直接运行的程序（另附 .config）
└─ src\
   ├─ Protocol.cs                 文本行解析（49 B 行）
   ├─ LinkStats.cs                链路质量统计
   ├─ SerialPortManager.cs        串口打开/关闭/接收线程
   ├─ MainForm.cs                 主界面逻辑
   ├─ MainForm.Designer.cs        界面布局
   ├─ MainForm.resx               窗体资源
   ├─ Program.cs                  程序入口
   ├─ app.config                  .NET 运行配置
   ├─ SDAM上位机.csproj            Visual Studio 工程文件
   ├─ build.bat                   一键构建脚本（Windows 内置编译器）
   ├─ build_vs.bat                Visual Studio / MSBuild 构建脚本
   └─ tests\
      ├─ ProtocolTests.cs         协议解析单元测试
      └─ run_tests.bat            一键测试脚本
```

## 快速运行

1. 用 USB 线连接板卡（板载 USB-TTL / 编程器虚拟串口），确认设备管理器中能看到 COM 口。
2. 双击 `exe\SDAM_Host_V2.exe`。
3. 选择串口与波特率（FPGA 调试串口默认 **115200**；板上拨码也可选择 9600 / 115200 / 230400 / 921600），打开串口即可开始接收。
4. 数据自动刷新；可保存 CSV、导出曲线 PNG。

运行环境：Windows 10/11，.NET Framework 4.8（系统自带，无需另装）。

## 上行数据格式

FPGA 每次发送一行 ASCII 文本（约 49 B，以 `\r\n` 结尾），上位机按字段解析：

```
D=0843 I=0924 A=0012 C=00 F=0000 U=3 B=0000 L=1
```

| 字段 | 含义 | 格式 |
|---|---|---|
| `D=` | 主目标距离，LSB = 1 mm | 4 位十六进制 |
| `I=` | 回波强度（相对值） | 4 位十六进制 |
| `A=` | 环境光/阳光基底（相对值） | 4 位十六进制 |
| `C=` | 累计 CRC 错误帧数 | 2 位十六进制 |
| `F=` | 累计有效帧数 | 4 位十六进制 |
| `U=` | 波特率档位 | 1 位十进制 |
| `B=` | 累计接收字节数 mod 65536 | 4 位十六进制 |
| `L=` | 链路状态（1=正常） | 1 位十进制 |

## 构建（src → exe）

在 `src\` 目录双击 `build.bat`（或命令行运行）：

```bat
cd src
build.bat
```

脚本调用 Windows 自带的 .NET Framework 4.x `csc.exe` 编译，**不需要 Visual Studio 或 .NET SDK**，
产物为 `src\bin\Release\SDAM_Host_V2.exe`（如使用 VS，可运行 `build_vs.bat`）。

## 测试

```bat
cd src\tests
run_tests.bat
```

编译并运行协议解析单元测试（77 项断言），全部通过时窗口显示 PASS 并正常退出。

## 验证状态

- 构建：使用 Windows 自带 .NET Framework 4.x `csc.exe` 编译通过，无报错（`/warn:4`）。
- 测试：协议解析单元测试 **77 / 77 通过**。
- 运行：Windows 11 上双击启动正常，标题为「SDAM 激光测距上位机 V2.0（FPGA 文本行）」；未连接串口时界面正常显示并给出提示。

## 说明

- 纯接收设计：不向串口写任何字节，不提供「开始测量 / 停止测量 / 设备设置」等下发命令功能。
- 曲线窗口支持 10 / 30 / 60 / 300 s；数据可导出 CSV，图表可导出 PNG。
- 若板卡尚未运行时序，界面仍可正常打开，日志区会提示无数据；请检查串口选择、波特率（拨码档位）与接线。
- 本程序为综合课程设计配套工具，src可按需修改；重新编译后覆盖 `exe\` 中的同名文件即可。
