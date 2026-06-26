// =============================================================
// img_proc.v
// 扩展要求 ② : 实时图像处理 — 灰度直通 / Sobel 边缘 / 阈值二值。
// 像素流入 (帧缓存读出或摄像头流), 同步流出处理后像素。
// =============================================================
`timescale 1ns/1ps
`include "pkt_fmt.vh"

module img_proc #(
    parameter IMG_W = 320,
    parameter IMG_H = 240
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [1:0]  mode,         // 0 raw, 1 gray, 2 edge, 3 detect(二值)
    input  wire        din_valid,
    input  wire [7:0]  din,
    output reg         dout_valid,
    output reg  [9:0]  x_o,
    output reg  [8:0]  y_o,
    output reg  [7:0]  dout,
    output reg         is_obj         // 二值前景标志
);
    wire        wv;
    wire [9:0]  wx;
    wire [8:0]  wy;
    wire [7:0]  p00,p01,p02,p10,p11,p12,p20,p21,p22;

    line_buf #(.IMG_W(IMG_W),.IMG_H(IMG_H)) u_lb (
        .clk(clk),.rst_n(rst_n),.din_valid(din_valid),.din(din),
        .win_valid(wv),.x_o(wx),.y_o(wy),
        .p00(p00),.p01(p01),.p02(p02),
        .p10(p10),.p11(p11),.p12(p12),
        .p20(p20),.p21(p21),.p22(p22));

    // Sobel
    wire signed [11:0] gx = (p02+ (p12<<1) + p22) - (p00 + (p10<<1) + p20);
    wire signed [11:0] gy = (p20+ (p21<<1) + p22) - (p00 + (p01<<1) + p02);
    wire [11:0] agx = gx[11]? -gx : gx;
    wire [11:0] agy = gy[11]? -gy : gy;
    wire [12:0] gsum = agx + agy;
    wire [7:0]  edge_pix = (gsum>12'd255) ? 8'hFF : gsum[7:0];

    localparam THR = 8'd128;        // 阈值检测

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dout_valid<=0; dout<=0; is_obj<=0; x_o<=0; y_o<=0;
        end else begin
            dout_valid <= wv;
            x_o <= wx; y_o <= wy;
            case (mode)
                `PROC_RAW    : dout <= p11;
                `PROC_GRAY   : dout <= p11;          // 输入已是灰度
                `PROC_EDGE   : dout <= edge_pix;
                `PROC_DETECT : dout <= (p11>THR)? 8'hFF : 8'h00;
            endcase
            is_obj <= (mode==`PROC_DETECT) ? (p11>THR) : 1'b0;
        end
    end
endmodule
