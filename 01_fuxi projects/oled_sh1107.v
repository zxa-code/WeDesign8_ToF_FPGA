// =============================================================================
// 文件名   : oled_sh1107.v
// 功能     : 1.12 寸 128x128 OLED（SH1107，4 线 SPI，CS 板上固定接地）驱动
// 说明     : 上电时序 -> 初始化命令表(23 项) 连发两遍 -> 0xAF 开屏 -> 循环刷新 16 页
//            每页 128 列，一行字符 8 像素高，共 16 行 x 16 字符
//            列数据由顶层共享的 font8x8 产生，字符由 disp_chargen 组合产生
//            SPI：SCLK = 3 MHz（clk 四分频），模式 0，MSB 先出
// 版本     : V1.6  (2026-11-04)
//
// ★ V1.6 上电可靠性改动（修“上电黑屏、按 KEY_B 复位后才出字”）：
//   1) RES 低电平 87 ms -> 175 ms，RES 拉高后等待 44 ms -> 175 ms；
//      冷启动时面板 VDD 爬升 + 内部 POR 完成需要更长时间，原时序余量不足。
//   2) 初始化表真正连发两遍：第一遍发完 -> S_GAP 等 43.7 ms -> 再发一遍 -> 0xAF。
//      （V1.5 及以前 S_GAP 没有任何入口，注释写的“发两遍”实际只发了一遍。）
//
// ★ 屏幕方向（两个参数，一起改才是 180°）
//   初始化表 init_idx=5 送 0xA0 / 0xA1：段方向（左右）
//       0xA0 = 正常；0xA1 = 左右镜像
//   初始化表 init_idx=6 送 0xC0 / 0xC8：COM 扫描方向（上下）
//       0xC0 = 正常；0xC8 = 上下翻转
//   现在用的是 0xA0 + 0xC0。若换屏后方向又反了：
//       只上下反 -> 0xC0 与 0xC8 对调；只左右反 -> 0xA0 与 0xA1 对调。
//
// ★ 每行文字起始位置（水平方向）：PIX_OFS
//   见下面 localparam PIX_OFS。原理：屏幕第 x 列像素取的是“源图第 (x+PIX_OFS) 列”，
//   所以 PIX_OFS 越大，整幅画面越往左移（文字起点越靠左）。
//   取值 0..15（单位：像素=1 个字符宽的 1/8），常用 0/2/4/6/8：
//       PIX_OFS = 0 -> 不左移；PIX_OFS = 8 -> 左移 1 个字符宽。
//   **实测文字左端已贴在第 0 列，所以默认 0**；再加就会把第一个字符切掉。
//   若换屏后左侧出现空白，再把它加到 2/4/6/8 补偿。
//   注意：左移 N 像素后，每行右侧会有 N 像素空白（源图超出 127 的部分按空白处理）。
//
// ★ 每行文字起始位置（垂直方向）：init_idx=11 的 0xDC 参数（display start line）
//       现在送 0x00；改成 0x04 之类可把整幅画面上移 4 行（下移用 128-4=0x7C）。
//   若只是想上下微调 1~2 行，优先改这里，别去改页序。
// =============================================================================
`timescale 1ns/1ps

module oled_sh1107 (
    input  wire        clk,
    input  wire        rst_n,
    output reg  [3:0]  rd_line,     // 当前扫描行（源行号，已做 180° 映射）
    output reg  [3:0]  rd_col,      // 当前字符列（源列号，已做 180° 映射）
    input  wire [7:0]  rd_ch,       // 该位置的字符（来自 disp_chargen）
    input  wire [7:0]  rd_bits,     // 共享字库给出的像素列（V3.0-P3d）
    output wire [2:0]  font_col,    // 本拍字库列地址（供顶层字库仲裁）
    output wire        ch_load,     // 1 = 本拍正在取字符（供 I²C 屏仲裁）
    input  wire        test_on,     // 1=全亮自检（V1.6：上电约 0.7 s）
    output reg         oled_sclk,
    output reg         oled_mosi,
    output reg         oled_dc,
    output reg         oled_res     // 低有效复位
);

    // ---------------- 水平起点偏移（见文件头说明） ----------------
    // 屏幕第 x 列 显示 源图第 (x + PIX_OFS) 列 -> 数值越大，文字越靠左
    // 实测：文字左端已经贴在第 0 列，再加偏移会把第一个字符切掉，所以默认 0。
    // 若换屏后发现左侧有空白，再把它加到 2/4/6/8 补偿。
    localparam [3:0] PIX_OFS = 4'd0;

    // ---------------- 字库：改为顶层共享（V3.0-P3d） ----------------
    reg  [2:0] fcol;
    reg         px_blank;       // 源像素超出 127 列时该字节输出空白
    reg  [8:0]  src_pix;        // 源像素号 = 扫描列 + PIX_OFS
    assign font_col = fcol;     // 顶层据此选择共享字库的列地址

    // ---------------- 上电时序：RES 低 175 ms -> 高后等 175 ms（V1.6 加长） ----------------
    reg [20:0] boot_cnt;
    reg [1:0]  boot_ph;
    reg        por_done;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            boot_cnt <= 21'd0;
            boot_ph  <= 2'd0;
            por_done <= 1'b0;
            oled_res <= 1'b0;
        end else begin
            case (boot_ph)
                2'd0: begin                          // RES 保持低电平
                    oled_res <= 1'b0;
                    if (boot_cnt == 21'h1FFFFF) begin // 约 175 ms（V1.6：原 87 ms）
                        boot_cnt <= 21'd0;
                        boot_ph  <= 2'd1;
                    end else begin
                        boot_cnt <= boot_cnt + 21'd1;
                    end
                end
                2'd1: begin                          // RES 拉高后等待面板内部 POR 完成
                    oled_res <= 1'b1;
                    if (boot_cnt == 21'h1FFFFF) begin // 约 175 ms（V1.6：原 44 ms）
                        boot_cnt <= 21'd0;
                        boot_ph  <= 2'd2;
                        por_done <= 1'b1;
                    end else begin
                        boot_cnt <= boot_cnt + 21'd1;
                    end
                end
                default: oled_res <= 1'b1;
            endcase
        end
    end

    // ---------------- 初始化命令表（23 项，0xAF 单独在最后发） ----------------
    // V1.4：A1+C8 反了，改为 A0+C0（整体再翻 180°）；其余保持不变
    // 参考 SH1107 128x128 常见初始化：0xAE 关屏 -> 时钟/复用/偏移/预充/VCOM/DC-DC
    // -> 段方向/扫描方向（A0+C0 与 A1+C8 互为 180°）-> 对比度 -> A4/A6 -> 最后 AF
    reg [4:0]  init_idx;
    reg [7:0]  init_byte;
    always @(*) begin
        case (init_idx)
            5'd0:  init_byte = 8'hAE;   // display off
            5'd1:  init_byte = 8'hD5;   // clock divide / oscillator
            5'd2:  init_byte = 8'h51;   // 0x51（128x128 常用；原 0x80 偏快）
            5'd3:  init_byte = 8'h20;   // memory addressing mode
            5'd4:  init_byte = 8'h00;   // 水平/页寻址（0x00：按页写）
            5'd5:  init_byte = 8'hA0;   // segment remap：0xA0 正常（0xA1 反向）
            5'd6:  init_byte = 8'hC0;   // COM scan：0xC0 正常（0xC8 反向）
            5'd7:  init_byte = 8'hA8;   // multiplex ratio
            5'd8:  init_byte = 8'h7F;   // 128 行
            5'd9:  init_byte = 8'hD3;   // display offset
            5'd10: init_byte = 8'h60;   // 96 行偏移
            5'd11: init_byte = 8'hDC;   // display start line
            5'd12: init_byte = 8'h00;
            5'd13: init_byte = 8'hD9;   // pre-charge period
            5'd14: init_byte = 8'h22;
            5'd15: init_byte = 8'hDB;   // VCOM deselect level
            5'd16: init_byte = 8'h35;
            5'd17: init_byte = 8'hAD;   // DC-DC on
            5'd18: init_byte = 8'h8A;
            5'd19: init_byte = 8'h81;   // contrast
            5'd20: init_byte = 8'h2F;
            5'd21: init_byte = 8'hA4;   // 按显存显示（非全亮）
            5'd22: init_byte = 8'hA6;   // 正常显示（非反色）
            default: init_byte = 8'hA6;
        endcase
    end

    // ---------------- 字节发送器（每 bit 4 个时钟 = 3 MHz） ----------------
    reg        tx_start;
    reg [7:0]  tx_byte;
    reg        tx_dc;
    reg        tx_busy;
    reg [5:0]  ph;
    reg [7:0]  sb;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            oled_sclk <= 1'b0;
            oled_mosi <= 1'b0;
            oled_dc   <= 1'b0;
            tx_busy   <= 1'b0;
            ph        <= 6'd0;
            sb        <= 8'd0;
        end else if (!tx_busy) begin
            oled_sclk <= 1'b0;
            if (tx_start) begin
                sb        <= tx_byte;
                oled_mosi <= tx_byte[7];
                oled_dc   <= tx_dc;
                oled_sclk <= 1'b0;
                ph        <= 6'd0;
                tx_busy   <= 1'b1;
            end
        end else begin
            ph <= ph + 6'd1;
            case (ph[1:0])
                2'b00:   oled_sclk <= 1'b1;                     // 上升沿，模块采样
                2'b10:   oled_sclk <= 1'b0;                     // 下降沿
                2'b11:   if (ph != 6'd31)                       // 提前半周期换下一位
                             oled_mosi <= sb[7 - ((ph + 6'd1) >> 2)];
                default: ;
            endcase
            if (ph == 6'd31)
                tx_busy <= 1'b0;                                // 8 bit 发完
        end
    end

    // ---------------- 刷新主状态机 ----------------
    localparam [2:0] S_WAIT = 3'd0;
    localparam [2:0] S_INIT = 3'd1;
    localparam [2:0] S_GAP  = 3'd2;
    localparam [2:0] S_PREP = 3'd3;
    localparam [2:0] S_SEND = 3'd4;
    localparam [2:0] S_LOAD = 3'd5;
    localparam [2:0] S_NEXT = 3'd6;
    localparam [2:0] S_ON   = 3'd7;

    reg [2:0]  state;
    reg [3:0]  page;
    reg [7:0]  bcnt;        // 0..127 列
    reg [1:0]  cidx;        // 每页 3 条命令
    reg [19:0] gap_cnt;
    reg        init_pass;   // 0=第一遍初始化，1=第二遍已发（V1.6）
    reg [7:0]  cmd_byte;
    reg        send_dc;
    reg [7:0]  send_byte;

    // V3.0-P3：S_LOAD 只用 1 拍取字符，顶层用本信号把 disp_chargen 让给 SPI 屏
    assign ch_load = (state == S_LOAD);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_WAIT;
            page      <= 4'd0;
            bcnt      <= 8'd0;
            cidx      <= 2'd0;
            init_idx  <= 5'd0;
            gap_cnt   <= 20'd0;
            init_pass <= 1'b0;
            tx_start  <= 1'b0;
            tx_byte   <= 8'd0;
            tx_dc     <= 1'b0;
            rd_line   <= 4'd15;
            rd_col    <= 4'd15;
            fcol      <= 3'd0;
            px_blank  <= 1'b0;
        end else begin
            tx_start <= 1'b0;
            case (state)
                S_WAIT: begin
                    if (por_done) begin
                        init_idx  <= 5'd0;
                        init_pass <= 1'b0;
                                    state     <= S_INIT;
                    end
                end

                // ---------- 初始化命令（V1.6：同一套命令真正连发两遍） ----------
                S_INIT: begin
                    if (!tx_busy && !tx_start) begin
                        tx_byte  <= init_byte;
                        tx_dc    <= 1'b0;
                        tx_start <= 1'b1;
                        if (init_idx == 5'd22) begin
                            init_idx <= 5'd0;
                            if (!init_pass) begin
                                init_pass <= 1'b1;      // 第一遍发完：等 43.7 ms 再发第二遍
                                gap_cnt   <= 20'd0;
                                state     <= S_GAP;
                            end else begin
                                state     <= S_ON;      // 第二遍发完：开屏
                            end
                        end else begin
                            init_idx <= init_idx + 5'd1;
                        end
                    end
                end

                // ---------- 两遍初始化之间的间隔（V1.6：此状态已可达） ----------
                S_GAP: begin
                    if (gap_cnt == 20'h7FFFF) begin   // 约 43.7 ms
                        gap_cnt <= 20'd0;
                        state   <= S_INIT;
                    end else begin
                        gap_cnt <= gap_cnt + 20'd1;
                    end
                end

                // ---------- 开屏（显式 0xAF） ----------
                S_ON: begin
                    if (!tx_busy && !tx_start) begin
                        tx_byte  <= 8'hAF;
                        tx_dc    <= 1'b0;
                        tx_start <= 1'b1;
                        page     <= 4'd0;
                        bcnt     <= 8'd0;
                        cidx     <= 2'd0;
                        state    <= S_PREP;
                    end
                end

                // ---------- 准备每页的命令/数据 ----------
                S_PREP: begin
                    rd_line <= page;
                    if (cidx != 2'd3) begin
                        // SH1107 寻址：低列地址=0，高列地址=0，页地址
                        send_dc <= 1'b0;
                        case (cidx)
                            2'd0:    send_byte <= 8'h00;
                            2'd1:    send_byte <= 8'h10;
                            default: send_byte <= 8'hB0 | {4'h0, page};
                        endcase
                        state <= S_SEND;
                    end else begin
                        // 源像素号 = 当前列 + PIX_OFS；超出 127 的部分显示空白
                        src_pix = {1'b0, bcnt} + {5'd0, PIX_OFS};
                        if (src_pix > 9'd127) begin
                            rd_col   <= 4'd15;
                            fcol     <= 3'd7;
                            px_blank <= 1'b1;
                        end else begin
                            rd_col   <= src_pix[7:3];     // 字符列 0..15
                            fcol     <= src_pix[2:0];     // 字符内像素列 0..7
                            px_blank <= 1'b0;
                        end
                        state <= S_LOAD;
                    end
                end

                // ---------- 取字模（列/字符稳定后再取） ----------
                S_LOAD: begin
                    send_dc   <= 1'b1;
                    send_byte <= test_on ? 8'hFF : (px_blank ? 8'h00 : rd_bits);   // 自检整屏点亮
                    state     <= S_SEND;
                end

                // ---------- 发送一个字节 ----------
                S_SEND: begin
                    if (!tx_busy && !tx_start) begin
                        tx_byte  <= send_byte;
                        tx_dc    <= send_dc;
                        tx_start <= 1'b1;
                        state    <= S_NEXT;
                    end
                end

                // ---------- 计数器推进 ----------
                S_NEXT: begin
                    if (!tx_busy) begin
                        if (cidx != 2'd3) begin
                            cidx  <= cidx + 2'd1;
                            state <= S_PREP;
                        end else if (bcnt != 8'd127) begin
                            bcnt  <= bcnt + 8'd1;
                            state <= S_PREP;
                        end else begin
                            bcnt  <= 8'd0;
                            cidx  <= 2'd0;
                            if (page == 4'd15)
                                page <= 4'd0;
                            else
                                page <= page + 4'd1;
                            state <= S_PREP;
                        end
                    end
                end

                default: state <= S_WAIT;
            endcase
        end
    end

endmodule
