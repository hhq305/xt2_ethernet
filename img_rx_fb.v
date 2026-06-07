// =============================================================
// img_rx_fb.v
// 基础要求 ② : 接收 PC 通过 UDP 下发的图像, 写入帧缓存。
// 报文格式 (CMD=0x10 IMG_FRAME)：
//   [MAGIC0,MAGIC1,CMD,LEN_H,LEN_L]            // 报文头
//   [FLAG,YH,YL,XH,XL, p0_R,p0_G,p0_B, p1_R,...] // payload
// 本模块解析 payload，把 RGB888 -> RGB444 12bit 写入 framebuf。
// =============================================================
`timescale 1ns/1ps
`include "pkt_fmt.vh"

module img_rx_fb #(
    parameter IMG_W = 160,
    parameter IMG_H = 120,
    parameter AW    = $clog2(IMG_W*IMG_H)
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,
    // 帧缓存写口
    output reg         fb_we,
    output reg  [AW-1:0] fb_waddr,
    output reg  [11:0] fb_wdata,
    // 状态
    output reg         frame_done
);
    localparam S_M0=0,S_M1=1,S_CMD=2,S_LH=3,S_LL=4,
               S_FLAG=5,S_YH=6,S_YL=7,S_XH=8,S_XL=9,
               S_R=10,S_G=11,S_B=12,S_DROP_ALL=13;

    reg [3:0]  st;
    reg [7:0]  cmd_r;
    reg [15:0] len_r, idx_r;          // payload 内偏移
    reg [7:0]  flag_r;
    reg [7:0]  rch, gch;

    // RGB888 -> RGB444，匹配 12-bit VGA_D，减少 RGB332 量化导致的细节损失。
    wire [11:0] pix444 = {rch[7:4], gch[7:4], rx_data[7:4]};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st<=S_M0; cmd_r<=0; len_r<=0; idx_r<=0;
            flag_r<=0; rch<=0; gch<=0;
            fb_we<=0; fb_waddr<=0; fb_wdata<=0; frame_done<=0;
        end else begin
            fb_we      <= 1'b0;
            frame_done <= 1'b0;

            if (rx_valid) begin
                case (st)
                    // 包头搜寻阶段：支持滑窗，支持连续 A5
                    S_M0  : st <= (rx_data==`MAGIC0)? S_M1 : S_M0;
                    S_M1  : st <= (rx_data==`MAGIC1)? S_CMD: (rx_data==`MAGIC0 ? S_M1 : S_M0);
                    
                    // 指令译码阶段
                    // 非图像命令也必须先读取 LEN_H/LEN_L 后再丢弃 payload。
                    // 否则先发送 led/seg/img_req 等短包后，本模块会卡在 S_DROP_ALL，
                    // 后续 CMD_IMG_FRAME 图像包将无法被解析，VGA 会一直停在接收状态色。
                    S_CMD : begin
                                cmd_r  <= rx_data;
                                st     <= S_LH;
                            end

                    // 长度提取阶段 (无论什么 CMD，都在这里安全地提取长度，供后续精准包尾对齐)
                    S_LH  : begin len_r[15:8]<=rx_data; st<=S_LL; end
                    S_LL  : begin
                                len_r[7:0] <=rx_data;
                                idx_r<=0;
                                if (cmd_r==`CMD_IMG_FRAME && {len_r[15:8], rx_data} >= 16'd5)
                                    st <= S_FLAG; // len=5 is an end-of-frame marker with no pixel data
                                else if ({len_r[15:8], rx_data} == 16'd0)
                                    st <= S_M0;
                                else
                                    st <= S_DROP_ALL;
                            end
                    
                    // 图像 Payload 解析阶段：这里不进行任何 A5 5A 检测，100% 免疫像素数据误判
                    S_FLAG: begin flag_r<=rx_data; idx_r<=idx_r+1'b1; st<=S_YH; end
                    S_YH  : begin idx_r<=idx_r+1'b1; st<=S_YL; end
                    S_YL  : begin idx_r<=idx_r+1'b1; st<=S_XH; end
                    S_XH  : begin idx_r<=idx_r+1'b1; st<=S_XL; end
                    S_XL  : begin
                                idx_r <= idx_r + 1'b1;
                                if (len_r == 16'd5) begin
                                    if (flag_r[0]) frame_done <= 1'b1;
                                    st <= S_M0;
                                end else begin
                                    st <= S_R;
                                end
                            end
                    S_R   : begin rch<=rx_data; idx_r<=idx_r+1'b1; st<=S_G; end
                    S_G   : begin gch<=rx_data; idx_r<=idx_r+1'b1; st<=S_B; end
                    S_B   : begin
                                // SDRAM path writes pixels sequentially; fb_waddr is kept only
                                // for legacy compatibility and is not used by sdram_img_fb.
                                // Avoid y*IMG_W address multiply to save MSlice resources.
                                fb_we    <= 1'b1;
                                fb_waddr <= {AW{1'b0}};
                                fb_wdata <= pix444;
                                idx_r    <= idx_r + 1'b1;
                                if (idx_r == len_r-1) begin
                                    if (flag_r[0]) frame_done <= 1'b1;
                                    st <= S_M0; // 完美传输，精准归位
                                end else st <= S_R;
                            end
                    
                    // 静默丢弃非图像包阶段：依靠提取出的 len_r 进行包尾对齐并重置
                    S_DROP_ALL: begin
                                idx_r <= idx_r + 1'b1;
                                if (idx_r == len_r-1) st <= S_M0; // 抛弃完毕，包尾精准归位
                            end
                    default: st <= S_M0;
                endcase
            end
        end
    end
endmodule
