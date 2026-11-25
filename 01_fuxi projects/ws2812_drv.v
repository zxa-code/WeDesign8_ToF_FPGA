`timescale 1ns/1ps
// =============================================================================
// ws2812_drv.v  —  V3.0 P4：两颗 WS2812（级联）驱动
//
// 时序（12 MHz）：
//   1 bit = 15 拍 = 1.25 us
//   T0H = 4 拍 (333 ns)，T1H = 9 拍 (750 ns)
//   48 bit 发完拉低 >300 us 锁存（兼容 WS2812 / WS2812B）
//
// 数据序：每颗灯 24 bit = G7..G0, R7..R0, B7..B0（MSB 先发）；
//         先发 c1（第一颗），再发 c2（第二颗）。
// =============================================================================

module ws2812_drv (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [23:0] c1,
    input  wire [23:0] c2,
    output reg         dout
);

    localparam PH_MAX  = 4'd14;      // 15 拍 / bit
    localparam GAP_MAX = 12'd3599;   // 3600 拍 = 300 us 低电平（兼容 WS2812B）

    reg  [5:0]  bit_idx;   // 0..47
    reg  [3:0]  ph;        // 0..14
    reg  [11:0] gap;
    reg         running;
    reg  [47:0] sh;

    wire        bitv = sh[47];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_idx <= 6'd0;
            ph      <= 4'd0;
            gap     <= 12'd0;
            running <= 1'b0;
            sh      <= 48'd0;
            dout    <= 1'b0;
        end else if (!running) begin
            dout <= 1'b0;
            if (gap == GAP_MAX) begin
                gap     <= 12'd0;
                sh      <= {c1, c2};
                bit_idx <= 6'd0;
                ph      <= 4'd0;
                running <= 1'b1;
            end else begin
                gap <= gap + 12'd1;
            end
        end else begin
            // 每个 bit 的高电平起点
            if (ph == 4'd0)
                dout <= 1'b1;
            else if (ph == (bitv ? 4'd9 : 4'd4))
                dout <= 1'b0;

            if (ph == PH_MAX) begin
                ph <= 4'd0;
                sh <= {sh[46:0], 1'b0};
                if (bit_idx == 6'd47) begin
                    running <= 1'b0;
                    gap     <= 12'd0;
                    dout    <= 1'b0;
                end else begin
                    bit_idx <= bit_idx + 6'd1;
                end
            end else begin
                ph <= ph + 4'd1;
            end
        end
    end

endmodule
