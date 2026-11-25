// =============================================================================
// 文件名   : top_tof.v
// 功能     : 单路 ToF 激光测距（SDAM）采集与显示 —— 顶层（V2.0 / M1）
// 说明     : 数据链路
//              CN1(TOF1) --UART 921600（固定）--> uart_rx
//              -> tof1_parser(CRC16) -> 距离/强度/环境光
//              -> OLED(128x128 SH1107) + 2 位数码管
//              -> 上位机串口 dbg_tx（速率由拨码选择）
//            功能要点（V2.0）
//              1) 拨码只决定 **上位机串口** 的波特率，与 ToF 模块无关：
//                 SW0=9600 SW1=115200 SW2=230400 SW3=921600；
//                 0 个 ON = 关闭上位机串口（OLED 第 12 行显示 OFF）；
//                 多个 ON = 非法（显示 ERROR，串口同样关闭）；
//                 恰好 1 个 ON 才按该档发送。测距/OLED/数码管不受影响。
//              2) ToF 侧固定 921600（模块出厂默认，改 FPGA 一侧对模块没有意义）：
//                 启动流命令 A5 03 20 01 00 00 00 02 6E，复位后先武装 1.4 s；
//                 一次尝试只发一条 9 字节帧，发完静默 1.4 s，锁不上才重发；
//                 KEY_A = 立即重发一次，KEY_B = 复位；收到帧（link_ok）后停发。
//              3) 8 个 LED 正逻辑（激活即亮；核心板 LED 低电平点亮，见设计说明 §19）：
//                 LED1 心跳 / LED2 距离报警 2 Hz（默认灭）/ LED3 链路 OK /
//                 LED4 上位机串口已开；LED5..8 = 档位 9600/115200/230400/921600
//                 （仅串口开启时亮）。
//              4) 2 位数码管按 厘米 / 米.分米 / 十米米 三档显示。
//              5) 上电复位用“升计数饱和 + 降计数归零”双计数器：HR02/HR03 寄存器
//                 上电默认输出 1（应用指南 §4.6），单计数器 POR 会立刻判完成。
// 引脚     : 见 docs/01 与 readme.txt（IO1..IO4 = OLED，IO14/17 = KEY，IO29.. = TOF）
// 版本     : V3.0-P4.1  (2026-11-14)
// 修 订     : V2.0 按用户要求完全重构：拨码语义由“ToF 速率”改为“上位机串口速率”，
//             ToF 固定 921600；LED 改正逻辑；正式放弃第二路 ToF（只保留单路 M1）；
//             删掉 V1.5~V1.9 遗留的 rate_cur/tx_rate/inc_* 三张 case 表、拨码非法门控
//             baud_err/sw_chg 与 KEY_A 切 CRC 字节序逻辑（字节序降为一行常量）。
//             本文件即 V2.0 定稿：S1 字库补 P、S2 POR、S3 ToF 固定 921600、
//             S4 拨码→上位机串口、S5 LED 正逻辑 + 上位机文本行 均已落地。
//             V3.0-P1（2026-11-13）：新增板载 4 键（key[3:0]）与旋转编码器
//             （phase_a/phase_b/key_enc）输入，20 ms 消抖 + 正交解码。
//             显示（I²C OLED）、设置页、报警在后续阶段接入。
//             V3.0-P2（2026-11-13）：新增 I²C 128x64 OLED（SSD1306 0x3C）驱动，
//             接 OLED_B 4 pin 座；P2 显示测试图案，P3 换成正式文字页。
//             V3.0-P3（2026-11-14）：I²C 屏文字页 + 4 键/编码器 UI；
//             两屏共享 disp_chargen 字符源；DEBUG_INPUT=0。
//             V3.0-P3c（2026-11-14）：小屏改为单页菜单（ALARM/WARN DIST/
//             05.00 M/LIGHT STYLE/INFO）+ WARN/LIGHT/INFO 子页；大屏 0..15 行不动。
//             V3.0-P3d（2026-11-14）：两屏共享一份 font8x8，I²C 屏去掉 16 字符
//             缓存（按像素现算），省 LUT 给 P4 报警/WS2812。显示内容不变。
//             V3.0-P4（2026-11-14）：距离报警（ALARM/WARN DIST）+ 6 种 WS2812
//             灯效；LED8 报警时覆盖 921600 档位灯（2 Hz 闪）。
//             V3.0-P4.1（2026-11-14）：放弃 WS2812 的距离报警；报警改由
//             LED2 2 Hz 闪（默认灭），LED2 不再做帧闪；LED8 只做 921600 档位灯；
//             WS2812 仅在 LIGHT STYLE 子页手动预览。
// =============================================================================
`timescale 1ns/1ps

module top_tof (
    input  wire        clk,          // 12 MHz 板载时钟
    input  wire [3:0]  sw,           // 板载拨码 SW0..SW3
    input  wire        key_a,        // 载板 KEY_A：立即补发一次启动命令
    input  wire        key_b,        // 载板 KEY_B：复位（低有效）
    input  wire [3:0]  key,          // 板载 KEY1..KEY4（低有效）
    input  wire        phase_a,      // 旋转编码器 A（IO15）
    input  wire        phase_b,      // 旋转编码器 B（IO16）
    input  wire        key_enc,      // 旋转编码器按下（IO18，低有效）
    input  wire        tof1_rx,      // TOF1 模块 TX -> FPGA
    output wire        tof1_tx,      // FPGA -> TOF1 模块 RX（发命令）
    output wire        dbg_tx,       // 上位机串口 TX（速率由拨码 SW0..SW3 选择）
    output wire [7:0]  led,          // 8 个板载 LED
    output wire [1:0]  seg_dig,      // 数码管位选
    output wire        seg_sck,
    output wire        seg_rck,
    output wire        seg_din,
    output wire        oled_sclk,
    output wire        oled_mosi,
    output wire        oled_dc,
    output wire        oled_res,
    output wire        i2c_scl,      // I²C 128x64 OLED SCL（IO31/H5）
    inout  wire        i2c_sda,      // I²C 128x64 OLED SDA（IO32/H9，开漏）
    output wire        COLOR         // 板载 RGB 数据（核心板 COLOR/C5；内部资源名必须为 COLOR）
);

    // =========================================================================
    // 复位与时钟
    // =========================================================================
    // HR02/HR03 的寄存器上电默认输出为 1（《HME-HR03 系列 FPGA 应用指南》§4.6），
    // 单靠“计到 0xFFFF 就置 por_done”的计数器可能上电第一拍就判完成、复位窗口为 0
    // （现场表现就是“上电后必须按一次 KEY_B 才初始化外设”）。这里用两个计数器：
    //   por_up 从任意初值升到 0xFFFF（最多 65535 拍后饱和）
    //   por_dn 从任意初值降到 0x0000（最多 65535 拍后饱和）
    // 两者都到位才释放复位 ⇒ 无论上电初值是全 0、全 1 还是混杂，都能得到确定的
    // 约 5.46 ms 复位窗口。
    reg [15:0] por_up;
    reg [15:0] por_dn;
    always @(posedge clk) begin
        if (por_up != 16'hFFFF) por_up <= por_up + 16'd1;
    end
    always @(posedge clk) begin
        if (por_dn != 16'h0000) por_dn <= por_dn - 16'd1;
    end
    wire por_n = (por_up == 16'hFFFF) && (por_dn == 16'h0000);

    // 按键同步
    reg key_a_d0, key_a_d1, key_b_d0, key_b_d1;
    always @(posedge clk) begin
        key_a_d0 <= key_a;  key_a_d1 <= key_a_d0;
        key_b_d0 <= key_b;  key_b_d1 <= key_b_d0;
    end
    wire key_a_press = (~key_a_d1) & key_a_d0;
    wire rst_n = por_n & key_b_d1;      // 上电复位窗口 & KEY_B（低有效）

    // =========================================================================
    // V3.0 输入：板载 4 键 + 旋转编码器（P1）
    //   key_scan  : 1 kHz 采样、20 ms 消抖、单周期按下脉冲
    //   rotary_enc: 正交解码，每档输出一个 step；P3 起由 ui_ctrl 消费
    // =========================================================================
    wire [4:0] key_press;
    wire [4:0] key_hold;
    wire       rot_step;
    wire       rot_dir;

    key_scan u_key_scan (
        .clk         (clk),
        .rst_n       (rst_n),
        .key_raw     (key),
        .key_enc_raw (key_enc),
        .key_press   (key_press),
        .key_hold    (key_hold)
    );

    rotary_enc u_rotary_enc (
        .clk     (clk),
        .rst_n   (rst_n),
        .phase_a (phase_a),
        .phase_b (phase_b),
        .step    (rot_step),
        .dir     (rot_dir)
    );

    // V3.0-P3c：小屏单页菜单（4 键 + 编码器 -> 页面/选中项/设置值）
    wire [1:0]  ui_page;      // 0=主页 1=WARN 2=LIGHT 3=INFO
    wire [1:0]  ui_sel;       // 主页选中项：0=ALARM 1=WARN 2=LIGHT 3=INFO
    wire        alarm_en;
    wire [15:0] warn_bcd;     // 预警阈值 {十米,米,分米,厘米}
    wire [2:0]  light_style;  // 0=RED BLINK 1=AMBER BLINK 2=GREEN SOLID
                              // 3=POLICE 4=BREATHE 5=RAINBOW
    wire [1:0]  digit_sel;    // WARN 子页当前编辑位：0=十米 1=米 2=分米 3=厘米
    wire [15:0] alarm_mm;     // 报警阈值（mm），P4 用

    ui_ctrl u_ui (
        .clk         (clk),
        .rst_n       (rst_n),
        .key_press   (key_press),
        .rot_step    (rot_step),
        .rot_dir     (rot_dir),
        .ui_page     (ui_page),
        .ui_sel      (ui_sel),
        .alarm_en    (alarm_en),
        .warn_bcd    (warn_bcd),
        .light_style (light_style),
        .digit_sel   (digit_sel),
        .alarm_mm    (alarm_mm)
    );

    // =========================================================================
    // 拨码：只选择 **上位机串口** 的波特率（V2.0 起与 ToF 模块无关）
    //   历史：V1.1~V1.9 一直把拨码当成“FPGA↔ToF 模块的速率”。可模块的速率是它自己
    //   的属性（出厂 921600），拨码只改 FPGA 一侧采样率，模块并不会跟着变，所以那套
    //   “只有 SW3 能用”的语义从一开始就没有意义；V1.5 还用 baud_ok 门控采集与发命令，
    //   让非 SW3 档和全 OFF 完全收不到数据、怎么拨都救不回来。V2.0 按用户要求改成
    //   选择“与电脑上位机通信”的速率：
    //     恰好 1 个 ON：SW0=9600 SW1=115200 SW2=230400 SW3=921600，按该档发文本行；
    //     0 个 ON     ：关闭上位机串口（一个字都不发），OLED 第 12 行显示 OFF；
    //     多个 ON     ：非法，串口同样关闭，OLED 第 12 行显示 ERROR；
    //   测距、OLED、数码管始终正常工作，与拨码无关（ToF 侧固定 921600，见下）。
    //   注：核心板拨码 ON = 高电平（《STEP-HR03-U81 快速入门》），sw_on 的 1 即 ON。
    // =========================================================================
    reg [3:0] sw_s0;
    always @(posedge clk) sw_s0 <= sw;

    wire [3:0] sw_on  = sw_s0;
    wire [2:0] sw_num = {2'd0, sw_on[0]} + {2'd0, sw_on[1]}
                      + {2'd0, sw_on[2]} + {2'd0, sw_on[3]};
    wire       sw_none  = (sw_num == 3'd0);   // 全 OFF
    wire       sw_multi = (sw_num >  3'd1);   // 多个 ON（非法）
    wire       pc_en    = ~sw_none & ~sw_multi;  // 恰好一个 ON：上位机串口开启

    // 采集链信号：提前声明，避免“先用后声明”的前向引用（V1.6.1 修正）
    wire [15:0] dist_mm;
    wire [15:0] inten;
    wire [15:0] amb;
    wire        dist_valid;
    wire        frame_ok;
    wire        crc_err;
    reg  [23:0] link_cnt;
    reg         link_ok;

    // 上位机串口档位（pc_en=0 时只用于 OLED/屏幕提示，串口一个字都不发）
    reg [1:0] pc_rate;
    always @(*) begin
        case (sw_on)
            4'b0001: pc_rate = 2'd0;   // SW0 -> 9600
            4'b0010: pc_rate = 2'd1;   // SW1 -> 115200
            4'b0100: pc_rate = 2'd2;   // SW2 -> 230400
            4'b1000: pc_rate = 2'd3;   // SW3 -> 921600
            default: pc_rate = 2'd3;   // 0 个或多个 ON：串口关闭，此值仅用于显示
        endcase
    end

    // =========================================================================
    // ToF 侧波特率：固定 921600（V2.0）
    //   模块出厂默认 921600；拨码只改 FPGA 自己的采样率、模块不会跟着变，所以改
    //   “FPGA 与模块之间”的速率没有任何意义（用户 V2.0 明确要求固定不变）。
    //   inc = baud * 65536 / 12MHz；收端再 ×8（8 倍过采样）
    // =========================================================================
    localparam [16:0] INC_TOF_RX = 17'd40265;   // 8 * 921600 * 65536 / 12e6
    localparam [16:0] INC_TOF_TX = 17'd5033;    // 921600 * 65536 / 12e6

    // =========================================================================
    // TOF1 串口接收 + 帧解析
    // =========================================================================
    wire [7:0] rx_byte;
    wire       rx_valid;
    uart_rx u_tof_rx (
        .clk      (clk),
        .rst_n    (rst_n),
        .inc      (INC_TOF_RX),
        .rx_in    (tof1_rx),
        .rx_data  (rx_byte),
        .rx_valid (rx_valid)
    );

    tof1_parser u_parser (
        .clk        (clk),
        .rst_n      (rst_n),
        .byte_valid (rx_valid),
        .byte_in    (rx_byte),
        .dist_mm    (dist_mm),
        .inten      (inten),
        .amb        (amb),
        .dist_valid (dist_valid),
        .frame_ok   (frame_ok),
        .crc_err    (crc_err)
    );

    // 帧计数 / CRC 错误计数 / 收到字节计数
    reg [15:0] frm_cnt;
    reg [15:0] crc_cnt;
    reg [15:0] rx_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frm_cnt <= 16'd0;
            crc_cnt <= 16'd0;
            rx_cnt  <= 16'd0;
        end else begin
            if (frame_ok) frm_cnt <= frm_cnt + 16'd1;
            if (crc_err)  crc_cnt <= crc_cnt + 16'd1;
            if (rx_valid) rx_cnt  <= rx_cnt + 16'd1;
        end
    end

    // =========================================================================
    // 链路状态：1.4 s 内收到过合法帧则 link_ok=1（供显示与命令重发使用）
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            link_cnt <= 24'd0;
            link_ok  <= 1'b0;
        end else if (frame_ok) begin
            link_cnt <= 24'd0;
            link_ok  <= 1'b1;
        end else if (link_cnt == 24'hFFFFFF) begin
            link_ok  <= 1'b0;
        end else begin
            link_cnt <= link_cnt + 24'd1;
        end
    end

    // =========================================================================
    // 启动流命令 A5 03 20 01 00 00 00 02 6E（9 字节，固定 921600 发送）
    //   V2.0 命令配方（在 V1.3 实测可用配方上定稿）：
    //   1) 复位后武装 1.4 s 再发（模块上电自检期间收到的命令不算数）；
    //   2) 一次“尝试”= 只发这一条 9 字节帧，发完静默 1.4 s 给模块启动推流的时间
    //      （连发或交替会让一半/全部命令变成 CRC 错帧；V1.6 就是这样把模块刚起来
    //       的推流打断、上板 RXB 恒 0000 的）；
    //   3) 触发：武装后第一次、KEY_A 立即补发、锁不上时每 1.4 s 重发；
    //   4) 收到帧（link_ok=1）后不再打扰模块；失链由 link_ok 自动掉下来驱动重发；
    //   5) CRC 字节序由 CMD_CRC_LSB_FIRST 常量决定（默认高字节在前 = 02 6E，
    //      与厂商上位机 Protocol.cs 一致），不再用按键切换。
    // =========================================================================
    reg         cmd_start;
    reg  [7:0]  cmd_data;
    wire        cmd_busy;
    reg  [3:0]  cmd_idx;
    reg  [1:0]  cmd_state;
    reg         cmd_seen;
    reg         cmd_issued;
    reg  [23:0] cmd_tick_cnt;
    reg         cmd_tick;
    reg         cmd_pend;
    reg         cmd_ack;
    reg  [7:0]  cmd_byte;
    reg  [15:0] cmd_cnt;          // 已发起的“尝试”次数（诊断：OLED CMD: 行）
    reg  [23:0] arm_cnt;          // 武装延时计数

    // CRC 字节序：0 = 高字节在前（02 6E，与厂商上位机 Protocol.cs 一致，默认）
    //             1 = 低字节在前（6E 02，手册示例文字的写法）
    // 现场若需要另一种，只改这一个常量，不必动别的代码。
    localparam CMD_CRC_LSB_FIRST = 1'b0;

    wire armed = (arm_cnt == 24'hFFFFFF);   // 约 1.4 s

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            arm_cnt <= 24'd0;
        else if (arm_cnt != 24'hFFFFFF)
            arm_cnt <= arm_cnt + 24'd1;
    end

    always @(*) begin
        case (cmd_idx)
            4'd0: cmd_byte = 8'hA5;
            4'd1: cmd_byte = 8'h03;
            4'd2: cmd_byte = 8'h20;
            4'd3: cmd_byte = 8'h01;
            4'd4: cmd_byte = 8'h00;
            4'd5: cmd_byte = 8'h00;
            4'd6: cmd_byte = 8'h00;
            4'd7: cmd_byte = CMD_CRC_LSB_FIRST ? 8'h6E : 8'h02;  // 02 = CRC 高字节在前
            4'd8: cmd_byte = CMD_CRC_LSB_FIRST ? 8'h02 : 8'h6E;  // 6E = CRC 低字节在前
            default: cmd_byte = 8'h00;
        endcase
    end

    // 锁不上时的重发节拍：约 1.4 s（V2.0 由 0.7 s 放慢，给模块留足启动推流时间）
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cmd_tick_cnt <= 24'd0;
            cmd_tick     <= 1'b0;
        end else begin
            if (cmd_tick_cnt == 24'hFFFFFF) begin
                cmd_tick_cnt <= 24'd0;
                cmd_tick     <= 1'b1;
            end else begin
                cmd_tick_cnt <= cmd_tick_cnt + 24'd1;
                cmd_tick     <= 1'b0;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cmd_pend <= 1'b0;
        else if (cmd_ack)
            cmd_pend <= 1'b0;
        else if (!armed && !key_a_press)
            cmd_pend <= 1'b0;                 // 模块上电自检期间不发命令（KEY_A 可插队）
        else if (!cmd_issued || key_a_press || (cmd_tick && !link_ok))
            cmd_pend <= 1'b1;                 // 首发 / KEY_A / 锁不上时的 1.4 s 节拍
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cmd_state    <= 2'd0;
            cmd_idx      <= 4'd0;
            cmd_start    <= 1'b0;
            cmd_data     <= 8'h00;
            cmd_seen     <= 1'b0;
            cmd_issued   <= 1'b0;
            cmd_ack      <= 1'b0;
            cmd_cnt      <= 16'd0;
        end else begin
            cmd_start <= 1'b0;
            cmd_ack   <= 1'b0;
            case (cmd_state)
                2'd0: begin                     // 等待发送请求
                    if (cmd_pend) begin
                        cmd_idx      <= 4'd0;
                        cmd_issued   <= 1'b1;
                        cmd_cnt      <= cmd_cnt + 16'd1;
                        cmd_state    <= 2'd1;
                    end
                end
                2'd1: begin                     // 发出一个字节
                    if (!cmd_busy && !cmd_start) begin
                        cmd_data  <= cmd_byte;
                        cmd_start <= 1'b1;
                        cmd_seen  <= 1'b0;
                        cmd_state <= 2'd2;
                    end
                end
                2'd2: begin                     // 等待发送完成
                    if (cmd_busy)
                        cmd_seen <= 1'b1;
                    if (cmd_seen && !cmd_busy) begin
                        if (cmd_idx == 4'd8) begin
                            cmd_ack   <= 1'b1;       // 本次尝试（单帧）结束
                            cmd_state <= 2'd0;
                        end else begin
                            cmd_idx   <= cmd_idx + 4'd1;
                            cmd_state <= 2'd1;
                        end
                    end
                end
                default: cmd_state <= 2'd0;
            endcase
        end
    end

    uart_tx u_tof_tx (
        .clk      (clk),
        .rst_n    (rst_n),
        .inc      (INC_TOF_TX),
        .tx_start (cmd_start),
        .tx_data  (cmd_data),
        .tx        (tof1_tx),
        .tx_busy  (cmd_busy)
    );

    // =========================================================================
    // 上位机串口：每 ~87 ms 按拨码选出的速率输出一行文本（共 49 字节）
    //   D=0843 I=0924 A=0012 C=00 F=0000 U=3 B=0000 L=1
    //   D 距离mm / I 强度 / A 环境光 / C CRC错计数 / F 帧计数 / U 上位机档 0..3 /
    //   B 收字节计数（4 位十六进制折回） / L 链路状态（1=1.4 s 内有合法帧）
    // 0 个或多个 ON（pc_en=0）时一个字都不发，见设计说明 §19。
    // =========================================================================
    reg  [19:0] pc_tick_cnt;
    reg         pc_tick;
    reg         pc_start;
    reg  [7:0]  pc_data;
    wire        pc_busy;
    reg  [5:0]  pc_idx;
    reg  [1:0]  pc_state;
    reg         pc_seen;
    reg  [7:0]  pc_byte;

    function [7:0] hexch;
        input [3:0] v;
        begin
            hexch = (v < 4'd10) ? (8'h30 + {4'd0, v}) : (8'h37 + {4'd0, v});
        end
    endfunction

    always @(*) begin
        pc_byte = 8'h20;
        case (pc_idx)
            6'd0:  pc_byte = "D";
            6'd1:  pc_byte = "=";
            6'd2:  pc_byte = hexch(dist_mm[15:12]);
            6'd3:  pc_byte = hexch(dist_mm[11:8]);
            6'd4:  pc_byte = hexch(dist_mm[7:4]);
            6'd5:  pc_byte = hexch(dist_mm[3:0]);
            6'd6:  pc_byte = " ";
            6'd7:  pc_byte = "I";
            6'd8:  pc_byte = "=";
            6'd9:  pc_byte = hexch(inten[15:12]);
            6'd10: pc_byte = hexch(inten[11:8]);
            6'd11: pc_byte = hexch(inten[7:4]);
            6'd12: pc_byte = hexch(inten[3:0]);
            6'd13: pc_byte = " ";
            6'd14: pc_byte = "A";
            6'd15: pc_byte = "=";
            6'd16: pc_byte = hexch(amb[15:12]);
            6'd17: pc_byte = hexch(amb[11:8]);
            6'd18: pc_byte = hexch(amb[7:4]);
            6'd19: pc_byte = hexch(amb[3:0]);
            6'd20: pc_byte = " ";
            6'd21: pc_byte = "C";
            6'd22: pc_byte = "=";
            6'd23: pc_byte = hexch(crc_cnt[7:4]);
            6'd24: pc_byte = hexch(crc_cnt[3:0]);
            6'd25: pc_byte = " ";
            6'd26: pc_byte = "F";
            6'd27: pc_byte = "=";
            6'd28: pc_byte = hexch(frm_cnt[15:12]);
            6'd29: pc_byte = hexch(frm_cnt[11:8]);
            6'd30: pc_byte = hexch(frm_cnt[7:4]);
            6'd31: pc_byte = hexch(frm_cnt[3:0]);
            6'd32: pc_byte = " ";
            6'd33: pc_byte = "U";
            6'd34: pc_byte = "=";
            6'd35: pc_byte = (pc_rate == 2'd0) ? "0" :   // 上位机串口档 0..3
                               (pc_rate == 2'd1) ? "1" :
                               (pc_rate == 2'd2) ? "2" : "3";
            6'd36: pc_byte = " ";
            6'd37: pc_byte = "B";
            6'd38: pc_byte = "=";
            6'd39: pc_byte = hexch(rx_cnt[15:12]);
            6'd40: pc_byte = hexch(rx_cnt[11:8]);
            6'd41: pc_byte = hexch(rx_cnt[7:4]);
            6'd42: pc_byte = hexch(rx_cnt[3:0]);
            6'd43: pc_byte = " ";
            6'd44: pc_byte = "L";
            6'd45: pc_byte = "=";
            6'd46: pc_byte = link_ok ? "1" : "0";   // 链路状态
            6'd47: pc_byte = 8'h0D;
            6'd48: pc_byte = 8'h0A;
            default: pc_byte = 8'h00;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_tick_cnt <= 20'd0;
            pc_tick     <= 1'b0;
        end else begin
            if (pc_tick_cnt == 20'hFFFFF) begin
                pc_tick_cnt <= 20'd0;
                pc_tick     <= 1'b1;
            end else begin
                pc_tick_cnt <= pc_tick_cnt + 20'd1;
                pc_tick     <= 1'b0;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_state <= 2'd0;
            pc_idx   <= 6'd0;
            pc_start <= 1'b0;
            pc_data  <= 8'h00;
            pc_seen  <= 1'b0;
        end else begin
            pc_start <= 1'b0;
            case (pc_state)
                2'd0: begin
                    // pc_en=0（0 个或多个 ON）时整行不启动，串口上没有任何字节
                    if (pc_tick && pc_en) begin
                        pc_idx   <= 6'd0;
                        pc_state <= 2'd1;
                    end
                end
                2'd1: begin
                    if (!pc_busy && !pc_start) begin
                        pc_data  <= pc_byte;
                        pc_start <= 1'b1;
                        pc_seen  <= 1'b0;
                        pc_state <= 2'd2;
                    end
                end
                2'd2: begin
                    if (pc_busy)
                        pc_seen <= 1'b1;
                    if (pc_seen && !pc_busy) begin
                        if (pc_idx == 6'd48)
                            pc_state <= 2'd0;
                        else begin
                            pc_idx   <= pc_idx + 6'd1;
                            pc_state <= 2'd1;
                        end
                    end
                end
                default: pc_state <= 2'd0;
            endcase
        end
    end

    // 上位机串口发送速率：由拨码 SW0..SW3 选出的 4 档之一
    // inc = baud * 65536 / 12 MHz（uart_tx 的步进约定）
    reg [16:0] inc_pc_tx;
    always @(*) begin
        case (pc_rate)
            2'd0:    inc_pc_tx = 17'd52;      // 9600
            2'd1:    inc_pc_tx = 17'd629;     // 115200
            2'd2:    inc_pc_tx = 17'd1258;    // 230400
            default: inc_pc_tx = 17'd5033;    // 921600
        endcase
    end

    uart_tx u_pc_tx (
        .clk      (clk),
        .rst_n    (rst_n),
        .inc      (inc_pc_tx),
        .tx_start (pc_start),
        .tx_data  (pc_data),
        .tx        (dbg_tx),
        .tx_busy  (pc_busy)
    );

    // =========================================================================
    // 距离 BCD 转换（供 OLED 与数码管共用）
    // =========================================================================
    reg        bcd_start;
    wire [19:0] bcd_dist;
    wire        bcd_busy;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            bcd_start <= 1'b0;
        else
            bcd_start <= frame_ok;
    end

    bcd_conv u_bcd (
        .clk     (clk),
        .rst_n   (rst_n),
        .start   (bcd_start),
        .bin_in  (dist_mm),
        .bcd_out (bcd_dist),
        .busy    (bcd_busy)
    );

    // =========================================================================
    // OLED 显示
    // =========================================================================
    wire [3:0] oled_line;
    wire [3:0] oled_col;
    wire       oled_load;      // SPI 屏正在取字符（S_LOAD）

    // I²C 屏请求的字符地址（由 ssd1306 驱动）
    wire [5:0] i2c_line;
    wire [3:0] i2c_col;

    // 共享 disp_chargen：SPI 屏 S_LOAD 时优先，其余周期给 I²C 屏
    wire [5:0] chg_line = oled_load ? {2'b00, oled_line} : i2c_line;
    wire [3:0] chg_col  = oled_load ? oled_col : i2c_col;
    wire [7:0] chg_ch;

    // V3.0-P3d：两块屏共享一份字库（原先 oled_sh1107 / ssd1306 各带一份）
    wire [2:0] oled_font_col;
    wire [2:0] i2c_font_col;
    wire [2:0] font_col = oled_load ? oled_font_col : i2c_font_col;
    wire [7:0] font_bits;

    font8x8 u_font (
        .ch   (chg_ch),
        .col  (font_col),
        .bits (font_bits)
    );

    disp_chargen u_chargen (
        .line      (chg_line),
        .col       (chg_col),
        .bcd_dist  (bcd_dist),
        .inten_hex (inten),
        .amb_hex   (amb),
        .crc_cnt   (crc_cnt),
        .frm_cnt   (frm_cnt),
        .rx_cnt    (rx_cnt),
        .pc_rate   (pc_rate),
        .cmd_cnt   (cmd_cnt),
        .sw_num    (sw_num),
        .dist_valid (link_ok),
        .link_ok    (link_ok),
        .ui_sel     (ui_sel),
        .alarm_en   (alarm_en),
        .warn_bcd   (warn_bcd),
        .light_style(light_style),
        .ch         (chg_ch)
    );

    // 上电全亮自检窗口：24'h7FFFFF 计数 ÷ 12 MHz ≈ 699 ms
    // （24'hFFFFFF 才是 1.398 s；V2.0 注释与常量逐项核对过，见 §19.5）
    reg [23:0] test_cnt;
    reg        test_on;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            test_cnt <= 24'd0;
            test_on  <= 1'b1;
        end else if (test_cnt != 24'h7FFFFF) begin
            test_cnt <= test_cnt + 24'd1;
        end else begin
            test_on  <= 1'b0;
        end
    end

    oled_sh1107 u_oled (
        .clk       (clk),
        .rst_n     (rst_n),
        .rd_line   (oled_line),
        .rd_col    (oled_col),
        .rd_bits   (font_bits),
        .font_col  (oled_font_col),
        .ch_load   (oled_load),
        .test_on   (test_on),
        .oled_sclk (oled_sclk),
        .oled_mosi (oled_mosi),
        .oled_dc   (oled_dc),
        .oled_res  (oled_res)
    );

    // =========================================================================
    // V3.0-P2：I²C 128x64 OLED（SSD1306，0x3C）
    //   接载板 OLED_B 4 pin 座（1 GND / 2 3V3 / 3 SCL / 4 SDA）；
    //   SCL = IO31（H5，推挽），SDA = IO32（H9，inout 开漏，需模块自带或
    //   外焊 4.7 kΩ 上拉）。P2 显示测试图案，P3 换成正式文字页。
    // =========================================================================
    ssd1306_128x64 u_i2c_oled (
        .clk      (clk),
        .rst_n    (rst_n),
        .i2c_scl  (i2c_scl),
        .i2c_sda  (i2c_sda),
        .chg_line (i2c_line),
        .chg_col  (i2c_col),
        .chg_ch   (chg_ch),
        .chg_busy (oled_load),
        .font_bits(font_bits),
        .font_col (i2c_font_col),
        .ui_page  (ui_page),
        .digit_sel(digit_sel),
        .bright   (4'd4)            // 固定亮度，UI 不再调
    );

    // =========================================================================
    // V3.0-P4：距离报警 + 两颗 WS2812 灯效预览
    //   判据与回差在 alarm_ctrl 内；距离报警由 LED2 2 Hz 闪指示，
    //   WS2812 只在 LIGHT STYLE 子页手动预览（P4.1 起不参与报警）。
    //   WS2812 数据脚 = 核心板 COLOR（C5），两颗级联。
    // =========================================================================
    wire        alarm_act;
    wire        alarm_blink;
    wire [23:0] ws_led1;
    wire [23:0] ws_led2;

    alarm_ctrl u_alarm (
        .clk         (clk),
        .rst_n       (rst_n),
        .dist_mm     (dist_mm),
        .dist_valid  (dist_valid),
        .link_ok     (link_ok),
        .alarm_en    (alarm_en),
        .alarm_mm    (alarm_mm),
        .light_style (light_style),
        .preview     (ui_page == 2'd2),   // LIGHT STYLE 子页实时预览灯效
        .alarm_act   (alarm_act),
        .alarm_blink (alarm_blink),
        .led1        (ws_led1),
        .led2        (ws_led2)
    );

    ws2812_drv u_ws2812 (
        .clk   (clk),
        .rst_n (rst_n),
        .c1    (ws_led1),
        .c2    (ws_led2),
        .dout  (COLOR)
    );

    // =========================================================================
    // 2 位数码管
    // =========================================================================
    seg7_595 u_seg7 (
        .clk         (clk),
        .rst_n       (rst_n),
        .bcd_dist    (bcd_dist),
        .dist_valid  (link_ok),
        .dig         (seg_dig),
        .seg_sck     (seg_sck),
        .seg_rck     (seg_rck),
        .seg_din     (seg_din)
    );

    // =========================================================================
    // LED 状态（V2.0：正逻辑 —— 下列表达式为 1 表示该灯点亮）
    //   LED1 心跳 ~0.5 s / LED2 距离报警 2 Hz（默认灭）/ LED3 链路 OK /
    //   LED4 上位机串口已开启 / LED5..8 = 档位 9600/115200/230400/921600
    // 核心板 LED 低电平点亮（《STEP-HR03-U81 快速入门》实验一“输出低电平时 LED 变亮”），
    // 所以逻辑值统一在末尾取反；换板后极性若相反，只改 LED_ACTIVE_LOW 一处即可。
    // =========================================================================
    localparam LED_ACTIVE_LOW = 1'b1;   // 1 = 低电平点亮（核心板实测/官方文档）
    reg [23:0] hb_cnt;
    reg        hb;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hb_cnt <= 24'd0;
            hb     <= 1'b0;
        end else if (hb_cnt == 24'h5FFFFF) begin     // 约 0.5 s
            hb_cnt <= 24'd0;
            hb     <= ~hb;
        end else begin
            hb_cnt <= hb_cnt + 24'd1;
        end
    end

    // LED2 不再做帧闪：V3.0-P4.1 起改为距离报警 2 Hz 闪烁（见下面 led_on[1]）
    // 说明：链路 OK 由 LED3 指示；CRC 错计数从 OLED 第 8 行读取。

    // ---- V3.0 P3 调试开关 ----
    //   DEBUG_INPUT=1：8 个 LED 直接映射输入（LED0..3 = KEY1..KEY4，LED4 = A，
    //                  LED5 = B，LED6 = 编码器按下，LED7 = 旋转 step 翻转）。
    //   DEBUG_INPUT=0：恢复 V2.0 运行状态指示（P3b 起为 0）。
    localparam DEBUG_INPUT = 1'b0;

    reg rot_tog;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rot_tog <= 1'b0;
        else if (rot_step)
            rot_tog <= ~rot_tog;
    end

    // ---- 正逻辑：1 = 亮 ----
    wire [7:0] led_on;

    generate
        if (DEBUG_INPUT) begin : g_dbg_input
            assign led_on = {rot_tog, key_hold[4], phase_b, phase_a,
                             key_hold[3:0]};
        end else begin : g_normal
            assign led_on[0] = hb;                          // 心跳：程序在跑
            assign led_on[1] = alarm_act ? alarm_blink : 1'b0; // 距离过近：2 Hz 报警闪（默认灭）
            assign led_on[2] = link_ok;                     // 链路 OK（1.4 s 内有合法帧）
            assign led_on[3] = pc_en;                       // 上位机串口已开启
            // 档位灯：只反映“上位机串口”的档位；串口关闭（0 个或多个 ON）时全灭
            assign led_on[4] = pc_en && (pc_rate == 2'd0);  // 9600
            assign led_on[5] = pc_en && (pc_rate == 2'd1);  // 115200
            assign led_on[6] = pc_en && (pc_rate == 2'd2);  // 230400
            assign led_on[7] = pc_en && (pc_rate == 2'd3);  // 921600（不再叠加报警）
        end
    endgenerate

    // 上电约 0.7 s 全亮自检（test_on）；之后按极性输出
    assign led = test_on ? (LED_ACTIVE_LOW ? 8'h00 : 8'hFF)
                         : (LED_ACTIVE_LOW ? ~led_on : led_on);

endmodule
