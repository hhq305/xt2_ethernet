// =============================================================
// seg_scan.v
// 4 位动态扫描 7 段数码管驱动 (共阳: en=0 选中, seg=0 点亮段)
// HX4S20C 板载 8 位数码管, 这里只用低 4 位 (en[3:0]) 避免与 LED/rd_en 冲突
//
// 输入: bcd_in[15:0] = {digit3,digit2,digit1,digit0}, 每 4 bit 一位 BCD (0-F)
// 输出: seg[6:0]  = 段码 (a..g, 低有效)
//       en[3:0]   = 位选 (低有效, 一次只点亮一位)
// =============================================================
`timescale 1ns/1ps

module seg_scan (
    input  wire        clk,        // 推荐 25MHz 或 50MHz
    input  wire        rst_n,
    input  wire [15:0] bcd_in,     // 4 个十六进制位
    output reg  [6:0]  seg,
    output reg  [3:0]  en
);

    // 16 位扫描计数, 25MHz 时刷新率 ~ 25M/2^16 / 4 = ~95Hz, OK
    reg [15:0] cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) cnt <= 16'd0;
        else        cnt <= cnt + 16'd1;
    end

    // 用 cnt[15:14] 选当前显示位
    wire [1:0] dsel = cnt[15:14];

    // 当前位的 BCD 值
    reg [3:0] nibble;
    always @(*) begin
        case (dsel)
            2'd0: nibble = bcd_in[3:0];
            2'd1: nibble = bcd_in[7:4];
            2'd2: nibble = bcd_in[11:8];
            2'd3: nibble = bcd_in[15:12];
        endcase
    end

    // 位选 (低有效)
    always @(*) begin
        case (dsel)
            2'd0: en = 4'b1110;
            2'd1: en = 4'b1101;
            2'd2: en = 4'b1011;
            2'd3: en = 4'b0111;
        endcase
    end

    // 段码查表 (0-F, 低有效, 与 sm_scan demo 一致)
    always @(*) begin
        case (nibble)
            4'h0: seg = 7'b1000000;
            4'h1: seg = 7'b1111001;
            4'h2: seg = 7'b0100100;
            4'h3: seg = 7'b0110000;
            4'h4: seg = 7'b0011001;
            4'h5: seg = 7'b0010010;
            4'h6: seg = 7'b0000010;
            4'h7: seg = 7'b1111000;
            4'h8: seg = 7'b0000000;
            4'h9: seg = 7'b0010000;
            4'hA: seg = 7'b0001000;
            4'hB: seg = 7'b0000011;
            4'hC: seg = 7'b1000110;
            4'hD: seg = 7'b0100001;
            4'hE: seg = 7'b0000110;
            4'hF: seg = 7'b0001110;
            default: seg = 7'b1111111;
        endcase
    end

endmodule
