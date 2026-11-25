// =============================================================================
// 文件名   : rotary_enc.v
// 功能     : 旋转编码器正交解码（V3.0）
// 说明     : phase_a/phase_b 两级同步；4 状态格雷码每 4 次合法跳变（1 档）
//            输出一个 step 脉冲；dir=1 表示正向（加），ENC_INVERT 可整体翻转
//            非法跳变（两相同时变化）忽略
// 版本     : V3.0  (2026-11-13)
// =============================================================================
`timescale 1ns/1ps

module rotary_enc #(
    parameter ENC_INVERT = 1'b0
)(
    input  wire clk,
    input  wire rst_n,
    input  wire phase_a,
    input  wire phase_b,
    output reg  step,
    output reg  dir
);

    // ---------------- 输入同步 ----------------
    reg a0, a1, b0, b1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a0 <= 1'b1;
            a1 <= 1'b1;
            b0 <= 1'b1;
            b1 <= 1'b1;
        end else begin
            a0 <= phase_a;
            a1 <= a0;
            b0 <= phase_b;
            b1 <= b0;
        end
    end

    wire [1:0] st = {a1, b1};

    reg [1:0] st_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            st_d <= 2'b00;
        else
            st_d <= st;
    end

    // ---------------- 跳变方向累计 ----------------
    reg signed [3:0] acc;
    reg signed [3:0] acc_inc;

    always @(*) begin
        acc_inc = acc;
        case ({st_d, st})
            // 正向：00 -> 01 -> 11 -> 10 -> 00
            4'b00_01: acc_inc = acc + 4'sd1;
            4'b01_11: acc_inc = acc + 4'sd1;
            4'b11_10: acc_inc = acc + 4'sd1;
            4'b10_00: acc_inc = acc + 4'sd1;
            // 反向：00 -> 10 -> 11 -> 01 -> 00
            4'b00_10: acc_inc = acc - 4'sd1;
            4'b10_11: acc_inc = acc - 4'sd1;
            4'b11_01: acc_inc = acc - 4'sd1;
            4'b01_00: acc_inc = acc - 4'sd1;
            default:  acc_inc = acc;        // 非法跳变：忽略
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc  <= 4'sd0;
            step <= 1'b0;
            dir  <= 1'b0;
        end else begin
            step <= 1'b0;
            if (acc_inc >= 4'sd4) begin
                acc  <= acc_inc - 4'sd4;
                step <= 1'b1;
                dir  <= ~ENC_INVERT;
            end else if (acc_inc <= -4'sd4) begin
                acc  <= acc_inc + 4'sd4;
                step <= 1'b1;
                dir  <= ENC_INVERT;
            end else begin
                acc <= acc_inc;
            end
        end
    end

endmodule
