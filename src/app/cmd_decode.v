// =============================================================
// cmd_decode.v
// 基础要求 ① : 解析 PC 通过以太网下发的 UDP 命令, 控制 LED 与数码管.
// 实现方式: 滑动窗口找 (A5, 5A) 字节对, 完全不依赖 rx_length / 包边界.
//   一旦在字节流中检测到 last_byte==A5 && rx_data==5A, 后续 4 拍 valid 字节
//   依次是 CMD, LEN_HI(忽略), LEN_LO(忽略), payload[0].
//   对 LED/PROC_MODE/CAM_START 取 payload[0]; 对 SEG 取 payload[0..3]; 
//   对 IMG_REQ 在 LEN_LO 后立即触发 pulse.
// 这样设计对 valid 是否中断、rx_length 是否准确均不敏感.
// =============================================================
`timescale 1ns/1ps
`include "pkt_fmt.vh"

module cmd_decode (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,
    input  wire [15:0] rx_length,    // 不再使用, 仅为接口兼容
    output reg  [7:0]  led_o,
    output reg  [31:0] seg_bcd_o,
    output reg  [1:0]  proc_mode_o,
    output reg         img_req_pulse_o,
    output reg         cam_en_o,
    output reg         ack_pulse_o
);

    localparam ST_HUNT  = 4'd0,    // 滑窗找 A5 5A
               ST_CMD   = 4'd1,    // 这一拍读 CMD
               ST_LH    = 4'd2,    // 跳过 LEN_HI
               ST_LL    = 4'd3,    // 跳过 LEN_LO
               ST_PAY0  = 4'd4,    // payload[0]
               ST_PAY1  = 4'd5,    // payload[1] (SEG)
               ST_PAY2  = 4'd6,
               ST_PAY3  = 4'd7;

    reg [3:0] st;
    reg [7:0] last_byte;     // 上一拍 valid 字节
    reg [7:0] cmd_r;
    reg [7:0] buf0, buf1, buf2, buf3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st              <= ST_HUNT;
            last_byte       <= 8'h00;
            cmd_r           <= 8'h00;
            led_o           <= 8'h00;
            seg_bcd_o       <= 32'h0;
            proc_mode_o     <= 2'd0;
            cam_en_o        <= 1'b0;
            img_req_pulse_o <= 1'b0;
            ack_pulse_o     <= 1'b0;
            buf0 <= 8'h00; buf1 <= 8'h00; buf2 <= 8'h00; buf3 <= 8'h00;
        end else begin
            // 一拍脉冲, 默认拉低
            img_req_pulse_o <= 1'b0;
            ack_pulse_o     <= 1'b0;

            if (rx_valid) begin
                last_byte <= rx_data;

                // 关键: A5 5A 检测优先级最高, 在任何状态下都强制重启解析.
                // 这样即使前面被假前缀骗到 ST_PAY0, 真包出现时也能纠正.
                if (last_byte == `MAGIC0 && rx_data == `MAGIC1) begin
                    st <= ST_CMD;
                end else begin
                    case (st)
                        ST_HUNT: ;    // 等 A5 5A
                        ST_CMD: begin
                            cmd_r <= rx_data;
                            st    <= ST_LH;
                        end
                        ST_LH: st <= ST_LL;
                        ST_LL: begin
                            if (cmd_r == `CMD_IMG_REQ) begin
                                img_req_pulse_o <= 1'b1;
                                ack_pulse_o     <= 1'b1;
                                st              <= ST_HUNT;
                            end else begin
                                st <= ST_PAY0;
                            end
                        end
                        ST_PAY0: begin
                            case (cmd_r)
                                `CMD_LED_SET   : begin led_o <= rx_data; ack_pulse_o <= 1'b1; st <= ST_HUNT; end
                                `CMD_PROC_MODE : begin proc_mode_o <= rx_data[1:0]; ack_pulse_o <= 1'b1; st <= ST_HUNT; end
                                `CMD_CAM_START : begin cam_en_o <= rx_data[0]; ack_pulse_o <= 1'b1; st <= ST_HUNT; end
                                `CMD_SEG_SET   : begin buf0 <= rx_data; st <= ST_PAY1; end
                                default        : begin st <= ST_HUNT; end
                            endcase
                        end
                        ST_PAY1: begin buf1 <= rx_data; st <= ST_PAY2; end
                        ST_PAY2: begin buf2 <= rx_data; st <= ST_PAY3; end
                        ST_PAY3: begin
                            buf3        <= rx_data;
                            seg_bcd_o   <= {buf0, buf1, buf2, rx_data};
                            ack_pulse_o <= 1'b1;
                            st          <= ST_HUNT;
                        end
                        default: st <= ST_HUNT;
                    endcase
                end
            end
        end
    end

endmodule
