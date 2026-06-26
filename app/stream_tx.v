// =============================================================
// stream_tx.v
// 閫氱敤 RGB565 娴佸紡 UDP 鍥炰紶鍖呭彂閫佸櫒銆?// 鍖呮牸寮?
//   [A5 5A CMD seqH seqL npktH npktL lenH lenL] + PKT_PAY bytes
// FIFO 璇诲欢杩?1 鎷? ren 褰撴媿寮瑰嚭, rdata 涓嬩竴鎷嶆湁鏁堛�?// =============================================================
`timescale 1ns/1ps
`include "pkt_fmt.vh"

module stream_tx #(
    parameter [7:0]  CMD_DATA = `CMD_CAM_FRAME,
    parameter [15:0] PKT_PAY  = 16'd960,
    parameter [15:0] NPKT     = 16'd40,
    parameter [11:0] START_TH = 12'd480,
    parameter [15:0] GAP_MAX  = 16'd8000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire        abort,
    output wire        fifo_ren,
    input  wire [15:0] fifo_rdata,
    input  wire [11:0] fifo_rused,
    input  wire        udp_tx_ready,
    input  wire        app_tx_ack,
    output reg  [7:0]  app_tx_data,
    output reg         app_tx_data_valid,
    output reg  [15:0] udp_data_length,
    output reg         app_tx_request,
    output wire        busy
);
    localparam [15:0] HDR_LEN  = 16'd9;
    localparam [15:0] TOT_LEN  = HDR_LEN + PKT_PAY;
    localparam [15:0] REN_LAST = HDR_LEN + PKT_PAY - 16'd3;

    localparam S_IDLE=3'd0, S_WAITDATA=3'd1, S_REQ=3'd2,
               S_WAIT_ACK=3'd3, S_SEND=3'd4, S_GAP=3'd5;

    reg [2:0]  st;
    reg [15:0] cnt;
    reg [15:0] gap_cnt;
    reg [15:0] seq;
    reg [7:0]  pix_lo;

    assign busy = (st != S_IDLE);

    // 在 header 最后一字节提前弹出首像素；之后每个低字节拍提前弹出下一像素。
    assign fifo_ren = (st==S_SEND) && (cnt>=HDR_LEN-16'd1) && (cnt<=REN_LAST) && (cnt[0]==1'b0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st                <= S_IDLE;
            cnt               <= 16'd0;
            gap_cnt           <= 16'd0;
            seq               <= 16'd0;
            pix_lo            <= 8'd0;
            app_tx_request    <= 1'b0;
            app_tx_data_valid <= 1'b0;
            app_tx_data       <= 8'h00;
            udp_data_length   <= TOT_LEN;
        end else begin
            app_tx_data_valid <= 1'b0;
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
                            st              <= S_WAITDATA;
                        end
                    end
                    S_WAITDATA: begin
                        if (fifo_rused >= START_TH) begin
                            cnt <= 16'd0;
                            st  <= S_REQ;
                        end
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
                            16'd1: app_tx_data <= `MAGIC1;
                            16'd2: app_tx_data <= CMD_DATA;
                            16'd3: app_tx_data <= seq[15:8];
                            16'd4: app_tx_data <= seq[7:0];
                            16'd5: app_tx_data <= NPKT[15:8];
                            16'd6: app_tx_data <= NPKT[7:0];
                            16'd7: app_tx_data <= PKT_PAY[15:8];
                            16'd8: app_tx_data <= PKT_PAY[7:0];
                            default: app_tx_data <= cnt[0] ? fifo_rdata[15:8] : pix_lo;
                        endcase
                        if (cnt[0]) pix_lo <= fifo_rdata[7:0];
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
                        if (gap_cnt == GAP_MAX) st <= S_WAITDATA;
                        else                    gap_cnt <= gap_cnt + 16'd1;
                    end
                    default: st <= S_IDLE;
                endcase
            end
        end
    end
endmodule
