// =============================================================================
// 文件名   : disp_chargen.v
// 功能     : 按 (行, 列) 生成 OLED 文本字符（纯组合），供 OLED 扫描直接取用
// 说明     : 46 行 x 16 列字符（0..45），每行 8 像素高；未定义位置输出空格
//            **所有行都从第 0 列开始显示**（左对齐，不再有 1 字符缩进）
//            距离用 BCD 十进制显示（≥10 m 自动用 5 位），其余计数用十六进制
//            标题行版本号随版本更新（用于肉眼确认“板上跑的确实是新版本”）
//            V2.0：第 11 行标签 UART: -> PC:，第 12 行显示上位机串口状态
//                  （OFF = 全 OFF 关闭 / ERROR = 多个 ON 非法 / 9600..921600 = 该档）
//            V3.0-P3c：line 扩到 6 bit；16..45 行给小屏单页菜单/子页（45 行空白）；
//                  大屏 0..15 行保持不变；I²C 128x64 屏复用本模块做文本源
// 版本     : V3.0-P3c (2026-11-14)
// =============================================================================
`timescale 1ns/1ps

module disp_chargen (
    input  wire [5:0]  line,        // 0..45
    input  wire [3:0]  col,         // 0..15
    input  wire [19:0] bcd_dist,    // 距离 mm 的 5 位 BCD
    input  wire [15:0] inten_hex,
    input  wire [15:0] amb_hex,
    input  wire [15:0] crc_cnt,
    input  wire [15:0] frm_cnt,
    input  wire [15:0] rx_cnt,      // 累计收到的字节数（诊断用）
    input  wire [1:0]  pc_rate,     // 上位机串口档位：0=9600 1=115200 2=230400 3=921600
    input  wire [15:0] cmd_cnt,     // 已发起的启动命令尝试次数
    input  wire [2:0]  sw_num,      // ON 的拨码个数：0=全 OFF 1=恰好一个 >1=非法
    input  wire        dist_valid,  // 1 = 最近 1.4 s 内有合法帧
    input  wire        link_ok,     // 1 = 已锁定并持续收到帧
    // ---- V3.0-P3c：小屏单页菜单输入 ----
    input  wire [1:0]  ui_sel,      // 主页选中项：0=ALARM 1=WARN 2=LIGHT 3=INFO
    input  wire        alarm_en,    // 报警开关
    input  wire [15:0] warn_bcd,    // 预警阈值 {十米,米,分米,厘米}，05.00 m = 16'h0500
    input  wire [2:0]  light_style, // 0=RED BLINK 1=AMBER BLINK 2=GREEN SOLID
                                    // 3=POLICE 4=BREATHE 5=RAINBOW
    output reg  [7:0]  ch
);

    // ---------------- 十六进制字符 ----------------
    function [7:0] hexch;
        input [3:0] v;
        begin
            if (v < 4'd10) hexch = 8'h30 + {4'd0, v};
            else           hexch = 8'h37 + {4'd0, v};   // 10 -> 'A'
        end
    endfunction

    // ---------------- 十进制字符 ----------------
    function [7:0] decch;
        input [3:0] v;
        decch = 8'h30 + {4'd0, v};
    endfunction

    // 预警距离 BCD 各位（便于行 21 / 25 显示 dd.dd）
    wire [3:0] w_tens   = warn_bcd[15:12];
    wire [3:0] w_units  = warn_bcd[11:8];
    wire [3:0] w_tenths = warn_bcd[7:4];
    wire [3:0] w_hund   = warn_bcd[3:0];

    always @(*) begin
        ch = 8'h20;   // 默认空格
        case (line)
            // ---- 第 0 行：标题 ----
            4'd0: case (col)
                4'd0:  ch = "T";
                4'd1:  ch = "O";
                4'd2:  ch = "F";
                4'd4:  ch = "M";
                4'd5:  ch = "1";
                4'd7:  ch = "V";
                4'd8:  ch = "3";
                4'd9:  ch = ".";
                4'd10: ch = "0";        // 标题行显示 TOF M1 V3.0
                default: ch = 8'h20;
            endcase

            // ---- 第 1 行：距离标题 ----
            4'd1: case (col)
                4'd0: ch = "D";
                4'd1: ch = "I";
                4'd2: ch = "S";
                4'd3: ch = "T";
                4'd4: ch = ":";
                default: ch = 8'h20;
            endcase

            // ---- 第 2 行：距离数值（左对齐，从第 0 列开始） ----
            // V1.6：bcd_dist[19:16] 是万位。≥10 m 时用 5 位显示，单位改到第 6/7 列，
            //       否则仍是 4 位 + 第 5/6 列的 MM（修复 ≥10 m 最高位丢失的问题）
            4'd2: begin
                if (!dist_valid) begin
                    case (col)
                        4'd0: ch = "-";
                        4'd1: ch = "-";
                        4'd2: ch = "-";
                        4'd3: ch = "-";
                        default: ch = 8'h20;
                    endcase
                end else if (bcd_dist[19:16] != 4'd0) begin
                    case (col)
                        4'd0: ch = decch(bcd_dist[19:16]);   // 万位
                        4'd1: ch = decch(bcd_dist[15:12]);   // 千位
                        4'd2: ch = decch(bcd_dist[11:8]);    // 百位
                        4'd3: ch = decch(bcd_dist[7:4]);     // 十位
                        4'd4: ch = decch(bcd_dist[3:0]);     // 个位
                        4'd6: ch = "M";
                        4'd7: ch = "M";
                        default: ch = 8'h20;
                    endcase
                end else begin
                    case (col)
                        4'd0: ch = decch(bcd_dist[15:12]);   // 千位
                        4'd1: ch = decch(bcd_dist[11:8]);    // 百位
                        4'd2: ch = decch(bcd_dist[7:4]);     // 十位
                        4'd3: ch = decch(bcd_dist[3:0]);     // 个位
                        4'd5: ch = "M";
                        4'd6: ch = "M";
                        default: ch = 8'h20;
                    endcase
                end
            end

            // ---- 第 3 行：强度标题 ----
            4'd3: case (col)
                4'd0: ch = "I";
                4'd1: ch = "N";
                4'd2: ch = "T";
                4'd3: ch = ":";
                default: ch = 8'h20;
            endcase

            // ---- 第 4 行：强度十六进制 ----
            4'd4: case (col)
                4'd0: ch = hexch(inten_hex[15:12]);
                4'd1: ch = hexch(inten_hex[11:8]);
                4'd2: ch = hexch(inten_hex[7:4]);
                4'd3: ch = hexch(inten_hex[3:0]);
                default: ch = 8'h20;
            endcase

            // ---- 第 5 行：环境光标题 ----
            4'd5: case (col)
                4'd0: ch = "A";
                4'd1: ch = "M";
                4'd2: ch = "B";
                4'd3: ch = ":";
                default: ch = 8'h20;
            endcase

            // ---- 第 6 行：环境光十六进制 ----
            4'd6: case (col)
                4'd0: ch = hexch(amb_hex[15:12]);
                4'd1: ch = hexch(amb_hex[11:8]);
                4'd2: ch = hexch(amb_hex[7:4]);
                4'd3: ch = hexch(amb_hex[3:0]);
                default: ch = 8'h20;
            endcase

            // ---- 第 7 行：CRC 错误计数标题 ----
            4'd7: case (col)
                4'd0: ch = "C";
                4'd1: ch = "R";
                4'd2: ch = "C";
                4'd3: ch = "-";
                4'd4: ch = "E";
                4'd5: ch = "R";
                4'd6: ch = "R";
                default: ch = 8'h20;
            endcase

            // ---- 第 8 行：CRC 错误计数 ----
            4'd8: case (col)
                4'd0: ch = hexch(crc_cnt[15:12]);
                4'd1: ch = hexch(crc_cnt[11:8]);
                4'd2: ch = hexch(crc_cnt[7:4]);
                4'd3: ch = hexch(crc_cnt[3:0]);
                default: ch = 8'h20;
            endcase

            // ---- 第 9 行：有效帧计数标题 ----
            4'd9: case (col)
                4'd0: ch = "F";
                4'd1: ch = "R";
                4'd2: ch = "A";
                4'd3: ch = "M";
                4'd4: ch = "E";
                4'd5: ch = ":";
                default: ch = 8'h20;
            endcase

            // ---- 第 10 行：有效帧计数 ----
            4'd10: case (col)
                4'd0: ch = hexch(frm_cnt[15:12]);
                4'd1: ch = hexch(frm_cnt[11:8]);
                4'd2: ch = hexch(frm_cnt[7:4]);
                4'd3: ch = hexch(frm_cnt[3:0]);
                default: ch = 8'h20;
            endcase

            // ---- 第 11 行：上位机串口标题（V2.0：UART: -> PC:） ----
            4'd11: case (col)
                4'd0: ch = "P";
                4'd1: ch = "C";
                4'd2: ch = ":";
                default: ch = 8'h20;
            endcase

            // ---- 第 12 行：上位机串口状态（V2.0） ----
            // 0 个 ON = OFF（串口关闭）；多个 ON = ERROR（非法，串口关闭）；
            // 恰好 1 个 ON = 按该档显示速率；拨码一变这里立刻跟着变。
            4'd12: begin
                if (sw_num == 3'd0) begin                 // 全 OFF：关闭上位机串口
                    case (col)
                        4'd0: ch = "O";
                        4'd1: ch = "F";
                        4'd2: ch = "F";
                        default: ch = 8'h20;
                    endcase
                end else if (sw_num > 3'd1) begin         // 多个 ON：非法
                    case (col)
                        4'd0: ch = "E";
                        4'd1: ch = "R";
                        4'd2: ch = "R";
                        4'd3: ch = "O";
                        4'd4: ch = "R";
                        default: ch = 8'h20;
                    endcase
                end else if (pc_rate == 2'd0) begin       // 9600
                    case (col)
                        4'd0: ch = "9";
                        4'd1: ch = "6";
                        4'd2: ch = "0";
                        4'd3: ch = "0";
                        default: ch = 8'h20;
                    endcase
                end else if (pc_rate == 2'd1) begin       // 115200
                    case (col)
                        4'd0: ch = "1";
                        4'd1: ch = "1";
                        4'd2: ch = "5";
                        4'd3: ch = "2";
                        4'd4: ch = "0";
                        4'd5: ch = "0";
                        default: ch = 8'h20;
                    endcase
                end else if (pc_rate == 2'd2) begin       // 230400
                    case (col)
                        4'd0: ch = "2";
                        4'd1: ch = "3";
                        4'd2: ch = "0";
                        4'd3: ch = "4";
                        4'd4: ch = "0";
                        4'd5: ch = "0";
                        default: ch = 8'h20;
                    endcase
                end else begin                            // 921600
                    case (col)
                        4'd0: ch = "9";
                        4'd1: ch = "2";
                        4'd2: ch = "1";
                        4'd3: ch = "6";
                        4'd4: ch = "0";
                        4'd5: ch = "0";
                        default: ch = 8'h20;
                    endcase
                end
            end

            // ---- 第 13 行：累计收到的字节数（判断“线上到底有没有数据”） ----
            4'd13: case (col)
                4'd0: ch = "R";
                4'd1: ch = "X";
                4'd2: ch = "B";
                4'd3: ch = ":";
                4'd4: ch = hexch(rx_cnt[15:12]);
                4'd5: ch = hexch(rx_cnt[11:8]);
                4'd6: ch = hexch(rx_cnt[7:4]);
                4'd7: ch = hexch(rx_cnt[3:0]);
                default: ch = 8'h20;
            endcase

            // ---- 第 14 行：链路状态 ----
            4'd14: case (col)
                4'd0: ch = "L";
                4'd1: ch = "I";
                4'd2: ch = "N";
                4'd3: ch = "K";
                4'd4: ch = ":";
                4'd5: ch = link_ok ? "O" : "N";
                4'd6: ch = link_ok ? "K" : "O";
                default: ch = 8'h20;
            endcase

            // ---- 第 15 行：启动命令尝试次数（V2.0 删掉 S0/S1：字节序已是常量） ----
            4'd15: case (col)
                4'd0: ch = "C";
                4'd1: ch = "M";
                4'd2: ch = "D";
                4'd3: ch = ":";
                4'd4: ch = hexch(cmd_cnt[15:12]);
                4'd5: ch = hexch(cmd_cnt[11:8]);
                4'd6: ch = hexch(cmd_cnt[7:4]);
                4'd7: ch = hexch(cmd_cnt[3:0]);
                default: ch = 8'h20;
            endcase

            // ================= V3.0-P3c：小屏单页菜单 + 子页（I²C 屏） =================

            // ---- 第 16 行：标题（与第 0 行一致） ----
            6'd16: case (col)
                4'd0:  ch = "T";
                4'd1:  ch = "O";
                4'd2:  ch = "F";
                4'd4:  ch = "M";
                4'd5:  ch = "1";
                4'd7:  ch = "V";
                4'd8:  ch = "3";
                4'd9:  ch = ".";
                4'd10: ch = "0";
                default: ch = 8'h20;
            endcase

            // ---- 第 17 行：固定副标题 ----
            6'd17: case (col)
                4'd0:  ch = "S";
                4'd1:  ch = "E";
                4'd2:  ch = "T";
                4'd3:  ch = "T";
                4'd4:  ch = "I";
                4'd5:  ch = "N";
                4'd6:  ch = "G";
                4'd8:  ch = "P";
                4'd9:  ch = "A";
                4'd10: ch = "G";
                4'd11: ch = "E";
                default: ch = 8'h20;
            endcase

            // ---- 第 18 行：分隔线 ----
            6'd18: case (col)
                4'd0: ch = "-";
                4'd1: ch = "-";
                4'd2: ch = "-";
                4'd3: ch = "-";
                4'd4: ch = "-";
                4'd5: ch = "-";
                4'd6: ch = "-";
                4'd7: ch = "-";
                default: ch = 8'h20;
            endcase

            // ---- 第 19 行：报警开关（主页选中项 0） ----
            6'd19: case (col)
                4'd0: ch = (ui_sel == 2'd0) ? ">" : 8'h20;
                4'd1: ch = "A";
                4'd2: ch = "L";
                4'd3: ch = "A";
                4'd4: ch = "R";
                4'd5: ch = "M";
                4'd7: ch = "O";
                4'd8: ch = alarm_en ? "N" : "F";
                4'd9: ch = alarm_en ? 8'h20 : "F";
                default: ch = 8'h20;
            endcase

            // ---- 第 20 行：预警距离入口（主页选中项 1） ----
            6'd20: case (col)
                4'd0: ch = (ui_sel == 2'd1) ? ">" : 8'h20;
                4'd1: ch = "W";
                4'd2: ch = "A";
                4'd3: ch = "R";
                4'd4: ch = "N";
                4'd6: ch = "D";
                4'd7: ch = "I";
                4'd8: ch = "S";
                4'd9: ch = "T";
                default: ch = 8'h20;
            endcase

            // ---- 第 21 行：预警距离当前值（只读，从 col1 对齐） ----
            6'd21: case (col)
                4'd1: ch = decch(w_tens);
                4'd2: ch = decch(w_units);
                4'd3: ch = ".";
                4'd4: ch = decch(w_tenths);
                4'd5: ch = decch(w_hund);
                4'd6: ch = 8'h20;
                4'd7: ch = "M";
                default: ch = 8'h20;
            endcase

            // ---- 第 22 行：灯光样式入口（主页选中项 2） ----
            6'd22: case (col)
                4'd0:  ch = (ui_sel == 2'd2) ? ">" : 8'h20;
                4'd1:  ch = "L";
                4'd2:  ch = "I";
                4'd3:  ch = "G";
                4'd4:  ch = "H";
                4'd5:  ch = "T";
                4'd7:  ch = "S";
                4'd8:  ch = "T";
                4'd9:  ch = "Y";
                4'd10: ch = "L";
                4'd11: ch = "E";
                default: ch = 8'h20;
            endcase

            // ---- 第 23 行：INFO 入口（主页选中项 3） ----
            6'd23: case (col)
                4'd0: ch = (ui_sel == 2'd3) ? ">" : 8'h20;
                4'd1: ch = "I";
                4'd2: ch = "N";
                4'd3: ch = "F";
                4'd4: ch = "O";
                default: ch = 8'h20;
            endcase

            // ---- 第 24-28 行：WARN DIST 子页 ----
            6'd24: case (col)
                4'd0: ch = "W";
                4'd1: ch = "A";
                4'd2: ch = "R";
                4'd3: ch = "N";
                4'd5: ch = "D";
                4'd6: ch = "I";
                4'd7: ch = "S";
                4'd8: ch = "T";
                default: ch = 8'h20;
            endcase

            6'd25: case (col)
                4'd0:  ch = "L";
                4'd1:  ch = "I";
                4'd2:  ch = "M";
                4'd3:  ch = "I";
                4'd4:  ch = "T";
                4'd5:  ch = 8'h20;
                4'd6:  ch = decch(w_tens);
                4'd7:  ch = decch(w_units);
                4'd8:  ch = ".";
                4'd9:  ch = decch(w_tenths);
                4'd10: ch = decch(w_hund);
                4'd11: ch = 8'h20;
                4'd12: ch = "M";
                default: ch = 8'h20;
            endcase

            6'd26: case (col)   // "K1/K2: SEL DIGIT"
                4'd0: ch = "K";
                4'd1: ch = "1";
                4'd2: ch = "/";
                4'd3: ch = "K";
                4'd4: ch = "2";
                4'd5: ch = ":";
                4'd7: ch = "S";
                4'd8: ch = "E";
                4'd9: ch = "L";
                4'd11: ch = "D";
                4'd12: ch = "I";
                4'd13: ch = "G";
                4'd14: ch = "I";
                4'd15: ch = "T";
                default: ch = 8'h20;
            endcase

            6'd27: case (col)   // "TURN: +/-"
                4'd0: ch = "T";
                4'd1: ch = "U";
                4'd2: ch = "R";
                4'd3: ch = "N";
                4'd4: ch = ":";
                4'd6: ch = "+";
                4'd7: ch = "/";
                4'd8: ch = "-";
                default: ch = 8'h20;
            endcase

            6'd28: case (col)
                4'd0:  ch = "K";
                4'd1:  ch = "3";
                4'd3:  ch = "O";
                4'd4:  ch = "K";
                4'd6:  ch = "K";
                4'd7:  ch = "4";
                4'd9:  ch = "C";
                4'd10: ch = "L";
                4'd11: ch = "R";
                default: ch = 8'h20;
            endcase

            // ---- 第 29-35 行：LIGHT STYLE 子页 ----
            6'd29: case (col)
                4'd0:  ch = "L";
                4'd1:  ch = "I";
                4'd2:  ch = "G";
                4'd3:  ch = "H";
                4'd4:  ch = "T";
                4'd6:  ch = "S";
                4'd7:  ch = "T";
                4'd8:  ch = "Y";
                4'd9:  ch = "L";
                4'd10: ch = "E";
                default: ch = 8'h20;
            endcase

            6'd30: case (col)   // style 0: RED BLINK
                4'd0: ch = (light_style == 3'd0) ? ">" : 8'h20;
                4'd1: ch = "R";
                4'd2: ch = "E";
                4'd3: ch = "D";
                4'd5: ch = "B";
                4'd6: ch = "L";
                4'd7: ch = "I";
                4'd8: ch = "N";
                4'd9: ch = "K";
                default: ch = 8'h20;
            endcase

            6'd31: case (col)   // style 1: AMBER BLINK
                4'd0:  ch = (light_style == 3'd1) ? ">" : 8'h20;
                4'd1:  ch = "A";
                4'd2:  ch = "M";
                4'd3:  ch = "B";
                4'd4:  ch = "E";
                4'd5:  ch = "R";
                4'd7:  ch = "B";
                4'd8:  ch = "L";
                4'd9:  ch = "I";
                4'd10: ch = "N";
                4'd11: ch = "K";
                default: ch = 8'h20;
            endcase

            6'd32: case (col)   // style 2: GREEN SOLID
                4'd0:  ch = (light_style == 3'd2) ? ">" : 8'h20;
                4'd1:  ch = "G";
                4'd2:  ch = "R";
                4'd3:  ch = "E";
                4'd4:  ch = "E";
                4'd5:  ch = "N";
                4'd7:  ch = "S";
                4'd8:  ch = "O";
                4'd9:  ch = "L";
                4'd10: ch = "I";
                4'd11: ch = "D";
                default: ch = 8'h20;
            endcase

            6'd33: case (col)   // style 3: POLICE
                4'd0: ch = (light_style == 3'd3) ? ">" : 8'h20;
                4'd1: ch = "P";
                4'd2: ch = "O";
                4'd3: ch = "L";
                4'd4: ch = "I";
                4'd5: ch = "C";
                4'd6: ch = "E";
                default: ch = 8'h20;
            endcase

            6'd34: case (col)   // style 4: BREATHE
                4'd0: ch = (light_style == 3'd4) ? ">" : 8'h20;
                4'd1: ch = "B";
                4'd2: ch = "R";
                4'd3: ch = "E";
                4'd4: ch = "A";
                4'd5: ch = "T";
                4'd6: ch = "H";
                4'd7: ch = "E";
                default: ch = 8'h20;
            endcase

            6'd35: case (col)   // style 5: RAINBOW
                4'd0: ch = (light_style == 3'd5) ? ">" : 8'h20;
                4'd1: ch = "R";
                4'd2: ch = "A";
                4'd3: ch = "I";
                4'd4: ch = "N";
                4'd5: ch = "B";
                4'd6: ch = "O";
                4'd7: ch = "W";
                default: ch = 8'h20;
            endcase

            6'd36: case (col)   // "K3:OK K4:DEF"
                4'd0:  ch = "K";
                4'd1:  ch = "3";
                4'd2:  ch = ":";
                4'd3:  ch = "O";
                4'd4:  ch = "K";
                4'd6:  ch = "K";
                4'd7:  ch = "4";
                4'd8:  ch = ":";
                4'd9:  ch = "D";
                4'd10: ch = "E";
                4'd11: ch = "F";
                default: ch = 8'h20;
            endcase

            // ---- 第 37-44 行：INFO 页 ----
            6'd37: case (col)
                4'd0: ch = "I";
                4'd1: ch = "N";
                4'd2: ch = "F";
                4'd3: ch = "O";
                default: ch = 8'h20;
            endcase

            6'd38: case (col)
                4'd0:  ch = "T";
                4'd1:  ch = "O";
                4'd2:  ch = "F";
                4'd4:  ch = "M";
                4'd5:  ch = "1";
                4'd7:  ch = "V";
                4'd8:  ch = "3";
                4'd9:  ch = ".";
                4'd10: ch = "0";
                default: ch = 8'h20;
            endcase

            6'd39: case (col)
                4'd0: ch = "H";
                4'd1: ch = "R";
                4'd2: ch = "0";
                4'd3: ch = "3";
                4'd5: ch = "F";
                4'd6: ch = "P";
                4'd7: ch = "G";
                4'd8: ch = "A";
                default: ch = 8'h20;
            endcase

            6'd40: case (col)
                4'd0: ch = "2";
                4'd1: ch = "0";
                4'd2: ch = "2";
                4'd3: ch = "6";
                4'd4: ch = "-";
                4'd5: ch = "1";
                4'd6: ch = "1";
                default: ch = 8'h20;
            endcase

            6'd41: case (col)   // "MAIN: TURN + OK"
                4'd0:  ch = "M";
                4'd1:  ch = "A";
                4'd2:  ch = "I";
                4'd3:  ch = "N";
                4'd4:  ch = ":";
                4'd6:  ch = "T";
                4'd7:  ch = "U";
                4'd8:  ch = "R";
                4'd9:  ch = "N";
                4'd11: ch = "+";
                4'd13: ch = "O";
                4'd14: ch = "K";
                default: ch = 8'h20;
            endcase

            6'd42: case (col)   // "Designed by ZXA"
                4'd0:  ch = "D";
                4'd1:  ch = "e";
                4'd2:  ch = "s";
                4'd3:  ch = "i";
                4'd4:  ch = "g";
                4'd5:  ch = "n";
                4'd6:  ch = "e";
                4'd7:  ch = "d";
                4'd9:  ch = "b";
                4'd10: ch = "y";
                4'd12: ch = "Z";
                4'd13: ch = "X";
                4'd14: ch = "A";
                default: ch = 8'h20;
            endcase

            6'd43: case (col)   // "WARN: K1/K2 SEL"
                4'd0:  ch = "W";
                4'd1:  ch = "A";
                4'd2:  ch = "R";
                4'd3:  ch = "N";
                4'd4:  ch = ":";
                4'd6:  ch = "K";
                4'd7:  ch = "1";
                4'd8:  ch = "/";
                4'd9:  ch = "K";
                4'd10: ch = "2";
                4'd12: ch = "S";
                4'd13: ch = "E";
                4'd14: ch = "L";
                default: ch = 8'h20;
            endcase

            6'd44: case (col)   // "K3: BACK"
                4'd0: ch = "K";
                4'd1: ch = "3";
                4'd2: ch = ":";
                4'd4: ch = "B";
                4'd5: ch = "A";
                4'd6: ch = "C";
                4'd7: ch = "K";
                default: ch = 8'h20;
            endcase

            // 第 45 行为子页共用空白行，落到外层 default

            default: ch = 8'h20;
        endcase
    end

endmodule
