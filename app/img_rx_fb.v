// =============================================================
// img_rx_fb.v
// Âü∫Á°ÄË¶ÅÊ±Ç ‚ë?: Êé•Êî∂ PC ÈÄöËøá UDP ‰∏ãÂèëÁöÑÂõæÂÉ? ÂÜôÂÖ•Â∏ßÁºìÂ≠ò„Ä?// Êä•ÊñáÊ†ºÂºè (CMD=0x10 IMG_FRAME)Ôº?//   [MAGIC0,MAGIC1,CMD,LEN_H,LEN_L]            // Êä•ÊñáÂ§?//   [FLAG,YH,YL,XH,XL, p0_R,p0_G,p0_B, p1_R,...] // payload
// Êú¨Ê®°ÂùóËß£Êû?payloadÔºåÊää RGB888 -> RGB444 12bit ÂÜôÂÖ• framebuf„Ä?// =============================================================
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
    // ÷°ª∫¥Ê–¥∂Àø⁄
    output reg         fb_we,
    output reg  [AW-1:0] fb_waddr,
    output reg  [11:0] fb_wdata,
    // ◊¥Ã¨
    output reg         frame_done
);
    localparam S_M0=0,S_M1=1,S_CMD=2,S_LH=3,S_LL=4,
               S_FLAG=5,S_YH=6,S_YL=7,S_XH=8,S_XL=9,
               S_R=10,S_G=11,S_B=12,S_DROP_ALL=13;

    reg [3:0]  st;
    reg [7:0]  cmd_r;
    reg [15:0] len_r, idx_r;
    reg [7:0]  flag_r;
    reg [7:0]  rch, gch;

    // RGB888 -> RGB444£¨∆•≈‰ 12-bit VGA_D°£
    wire [11:0] pix444 = {rch[7:4], gch[7:4], rx_data[7:4]};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_M0;
            cmd_r <= 8'd0;
            len_r <= 16'd0;
            idx_r <= 16'd0;
            flag_r <= 8'd0;
            rch <= 8'd0;
            gch <= 8'd0;
            fb_we <= 1'b0;
            fb_waddr <= {AW{1'b0}};
            fb_wdata <= 12'd0;
            frame_done <= 1'b0;
        end else begin
            fb_we      <= 1'b0;
            frame_done <= 1'b0;

            if (rx_valid) begin
                case (st)
                    S_M0: begin
                        st <= (rx_data == `MAGIC0) ? S_M1 : S_M0;
                    end

                    S_M1: begin
                        st <= (rx_data == `MAGIC1) ? S_CMD :
                              (rx_data == `MAGIC0) ? S_M1  : S_M0;
                    end

                    S_CMD: begin
                        cmd_r <= rx_data;
                        st    <= S_LH;
                    end

                    S_LH: begin
                        len_r[15:8] <= rx_data;
                        st <= S_LL;
                    end

                    S_LL: begin
                        len_r[7:0] <= rx_data;
                        idx_r <= 16'd0;
                        if (cmd_r == `CMD_IMG_FRAME && {len_r[15:8], rx_data} >= 16'd5)
                            st <= S_FLAG;
                        else if ({len_r[15:8], rx_data} == 16'd0)
                            st <= S_M0;
                        else
                            st <= S_DROP_ALL;
                    end

                    S_FLAG: begin
                        flag_r <= rx_data;
                        idx_r  <= idx_r + 1'b1;
                        st     <= S_YH;
                    end

                    S_YH: begin idx_r <= idx_r + 1'b1; st <= S_YL; end
                    S_YL: begin idx_r <= idx_r + 1'b1; st <= S_XH; end
                    S_XH: begin idx_r <= idx_r + 1'b1; st <= S_XL; end

                    S_XL: begin
                        idx_r <= idx_r + 1'b1;
                        if (len_r == 16'd5) begin
                            if (flag_r[0]) frame_done <= 1'b1;
                            st <= S_M0;
                        end else begin
                            st <= S_R;
                        end
                    end

                    S_R: begin
                        rch <= rx_data;
                        idx_r <= idx_r + 1'b1;
                        st <= S_G;
                    end

                    S_G: begin
                        gch <= rx_data;
                        idx_r <= idx_r + 1'b1;
                        st <= S_B;
                    end

                    S_B: begin
                        fb_we    <= 1'b1;
                        fb_waddr <= {AW{1'b0}};
                        fb_wdata <= pix444;
                        idx_r    <= idx_r + 1'b1;
                        if (idx_r == len_r - 1'b1) begin
                            if (flag_r[0]) frame_done <= 1'b1;
                            st <= S_M0;
                        end else begin
                            st <= S_R;
                        end
                    end

                    S_DROP_ALL: begin
                        idx_r <= idx_r + 1'b1;
                        if (idx_r == len_r - 1'b1)
                            st <= S_M0;
                    end

                    default: begin
                        st <= S_M0;
                    end
                endcase
            end
        end
    end
endmodule
