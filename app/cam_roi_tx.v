// =============================================================
// cam_roi_tx.v
// Standalone FPGA ROI metadata UDP payload sender.
// Packet length is fixed at 24 bytes and is intentionally separate
// from HXV2 video row packets so the live-video path remains stable.
// =============================================================
`timescale 1ns/1ps
`include "pkt_fmt.vh"

module cam_roi_tx #(
    parameter [7:0] GRID_W = 8'd80,
    parameter [7:0] GRID_H = 8'd60
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        roi_event_tog,
    input  wire [6:0]  roi_xmin,
    input  wire [6:0]  roi_xmax,
    input  wire [6:0]  roi_ymin,
    input  wire [6:0]  roi_ymax,
    input  wire [12:0] roi_area,
    input  wire        roi_valid,

    input  wire        udp_tx_ready,
    input  wire        app_tx_ack,
    output reg  [7:0]  app_tx_data,
    output reg         app_tx_data_valid,
    output reg  [15:0] udp_data_length,
    output reg         app_tx_request,
    output wire        busy
);
    localparam [15:0] PKT_LEN = 16'd24;
    localparam S_IDLE     = 2'd0;
    localparam S_REQ      = 2'd1;
    localparam S_WAIT_ACK = 2'd2;
    localparam S_SEND     = 2'd3;

    reg [1:0]  st;
    reg [15:0] cnt;
    reg        roi_event_d;
    reg [15:0] frame_id;

    reg [6:0]  lxmin, lxmax, lymin, lymax;
    reg [12:0] larea;
    reg        lvalid;
    reg [7:0]  lscore;

    wire roi_event = roi_event_tog ^ roi_event_d;
    wire [7:0] area_score = (roi_area[12:2] > 8'd255) ? 8'd255 : roi_area[9:2];
    wire [7:0] flags = {6'd0, 1'b1, lvalid};

    wire [7:0] checksum =
        `MAGIC0 ^ `MAGIC1 ^ `CMD_CAM_ROI ^ 8'h01 ^
        frame_id[15:8] ^ frame_id[7:0] ^ flags ^ {7'd0, lvalid} ^
        GRID_W ^ GRID_H ^ {1'b0, lxmin} ^ {1'b0, lymin} ^
        {1'b0, lxmax} ^ {1'b0, lymax} ^ {3'd0, larea[12:8]} ^
        larea[7:0] ^ lscore;

    assign busy = (st != S_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st                <= S_IDLE;
            cnt               <= 16'd0;
            roi_event_d       <= 1'b0;
            frame_id          <= 16'd0;
            lxmin             <= 7'd0;
            lxmax             <= 7'd0;
            lymin             <= 7'd0;
            lymax             <= 7'd0;
            larea             <= 13'd0;
            lvalid            <= 1'b0;
            lscore            <= 8'd0;
            app_tx_data       <= 8'd0;
            app_tx_data_valid <= 1'b0;
            udp_data_length   <= PKT_LEN;
            app_tx_request    <= 1'b0;
        end else begin
            app_tx_data_valid <= 1'b0;
            udp_data_length   <= PKT_LEN;

            case (st)
                S_IDLE: begin
                    app_tx_request <= 1'b0;
                    if (roi_event) begin
                        roi_event_d <= roi_event_tog;
                        frame_id    <= frame_id + 16'd1;
                        lxmin       <= roi_xmin;
                        lxmax       <= roi_xmax;
                        lymin       <= roi_ymin;
                        lymax       <= roi_ymax;
                        larea       <= roi_area;
                        lvalid      <= roi_valid;
                        lscore      <= area_score;
                        cnt         <= 16'd0;
                        st          <= S_REQ;
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
                        16'd1:  app_tx_data <= `MAGIC1;
                        16'd2:  app_tx_data <= `CMD_CAM_ROI;
                        16'd3:  app_tx_data <= 8'h01;
                        16'd4:  app_tx_data <= frame_id[15:8];
                        16'd5:  app_tx_data <= frame_id[7:0];
                        16'd6:  app_tx_data <= flags;
                        16'd7:  app_tx_data <= {7'd0, lvalid};
                        16'd8:  app_tx_data <= GRID_W;
                        16'd9:  app_tx_data <= GRID_H;
                        16'd10: app_tx_data <= {1'b0, lxmin};
                        16'd11: app_tx_data <= {1'b0, lymin};
                        16'd12: app_tx_data <= {1'b0, lxmax};
                        16'd13: app_tx_data <= {1'b0, lymax};
                        16'd14: app_tx_data <= {3'd0, larea[12:8]};
                        16'd15: app_tx_data <= larea[7:0];
                        16'd16: app_tx_data <= lscore;
                        16'd17: app_tx_data <= 8'd0;
                        16'd18: app_tx_data <= 8'd0;
                        16'd19: app_tx_data <= 8'd0;
                        16'd20: app_tx_data <= 8'd0;
                        16'd21: app_tx_data <= 8'd0;
                        16'd22: app_tx_data <= checksum;
                        16'd23: app_tx_data <= 8'h0d;
                        default: app_tx_data <= 8'd0;
                    endcase
                    if (cnt == PKT_LEN - 16'd1) begin
                        cnt <= 16'd0;
                        st  <= S_IDLE;
                    end else begin
                        cnt <= cnt + 16'd1;
                    end
                end

                default: st <= S_IDLE;
            endcase
        end
    end
endmodule
