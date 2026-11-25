// =============================================================================
// 文件名   : bcd_conv.v
// 功能     : 16 位二进制 -> 5 位 BCD（double dabble 算法，每拍完成“加3判断+左移”）
// 说明     : 结果 bcd_out[19:16]=万位 ... bcd_out[3:0]=个位
//            单次转换 16 个时钟周期，转换期间 bcd_out 保持上一次结果
// 版本     : V1.0  (2026-11-02)
// =============================================================================
`timescale 1ns/1ps

module bcd_conv (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,      // 单周期启动
    input  wire [15:0] bin_in,
    output reg  [19:0] bcd_out,
    output reg         busy
);

    reg [35:0] sr;      // {20 位 BCD, 16 位二进制}
    reg [4:0]  iter;    // 0..15

    // 各 BCD 位 >=5 则加 3
    reg [19:0] adj;
    always @(*) begin
        adj = sr[35:16];
        if (adj[3:0]   >= 4'd5) adj[3:0]   = adj[3:0]   + 4'd3;
        if (adj[7:4]   >= 4'd5) adj[7:4]   = adj[7:4]   + 4'd3;
        if (adj[11:8]  >= 4'd5) adj[11:8]  = adj[11:8]  + 4'd3;
        if (adj[15:12] >= 4'd5) adj[15:12] = adj[15:12] + 4'd3;
        if (adj[19:16] >= 4'd5) adj[19:16] = adj[19:16] + 4'd3;
    end

    // 本周期的“加3后左移”结果
    wire [35:0] sr_next = {adj, sr[15:0]} << 1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sr      <= 36'd0;
            iter    <= 5'd0;
            bcd_out <= 20'd0;
            busy    <= 1'b0;
        end else if (!busy) begin
            if (start) begin
                sr   <= {20'd0, bin_in};
                iter <= 5'd0;
                busy <= 1'b1;
            end
        end else begin
            if (iter == 5'd15) begin
                bcd_out <= sr_next[35:16];
                busy    <= 1'b0;
                iter    <= 5'd0;
            end else begin
                sr   <= sr_next;
                iter <= iter + 5'd1;
            end
        end
    end

endmodule
