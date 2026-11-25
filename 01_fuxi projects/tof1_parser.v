// =============================================================================
// 文件名   : tof1_parser.v
// 功能     : SDAM 单通道测距帧解析器 + CRC16 校验
// 帧格式   : A5 03 20 CMD(01) RSV(00) LEN_H LEN_L(00 0E) + 14B data + CRC_H CRC_L
//            data 小端：[6:7] 主目标距离 mm，[10:11] 主目标强度，[12:13] 环境光
// 说明     : CRC 大端发送（与上位机 Protocol.cs 一致）；为兼容手册写法，
//            同时接受高低字节交换的 CRC。
// 版本     : V1.0  (2026-11-02)
// =============================================================================
`timescale 1ns/1ps

module tof1_parser (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        byte_valid,   // 收到一个字节
    input  wire [7:0]  byte_in,
    output reg  [15:0] dist_mm,      // 主目标距离（mm）
    output reg  [15:0] inten,        // 主目标强度
    output reg  [15:0] amb,          // 环境光基底
    output reg         dist_valid,   // 单周期：距离有效
    output reg         frame_ok,     // 单周期：整帧校验通过
    output reg         crc_err       // 单周期：CRC 校验失败
);

    // ---------------- 运行 CRC ----------------
    reg  [15:0] crc_cur;
    wire [15:0] crc_nxt;

    // 帧头起点/重新同步时必须用初值 0xFFFF 起算，否则第一帧之后
    // 每帧都会用上一帧的 CRC 余数做初值，导致后续帧全部校验失败。
    wire        crc_seed = (idx == 5'd0) || ((idx <= 5'd6) && (byte_in == 8'hA5));
    wire [15:0] crc_in   = crc_seed ? 16'hFFFF : crc_cur;

    crc16_modbus u_crc (
        .crc_in  (crc_in),
        .data_in (byte_in),
        .crc_out (crc_nxt)
    );

    // ---------------- 字段缓存（7 个 16 位小端字） ----------------
    reg [15:0] word0, word1, word2, word3, word4, word5, word6;
    reg [7:0]  lo_byte;
    reg [7:0]  crc_hi;

    // ---------------- 状态计数 ----------------
    reg [4:0] idx;     // 0..6 头部, 7..20 数据, 21 CRC 高, 22 CRC 低

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            idx        <= 5'd0;
            crc_cur    <= 16'hFFFF;
            lo_byte    <= 8'd0;
            crc_hi     <= 8'd0;
            word0      <= 16'd0;
            word1      <= 16'd0;
            word2      <= 16'd0;
            word3      <= 16'd0;
            word4      <= 16'd0;
            word5      <= 16'd0;
            word6      <= 16'd0;
            dist_mm    <= 16'd0;
            inten      <= 16'd0;
            amb        <= 16'd0;
            dist_valid <= 1'b0;
            frame_ok   <= 1'b0;
            crc_err    <= 1'b0;
        end else begin
            frame_ok   <= 1'b0;
            crc_err    <= 1'b0;
            dist_valid <= 1'b0;

            if (byte_valid) begin
                case (idx)
                    // ---------------- 头部 ----------------
                    5'd0: begin
                        if (byte_in == 8'hA5) begin
                            idx     <= 5'd1;
                            crc_cur <= crc_nxt;
                        end else begin
                            idx     <= 5'd0;
                            crc_cur <= 16'hFFFF;
                        end
                    end
                    5'd1: begin
                        if (byte_in == 8'h03) begin idx <= 5'd2; crc_cur <= crc_nxt; end
                        else idx <= (byte_in == 8'hA5) ? 5'd1 : 5'd0;
                    end
                    5'd2: begin
                        if (byte_in == 8'h20) begin idx <= 5'd3; crc_cur <= crc_nxt; end
                        else idx <= (byte_in == 8'hA5) ? 5'd1 : 5'd0;
                    end
                    5'd3: begin
                        if (byte_in == 8'h01) begin idx <= 5'd4; crc_cur <= crc_nxt; end
                        else idx <= (byte_in == 8'hA5) ? 5'd1 : 5'd0;
                    end
                    5'd4: begin
                        if (byte_in == 8'h00) begin idx <= 5'd5; crc_cur <= crc_nxt; end
                        else idx <= (byte_in == 8'hA5) ? 5'd1 : 5'd0;
                    end
                    5'd5: begin   // LEN_H
                        if (byte_in == 8'h00) begin idx <= 5'd6; crc_cur <= crc_nxt; end
                        else idx <= (byte_in == 8'hA5) ? 5'd1 : 5'd0;
                    end
                    5'd6: begin   // LEN_L 必须为 0x0E
                        if (byte_in == 8'h0E) begin idx <= 5'd7; crc_cur <= crc_nxt; end
                        else idx <= (byte_in == 8'hA5) ? 5'd1 : 5'd0;
                    end

                    // ---------------- 14 字节数据 ----------------
                    5'd7, 5'd9, 5'd11, 5'd13, 5'd15, 5'd17, 5'd19: begin
                        lo_byte <= byte_in;          // 偶数字节 = 低位
                        crc_cur <= crc_nxt;
                        idx     <= idx + 5'd1;
                    end
                    5'd8:  begin word0 <= {byte_in, lo_byte}; crc_cur <= crc_nxt; idx <= idx + 5'd1; end
                    5'd10: begin word1 <= {byte_in, lo_byte}; crc_cur <= crc_nxt; idx <= idx + 5'd1; end
                    5'd12: begin word2 <= {byte_in, lo_byte}; crc_cur <= crc_nxt; idx <= idx + 5'd1; end
                    5'd14: begin word3 <= {byte_in, lo_byte}; crc_cur <= crc_nxt; idx <= idx + 5'd1; end
                    5'd16: begin word4 <= {byte_in, lo_byte}; crc_cur <= crc_nxt; idx <= idx + 5'd1; end
                    5'd18: begin word5 <= {byte_in, lo_byte}; crc_cur <= crc_nxt; idx <= idx + 5'd1; end
                    5'd20: begin word6 <= {byte_in, lo_byte}; crc_cur <= crc_nxt; idx <= 5'd21; end

                    // ---------------- CRC 两字节 ----------------
                    5'd21: begin
                        crc_hi <= byte_in;
                        idx    <= 5'd22;
                    end
                    5'd22: begin
                        idx <= 5'd0;
                        // 大端优先，同时容忍低高交换
                        if ({crc_hi, byte_in} == crc_cur || {byte_in, crc_hi} == crc_cur) begin
                            frame_ok <= 1'b1;
                            dist_mm  <= word3;
                            inten    <= word5;
                            amb      <= word6;
                            if (word3 != 16'h0000 && word3 != 16'hFFFF && word3[15] == 1'b0)
                                dist_valid <= 1'b1;
                        end else begin
                            crc_err <= 1'b1;
                        end
                    end

                    default: idx <= 5'd0;
                endcase
            end
        end
    end

endmodule
