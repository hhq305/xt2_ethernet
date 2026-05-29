// =============================================================
// photo_tx.v
// 选题二 扩展⑥ : 64x64 RGB222 照片多包回传 (FPGA -> PC)
//
// frame_ready 上升沿后自动发送 NPKT 个 UDP 包, 每包:
//   [A5 5A 0x51 seq NPKT LEN_H LEN_L] + PKT_PAY 字节 payload
//   payload[o] = BRAM[seq*PKT_PAY + o] 的 6bit RGB222 (高 2 位补 0)
// 与 temac 应用层 request/ack/valid 握手, 每包独立握手一次。
// 运行于 udp_clk 域。BRAM 读端口 1 拍延迟, raddr 组合给出。
// =============================================================
`timescale 1ns/1ps
`include "pkt_fmt.vh"

module photo_tx #(
    parameter [15:0] PKT_PAY = 16'd1024,   // 每包 payload 字节数
    parameter [7:0]  NPKT    = 8'd4         // 包个数 (4*1024 = 4096 = 64x64)
)(
    input  wire        clk,                 // udp_clk
    input  wire        rst_n,
    input  wire        frame_ready,         // 已同步到本域的单脉冲
    // BRAM 读端口
    output wire [11:0] bram_raddr,
    input  wire [5:0]  bram_rdata,
    // temac 应用层发送接口
    input  wire        udp_tx_ready,
    input  wire        app_tx_ack,
    output reg  [7:0]  app_tx_data,
    output reg         app_tx_data_valid,
    output reg  [15:0] udp_data_length,
    output reg         app_tx_request,
    output wire        busy
);
    localparam [15:0] HDR_LEN = 16'd7;
    localparam [15:0] TOT_LEN = HDR_LEN + PKT_PAY;   // 1031

    localparam S_IDLE=3'd0, S_REQ=3'd1, S_WAIT_ACK=3'd2, S_SEND=3'd3, S_GAP=3'd4;
    localparam [15:0] GAP_MAX = 16'd4000;   // 包间间隔, 等协议栈发完上一包并重新就绪
    reg [2:0]  st;
    reg [15:0] cnt;        // 当前包内字节计数
    reg [15:0] gap_cnt;    // 包间间隔计数
    reg [7:0]  seq;        // 当前包序号 0..NPKT-1

    assign busy = (st != S_IDLE);

    // BRAM 读地址 : base = seq*PKT_PAY (PKT_PAY=1024 -> 左移 10)
    wire [11:0] base = {seq[1:0], 10'd0};
    wire [11:0] pay_addr = (cnt >= 16'd6) ? (cnt[11:0] - 12'd6) : 12'd0;
    assign bram_raddr = base + pay_addr;

    wire [7:0] pix_byte = {2'b00, bram_rdata};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st                <= S_IDLE;
            cnt               <= 16'd0;
            gap_cnt           <= 16'd0;
            seq               <= 8'd0;
            app_tx_request    <= 1'b0;
            app_tx_data_valid <= 1'b0;
            app_tx_data       <= 8'h00;
            udp_data_length   <= TOT_LEN;
        end else begin
            app_tx_data_valid <= 1'b0;
            case (st)
                S_IDLE: begin
                    app_tx_request <= 1'b0;
                    if (frame_ready) begin
                        seq             <= 8'd0;
                        cnt             <= 16'd0;
                        udp_data_length <= TOT_LEN;
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
                        16'd2: app_tx_data <= `CMD_PHOTO_DATA;
                        16'd3: app_tx_data <= seq;
                        16'd4: app_tx_data <= NPKT;
                        16'd5: app_tx_data <= PKT_PAY[15:8];
                        16'd6: app_tx_data <= PKT_PAY[7:0];
                        default: app_tx_data <= pix_byte;   // cnt>=7 -> payload
                    endcase
                    cnt <= cnt + 16'd1;
                    if (cnt == TOT_LEN - 16'd1) begin
                        // 本包发送完毕
                        if (seq == NPKT - 8'd1) begin
                            st <= S_IDLE;       // 全部包发完
                        end else begin
                            seq     <= seq + 8'd1;
                            cnt     <= 16'd0;
                            gap_cnt <= 16'd0;
                            st      <= S_GAP;   // 先间隔, 再握手下一包
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
endmodule
