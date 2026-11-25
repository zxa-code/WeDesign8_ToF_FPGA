// =============================================================================
// 文件名   : crc16_modbus.v
// 功能     : CRC16/Modbus 单字节递推函数库（纯组合，供 TOF 解析模块逐字节调用）
// 参数     : poly 0xA001（0x8005 反向）、初值 0xFFFF、输入/输出均反射、结果不取反
// 说明     : SDAM 手册中的 CRC 与上位机 Protocol.cs 一致，按字节逐位移位即可
// 版本     : V1.0  (2026-11-02)
// =============================================================================
`timescale 1ns/1ps

module crc16_modbus (
    input  wire [15:0] crc_in,
    input  wire [7:0]  data_in,
    output reg  [15:0] crc_out
);

    integer i;
    reg [15:0] c;

    always @(*) begin
        c = crc_in ^ {8'h00, data_in};   // 低 8 位异或
        for (i = 0; i < 8; i = i + 1) begin
            if (c[0])
                c = {1'b0, c[15:1]} ^ 16'hA001;
            else
                c = {1'b0, c[15:1]};
        end
        crc_out = c;
    end

endmodule
