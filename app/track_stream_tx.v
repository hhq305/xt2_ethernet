// =============================================================
// track_stream_tx.v
// 视频 + 运动检测结�?流式 UDP 回传发送器 (基于已验证的 stream_tx)�?// 包格�?(17 字节包头, 每包都带检测元数据, 抗丢�?:
//   [0]  A5
//   [1]  5A
//   [2]  CMD            (= CMD_CAM_FRAME 0x31)
//   [3:4]  seq          当前包序�?//   [5:6]  npkt         总包�?//   [7:8]  plen         本包 payload 字节�?//   [9]  m_xmin         运动包围�?(0..OUT_W-1)
//   [10] m_xmax
//   [11] m_ymin
//   [12] m_ymax
//   [13] areaH          运动像素数高字节
//   [14] areaL
//   [15] valid          1=检测到有效运动目标
//   [16] reserved (0)
//   [17..] payload      RGB565 视频像素 (高字节在�?
//
// 视频源是 80x60 �?BRAM (始终就绪)。读端口�?rclear/ren, rdata 延迟 1 拍�?// rclear 在每帧发送开始拉�?1 �? 把读地址复位�?0�?// =============================================================
`timescale 1ns/1ps
`include "pkt_fmt.vh"

module track_stream_tx #(
    parameter [7:0]  CMD_DATA = `CMD_CAM_FRAME,
    parameter [15:0] PKT_PAY  = 16'd960,
    parameter [15:0] NPKT     = 16'd10,
    parameter [15:0] GAP_MAX  = 16'd8000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire        abort,
    // ��Ƶ BRAM ���ӿ�
    output reg         rclear,
    output wire        ren,
    input  wire [15:0] rdata,
    // ���Ԫ����
    input  wire [7:0]  meta_xmin,
    input  wire [7:0]  meta_xmax,
    input  wire [7:0]  meta_ymin,
    input  wire [7:0]  meta_ymax,
    input  wire [15:0] meta_area,
    input  wire        meta_valid,
    // UDP ���ͽӿ�
    input  wire        udp_tx_ready,
    input  wire        app_tx_ack,
    output reg  [7:0]  app_tx_data,
    output reg         app_tx_data_valid,
    output reg  [15:0] udp_data_length,
    output reg         app_tx_request,
    output wire        busy
);
    localparam [15:0] HDR_LEN  = 16'd17;
    localparam [15:0] TOT_LEN  = HDR_LEN + PKT_PAY;
    localparam [15:0] REN_LAST = HDR_LEN + PKT_PAY - 16'd3;

    localparam S_IDLE=3'd0, S_CLR=3'd1, S_REQ=3'd2,
               S_WAIT_ACK=3'd3, S_SEND=3'd4, S_GAP=3'd5;

    reg [2:0]  st;
    reg [15:0] cnt;
    reg [15:0] gap_cnt;
    reg [15:0] seq;
    reg [7:0]  pix_lo;

    // 帧内锁存的检测元数据 (start 时刻采样, 整帧发送期间稳�?
    reg [7:0]  lx0, lx1, ly0, ly1;
    reg [15:0] larea;
    reg        lvalid;

    assign busy = (st != S_IDLE);

    // header 最后一字节(cnt=HDR_LEN-1)提前弹出首像�? 之后每偶数拍预取下一像素
    assign ren = (st==S_SEND) && (cnt>=HDR_LEN-16'd1) && (cnt<=REN_LAST) && (cnt[0]==1'b0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st                <= S_IDLE;
            cnt               <= 16'd0;
            gap_cnt           <= 16'd0;
            seq               <= 16'd0;
            pix_lo            <= 8'd0;
            rclear            <= 1'b0;
            app_tx_request    <= 1'b0;
            app_tx_data_valid <= 1'b0;
            app_tx_data       <= 8'h00;
            udp_data_length   <= TOT_LEN;
            lx0<=0; lx1<=0; ly0<=0; ly1<=0; larea<=0; lvalid<=0;
        end else begin
            app_tx_data_valid <= 1'b0;
            rclear            <= 1'b0;
            if (abort) begin
                st             <= S_IDLE;
                app_tx_request <= 1'b0;
                cnt            <= 16'd0;
                gap_cnt        <= 16'd0;
            end else begin
                case (st)
                    S_IDLE: begin
                        app_tx_request <= 1'b0;
                        if (start) begin
                            seq             <= 16'd0;
                            cnt             <= 16'd0;
                            udp_data_length <= TOT_LEN;
                            // 锁存检测元数据 (整帧稳定)
                            lx0   <= meta_xmin; lx1 <= meta_xmax;
                            ly0   <= meta_ymin; ly1 <= meta_ymax;
                            larea <= meta_area; lvalid <= meta_valid;
                            rclear<= 1'b1;          // 复位视频读地址�?0
                            st    <= S_CLR;
                        end
                    end
                    S_CLR: begin
                        st <= S_REQ;
                    end
                    S_REQ: begin
                        if (udp_tx_ready) begin
                            app_tx_request <= 1'b1;
                            st             <= S_WAIT_ACK;
                        end
                    end
                    S_WAIT_ACK: begin
                        if (app_tx_ack) begin
                            app_tx_request    <= 1'b0;
                            app_tx_data_valid <= 1'b1;
                            app_tx_data       <= `MAGIC0;
                            cnt               <= 16'd1;
                            st                <= S_SEND;
                        end
                    end
                    S_SEND: begin
                        app_tx_data_valid <= 1'b1;
                        case (cnt)
                            16'd1:  app_tx_data <= `MAGIC1;
                            16'd2:  app_tx_data <= CMD_DATA;
                            16'd3:  app_tx_data <= seq[15:8];
                            16'd4:  app_tx_data <= seq[7:0];
                            16'd5:  app_tx_data <= NPKT[15:8];
                            16'd6:  app_tx_data <= NPKT[7:0];
                            16'd7:  app_tx_data <= PKT_PAY[15:8];
                            16'd8:  app_tx_data <= PKT_PAY[7:0];
                            16'd9:  app_tx_data <= lx0;
                            16'd10: app_tx_data <= lx1;
                            16'd11: app_tx_data <= ly0;
                            16'd12: app_tx_data <= ly1;
                            16'd13: app_tx_data <= larea[15:8];
                            16'd14: app_tx_data <= larea[7:0];
                            16'd15: app_tx_data <= {7'd0, lvalid};
                            16'd16: app_tx_data <= 8'd0;
                            default: app_tx_data <= cnt[0] ? rdata[15:8] : pix_lo;
                        endcase
                        if (cnt[0]) pix_lo <= rdata[7:0];
                        cnt <= cnt + 16'd1;
                        if (cnt == TOT_LEN - 16'd1) begin
                            if (seq == NPKT - 16'd1) begin
                                st <= S_IDLE;
                            end else begin
                                seq     <= seq + 16'd1;
                                cnt     <= 16'd0;
                                gap_cnt <= 16'd0;
                                st      <= S_GAP;
                            end
                        end
                    end
                    S_GAP: begin
                        if (gap_cnt == GAP_MAX) st <= S_REQ;
                        else                    gap_cnt <= gap_cnt + 16'd1;
                    end
                    default: st <= S_IDLE;
                endcase
            end
        end
    end
endmodule
