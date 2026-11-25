// =============================================================================
// 文件名   : ui_ctrl.v
// 功能     : 板载 4 键 + 旋转编码器的界面状态机（V3.0-P3c）
// 说明     : 小屏单页菜单 + 3 个模态子页
//            主页面：0=ALARM（开关），1=WARN DIST，2=LIGHT STYLE，3=INFO
//            旋转：主页循环选中项；WARN 子页调当前位的值；LIGHT 子页切换样式
//            KEY1=右移数位，KEY2=左移数位，KEY3=OK，KEY4=CLR，KEY_ENC=确认/按下
//            主页按编码器/K3：ALARM 翻转；WARN/LIGHT/INFO 进入对应子页
//            WARN 子页：K1/K2 左右移动 digit_sel（十米/米/分米/厘米），
//                       旋转按当前位 ±1 个 BCD 位；K3/ENC 返回；K4 复位
//            LIGHT 子页：6 种预设；K4 恢复默认并返回
//            子页按编码器/K3：确认返回；K4：恢复默认
//            WARN 精度 0.01 m：BCD 16 bit {十米,米,分米,厘米}，避免除法
//            默认：ALARM OFF，WARN 05.00 m，LIGHT RED BLINK
// 版本     : V3.0-P3c (2026-11-14)
// =============================================================================
`timescale 1ns/1ps

module ui_ctrl (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [4:0]  key_press,    // [0]=KEY1 [1]=KEY2 [2]=KEY3 [3]=KEY4 [4]=KEY_ENC
    input  wire [4:0]  key_hold,     // 预留（当前未做长按）
    input  wire        rot_step,     // 编码器走一格（单周期）
    input  wire        rot_dir,      // 1 = 正转（方向反了改这里）
    output reg  [1:0]  ui_page,      // 0=主页 1=WARN 2=LIGHT 3=INFO
    output reg  [1:0]  ui_sel,       // 主页选中项：0=ALARM 1=WARN 2=LIGHT 3=INFO
    output reg         alarm_en,     // 报警开关（默认 0）
    output reg  [15:0] warn_bcd,     // {十米位,米位,分米位,厘米位}，05.00 m = 16'h0500
    output reg  [2:0]  light_style,  // 0=RED BLINK 1=AMBER BLINK 2=GREEN SOLID
                                     // 3=POLICE 4=BREATHE 5=RAINBOW
    output reg  [1:0]  digit_sel,    // WARN 子页当前编辑位：0=十米 1=米 2=分米 3=厘米
    output wire [15:0] alarm_mm      // 报警阈值（mm），供报警模块
);

    localparam [15:0] WARN_MIN   = 16'h0010;  // 00.10 m
    localparam [15:0] WARN_MAX   = 16'h2000;  // 20.00 m
    localparam [15:0] WARN_DEF   = 16'h0500;  // 05.00 m
    localparam [2:0]  STYLE_MAX  = 3'd5;      // 6 种预设（0..5）

    // ---------------- BCD 加/减：按位，带进位/借位 ----------------
    // 位宽约定：t[3:0]=厘米位，t[7:4]=分米位，t[11:8]=米位，t[15:12]=十米位
    function [15:0] bcd_inc01;   // +0.01 m
        input [15:0] v;
        reg [15:0] t;
        begin
            t = v;
            t[3:0] = t[3:0] + 4'd1;
            if (t[3:0] >= 4'd10) begin t[3:0] = 4'd0; t[7:4] = t[7:4] + 4'd1; end
            if (t[7:4] >= 4'd10) begin t[7:4] = 4'd0; t[11:8] = t[11:8] + 4'd1; end
            if (t[11:8] >= 4'd10) begin t[11:8] = 4'd0; t[15:12] = t[15:12] + 4'd1; end
            bcd_inc01 = t;
        end
    endfunction

    function [15:0] bcd_dec01;   // -0.01 m
        input [15:0] v;
        reg [15:0] t;
        begin
            t = v;
            if (t[3:0] != 4'd0) begin
                t[3:0] = t[3:0] - 4'd1;
            end else begin
                t[3:0] = 4'd9;
                if (t[7:4] != 4'd0) begin
                    t[7:4] = t[7:4] - 4'd1;
                end else begin
                    t[7:4] = 4'd9;
                    if (t[11:8] != 4'd0) begin
                        t[11:8] = t[11:8] - 4'd1;
                    end else begin
                        t[11:8] = 4'd9;
                        t[15:12] = t[15:12] - 4'd1;
                    end
                end
            end
            bcd_dec01 = t;
        end
    endfunction

    function [15:0] bcd_inc10;   // +0.10 m
        input [15:0] v;
        reg [15:0] t;
        begin
            t = v;
            t[7:4] = t[7:4] + 4'd1;
            if (t[7:4] >= 4'd10) begin t[7:4] = 4'd0; t[11:8] = t[11:8] + 4'd1; end
            if (t[11:8] >= 4'd10) begin t[11:8] = 4'd0; t[15:12] = t[15:12] + 4'd1; end
            bcd_inc10 = t;
        end
    endfunction

    function [15:0] bcd_dec10;   // -0.10 m
        input [15:0] v;
        reg [15:0] t;
        begin
            t = v;
            if (t[7:4] != 4'd0) begin
                t[7:4] = t[7:4] - 4'd1;
            end else begin
                t[7:4] = 4'd9;
                if (t[11:8] != 4'd0) begin
                    t[11:8] = t[11:8] - 4'd1;
                end else begin
                    t[11:8] = 4'd9;
                    t[15:12] = t[15:12] - 4'd1;
                end
            end
            bcd_dec10 = t;
        end
    endfunction

    function [15:0] bcd_inc100;  // +1.00 m
        input [15:0] v;
        reg [15:0] t;
        begin
            t = v;
            t[11:8] = t[11:8] + 4'd1;
            if (t[11:8] >= 4'd10) begin t[11:8] = 4'd0; t[15:12] = t[15:12] + 4'd1; end
            bcd_inc100 = t;
        end
    endfunction

    function [15:0] bcd_dec100;  // -1.00 m
        input [15:0] v;
        reg [15:0] t;
        begin
            t = v;
            if (t[11:8] != 4'd0) begin
                t[11:8] = t[11:8] - 4'd1;
            end else begin
                t[11:8] = 4'd9;
                t[15:12] = t[15:12] - 4'd1;
            end
            bcd_dec100 = t;
        end
    endfunction

    function [15:0] bcd_inc1000; // +10.00 m
        input [15:0] v;
        reg [15:0] t;
        begin
            t = v;
            t[15:12] = t[15:12] + 4'd1;
            bcd_inc1000 = t;
        end
    endfunction

    function [15:0] bcd_dec1000; // -10.00 m
        input [15:0] v;
        reg [15:0] t;
        begin
            t = v;
            t[15:12] = t[15:12] - 4'd1;
            bcd_dec1000 = t;
        end
    endfunction

    wire [15:0] inc01 = bcd_inc01(warn_bcd);
    wire [15:0] dec01 = bcd_dec01(warn_bcd);
    wire [15:0] inc10 = bcd_inc10(warn_bcd);
    wire [15:0] dec10 = bcd_dec10(warn_bcd);
    wire [15:0] inc100 = bcd_inc100(warn_bcd);
    wire [15:0] dec100 = bcd_dec100(warn_bcd);
    wire [15:0] inc1000 = bcd_inc1000(warn_bcd);
    wire [15:0] dec1000 = bcd_dec1000(warn_bcd);

    // 当前选中位对应的加减结果
    wire [15:0] inc_sel = (digit_sel == 2'd0) ? inc1000 :
                          (digit_sel == 2'd1) ? inc100  :
                          (digit_sel == 2'd2) ? inc10   : inc01;
    wire [15:0] dec_sel = (digit_sel == 2'd0) ? dec1000 :
                          (digit_sel == 2'd1) ? dec100  :
                          (digit_sel == 2'd2) ? dec10   : dec01;

    // 上限截断；下限/借位下溢一律回到 00.10 m
    wire [15:0] inc_sel_c = (inc_sel > WARN_MAX) ? WARN_MAX : inc_sel;
    wire [15:0] dec_sel_c = (dec_sel > WARN_MAX || dec_sel < WARN_MIN) ? WARN_MIN : dec_sel;

    // ---------------- 主状态机 ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ui_page     <= 2'd0;
            ui_sel      <= 2'd0;
            alarm_en    <= 1'b0;
            warn_bcd    <= WARN_DEF;
            light_style <= 3'd0;
            digit_sel   <= 2'd0;
        end else begin
            case (ui_page)
                // ---- 主页面：旋转选条目，按下执行 ----
                2'd0: begin
                    if (rot_step) begin
                        if (rot_dir)
                            ui_sel <= (ui_sel == 2'd3) ? 2'd0 : (ui_sel + 2'd1);
                        else
                            ui_sel <= (ui_sel == 2'd0) ? 2'd3 : (ui_sel - 2'd1);
                    end
                    if (key_press[4] || key_press[2]) begin
                        case (ui_sel)
                            2'd0: alarm_en <= ~alarm_en;
                            2'd1: begin
                                ui_page   <= 2'd1;
                                digit_sel <= 2'd0;
                            end
                            2'd2: ui_page <= 2'd2;
                            default: ui_page <= 2'd3;
                        endcase
                    end
                end

                // ---- WARN DIST 子页：K1/K2 左右移动数位，旋转按当前位调值 ----
                2'd1: begin
                    if (key_press[0]) begin
                        // KEY1：右移一位（十米 -> 米 -> 分米 -> 厘米 -> 十米）
                        digit_sel <= (digit_sel == 2'd3) ? 2'd0 : (digit_sel + 2'd1);
                    end else if (key_press[1]) begin
                        // KEY2：左移一位（厘米 -> 分米 -> 米 -> 十米 -> 厘米）
                        digit_sel <= (digit_sel == 2'd0) ? 2'd3 : (digit_sel - 2'd1);
                    end else if (rot_step) begin
                        if (rot_dir) warn_bcd <= inc_sel_c;
                        else         warn_bcd <= dec_sel_c;
                    end else if (key_press[3]) begin
                        warn_bcd  <= WARN_DEF;
                        digit_sel <= 2'd0;
                    end
                    if (key_press[4] || key_press[2])
                        ui_page <= 2'd0;
                end

                // ---- LIGHT STYLE 子页：旋转选 6 种样式，K4 恢复默认 ----
                2'd2: begin
                    if (rot_step) begin
                        if (rot_dir)
                            light_style <= (light_style == STYLE_MAX) ? 3'd0 : (light_style + 3'd1);
                        else
                            light_style <= (light_style == 3'd0) ? STYLE_MAX : (light_style - 3'd1);
                    end
                    if (key_press[3]) begin
                        light_style <= 3'd0;
                        ui_page     <= 2'd0;
                    end else if (key_press[4] || key_press[2]) begin
                        ui_page <= 2'd0;
                    end
                end

                // ---- INFO 页：任意确认键返回 ----
                default: begin
                    if (key_press[4] || key_press[2] || key_press[3])
                        ui_page <= 2'd0;
                end
            endcase
        end
    end

    // ---------------- BCD -> mm（0.01 m = 10 mm） ----------------
    assign alarm_mm = {12'd0, warn_bcd[15:12]} * 16'd10000
                    + {12'd0, warn_bcd[11:8]}  * 16'd1000
                    + {12'd0, warn_bcd[7:4]}   * 16'd100
                    + {12'd0, warn_bcd[3:0]}   * 16'd10;

endmodule
