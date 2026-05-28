// =============================================================
// img_rx_fb.v
// 基础要求 ② : 接收 PC 通过 UDP 下发的图像, 写入帧缓存。
// 报文格式 (CMD=0x10 IMG_FRAME)：
//   [MAGIC0,MAGIC1,CMD,LEN_H,LEN_L]            // 报文头
//   [FLAG,YH,YL, p0_R,p0_G,p0_B, p1_R,...]     // payload
// 本模块解析 payload，把 RGB888 -> 灰度 8bit 写入 framebuf。
// =============================================================
`timescale 1ns/1ps
`include "pkt_fmt.vh"

module img_rx_fb #(
    parameter IMG_W = 320,
    parameter IMG_H = 240
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,
    // 帧缓存写口
    output reg         fb_we,
    output reg  [$clog2(IMG_W*IMG_H)-1:0] fb_waddr,
    output reg  [7:0]  fb_wdata,
    // 状态
    output reg         frame_done
);
    localparam S_M0=0,S_M1=1,S_CMD=2,S_LH=3,S_LL=4,
               S_FLAG=5,S_YH=6,S_YL=7,
               S_R=8,S_G=9,S_B=10,S_DROP=11;

    reg [3:0]  st;
    reg [7:0]  cmd_r;
    reg [15:0] len_r, idx_r;          // payload 内偏移
    reg [7:0]  flag_r;
    reg [15:0] yline_r;
    reg [9:0]  xpix;
    reg [7:0]  rch, gch;

    // RGB888 -> Y (近似 (R+2G+B)/4)
    wire [9:0] ysum = rch + (gch<<1) + rx_data;
    wire [7:0] ypix = ysum[9:2];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st<=S_M0; cmd_r<=0; len_r<=0; idx_r<=0;
            flag_r<=0; yline_r<=0; xpix<=0; rch<=0; gch<=0;
            fb_we<=0; fb_waddr<=0; fb_wdata<=0; frame_done<=0;
        end else begin
            fb_we      <= 1'b0;
            frame_done <= 1'b0;
            if (rx_valid) begin
                case (st)
                    S_M0  : st <= (rx_data==`MAGIC0)? S_M1 : S_M0;
                    S_M1  : st <= (rx_data==`MAGIC1)? S_CMD: S_M0;
                    S_CMD : begin cmd_r<=rx_data;
                                  st <= (rx_data==`CMD_IMG_FRAME)? S_LH : S_DROP; end
                    S_LH  : begin len_r[15:8]<=rx_data; st<=S_LL; end
                    S_LL  : begin len_r[7:0] <=rx_data; idx_r<=0; st<=S_FLAG; end
                    S_FLAG: begin flag_r<=rx_data; idx_r<=idx_r+1'b1; st<=S_YH; end
                    S_YH  : begin yline_r[15:8]<=rx_data; idx_r<=idx_r+1'b1; st<=S_YL; end
                    S_YL  : begin yline_r[7:0] <=rx_data; idx_r<=idx_r+1'b1;
                                  xpix <= 0; st<=S_R; end
                    S_R   : begin rch<=rx_data; idx_r<=idx_r+1'b1; st<=S_G; end
                    S_G   : begin gch<=rx_data; idx_r<=idx_r+1'b1; st<=S_B; end
                    S_B   : begin
                                fb_we    <= 1'b1;
                                fb_waddr <= yline_r[8:0]*IMG_W + xpix;
                                fb_wdata <= ypix;
                                xpix     <= xpix + 1'b1;
                                idx_r    <= idx_r + 1'b1;
                                if (idx_r == len_r-1) begin
                                    if (flag_r[0]) frame_done <= 1'b1;
                                    st <= S_M0;
                                end else st <= S_R;
                            end
                    S_DROP: begin
                                if (idx_r == len_r-1) st <= S_M0;
                                idx_r <= idx_r + 1'b1;
                            end
                    default: st <= S_M0;
                endcase
            end
        end
    end
endmodule
