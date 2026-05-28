// =============================================================
// vga_ctrl.v : VGA 800x600@60 时序 (像素时钟 40MHz)
// 显示居中 320x240 灰度图区域, 其它为黑色。
// =============================================================
`timescale 1ns/1ps
module vga_ctrl #(
    parameter IMG_W = 320,
    parameter IMG_H = 240
)(
    input  wire        pclk,           // 40MHz
    input  wire        rst_n,
    // 帧缓存读接口
    output reg         fb_re,
    output reg  [$clog2(IMG_W*IMG_H)-1:0] fb_raddr,
    input  wire [7:0]  fb_rdata,
    // VGA 输出
    output reg         hs, vs,
    output reg         de,
    output reg  [4:0]  r,
    output reg  [5:0]  g,
    output reg  [4:0]  b
);
    // 800x600@60 timing
    localparam H_ACT=800,H_FP=40, H_SY=128,H_BP=88, H_TOT=1056;
    localparam V_ACT=600,V_FP=1,  V_SY=4,  V_BP=23, V_TOT=628;

    reg [11:0] hcnt, vcnt;
    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin hcnt<=0; vcnt<=0; end
        else begin
            if (hcnt==H_TOT-1) begin
                hcnt<=0;
                vcnt <= (vcnt==V_TOT-1)? 0 : vcnt+1'b1;
            end else hcnt<=hcnt+1'b1;
        end
    end

    wire h_active = (hcnt < H_ACT);
    wire v_active = (vcnt < V_ACT);

    localparam X0 = (H_ACT-IMG_W)/2;     // 240
    localparam Y0 = (V_ACT-IMG_H)/2;     // 180

    wire in_img = h_active && v_active &&
                  (hcnt>=X0) && (hcnt<X0+IMG_W) &&
                  (vcnt>=Y0) && (vcnt<Y0+IMG_H);
    wire [9:0]  ix = hcnt - X0[11:0];
    wire [8:0]  iy = vcnt - Y0[11:0];

    // 提前一拍发起 BRAM 读
    always @(posedge pclk) begin
        fb_re    <= in_img;
        fb_raddr <= iy*IMG_W + ix;
    end

    // 输出寄存
    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            hs<=1; vs<=1; de<=0; r<=0; g<=0; b<=0;
        end else begin
            // 极性: 800x600@60 为正极性
            hs <= (hcnt>=H_ACT+H_FP) && (hcnt<H_ACT+H_FP+H_SY);
            vs <= (vcnt>=V_ACT+V_FP) && (vcnt<V_ACT+V_FP+V_SY);
            de <= h_active && v_active;
            if (in_img) begin
                r <= fb_rdata[7:3];
                g <= fb_rdata[7:2];
                b <= fb_rdata[7:3];
            end else begin
                r<=0; g<=0; b<=0;
            end
        end
    end
endmodule
