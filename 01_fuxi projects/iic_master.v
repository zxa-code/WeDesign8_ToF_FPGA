// =============================================================================
// 文件名   : i2c_master.v
// 功能     : I2C 主机（字节级），400 kHz 档（12 MHz / 32 = 375 kHz）
// 说明     : 只支持三种操作：START、WRITE 一个字节、STOP；
//            SCL 推挽输出；SDA 开漏（1 = 拉低，0 = 释放，靠外部/模块上拉）
//            每次操作由 req 触发，完成后 done 单周期脉冲；ack 为从机应答
//            时序：每个相位 16 个 clk（1.33 us），SDA 在 SCL 低电平期间变化
// 版本     : V3.0  (2026-11-13)
// =============================================================================
`timescale 1ns/1ps

module i2c_master (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       req,
    input  wire [1:0] op,       // 00=START, 01=WRITE, 10=STOP
    input  wire [7:0] data,
    output reg        busy,
    output reg        done,
    output reg        ack,
    output reg        scl,
    inout  wire       sda
);

    localparam [1:0] OP_START = 2'd0;
    localparam [1:0] OP_WRITE = 2'd1;
    localparam [1:0] OP_STOP  = 2'd2;

    // ---------------- 相位节拍：16 clk = 1.33 us，1 bit = 2 相位 ----------------
    localparam integer TICK_DIV = 16;

    reg [3:0] tick_cnt;
    wire      tick = (tick_cnt == TICK_DIV - 1);

    // ---------------- SDA 输入同步（读应答/总线电平） ----------------
    reg sda_d0, sda_d1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sda_d0 <= 1'b1;
            sda_d1 <= 1'b1;
        end else begin
            sda_d0 <= sda;
            sda_d1 <= sda_d0;
        end
    end

    // ---------------- 开漏输出 ----------------
    reg sda_oe;     // 1 = 拉低，0 = 释放
    assign sda = sda_oe ? 1'b0 : 1'bz;

    // ---------------- 状态机 ----------------
    localparam [3:0] S_IDLE     = 4'd0;
    localparam [3:0] S_START_A  = 4'd1;   // SCL 低、释放 SDA
    localparam [3:0] S_START_B  = 4'd2;   // SCL 高
    localparam [3:0] S_START_C  = 4'd3;   // SDA 拉低（START 条件）
    localparam [3:0] S_START_D  = 4'd4;   // SCL 低
    localparam [3:0] S_WR_LOW   = 4'd5;
    localparam [3:0] S_WR_HIGH  = 4'd6;
    localparam [3:0] S_ACK_LOW  = 4'd7;
    localparam [3:0] S_ACK_HIGH = 4'd8;
    localparam [3:0] S_ACK_END  = 4'd9;
    localparam [3:0] S_STOP_A   = 4'd10;  // SCL 低、SDA 拉低
    localparam [3:0] S_STOP_B   = 4'd11;  // SCL 高
    localparam [3:0] S_STOP_C   = 4'd12;  // SDA 释放（STOP 条件）

    reg [3:0] st;
    reg [1:0] op_l;
    reg [7:0] data_l;
    reg [3:0] bitn;
    reg       scl_idle;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st       <= S_IDLE;
            busy     <= 1'b0;
            done     <= 1'b0;
            ack      <= 1'b0;
            scl      <= 1'b1;
            sda_oe   <= 1'b0;
            scl_idle <= 1'b1;
            op_l     <= 2'd0;
            data_l   <= 8'd0;
            bitn     <= 4'd7;
            tick_cnt <= 4'd0;
        end else begin
            done <= 1'b0;

            // 相位节拍计数（与 FSM 同块，避免多驱动）
            if (tick)
                tick_cnt <= 4'd0;
            else
                tick_cnt <= tick_cnt + 4'd1;

            if (busy) begin
                if (tick) begin
                    case (st)
                        S_START_A: begin
                            scl    <= 1'b0;
                            sda_oe <= 1'b0;
                            st     <= S_START_B;
                        end
                        S_START_B: begin
                            scl <= 1'b1;
                            st  <= S_START_C;
                        end
                        S_START_C: begin
                            sda_oe <= 1'b1;         // SCL 高时 SDA 下降 = START
                            st     <= S_START_D;
                        end
                        S_START_D: begin
                            scl      <= 1'b0;
                            scl_idle <= 1'b0;
                            busy     <= 1'b0;
                            done     <= 1'b1;
                            st       <= S_IDLE;
                        end
                        S_WR_LOW: begin
                            scl    <= 1'b0;
                            sda_oe <= ~data_l[bitn];
                            st     <= S_WR_HIGH;
                        end
                        S_WR_HIGH: begin
                            scl <= 1'b1;
                            if (bitn == 4'd0) begin
                                st <= S_ACK_LOW;
                            end else begin
                                bitn <= bitn - 4'd1;
                                st  <= S_WR_LOW;
                            end
                        end
                        S_ACK_LOW: begin
                            scl    <= 1'b0;
                            sda_oe <= 1'b0;         // 释放 SDA，等从机拉低
                            st     <= S_ACK_HIGH;
                        end
                        S_ACK_HIGH: begin
                            scl <= 1'b1;            // 高电平期间采样 ACK
                            ack <= sda_d1;
                            st  <= S_ACK_END;
                        end
                        S_ACK_END: begin
                            scl  <= 1'b0;
                            busy <= 1'b0;
                            done <= 1'b1;
                            st   <= S_IDLE;
                        end
                        S_STOP_A: begin
                            scl    <= 1'b0;
                            sda_oe <= 1'b1;
                            st     <= S_STOP_B;
                        end
                        S_STOP_B: begin
                            scl <= 1'b1;
                            st  <= S_STOP_C;
                        end
                        S_STOP_C: begin
                            sda_oe   <= 1'b0;       // SCL 高时 SDA 上升 = STOP
                            scl_idle <= 1'b1;
                            busy     <= 1'b0;
                            done     <= 1'b1;
                            st       <= S_IDLE;
                        end
                        default: st <= S_IDLE;
                    endcase
                end
            end else if (req) begin
                op_l     <= op;
                data_l   <= data;
                busy     <= 1'b1;
                ack      <= 1'b0;
                tick_cnt <= 4'd0;       // 保证第一个相位完整
                bitn     <= 4'd7;
                case (op)
                    OP_START: st <= S_START_A;
                    OP_WRITE: st <= S_WR_LOW;
                    OP_STOP:  st <= S_STOP_A;
                    default:  st <= S_IDLE;
                endcase
            end else begin
                scl <= scl_idle;
            end
        end
    end

endmodule
