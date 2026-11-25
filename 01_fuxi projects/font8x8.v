// =============================================================================
// 文件名   : font8x8.v
// 功能     : 5x7 点阵字库（居中到 8x8 单元），按"列"输出，供 OLED 页寻址写入
// 说明     : 每个字符存 5 个 8 bit 列向量（低 7 位有效，bit0 = 最上面一行）
//            输出 col = 0..7，其中 col=1..5 对应字形第 0..4 列，其余输出 0
//            字库只含本工程用到的字符，用 40 bit/字符 节省 LUT
//            离线自检：python Projects/Projects_V1.0/02_debug/glyph_preview.py
//            已实现字符集（V1.6 补齐 K/L/N/X，V2.0 补 P，V3.0-P3 补 G/H/+/>//，P3c 补 W/Y 与小写 b/d/e/g/i/n/s/y）：
//              空格 0-9 A B C D E F G H I K L M N O P R S T U V W X Y
//              b d e g i n s y  - . : ? + > /
//            字形排布：40 bit = 5 列 x 8 bit，**低字节是第 0 列**，bit0 = 最上面一行
// 版本     : V3.0-P3c (2026-11-14，补 W/Y 与 INFO 页 "Designed by ZXA" 所需小写)
// =============================================================================
`timescale 1ns/1ps

module font8x8 (
    input  wire [7:0] ch,
    input  wire [2:0] col,
    output wire [7:0] bits
);

    reg [39:0] glyph;

    always @(*) begin
        glyph = 40'h0;
        case (ch)
            8'h20: glyph = 40'h0000000000;   //  
            8'h30: glyph = 40'h3E4549513E;   // 0
            8'h31: glyph = 40'h00407F4200;   // 1
            8'h32: glyph = 40'h4649516142;   // 2
            8'h33: glyph = 40'h314B454121;   // 3
            8'h34: glyph = 40'h107F121418;   // 4
            8'h35: glyph = 40'h3945454527;   // 5
            8'h36: glyph = 40'h3049494A3C;   // 6
            8'h37: glyph = 40'h0305097101;   // 7
            8'h38: glyph = 40'h3649494936;   // 8
            8'h39: glyph = 40'h1E29494906;   // 9
            8'h41: glyph = 40'h7E0909097E;   // A
            8'h42: glyph = 40'h364949497F;   // B
            8'h43: glyph = 40'h224141413E;   // C
            8'h44: glyph = 40'h3E4141417F;   // D
            8'h45: glyph = 40'h414949497F;   // E
            8'h46: glyph = 40'h010909097F;   // F
            8'h47: glyph = 40'h3A4941413E;   // G（V3.0-P3 新增）
            8'h48: glyph = 40'h7F0808087F;   // H（V3.0-P3 新增）
            8'h49: glyph = 40'h00417F4100;   // I
            8'h4B: glyph = 40'h412214087F;   // K（V1.6 新增）
            8'h4C: glyph = 40'h404040407F;   // L（V1.6 新增）
            8'h4D: glyph = 40'h7F020C027F;   // M
            8'h4E: glyph = 40'h7F1008047F;   // N（V1.6 新增）
            8'h4F: glyph = 40'h3E4141413E;   // O
            8'h50: glyph = 40'h060909097F;   // P（V2.0 新增）
            8'h52: glyph = 40'h462919097F;   // R
            8'h53: glyph = 40'h3249494926;   // S
            8'h54: glyph = 40'h01017F0101;   // T
            8'h55: glyph = 40'h3F4040403F;   // U
            8'h56: glyph = 40'h1F2040201F;   // V
            8'h57: glyph = 40'h7F3018307F;   // W（V3.0-P3c 新增）
            8'h58: glyph = 40'h6314081463;   // X（V1.6 新增）
            8'h59: glyph = 40'h01027C0201;   // Y（V3.0-P3c 新增）
            8'h62: glyph = 40'h384444487F;   // b（V3.0-P3c 新增，INFO 页）
            8'h64: glyph = 40'h7F48444438;   // d（V3.0-P3c 新增，INFO 页）
            8'h65: glyph = 40'h1854545438;   // e（V3.0-P3c 新增，INFO 页）
            8'h67: glyph = 40'h3E5252520C;   // g（V3.0-P3c 新增，INFO 页）
            8'h69: glyph = 40'h00407D4400;   // i（V3.0-P3c 新增，INFO 页）
            8'h6E: glyph = 40'h780404087C;   // n（V3.0-P3c 新增，INFO 页）
            8'h73: glyph = 40'h2054545448;   // s（V3.0-P3c 新增，INFO 页）
            8'h79: glyph = 40'h3C5050500C;   // y（V3.0-P3c 新增，INFO 页）
            8'h2B: glyph = 40'h083E080808;   // +（V3.0-P3 新增）
            8'h2D: glyph = 40'h0808080808;   // -
            8'h2E: glyph = 40'h0000606000;   // .
            8'h2F: glyph = 40'h0102040810;   // /（V3.0-P3 新增）
            8'h3A: glyph = 40'h0000363600;   // :
            8'h3E: glyph = 40'h0008142241;   // >（V3.0-P3 新增）
            8'h3F: glyph = 40'h0609510102;   // ?
            default: glyph = 40'h7F4141417F;   // 未定义字符：方框（V1.6：不再静默空白）
        endcase
    end

    wire       in_range = (col >= 3'd1) && (col <= 3'd5);
    wire [2:0] sel      = col - 3'd1;              // 0..4：字形第几列

    assign bits = in_range ? glyph[{sel, 3'b000} +: 7] : 8'h00;

endmodule
