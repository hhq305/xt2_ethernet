// =============================================================
// img_tx_rom.v  (Phase-2 简化版)
// 选题�?扩展�?: FPGA -> PC 通过 UDP 单包回传一�?"图像" 数据�?// 数据�? 内部生成的测试图�?(8bit, addr 的低 8 �?。一次回�?PKT_LEN 字节,
// �?5 字节�?[MAGIC0 MAGIC1 CMD_IMG_DATA LEN_H LEN_L], 然后 PAY 字节正文�?// 仅作�?"FPGA �?PC 主动发送图�? 的数据通路演示, 不依赖任何外�?ROM/BRAM�?// =============================================================
`timescale 1ns/1ps
`include "pkt_fmt.vh"

module img_tx_rom #(
    parameter PAY_LEN = 16'd256             // payload 字节�?= 16x16 像素
)(
    input  wire        clk,                  // = app_tx_clk = udp_clk = udp_rx_clk
    input  wire        rst_n,
    input  wire        start,                // cmd_decode �?img_req_pulse_o
    // 接收 addr_crt 的写信号 (用于维护图像镜像)
    input  wire        wr_en,
    input  wire [7:0]  wr_addr,              // {y[3:0], x[3:0]}
    input  wire [5:0]  wr_data,              // 6-bit RGB222
    // UDP ���ͽӿ�
    input  wire        udp_tx_ready,
    input  wire        app_tx_ack,
    output reg  [7:0]  app_tx_data,
    output reg         app_tx_data_valid,
    output reg  [15:0] udp_data_length,
    output reg         app_tx_request
);
    localparam HDR_LEN = 16'd5;
    localparam TOT_LEN = HDR_LEN + PAY_LEN;

    localparam S_IDLE=3'd0, S_REQ=3'd1, S_WAIT_ACK=3'd2, S_SEND=3'd3;
    reg [2:0]  st;
    reg [15:0] cnt;        // 已发送字节数

    // 256 entry x 6 bit ͼ���� RAM��Ĭ������ 16x16 ��ɫ����ͼ��
    reg [5:0] mem [0:255];
    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            mem[i] = {i[3:2], i[7:6], i[1:0]};
        end
    end
    always @(posedge clk) if (wr_en) mem[wr_addr] <= wr_data;

    // payload 字节 i 对应像素 i, 6 bit RGB 放低�? �?2 位零
    wire [7:0] pay_idx  = cnt - HDR_LEN;       // 0..PAY_LEN-1
    wire [7:0] pix_byte = {2'b00, mem[pay_idx]};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st                <= S_IDLE;
            cnt               <= 16'd0;
            app_tx_request    <= 1'b0;
            app_tx_data_valid <= 1'b0;
            app_tx_data       <= 8'h00;
            udp_data_length   <= TOT_LEN[15:0];
        end else begin
            app_tx_data_valid <= 1'b0;
            case (st)
                S_IDLE: begin
                    app_tx_request <= 1'b0;
                    if (start) begin
                        cnt             <= 16'd0;
                        udp_data_length <= TOT_LEN[15:0];
                        st              <= S_REQ;
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
                        16'd2: app_tx_data <= `CMD_IMG_DATA;
                        16'd3: app_tx_data <= PAY_LEN[15:8];
                        16'd4: app_tx_data <= PAY_LEN[7:0];
                        default: app_tx_data <= pix_byte;
                    endcase
                    cnt <= cnt + 16'd1;
                    if (cnt == TOT_LEN-1) begin
                        app_tx_data_valid <= 1'b1;  // 最后一个字节仍 valid
                        st                <= S_IDLE;
                    end
                end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule
