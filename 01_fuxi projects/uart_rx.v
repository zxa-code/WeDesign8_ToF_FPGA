// =============================================================================
// 文件名   : uart_rx.v
// 功能     : 8N1 串口接收机，采样率为 8 倍波特率（由 inc 累加器产生）
// 说明     : inc = round(8 * baud * 65536 / fclk)，fclk = 12 MHz
//            115200  -> inc = 5033
//            921600  -> inc = 40265
//            在起始位中点(4 tick)采样并校验，随后每 8 tick 采样一位数据
// 版本     : V1.0  (2026-11-02)
// =============================================================================
`timescale 1ns/1ps

module uart_rx (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [16:0] inc,        // 8 倍波特率累加步进
    input  wire        rx_in,      // 来自引脚（已同步前）
    output reg  [7:0]  rx_data,    // 收到的字节
    output reg         rx_valid    // 单周期有效脉冲
);

    // ---------------- 输入同步 ----------------
    reg rx_d0, rx_d1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_d0 <= 1'b1;
            rx_d1 <= 1'b1;
        end else begin
            rx_d0 <= rx_in;
            rx_d1 <= rx_d0;
        end
    end

    // ---------------- 8x 波特率 tick 产生 ----------------
    reg [16:0] acc;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            acc <= 17'd0;
        else
            acc <= {1'b0, acc[15:0]} + inc;   // 进位在 bit16
    end
    wire tick = acc[16];

    // ---------------- 接收状态机 ----------------
    localparam S_IDLE  = 2'd0;
    localparam S_START = 2'd1;
    localparam S_DATA  = 2'd2;
    localparam S_STOP  = 2'd3;

    reg [1:0] state;
    reg [2:0] cnt;      // 每比特内 tick 计数
    reg [2:0] bitn;     // 数据位序号
    reg [7:0] shifter;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            cnt      <= 3'd0;
            bitn     <= 3'd0;
            shifter  <= 8'd0;
            rx_data  <= 8'd0;
            rx_valid <= 1'b0;
        end else begin
            rx_valid <= 1'b0;
            case (state)
                S_IDLE: begin
                    cnt <= 3'd0;
                    if (!rx_d1)                 // 检测到下降沿（起始位）
                        state <= S_START;
                end

                S_START: begin
                    if (tick) begin
                        if (cnt == 3'd3) begin // 起始位中点
                            cnt <= 3'd0;
                            if (!rx_d1)
                                state <= S_DATA;
                            else
                                state <= S_IDLE; // 毛刺
                        end else begin
                            cnt <= cnt + 3'd1;
                        end
                    end
                end

                S_DATA: begin
                    if (tick) begin
                        if (cnt == 3'd7) begin
                            cnt     <= 3'd0;
                            shifter <= {rx_d1, shifter[7:1]};  // LSB 先到
                            if (bitn == 3'd7) begin
                                bitn  <= 3'd0;
                                state <= S_STOP;
                            end else begin
                                bitn  <= bitn + 3'd1;
                            end
                        end else begin
                            cnt <= cnt + 3'd1;
                        end
                    end
                end

                S_STOP: begin
                    if (tick) begin
                        if (cnt == 3'd7) begin
                            cnt      <= 3'd0;
                            rx_data  <= shifter;
                            rx_valid <= 1'b1;
                            state    <= S_IDLE;
                        end else begin
                            cnt <= cnt + 3'd1;
                        end
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
