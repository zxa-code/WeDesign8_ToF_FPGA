// =============================================================================
// 文件名   : key_scan.v
// 功能     : 板载 4 键 + 编码器按键的同步、消抖与边沿提取（V3.0）
// 说明     : 1 kHz 采样；连续 20 ms 电平一致才认（20 个采样点全 1）
//            输入均低有效（按下 = 0），内部取反后移位
//            输出 key_press 为单周期按下脉冲，key_hold 为消抖后电平
//            位序：bit0..3 = KEY1..KEY4，bit4 = 编码器按下
// 版本     : V3.0  (2026-11-13)
// =============================================================================
`timescale 1ns/1ps

module key_scan (
    input  wire       clk,          // 12 MHz
    input  wire       rst_n,
    input  wire [3:0] key_raw,      // KEY1..KEY4（低有效）
    input  wire       key_enc_raw,  // 编码器按下（低有效）
    output reg  [4:0] key_press,    // 单周期按下脉冲
    output reg  [4:0] key_hold      // 消抖后电平（1 = 按下）
);

    // ---------------- 1 kHz 采样节拍 ----------------
    localparam integer TICK_DIV = 12000;   // 12 MHz / 12000 = 1 kHz

    reg [13:0] tick_cnt;
    wire       tick = (tick_cnt == TICK_DIV - 1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            tick_cnt <= 14'd0;
        else if (tick)
            tick_cnt <= 14'd0;
        else
            tick_cnt <= tick_cnt + 14'd1;
    end

    // ---------------- 5 通道 20 ms 移位消抖 ----------------
    wire [4:0] raw_pressed = {~key_enc_raw, ~key_raw[3], ~key_raw[2],
                              ~key_raw[1],  ~key_raw[0]};

    reg [19:0] sh0, sh1, sh2, sh3, sh4;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sh0 <= 20'd0;
            sh1 <= 20'd0;
            sh2 <= 20'd0;
            sh3 <= 20'd0;
            sh4 <= 20'd0;
            key_hold  <= 5'd0;
            key_press <= 5'd0;
        end else if (tick) begin
            sh0 <= {sh0[18:0], raw_pressed[0]};
            sh1 <= {sh1[18:0], raw_pressed[1]};
            sh2 <= {sh2[18:0], raw_pressed[2]};
            sh3 <= {sh3[18:0], raw_pressed[3]};
            sh4 <= {sh4[18:0], raw_pressed[4]};

            // 20 个采样点全为 1 才认为按下（比“取最新一次”稳）
            key_hold  <= {&sh4, &sh3, &sh2, &sh1, &sh0};
            key_press <= {&sh4, &sh3, &sh2, &sh1, &sh0} & ~key_hold;
        end else begin
            // key_press 只在采样节拍后拉高 1 个 12 MHz 周期。
            // 若保持到下一拍（约 1 ms），ui_ctrl 会每拍都执行：
            //   ALARM 反复翻转回到原值、INFO 进入后立刻退出、
            //   WARN 页 K3 返回后又被重新进入。
            key_press <= 5'd0;
        end
    end

endmodule
