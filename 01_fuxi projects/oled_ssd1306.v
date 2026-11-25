// =============================================================================
// 文件名   : ssd1306_128x64.v
// 功能     : I2C 128x64 OLED（SSD1306，0x3C）文字页驱动（V3.0-P3d）
// 说明     : 上电等 200 ms -> 26 字节初始化 -> 循环写 8 页 x 128 列
//            每列从共享的 disp_chargen 取字符、再用顶层共享 font8x8 取点阵；
//            不再整页缓存 16 字符（V3.0-P3d，省 LUT/寄存器）。
//            与 SPI 128x128 屏共享同一个 disp_chargen 和同一份字库：顶层在
//            SPI 屏 S_LOAD 那一拍把地址/字库让给 SPI（chg_busy=1），本模块等待。
//            I2C：START + 0x78 + 控制字节 + 数据 + STOP；命令流用 0x00，
//            显存数据用 0x40；每字节 9 个 SCL 周期，约 24 us。
// 版本     : V3.0-P3d  (2026-11-14，共享字库 + 去字符缓存)
// =============================================================================
`timescale 1ns/1ps

module ssd1306_128x64 (
    input  wire        clk,
    input  wire        rst_n,
    output wire        i2c_scl,
    inout  wire        i2c_sda,
    // ---- 字符取数接口（共享 disp_chargen） ----
    output reg  [5:0]  chg_line,    // 请求的行号（0..45）
    output reg  [3:0]  chg_col,     // 请求的字符列（0..15）
    input  wire [7:0]  chg_ch,      // disp_chargen 返回的字符
    input  wire        chg_busy,    // 1 = SPI 屏正在 S_LOAD，先等它
    input  wire [1:0]  ui_page,     // 0=主页 1=WARN 2=LIGHT 3=INFO
    input  wire [1:0]  digit_sel,   // WARN 子页当前编辑位：0=十米 1=米 2=分米 3=厘米
    input  wire [7:0]  font_bits,   // 顶层共享字库的像素列（V3.0-P3d）
    output wire [2:0]  font_col,    // 本拍字库列地址（供顶层字库仲裁）
    input  wire [3:0]  bright       // 固定 4（0x4F），不再由 UI 调节
);

    localparam [6:0] I2C_ADDR = 7'h3C;
    localparam [7:0] ADDR_W   = {I2C_ADDR, 1'b0};   // 0x78

    // ---------------- 初始化命令表（26 字节，按 SSD1306 常用序列） ----------------
    localparam integer INIT_LEN = 26;

    function [7:0] init_byte;
        input [4:0] idx;
        begin
            case (idx)
                5'd0:  init_byte = 8'hAE;   // display off
                5'd1:  init_byte = 8'hD5;   // clock divide
                5'd2:  init_byte = 8'h80;
                5'd3:  init_byte = 8'hA8;   // multiplex ratio
                5'd4:  init_byte = 8'h3F;   // 64 行
                5'd5:  init_byte = 8'hD3;   // display offset
                5'd6:  init_byte = 8'h00;
                5'd7:  init_byte = 8'h40;   // start line = 0
                5'd8:  init_byte = 8'h8D;   // charge pump
                5'd9:  init_byte = 8'h14;   // enable
                5'd10: init_byte = 8'h20;   // memory addressing
                5'd11: init_byte = 8'h02;   // page mode
                5'd12: init_byte = 8'hA1;   // segment remap（若左右反，改 A0）
                5'd13: init_byte = 8'hC8;   // COM scan dec（若上下反，改 C0）
                5'd14: init_byte = 8'hDA;   // COM pins
                5'd15: init_byte = 8'h12;
                5'd16: init_byte = 8'h81;   // contrast
                5'd17: init_byte = 8'h7F;
                5'd18: init_byte = 8'hD9;   // pre-charge
                5'd19: init_byte = 8'hF1;
                5'd20: init_byte = 8'hDB;   // VCOMH
                5'd21: init_byte = 8'h40;
                5'd22: init_byte = 8'hA4;   // 按显存显示
                5'd23: init_byte = 8'hA6;   // 正常（非反色）
                5'd24: init_byte = 8'h2E;   // 关闭滚动
                5'd25: init_byte = 8'hAF;   // display on
                default: init_byte = 8'h00;
            endcase
        end
    endfunction

    // ---------------- 上电等待 200 ms ----------------
    reg [21:0] boot_cnt;
    localparam [21:0] BOOT_END = 22'd2399999;   // 2,400,000 拍 = 200 ms

    // ---------------- 传输类型/序号 ----------------
    localparam [1:0] K_INIT  = 2'd0;
    localparam [1:0] K_PCMD  = 2'd1;
    localparam [1:0] K_PDATA = 2'd2;

    reg [1:0] kind;
    reg [7:0] idx;
    reg [2:0] page;

    wire [7:0] last_idx;
    assign last_idx = (kind == K_INIT)  ? 8'd27 :
                      (kind == K_PCMD)  ? 8'd6  : 8'd129;

    // ---------------- 页行映射：I2C 每页 8 行文字（V3.0-P3c） ----------------
    // 主页 16..23；WARN 24..28（5..7 用空白行 45）；LIGHT 29..36；INFO 37..44
    reg [5:0] row_line;
    always @(*) begin
        case (ui_page)
            2'd0: row_line = 6'd16 + {3'd0, page};                             // 主页 16..23
            2'd1: row_line = (page <= 3'd4) ? (6'd24 + {3'd0, page}) : 6'd45;  // WARN 24..28
            2'd2: row_line = 6'd29 + {3'd0, page};                             // LIGHT 29..36
            default: row_line = 6'd37 + {3'd0, page};                          // INFO 37..44
        endcase
    end

    // ---------------- 点阵取数（V3.0-P3d：共享字库 + 按像素现算，去掉 16 字符缓存） ----------------
    wire [7:0] dcol8 = idx - 8'd2;
    wire [6:0] dcol  = dcol8[6:0];
    wire [3:0] char_idx = dcol[6:3];
    assign font_col = dcol[2:0];
    reg  [7:0] pix_byte_r;      // 本列像素字节（等待字库稳定后锁存）

    // ---------------- 当前要发送的字节 ----------------
    // WARN 子页 LIMIT 行（第 25 行 = page 1）反色显示当前编辑位
    wire [3:0] digit_col = (digit_sel == 2'd0) ? 4'd6  :
                          (digit_sel == 2'd1) ? 4'd7  :
                          (digit_sel == 2'd2) ? 4'd9  : 4'd10;
    wire inv_cell = (ui_page == 2'd1) && (page == 3'd1) && (char_idx == digit_col);

    reg [7:0] byte_cur;
    always @(*) begin
        case (kind)
            K_INIT: begin
                if (idx == 8'd0)
                    byte_cur = ADDR_W;
                else if (idx == 8'd1)
                    byte_cur = 8'h00;               // 命令流
                else
                    byte_cur = init_byte(idx - 8'd2);
            end
            K_PCMD: begin
                case (idx)
                    8'd0:    byte_cur = ADDR_W;
                    8'd1:    byte_cur = 8'h00;      // 命令流
                    8'd2:    byte_cur = 8'hB0 | {5'd0, page};
                    8'd3:    byte_cur = 8'h00;      // 低列地址
                    8'd4:    byte_cur = 8'h10;      // 高列地址
                    8'd5:    byte_cur = 8'h81;      // 对比度命令
                    default: byte_cur = {bright, 4'hF};  // 1->0x1F ... 8->0x8F
                endcase
            end
            default: begin                          // K_PDATA
                if (idx == 8'd0)
                    byte_cur = ADDR_W;
                else if (idx == 8'd1)
                    byte_cur = 8'h40;               // 显存数据流
                else
                    byte_cur = pix_byte_r;
            end
        endcase
    end

    // ---------------- I2C 主机 ----------------
    reg        i2c_req;
    reg [1:0]  i2c_op;
    reg [7:0]  i2c_data;
    wire       i2c_busy;
    wire       i2c_done;
    wire       i2c_ack;

    i2c_master u_i2c (
        .clk   (clk),
        .rst_n (rst_n),
        .req   (i2c_req),
        .op    (i2c_op),
        .data  (i2c_data),
        .busy  (i2c_busy),
        .done  (i2c_done),
        .ack   (i2c_ack),
        .scl   (i2c_scl),
        .sda   (i2c_sda)
    );

    // ---------------- 主状态机 ----------------
    localparam [2:0] S_BOOT  = 3'd0;
    localparam [2:0] S_ACT   = 3'd1;   // 发起一次 START/WRITE/STOP
    localparam [2:0] S_WAIT  = 3'd2;   // 等 i2c done
    localparam [2:0] S_ADV   = 3'd3;   // 推进字节/类型
    localparam [2:0] S_PIX   = 3'd4;   // 设置本列字符地址（按像素现算）
    localparam [2:0] S_PIXW  = 3'd5;   // 等字库稳定（SPI 取字时让路）

    reg [2:0] state;
    reg [1:0] seq;                     // 0=START, 1=WRITE, 2=STOP

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_BOOT;
            boot_cnt <= 22'd0;
            kind     <= K_INIT;
            idx      <= 8'd0;
            page     <= 3'd0;
            seq      <= 2'd0;
            i2c_req  <= 1'b0;
            i2c_op   <= 2'd0;
            i2c_data <= 8'd0;
            pix_byte_r <= 8'd0;
            chg_line   <= 6'd0;
            chg_col    <= 4'd0;
        end else begin
            i2c_req <= 1'b0;

            case (state)
                S_BOOT: begin
                    if (boot_cnt == BOOT_END) begin
                        boot_cnt <= 22'd0;
                        kind     <= K_INIT;
                        idx      <= 8'd0;
                        page     <= 3'd0;
                        seq      <= 2'd0;
                        state    <= S_ACT;
                    end else begin
                        boot_cnt <= boot_cnt + 22'd1;
                    end
                end

                S_ACT: begin
                    i2c_req  <= 1'b1;
                    i2c_data <= byte_cur;
                    case (seq)
                        2'd0:    i2c_op <= 2'd0;   // START
                        2'd1:    i2c_op <= 2'd1;   // WRITE
                        default: i2c_op <= 2'd2;   // STOP
                    endcase
                    state <= S_WAIT;
                end

                S_WAIT: begin
                    if (i2c_done)
                        state <= S_ADV;
                end

                S_ADV: begin
                    if (seq == 2'd0) begin
                        seq   <= 2'd1;
                        idx   <= 8'd0;
                        state <= S_ACT;
                    end else if (seq == 2'd1) begin
                        if (idx == last_idx) begin
                            seq   <= 2'd2;
                            state <= S_ACT;
                        end else begin
                            idx <= idx + 8'd1;
                            // 显存数据流从 idx=2 起，每个字节先按像素取一次字模
                            if (kind == K_PDATA && (idx + 8'd1) >= 8'd2)
                                state <= S_PIX;
                            else
                                state <= S_ACT;
                        end
                    end else begin
                        case (kind)
                            K_INIT: begin
                                kind  <= K_PCMD;
                                page  <= 3'd0;
                                idx   <= 8'd0;
                                seq   <= 2'd0;
                                state <= S_ACT;
                            end
                            K_PCMD: begin
                                // V3.0-P3d：不再整页缓存 16 个字符，直接进入显存数据流
                                kind  <= K_PDATA;
                                idx   <= 8'd0;
                                seq   <= 2'd0;
                                state <= S_ACT;
                            end
                            default: begin
                                page  <= (page == 3'd7) ? 3'd0 : (page + 3'd1);
                                kind  <= K_PCMD;
                                idx   <= 8'd0;
                                seq   <= 2'd0;
                                state <= S_ACT;
                            end
                        endcase
                    end
                end

                S_PIX: begin
                    chg_line <= row_line;
                    chg_col  <= dcol[6:3];
                    state    <= S_PIXW;
                end

                S_PIXW: begin
                    if (!chg_busy) begin
                        pix_byte_r <= inv_cell ? ~font_bits : font_bits;
                        state      <= S_ACT;
                    end
                end

                default: state <= S_BOOT;
            endcase
        end
    end

endmodule
