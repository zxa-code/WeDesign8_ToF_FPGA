// =============================================================================
// 文件名   : uart_tx.v
// 功能     : 8N1 串口发送机（1 tick = 1 比特，tick 由 inc 累加器产生）
// 说明     : inc_tx = round(baud * 65536 / fclk)，fclk = 12 MHz
//            115200 -> 629      921600 -> 5033
//            启动时清零累加器，保证起始位宽度为一个完整比特
// 版本     : V1.0  (2026-11-02)
// =============================================================================
`timescale 1ns/1ps

module uart_tx (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [16:0] inc,        // 1 倍波特率累加步进
    input  wire        tx_start,   // 单周期启动脉冲
    input  wire [7:0]  tx_data,    // 待发送字节
    output reg         tx,         // 串行输出
    output reg         tx_busy     // 忙标志
);

    // ---------------- 波特率 tick ----------------
    reg [16:0] acc;
    reg        run;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            acc <= 17'd0;
        else if (tx_start)
            acc <= 17'd0;
        else if (run)
            acc <= {1'b0, acc[15:0]} + inc;
        else
            acc <= 17'd0;
    end
    wire tick = acc[16];

    // ---------------- 发送状态机 ----------------
    reg [3:0] phase;      // 已发送位数：0 起始位, 1..8 数据位, 9 停止位
    reg [7:0] shifter;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx      <= 1'b1;
            tx_busy <= 1'b0;
            run     <= 1'b0;
            phase   <= 4'd0;
            shifter <= 8'd0;
        end else if (!tx_busy) begin
            tx  <= 1'b1;
            run <= 1'b0;
            if (tx_start) begin
                shifter <= tx_data;
                tx_busy <= 1'b1;
                run     <= 1'b1;
                phase   <= 4'd0;
                tx      <= 1'b0;          // 起始位
            end
        end else if (tick) begin
            if (phase < 4'd8) begin
                phase   <= phase + 4'd1;
                tx      <= shifter[0];    // 数据位 LSB 先出
                shifter <= {1'b0, shifter[7:1]};
            end else if (phase == 4'd8) begin
                phase <= 4'd9;
                tx    <= 1'b1;            // 停止位
            end else begin
                tx_busy <= 1'b0;
                run     <= 1'b0;
                phase   <= 4'd0;
            end
        end
    end

endmodule
