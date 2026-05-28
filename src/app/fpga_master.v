// =============================================================
// fpga_master.v
// 扩展要求 ① : 两块开发板互联, 由 FPGA 端代替 PC, 主动产生四类
// 基础命令并通过 UDP 发送到对端开发板。
// 通过板上拨码/按键 (mode_sel) 选择当前要发送的命令类型与节奏。
// =============================================================
`timescale 1ns/1ps
`include "pkt_fmt.vh"

module fpga_master #(
    parameter CLK_HZ = 50_000_000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [1:0]  mode_sel,        // 0:LED  1:SEG  2:PROC  3:IMG_REQ
    input  wire [7:0]  led_pat,         // 给对端的 LED 模式
    input  wire [15:0] seg_val,         // 给对端的数码管 BCD
    input  wire [1:0]  proc_mode,
    // temac 发送接口
    input  wire        udp_tx_ready,
    input  wire        app_tx_ack,
    output reg  [7:0]  app_tx_data,
    output reg         app_tx_data_valid,
    output reg  [15:0] udp_data_length,
    output reg         app_tx_request
);
    // 1Hz 周期触发一次发送
    reg [25:0] tick;
    reg        send_pulse;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin tick<=0; send_pulse<=0; end
        else begin
            send_pulse<=1'b0;
            if (tick==CLK_HZ-1) begin tick<=0; send_pulse<=1'b1; end
            else tick<=tick+1'b1;
        end
    end

    // 报文组装 (固定 8 字节: MAGIC0,MAGIC1,CMD,LEN_H,LEN_L, p0,p1,p2)
    localparam PKT_LEN = 8;
    reg [3:0]  bidx;
    reg [2:0]  st;
    localparam S_IDLE=0,S_REQ=1,S_SEND=2;
    reg [7:0] payload [0:2];
    reg [7:0] cmd_r;
    reg [15:0] plen_r;

    always @(*) begin
        case (mode_sel)
            2'd0: begin cmd_r=`CMD_LED_SET;    plen_r=16'd1; end
            2'd1: begin cmd_r=`CMD_SEG_SET;    plen_r=16'd4; end
            2'd2: begin cmd_r=`CMD_PROC_MODE;  plen_r=16'd1; end
            2'd3: begin cmd_r=`CMD_IMG_REQ;    plen_r=16'd0; end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st<=S_IDLE; bidx<=0;
            app_tx_data<=0; app_tx_data_valid<=0;
            udp_data_length<=PKT_LEN; app_tx_request<=0;
        end else begin
            app_tx_data_valid<=1'b0;
            case (st)
                S_IDLE: if (send_pulse) begin
                            udp_data_length <= 16'd5+plen_r;
                            payload[0]<=led_pat;
                            payload[1]<={4'h0,seg_val[15:12]};
                            payload[2]<=proc_mode;
                            st<=S_REQ;
                        end
                S_REQ : if (udp_tx_ready) begin
                            app_tx_request<=1'b1;
                            if (app_tx_ack) begin
                                app_tx_request<=1'b0; bidx<=0; st<=S_SEND;
                            end
                        end
                S_SEND: begin
                            app_tx_data_valid<=1'b1;
                            case (bidx)
                                4'd0: app_tx_data<=`MAGIC0;
                                4'd1: app_tx_data<=`MAGIC1;
                                4'd2: app_tx_data<=cmd_r;
                                4'd3: app_tx_data<=plen_r[15:8];
                                4'd4: app_tx_data<=plen_r[7:0];
                                4'd5: app_tx_data<=payload[0];
                                4'd6: app_tx_data<=payload[1];
                                4'd7: app_tx_data<=payload[2];
                                default: app_tx_data<=8'h00;
                            endcase
                            bidx<=bidx+1'b1;
                            if (bidx == 5+plen_r-1) st<=S_IDLE;
                        end
            endcase
        end
    end
endmodule
