// =============================================================
// cam_hxv2_tx.v
// Reference-style OV5640 RGB565 live UDP sender.
// Packet format: 20-byte "HXV2" header + one 640-pixel RGB565 row.
// =============================================================
`timescale 1ns/1ps

module cam_hxv2_tx #(
    parameter [15:0] FRAME_WIDTH       = 16'd640,
    parameter [15:0] FRAME_HEIGHT      = 16'd480,
    parameter [15:0] HXV2_HEADER_BYTES = 16'd20,
    parameter [15:0] PACKET_PIXELS     = 16'd640,
    parameter [15:0] PACKET_BYTES      = 16'd1300
)(
    input  wire        cam_pclk,
    input  wire        rst_n,
    input  wire        enable,
    input  wire        cmos_frame_vsync,
    input  wire        cmos_frame_href,
    input  wire        cmos_frame_valid,
    input  wire [15:0] cmos_frame_data,

    input  wire        clk,
    input  wire        udp_tx_ready,
    input  wire        app_tx_ack,
    output reg  [7:0]  app_tx_data,
    output reg         app_tx_data_valid,
    output reg  [15:0] udp_data_length,
    output reg         app_tx_request,
    output wire        busy,
    output wire [11:0] fifo_rused,
    output reg  [3:0]  dbg_state_seen
);
    localparam S_WAIT      = 3'd0;
    localparam S_PREFETCH  = 3'd1;
    localparam S_WAIT_WORD = 3'd2;
    localparam S_WAIT_ROW  = 3'd3;
    localparam S_REQ       = 3'd4;
    localparam S_SEND      = 3'd5;
    localparam S_GAP       = 3'd6;

    localparam [11:0] ROW_REMAIN_WORDS = PACKET_PIXELS[11:0] - 12'd1;

    reg [2:0]  st;
    reg [15:0] cnt;
    reg [15:0] frame_id;
    reg [15:0] row_id;
    reg        current_frame_tag;
    reg        frame_tag_valid;
    reg        fifo_ren;
    reg        fifo_rflush;
    reg        vs_d;
    reg        href_d;
    reg        frame_tag_cam;
    reg [9:0]  cam_x_cnt;
    reg [17:0] pixel_word;
    reg [10:0] align_drop_cnt;

    wire       rempty;
    wire       fifo_wfull;
    wire [11:0] fifo_wused;
    wire [17:0] fifo_rdata;
    wire        pixel_frame_tag  = pixel_word[17];
    wire        pixel_line_start = pixel_word[16];
    wire [15:0] rgb565_data      = pixel_word[15:0];
    wire        line_start_cam   = cmos_frame_valid & (cam_x_cnt == 10'd0);
    wire        frame_start_cam  = cmos_frame_vsync & ~vs_d;
    wire        fifo_wen         = enable & cmos_frame_valid & cmos_frame_href &
                                    (cam_x_cnt < FRAME_WIDTH[9:0]) & ~fifo_wfull;

    assign busy = (st != S_WAIT);

    dpram_64x64 #(
        .DW(18),
        .AW(11)
    ) u_cam_live_fifo (
        .wclk    (cam_pclk),
        .wrst_n  (rst_n),
        .wflush  (!enable),
        .wen     (fifo_wen),
        .wdata   ({frame_tag_cam, line_start_cam, cmos_frame_data}),
        .wfull   (fifo_wfull),
        .wused   (fifo_wused),
        .rclk    (clk),
        .rrst_n  (rst_n),
        .rflush  (fifo_rflush | !enable),
        .ren     (fifo_ren),
        .rdata   (fifo_rdata),
        .rempty  (rempty),
        .rused   (fifo_rused)
    );

    always @(posedge cam_pclk or negedge rst_n) begin
        if (!rst_n) begin
            vs_d          <= 1'b0;
            href_d        <= 1'b0;
            frame_tag_cam <= 1'b0;
            cam_x_cnt     <= 10'd0;
        end else begin
            vs_d   <= cmos_frame_vsync;
            href_d <= cmos_frame_href;
            if (!enable) begin
                frame_tag_cam <= 1'b0;
                cam_x_cnt     <= 10'd0;
            end else begin
                if (frame_start_cam) begin
                    frame_tag_cam <= ~frame_tag_cam;
                    cam_x_cnt     <= 10'd0;
                end else if (!cmos_frame_href) begin
                    cam_x_cnt <= 10'd0;
                end else if (cmos_frame_valid) begin
                    if (cam_x_cnt < FRAME_WIDTH[9:0])
                        cam_x_cnt <= cam_x_cnt + 10'd1;
                end
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st                <= S_WAIT;
            cnt               <= 16'd0;
            frame_id          <= 16'd0;
            row_id            <= 16'd0;
            current_frame_tag <= 1'b0;
            frame_tag_valid   <= 1'b0;
            fifo_ren          <= 1'b0;
            fifo_rflush       <= 1'b0;
            app_tx_request    <= 1'b0;
            app_tx_data_valid <= 1'b0;
            app_tx_data       <= 8'd0;
            udp_data_length   <= PACKET_BYTES;
            pixel_word        <= 18'd0;
            align_drop_cnt    <= 11'd0;
            dbg_state_seen    <= 4'b0000;
        end else begin
            fifo_ren          <= 1'b0;
            fifo_rflush       <= 1'b0;
            app_tx_data_valid <= 1'b0;

            if (!enable) begin
                st                <= S_WAIT;
                cnt               <= 16'd0;
                row_id            <= 16'd0;
                frame_tag_valid   <= 1'b0;
                app_tx_request    <= 1'b0;
                fifo_rflush       <= 1'b1;
                align_drop_cnt    <= 11'd0;
                dbg_state_seen    <= 4'b0000;
            end else begin
                case (st)
                    S_WAIT: begin
                        cnt             <= 16'd0;
                        app_tx_request  <= 1'b0;
                        udp_data_length <= PACKET_BYTES;
                        if (fifo_rused >= PACKET_PIXELS[11:0]) begin
                            dbg_state_seen[0] <= 1'b1;
                            st <= S_PREFETCH;
                        end
                    end

                    S_PREFETCH: begin
                        if (!rempty) begin
                            fifo_ren <= 1'b1;
                            st       <= S_WAIT_WORD;
                        end else begin
                            st <= S_WAIT;
                        end
                    end

                    S_WAIT_WORD: begin
                        pixel_word <= fifo_rdata;
                        st         <= S_WAIT_ROW;
                    end

                    S_WAIT_ROW: begin
                        if (!pixel_line_start && (align_drop_cnt < PACKET_PIXELS[10:0]) && !rempty) begin
                            fifo_ren       <= 1'b1;
                            align_drop_cnt <= align_drop_cnt + 1'b1;
                            st             <= S_WAIT_WORD;
                        end else if (fifo_rused >= ROW_REMAIN_WORDS) begin
                            align_drop_cnt <= 11'd0;
                            if (!frame_tag_valid) begin
                                current_frame_tag <= pixel_frame_tag;
                                frame_tag_valid   <= 1'b1;
                                row_id            <= 16'd0;
                            end else if (pixel_frame_tag != current_frame_tag) begin
                                current_frame_tag <= pixel_frame_tag;
                                frame_id          <= frame_id + 1'b1;
                                row_id            <= 16'd0;
                            end
                            app_tx_request     <= 1'b0;
                            dbg_state_seen[1] <= 1'b1;
                            st                 <= S_REQ;
                        end
                    end

                    S_REQ: begin
                        if (!app_tx_request) begin
                            if (udp_tx_ready) begin
                                dbg_state_seen[2] <= 1'b1;
                                app_tx_request    <= 1'b1;
                            end
                        end else if (app_tx_ack) begin
                            app_tx_request     <= 1'b0;
                            app_tx_data_valid  <= 1'b1;
                            app_tx_data        <= 8'h48;
                            cnt                <= 16'd1;
                            dbg_state_seen[3]  <= 1'b1;
                            st                 <= S_SEND;
                        end
                    end

                    S_SEND: begin
                        app_tx_data_valid <= 1'b1;
                        cnt <= cnt + 1'b1;

                        case (cnt)
                            16'd0:  app_tx_data <= 8'h48;
                            16'd1:  app_tx_data <= 8'h58;
                            16'd2:  app_tx_data <= 8'h56;
                            16'd3:  app_tx_data <= 8'h32;
                            16'd4:  app_tx_data <= frame_id[15:8];
                            16'd5:  app_tx_data <= frame_id[7:0];
                            16'd6:  app_tx_data <= row_id[15:8];
                            16'd7:  app_tx_data <= row_id[7:0];
                            16'd8:  app_tx_data <= FRAME_WIDTH[15:8];
                            16'd9:  app_tx_data <= FRAME_WIDTH[7:0];
                            16'd10: app_tx_data <= FRAME_HEIGHT[15:8];
                            16'd11: app_tx_data <= FRAME_HEIGHT[7:0];
                            16'd12: app_tx_data <= 8'd1;
                            16'd13: app_tx_data <= 8'd0;
                            16'd14: app_tx_data <= 8'd0;
                            16'd15: app_tx_data <= 8'd0;
                            16'd16: app_tx_data <= FRAME_WIDTH[15:8];
                            16'd17: app_tx_data <= FRAME_WIDTH[7:0];
                            16'd18: app_tx_data <= 8'd5;
                            16'd19: app_tx_data <= 8'd0;
                            default: app_tx_data <= cnt[0] ? rgb565_data[7:0] : rgb565_data[15:8];
                        endcase

                        if ((cnt >= HXV2_HEADER_BYTES) &&
                            (cnt < PACKET_BYTES - 16'd2) && !cnt[0]) begin
                            fifo_ren <= 1'b1;
                        end

                        if ((cnt >= HXV2_HEADER_BYTES + 16'd1) &&
                            (cnt < PACKET_BYTES - 16'd1) && cnt[0]) begin
                            pixel_word <= fifo_rdata;
                        end

                        if (cnt == PACKET_BYTES - 1'b1) begin
                            cnt <= 16'd0;
                            if (row_id == FRAME_HEIGHT - 1'b1)
                                row_id <= 16'd0;
                            else
                                row_id <= row_id + 1'b1;
                            st <= S_GAP;
                        end
                    end

                    S_GAP: begin
                        st <= S_WAIT;
                    end

                    default: st <= S_WAIT;
                endcase
            end
        end
    end
endmodule
