// =============================================================================
// 文件名   : seg7_595.v
// 功能     : 板载 2 位共阴数码管显示距离（74HC595 串行驱动）
// 说明     : 显示规则（V1.6 修正：原头注释把 <10 m 写成 "0.8"，与实现不符）
//              - dist_valid=0    -> 两位都显示 "-"
//              - >= 10 m         -> 左=十米位，右=米位，无小数点
//                                   例：12345 mm -> "12"
//              - 1.00 ~ 9.99 m   -> 左=米位(带小数点)，右=分米位
//                                   例：1234 mm -> "1.2"，8765 mm -> "8.7"
//              - < 1 m           -> 显示厘米两位（左=十位，右=个位），无小数点
//                                   例：843 mm -> "84"，205 mm -> "20"，87 mm -> "08"
//            dig[1]=2'b10 选左位，dig[1]=2'b01 选右位（与厂家 nixie 例程一致）
//            扫描频率约 40 kHz（12 MHz / 300）
// 版本     : V1.6  (2026-11-04)
// =============================================================================
`timescale 1ns/1ps

module seg7_595 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [19:0] bcd_dist,      // 距离 mm 的 5 位 BCD，[19:16]=万位
    input  wire        dist_valid,
    output reg  [1:0]  dig,
    output reg         seg_sck,
    output reg         seg_rck,
    output reg         seg_din
);

    // ---------------- 共阴 7 段码 {G,F,E,D,C,B,A} ----------------
    function [6:0] seg7;
        input [3:0] v;
        begin
            case (v)
                4'd0: seg7 = 7'h3F;
                4'd1: seg7 = 7'h06;
                4'd2: seg7 = 7'h5B;
                4'd3: seg7 = 7'h4F;
                4'd4: seg7 = 7'h66;
                4'd5: seg7 = 7'h6D;
                4'd6: seg7 = 7'h7D;
                4'd7: seg7 = 7'h07;
                4'd8: seg7 = 7'h7F;
                4'd9: seg7 = 7'h6F;
                default: seg7 = 7'h00;
            endcase
        end
    endfunction

    // ---------------- 待显示数字（左位/右位） ----------------
    reg [3:0] left_num, right_num;
    reg       left_dp;

    always @(*) begin
        if (!dist_valid) begin
            left_num  = 4'hF;      // F 表示横杠
            right_num = 4'hF;
            left_dp   = 1'b0;
        end else if (bcd_dist[19:16] != 4'd0) begin
            // >= 10 m：左=十米位，右=米位
            left_num  = bcd_dist[19:16];
            right_num = bcd_dist[15:12];
            left_dp   = 1'b0;
        end else if (bcd_dist[15:12] != 4'd0) begin
            // 1.00 ~ 9.99 m：左=米位(带小数点)，右=分米位
            left_num  = bcd_dist[15:12];
            right_num = bcd_dist[11:8];
            left_dp   = 1'b1;
        end else begin
            // < 1 m：显示厘米两位（左=十位，右=个位），无小数点
            // 例：843 mm -> "84"，205 mm -> "20"，87 mm -> "08"
            left_num  = bcd_dist[11:8];
            right_num = bcd_dist[7:4];
            left_dp   = 1'b0;
        end
    end

    function [7:0] digit_byte;
        input [3:0] v;
        input       dp;
        begin
            digit_byte = (v == 4'hF) ? 8'h40 : {dp, seg7(v)};
        end
    endfunction

    // 两位的段码（组合产生）
    wire [7:0] left_byte  = digit_byte(left_num,  left_dp);
    wire [7:0] right_byte = digit_byte(right_num, 1'b0);

    // ---------------- 扫描与移位状态机 ----------------
    localparam S_IDLE  = 2'd0;
    localparam S_SHIFT = 2'd1;
    localparam S_LATCH = 2'd2;
    localparam S_RCK   = 2'd3;

    reg [8:0] scan_cnt;
    reg       scan_tick;
    reg [1:0] state;
    reg       active;        // 0=左位 1=右位
    reg [7:0] sh_byte;
    reg [3:0] bit_i;
    reg       half;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan_cnt <= 9'd0;
            scan_tick<= 1'b0;
        end else if (scan_cnt == 9'd299) begin
            scan_cnt <= 9'd0;
            scan_tick<= 1'b1;
        end else begin
            scan_cnt <= scan_cnt + 9'd1;
            scan_tick<= 1'b0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            active   <= 1'b0;
            sh_byte  <= 8'h00;
            bit_i    <= 4'd0;
            half     <= 1'b0;
            dig      <= 2'b11;
            seg_sck  <= 1'b0;
            seg_rck  <= 1'b0;
            seg_din  <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    seg_sck <= 1'b0;
                    seg_rck <= 1'b0;
                    if (scan_tick) begin
                        if (active == 1'b0) begin
                            sh_byte <= left_byte;
                            dig     <= 2'b10;
                        end else begin
                            sh_byte <= right_byte;
                            dig     <= 2'b01;
                        end
                        seg_din <= (active == 1'b0) ? left_byte[7] : right_byte[7];
                        bit_i   <= 4'd0;
                        half    <= 1'b0;
                        state   <= S_SHIFT;
                    end
                end

                S_SHIFT: begin
                    if (half == 1'b0) begin
                        seg_sck <= 1'b1;        // 上升沿：595 移位
                        half    <= 1'b1;
                    end else begin
                        seg_sck <= 1'b0;
                        half    <= 1'b0;
                        if (bit_i == 4'd7) begin
                            state <= S_LATCH;
                        end else begin
                            bit_i   <= bit_i + 4'd1;
                            seg_din <= sh_byte[6 - bit_i];
                        end
                    end
                end

                S_LATCH: begin
                    seg_rck <= 1'b1;            // 锁存到输出
                    state   <= S_RCK;
                end

                S_RCK: begin
                    seg_rck <= 1'b0;
                    active  <= ~active;
                    state   <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
