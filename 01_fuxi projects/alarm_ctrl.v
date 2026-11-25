`timescale 1ns/1ps
// =============================================================================
// alarm_ctrl.v  —  V3.0 P4.2：距离报警判断 + LIGHT 页 WS2812 预览
//
// 输入：
//   dist_mm    : tof1_parser 的主目标距离（mm）
//   dist_valid : 解析器每帧给出的“有效距离”脉冲（只有 1 个 12 MHz 周期）
//   link_ok    : 1.4 s 内收到过合法帧（失链后自动掉 0）
//   alarm_en   : 设置页 ALARM ON/OFF
//   alarm_mm   : 预警距离（mm），来自 ui_ctrl 的 BCD 阈值
//   light_style: 0=RED BLINK 1=AMBER BLINK 2=GREEN SOLID
//                3=POLICE 4=BREATHE 5=RAINBOW
//   preview    : 1=LIGHT STYLE 子页预览当前灯效（不要求报警有效）
//
// 输出：
//   alarm_act  : 报警有效（超阈值持续 200 ms 清除、1 s 失链清除）
//   alarm_blink: 2 Hz 闪烁（给 LED2 用，1=亮）
//   led1/led2  : 两颗 WS2812 的 24 bit 颜色；V3.0-P4.1 起仅在
//                LIGHT STYLE 子页预览时输出，距离报警不再驱动彩灯
//
// 判据：alarm_en && link_ok && last_valid && last_dist != 0 && last_dist <= alarm_mm
// 说明：dist_valid 是单周期脉冲，不能直接当电平做 200 ms 计时；这里先把它
//       锁存成 last_dist/last_valid（200 ms 内无新脉冲则失效），再用 latched
//       距离做阈值判断，否则 clear_ms 几乎永远加不上去，报警会一直不撤。
// =============================================================================

module alarm_ctrl (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] dist_mm,
    input  wire        dist_valid,
    input  wire        link_ok,
    input  wire        alarm_en,
    input  wire [15:0] alarm_mm,
    input  wire [2:0]  light_style,
    input  wire        preview,
    output reg         alarm_act,
    output reg         alarm_blink,
    output reg  [23:0] led1,
    output reg  [23:0] led2
);

    localparam TICK_MAX   = 14'd11999;   // 1 ms @ 12 MHz
    localparam CLEAR_MS   = 10'd200;     // 超阈值持续 200 ms 才清除
    localparam LOST_MS    = 11'd1000;    // 失链持续 1 s 才清除
    localparam BLINK_HALF = 9'd250;      // 250 ms 半周期 -> 2 Hz

    // WS2812 颜色（{G,R,B}）
    localparam C_RED     = 24'h00FF00;
    localparam C_AMBER   = 24'h80FF00;
    localparam C_YELLOW  = 24'hFFFF00;
    localparam C_GREEN   = 24'hFF0000;
    localparam C_BLUE    = 24'h0000FF;
    localparam C_MAGENTA = 24'h00FFFF;

    reg  [13:0] tick_cnt;
    wire        tick = (tick_cnt == TICK_MAX);

    reg  [10:0] ms_cnt;       // 0..1999：2 s 灯效时基
    reg  [8:0]  blink_ms;     // 0..499：2 Hz 闪烁
    reg  [7:0]  rainbow_cnt;  // 0..249：彩虹步进
    reg  [2:0]  rainbow_idx;  // 0..5

    reg  [9:0]  clear_ms;
    reg  [10:0] lost_ms;

    reg  [15:0] last_dist;    // 最近一次有效帧的距离
    reg         last_valid;   // last_dist 是否仍在有效期内
    reg  [10:0] last_ms;      // 距上次 dist_valid 的毫秒数

    // ---------------------------------------------------------------------
    // 1 ms 节拍与灯效时基
    // ---------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tick_cnt    <= 14'd0;
            ms_cnt      <= 11'd0;
            blink_ms    <= 9'd0;
            rainbow_cnt <= 8'd0;
            rainbow_idx <= 3'd0;
        end else if (tick) begin
            tick_cnt <= 14'd0;

            if (ms_cnt == 11'd1999)
                ms_cnt <= 11'd0;
            else
                ms_cnt <= ms_cnt + 11'd1;

            if (blink_ms == 9'd499)
                blink_ms <= 9'd0;
            else
                blink_ms <= blink_ms + 9'd1;

            if (rainbow_cnt == 8'd249) begin
                rainbow_cnt <= 8'd0;
                if (rainbow_idx == 3'd5)
                    rainbow_idx <= 3'd0;
                else
                    rainbow_idx <= rainbow_idx + 3'd1;
            end else begin
                rainbow_cnt <= rainbow_cnt + 8'd1;
            end
        end else begin
            tick_cnt <= tick_cnt + 14'd1;
        end
    end

    // ---------------------------------------------------------------------
    // 锁存最近一次有效距离
    // dist_valid 是 tof1_parser 输出的单周期脉冲（每帧只高 1 个 12 MHz 周期），
    // 不能直接拿它当电平做 200 ms 清除计时，否则 clear_ms 几乎永远加不上去。
    // 这里把它转成“有效期 200 ms 的电平”：收到脉冲就刷新，超时未更新则失效。
    // ---------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            last_dist  <= 16'd0;
            last_valid <= 1'b0;
            last_ms    <= 11'd0;
        end else if (!alarm_en) begin
            last_valid <= 1'b0;
            last_ms    <= 11'd0;
        end else if (dist_valid) begin
            last_dist  <= dist_mm;
            last_valid <= 1'b1;
            last_ms    <= 11'd0;
        end else if (tick) begin
            if (last_ms >= 11'd200) begin
                last_ms    <= 11'd200;
                last_valid <= 1'b0;
            end else begin
                last_ms <= last_ms + 11'd1;
            end
        end
    end

    // ---------------------------------------------------------------------
    // 报警判断（超阈值 200 ms 去抖、失链 1 s 超时）
    // ---------------------------------------------------------------------
    wire in_range  = last_valid && link_ok && (last_dist != 16'd0) &&
                     (last_dist <= alarm_mm);
    wire out_range = last_valid && link_ok &&
                     ((last_dist == 16'd0) || (last_dist > alarm_mm));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alarm_act <= 1'b0;
            clear_ms  <= 10'd0;
            lost_ms   <= 11'd0;
        end else if (!alarm_en) begin
            alarm_act <= 1'b0;
            clear_ms  <= 10'd0;
            lost_ms   <= 11'd0;
        end else if (in_range) begin
            alarm_act <= 1'b1;
            clear_ms  <= 10'd0;
            lost_ms   <= 11'd0;
        end else if (!link_ok || !last_valid) begin
            clear_ms <= 10'd0;
            if (tick) begin
                if (lost_ms >= LOST_MS) begin
                    lost_ms   <= LOST_MS;
                    alarm_act <= 1'b0;
                end else begin
                    lost_ms <= lost_ms + 11'd1;
                end
            end
        end else if (out_range) begin
            lost_ms <= 11'd0;
            if (tick) begin
                if (clear_ms >= CLEAR_MS) begin
                    clear_ms  <= CLEAR_MS;
                    alarm_act <= 1'b0;
                end else begin
                    clear_ms <= clear_ms + 10'd1;
                end
            end
        end else begin
            // 兜底：in_range/out_range 已覆盖 last_dist 的 0 与非 0，
            // 正常不会走到这里；保持原状态并清计时。
            clear_ms <= 10'd0;
            lost_ms  <= 11'd0;
        end
    end

    // 2 Hz 闪烁：报警有效时亮 250 ms、灭 250 ms
    always @(*) begin
        alarm_blink = alarm_act && (blink_ms < BLINK_HALF);
    end

    // ---------------------------------------------------------------------
    // 6 种灯效
    // ---------------------------------------------------------------------
    wire [7:0] breathe = ms_cnt[10] ? (8'd255 - ms_cnt[9:2]) : ms_cnt[9:2];
    // LIGHT STYLE 子页预览：仅手动预览，V3.0-P4.1 起不再参与距离报警
    wire       show    = preview;

    always @(*) begin
        led1 = 24'd0;
        led2 = 24'd0;

        if (show) begin
            case (light_style)
                3'd0: begin                       // RED BLINK
                    if (blink_ms < BLINK_HALF) begin
                        led1 = C_RED;
                        led2 = C_RED;
                    end
                end
                3'd1: begin                       // AMBER BLINK
                    if (blink_ms < BLINK_HALF) begin
                        led1 = C_AMBER;
                        led2 = C_AMBER;
                    end
                end
                3'd2: begin                       // GREEN SOLID
                    led1 = C_GREEN;
                    led2 = C_GREEN;
                end
                3'd3: begin                       // POLICE：红蓝交替 ~256 ms
                    if (ms_cnt[8]) begin
                        led1 = C_RED;
                        led2 = C_BLUE;
                    end else begin
                        led1 = C_BLUE;
                        led2 = C_RED;
                    end
                end
                3'd4: begin                       // BREATHE：红色呼吸
                    led1 = {8'h00, breathe, 8'h00};
                    led2 = led1;
                end
                3'd5: begin                       // RAINBOW：6 色循环
                    case (rainbow_idx)
                        3'd0: led1 = C_RED;
                        3'd1: led1 = C_AMBER;
                        3'd2: led1 = C_YELLOW;
                        3'd3: led1 = C_GREEN;
                        3'd4: led1 = C_BLUE;
                        default: led1 = C_MAGENTA;
                    endcase
                    led2 = led1;
                end
                default: begin                    // 保留：默认红闪
                    if (blink_ms < BLINK_HALF) begin
                        led1 = C_RED;
                        led2 = C_RED;
                    end
                end
            endcase
        end
    end

endmodule
