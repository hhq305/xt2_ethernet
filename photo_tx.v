// =============================================================
// photo_tx.v
// 选题二 扩展⑥ : 全分辨率 RGB565 照片流式回传 (FPGA -> PC)
//
// start 脉冲后, 从异步 FIFO 取数, 分成 NPKT 个 UDP 包, 每包:
//   [A5 5A 0x51 seqH seqL npktH npktL lenH lenL] + PKT_PAY 字节 payload
//   每像素 16bit RGB565, 高字节在前; PKT_PAY/2 个像素/包
// 每包开始前等 FIFO 可读量 >= START_TH (=512 像素), 保证一包内连续无气泡。
// FIFO 读延迟 1 拍: ren 当拍弹出, rdata 下一拍有效。
// 运行于 udp_clk 域, 与 temac request/ack/valid 握手。
// =============================================================
`timescale 1ns/1ps
`include "pkt_fmt.vh"

module photo_tx #(
    parameter [15:0] PKT_PAY  = 16'd1024,  // 每包 payload 字节数 (=512 像素)
    parameter [15:0] NPKT     = 16'd600,   // 包个数 (600*512 = 307200 = 640x480)
    parameter [11:0] START_TH = 12'd512    // 起包前 FIFO 至少可读这么多像素
)(
    input  wire        clk,                 // udp_clk
    input  wire        rst_n,
    input  wire        start,               // 已同步到本域的单脉冲, 触发一次整图回传
    // 异步 FIFO 读端口
    output wire        fifo_ren,
    input  wire [15:0] fifo_rdata,
    input  wire [11:0] fifo_rused,
    // temac 应用层发送接口
    input  wire        udp_tx_ready,
    input  wire        app_tx_ack,
    output reg  [7:0]  app_tx_data,
    output reg         app_tx_data_valid,
    output reg  [15:0] udp_data_length,
    output reg         app_tx_request,
    output wire        busy
);
    localparam [15:0] HDR_LEN = 16'd9;
    localparam [15:0] TOT_LEN = HDR_LEN + PKT_PAY;   // 9 + 1024 = 1033

    localparam S_IDLE=3'd0, S_WAITDATA=3'd1, S_REQ=3'd2,
               S_WAIT_ACK=3'd3, S_SEND=3'd4, S_GAP=3'd5;
    localparam [15:0] GAP_MAX = 16'd2000;   // 包间小间隔, 等协议栈发完上包
    reg [2:0]  st;
    reg [15:0] cnt;        // 当前包内字节计数
    reg [15:0] gap_cnt;
    reg [15:0] seq;        // 当前包序号 0..NPKT-1
    reg [7:0]  pix_lo;     // 暂存当前像素低字节

    assign busy = (st != S_IDLE);

    // payload 取数: cnt 偶(8..1030) 弹出一个像素,
    //   供 cnt 奇(9..1031) 输高字节 + 次拍 cnt 偶输低字节
    assign fifo_ren = (st==S_SEND) && (cnt>=16'd8) && (cnt<=16'd1030) && (cnt[0]==1'b0);

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
                    // 等 FIFO 攒够一包像素, 保证发送中途不下溢
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
                        16'd2: app_tx_data <= `CMD_PHOTO_DATA;
                        16'd3: app_tx_data <= seq[15:8];
                        16'd4: app_tx_data <= seq[7:0];
                        16'd5: app_tx_data <= NPKT[15:8];
                        16'd6: app_tx_data <= NPKT[7:0];
                        16'd7: app_tx_data <= PKT_PAY[15:8];
                        16'd8: app_tx_data <= PKT_PAY[7:0];
                        // cnt>=9: payload. cnt 奇->高字节(fifo_rdata 当拍有效), cnt 偶->低字节
                        default: app_tx_data <= cnt[0] ? fifo_rdata[15:8] : pix_lo;
                    endcase
                    // 高字节拍(奇)同时锁存低字节, 供下一(偶)拍输出
                    if (cnt[0]) pix_lo <= fifo_rdata[7:0];
                    cnt <= cnt + 16'd1;
                    if (cnt == TOT_LEN - 16'd1) begin
                        if (seq == NPKT - 16'd1) begin
                            st <= S_IDLE;             // 全部包发完
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
endmodule
