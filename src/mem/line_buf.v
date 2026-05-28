// =============================================================
// line_buf.v : 3 行行缓存, 用于 3x3 邻域卷积 (Sobel)。
// 输入: 像素流 din 与 valid (一行 IMG_W 像素), 输出窗口 9 像素同步打出。
// =============================================================
`timescale 1ns/1ps
module line_buf #(
    parameter IMG_W = 320,
    parameter IMG_H = 240
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        din_valid,
    input  wire [7:0]  din,
    output reg         win_valid,
    output reg  [9:0]  x_o,
    output reg  [8:0]  y_o,
    output reg  [7:0]  p00,p01,p02,
    output reg  [7:0]  p10,p11,p12,
    output reg  [7:0]  p20,p21,p22
);
    reg [7:0] line0 [0:IMG_W-1];
    reg [7:0] line1 [0:IMG_W-1];
    reg [9:0] x;
    reg [8:0] y;

    reg [7:0] s0a,s0b,s0c;
    reg [7:0] s1a,s1b,s1c;
    reg [7:0] s2a,s2b,s2c;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x<=0; y<=0; win_valid<=0;
            {s0a,s0b,s0c,s1a,s1b,s1c,s2a,s2b,s2c}<=0;
            x_o<=0; y_o<=0;
            {p00,p01,p02,p10,p11,p12,p20,p21,p22}<=0;
        end else begin
            win_valid<=1'b0;
            if (din_valid) begin
                // 移位窗口 (右移)
                s0a<=s0b; s0b<=s0c; s0c<=line0[x];
                s1a<=s1b; s1b<=s1c; s1c<=line1[x];
                s2a<=s2b; s2b<=s2c; s2c<=din;
                // 写入 line buffer (双行循环): line0=上一行 line1=本行->新像素
                line0[x] <= line1[x];
                line1[x] <= din;
                // 输出窗口
                if (y>=2 && x>=2) begin
                    win_valid<=1'b1;
                    x_o<=x-10'd1; y_o<=y-9'd1;       // 中心坐标
                    p00<=s0a; p01<=s0b; p02<=s0c;
                    p10<=s1a; p11<=s1b; p12<=s1c;
                    p20<=s2a; p21<=s2b; p22<=s2c;
                end
                if (x==IMG_W-1) begin
                    x<=0;
                    if (y<IMG_H-1) y<=y+1'b1;
                end else x<=x+1'b1;
            end
        end
    end
endmodule
