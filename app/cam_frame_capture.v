// =============================================================
// cam_frame_capture.v
// OV5640 RGB565 DVP capture for PC return.
//
// This module keeps the Wildfire STM32 chapter 48 DCMI idea: hardware
// VSYNC/HREF/PCLK sampling and a frame buffer used like a small DMA buffer.
// The buffer is explicitly implemented with EG_LOGIC_BRAM so the 80x60
// RGB565 frame does not consume MSlices as distributed registers.
//
// Camera side:
//   - capture_en lets the camera capture after OV5640 init/start;
//   - every usable VSYNC frame boundary starts a 320x240 -> 80x60 sampler;
//   - one completed frame is published and held until the UDP side consumes it.
//
// UDP side:
//   - read_start freezes the completed frame for one UDP transfer;
//   - fifo_ren/fifo_rdata/fifo_rused look like the old FIFO read port, so
//     track_fifo_tx can be reused without changing the UDP packet format.
//
// Only one frame buffer is kept.  While a frame is waiting or being sent, new
// camera frames are dropped instead of allocating a second 4800x16 bank.
// =============================================================
`timescale 1ns/1ps

module cam_frame_capture #(
    parameter [10:0] SRC_W      = 11'd320,
    parameter [10:0] SRC_H      = 11'd240,
    parameter [9:0]  OUT_W      = 10'd80,
    parameter [9:0]  OUT_H      = 10'd60,
    parameter [3:0]  DEC_X      = 4'd4,
    parameter [3:0]  DEC_Y      = 4'd4,
    parameter [15:0] TOTAL_PIX  = 16'd4800,
    parameter [13:0] FIFO_ROOM  = 14'd8000
)(
    input  wire        cam_pclk,
    input  wire        rst_n,
    input  wire        capture_en,

    input  wire        cmos_frame_vsync,
    input  wire        cmos_frame_href,
    input  wire        cmos_frame_valid,
    input  wire [15:0] cmos_frame_data,

    input  wire        rclk,
    input  wire        read_start,
    input  wire        read_abort,
    input  wire        fifo_ren,
    output wire [15:0] fifo_rdata,
    output wire [13:0] fifo_rused,
    output wire        fifo_rempty,
    output reg         frame_ready,

    output reg         fifo_wfull,
    output reg  [13:0] fifo_wused,
    output reg         fifo_wen,
    output reg  [15:0] fifo_wdata,
    output reg         fifo_wflush,
    output reg         busy,
    output reg         done_toggle,
    output reg         overflow_toggle,
    output reg         dbg_start_seen,
    output reg         dbg_vsync_seen,
    output reg         dbg_cap_seen,
    output reg         dbg_wen_seen,
    output reg         dbg_pix_80_seen,
    output reg         dbg_pix_240_seen,
    output reg         dbg_pix_800_seen,
    output reg         dbg_href_4_seen,
    output reg         dbg_href_16_seen
);
    localparam S_IDLE = 1'b0;
    localparam S_CAP  = 1'b1;
    localparam [13:0] FRAME_WORDS = TOTAL_PIX;

    reg st;

    // ------------------------------------------------------------------
    // UDP read-domain state.  rd_do/rd_addr are declared before the BRAM
    // instance because they directly drive the BRAM read port.
    // ------------------------------------------------------------------
    reg        pub_tog_meta;
    reg        pub_tog_sync;
    reg        pub_tog_d;
    reg        pub_valid_meta;
    reg        pub_valid_sync;

    reg        read_active;
    reg [13:0] rd_addr;
    reg [13:0] rd_left;

    reg        cap_en_r0;
    reg        cap_en_r1;
    reg        consume_toggle_udp;
    wire       capture_en_rclk = cap_en_r1;
    wire       publish_edge    = pub_tog_sync ^ pub_tog_d;
    wire       rd_do           = fifo_ren & read_active & (rd_left != 14'd0);

    assign fifo_rused  = read_active ? rd_left : (frame_ready ? FRAME_WORDS : 14'd0);
    assign fifo_rempty = (fifo_rused == 14'd0);

    // ------------------------------------------------------------------
    // Explicit frame BRAM: 8192 x 16, using only addresses 0..4799.
    // Port A writes sampled camera pixels in cam_pclk domain.
    // Port B is read by track_fifo_tx in rclk domain.  fifo_ren is asserted
    // one byte before track_fifo_tx needs the word, so the BRAM read latency
    // matches the old registered FIFO read behavior.
    // ------------------------------------------------------------------
    reg         ram_we;
    reg  [12:0] ram_waddr;
    reg  [15:0] ram_wdata;
    wire [12:0] ram_raddr = rd_addr[12:0];
    wire [15:0] ram_rdata;

    assign fifo_rdata = ram_rdata;

    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(16),
        .DATA_WIDTH_B(16),
        .ADDR_WIDTH_A(13),
        .ADDR_WIDTH_B(13),
        .DATA_DEPTH_A(8192),
        .DATA_DEPTH_B(8192),
        .MODE("PDPW"),
        .REGMODE_A("NOREG"),
        .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"),
        .WRITEMODE_B("READBEFOREWRITE"),
        .RESETMODE("SYNC"),
        .IMPLEMENT("9K"),
        .INIT_FILE("NONE"),
        .FILL_ALL("NONE")
    ) u_frame_bram (
        .dia   (ram_wdata),
        .dib   (16'd0),
        .addra (ram_waddr),
        .addrb (ram_raddr),
        .cea   (ram_we),
        .ceb   (rd_do),
        .ocea  (1'b0),
        .oceb  (1'b0),
        .clka  (cam_pclk),
        .clkb  (rclk),
        .wea   (ram_we),
        .web   (1'b0),
        .bea   (2'b00),
        .beb   (2'b00),
        .rsta  (1'b0),
        .rstb  (1'b0),
        .doa   (),
        .dob   (ram_rdata)
    );

    always @(posedge rclk or negedge rst_n) begin
        if (!rst_n) begin
            pub_tog_meta      <= 1'b0;
            pub_tog_sync      <= 1'b0;
            pub_tog_d         <= 1'b0;
            pub_valid_meta    <= 1'b0;
            pub_valid_sync    <= 1'b0;
            read_active       <= 1'b0;
            rd_addr           <= 14'd0;
            rd_left           <= 14'd0;
            frame_ready       <= 1'b0;
            cap_en_r0         <= 1'b0;
            cap_en_r1         <= 1'b0;
            consume_toggle_udp <= 1'b0;
        end else begin
            cap_en_r0 <= capture_en;
            cap_en_r1 <= cap_en_r0;

            pub_tog_meta   <= pub_toggle_cam;
            pub_tog_sync   <= pub_tog_meta;
            pub_tog_d      <= pub_tog_sync;
            pub_valid_meta <= pub_valid_cam;
            pub_valid_sync <= pub_valid_meta;

            if (!capture_en_rclk || read_abort) begin
                if (frame_ready || read_active)
                    consume_toggle_udp <= ~consume_toggle_udp;
                read_active <= 1'b0;
                rd_addr     <= 14'd0;
                rd_left     <= 14'd0;
                frame_ready <= 1'b0;
            end else begin
                if (publish_edge && pub_valid_sync)
                    frame_ready <= 1'b1;

                if (read_start && frame_ready && !read_active) begin
                    rd_addr     <= 14'd0;
                    rd_left     <= FRAME_WORDS;
                    read_active <= 1'b1;
                    frame_ready <= 1'b0;
                end else if (rd_do) begin
                    rd_addr <= rd_addr + 1'b1;
                    rd_left <= rd_left - 1'b1;
                    if (rd_left == 14'd1) begin
                        read_active        <= 1'b0;
                        consume_toggle_udp <= ~consume_toggle_udp;
                    end
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // Camera write-domain state and frame publication
    // ------------------------------------------------------------------
    reg        cap_en_c0;
    reg        cap_en_c1;
    wire       capture_en_cam = cap_en_c1;

    reg        rd_active_c0;
    reg        rd_active_c1;
    reg        consume_c0;
    reg        consume_c1;
    reg        consume_d;
    wire       consume_edge = consume_c1 ^ consume_d;

    reg        vs_d;
    reg        href_d;
    wire       vs_rise   = cmos_frame_vsync & ~vs_d;
    wire       href_rise = cmos_frame_href  & ~href_d;
    wire       href_fall = ~cmos_frame_href & href_d;

    reg        pub_valid_cam;
    reg        pub_toggle_cam;
    reg        pub_pending;
    reg        frame_locked_cam;
    wire       buffer_blocked = frame_locked_cam | rd_active_c1;

    reg [13:0] wr_count;
    reg [3:0]  dec_x_cnt;
    reg [3:0]  dec_y_cnt;
    reg [9:0]  out_x;
    reg [9:0]  out_y;
    reg        take_line;

    wire       line_take_now = href_rise ? ((dec_y_cnt == 4'd0) && (out_y < OUT_H)) : take_line;
    wire [3:0] dec_x_now     = href_rise ? 4'd0 : dec_x_cnt;
    wire [9:0] out_x_now     = href_rise ? 10'd0 : out_x;
    wire       take_sample   = cmos_frame_valid && line_take_now &&
                               (dec_x_now == 4'd0) &&
                               (out_x_now < OUT_W) &&
                               (out_y < OUT_H) &&
                               (wr_count < FRAME_WORDS);

    always @(posedge cam_pclk or negedge rst_n) begin
        if (!rst_n) begin
            st              <= S_IDLE;
            cap_en_c0       <= 1'b0;
            cap_en_c1       <= 1'b0;
            rd_active_c0    <= 1'b0;
            rd_active_c1    <= 1'b0;
            consume_c0      <= 1'b0;
            consume_c1      <= 1'b0;
            consume_d       <= 1'b0;
            vs_d            <= 1'b0;
            href_d          <= 1'b0;
            pub_valid_cam   <= 1'b0;
            pub_toggle_cam  <= 1'b0;
            pub_pending     <= 1'b0;
            frame_locked_cam <= 1'b0;
            wr_count        <= 14'd0;
            dec_x_cnt       <= 4'd0;
            dec_y_cnt       <= 4'd0;
            out_x           <= 10'd0;
            out_y           <= 10'd0;
            take_line       <= 1'b0;
            ram_we          <= 1'b0;
            ram_waddr       <= 13'd0;
            ram_wdata       <= 16'd0;
            fifo_wfull      <= 1'b0;
            fifo_wused      <= 14'd0;
            fifo_wen        <= 1'b0;
            fifo_wdata      <= 16'd0;
            fifo_wflush     <= 1'b0;
            busy            <= 1'b0;
            done_toggle     <= 1'b0;
            overflow_toggle <= 1'b0;
            dbg_start_seen  <= 1'b0;
            dbg_vsync_seen  <= 1'b0;
            dbg_cap_seen    <= 1'b0;
            dbg_wen_seen    <= 1'b0;
            dbg_pix_80_seen <= 1'b0;
            dbg_pix_240_seen <= 1'b0;
            dbg_pix_800_seen <= 1'b0;
            dbg_href_4_seen <= 1'b0;
            dbg_href_16_seen <= 1'b0;
        end else begin
            cap_en_c0    <= capture_en;
            cap_en_c1    <= cap_en_c0;
            rd_active_c0 <= read_active;
            rd_active_c1 <= rd_active_c0;
            consume_c0   <= consume_toggle_udp;
            consume_c1   <= consume_c0;
            consume_d    <= consume_c1;
            vs_d         <= cmos_frame_vsync;
            href_d       <= cmos_frame_href;
            ram_we       <= 1'b0;
            fifo_wen     <= 1'b0;
            fifo_wflush  <= 1'b0;
            fifo_wfull   <= buffer_blocked;

            if (!capture_en_cam) begin
                st               <= S_IDLE;
                busy             <= 1'b0;
                pub_valid_cam    <= 1'b0;
                pub_pending      <= 1'b0;
                frame_locked_cam <= 1'b0;
                wr_count         <= 14'd0;
                fifo_wused       <= 14'd0;
                take_line        <= 1'b0;
            end else begin
                if (consume_edge) begin
                    frame_locked_cam <= 1'b0;
                    if (st == S_IDLE)
                        fifo_wused <= 14'd0;
                end

                if (pub_pending) begin
                    // Keep pub_valid_cam stable for one cam_pclk before toggling
                    // the CDC flag, so the rclk domain samples a stable publish.
                    pub_toggle_cam <= ~pub_toggle_cam;
                    done_toggle    <= ~done_toggle;
                    pub_pending    <= 1'b0;
                end

                if (vs_rise) begin
                    dbg_vsync_seen <= 1'b1;
                    if (st == S_CAP && (wr_count != FRAME_WORDS))
                        overflow_toggle <= ~overflow_toggle;

                    if (!buffer_blocked) begin
                        st             <= S_CAP;
                        busy           <= 1'b1;
                        wr_count       <= 14'd0;
                        fifo_wused     <= 14'd0;
                        dec_x_cnt      <= 4'd0;
                        dec_y_cnt      <= 4'd0;
                        out_x          <= 10'd0;
                        out_y          <= 10'd0;
                        take_line      <= 1'b0;
                        fifo_wflush    <= 1'b1;
                        dbg_start_seen <= 1'b1;
                    end else begin
                        st        <= S_IDLE;
                        busy      <= 1'b0;
                        take_line <= 1'b0;
                    end
                end else if (st == S_CAP) begin
                    if (href_rise) begin
                        dec_x_cnt <= 4'd0;
                        out_x     <= 10'd0;
                        take_line <= ((dec_y_cnt == 4'd0) && (out_y < OUT_H));
                        dbg_cap_seen <= 1'b1;
                        if (out_y >= 10'd3)  dbg_href_4_seen  <= 1'b1;
                        if (out_y >= 10'd15) dbg_href_16_seen <= 1'b1;
                    end

                    if (take_sample) begin
                        ram_we       <= 1'b1;
                        ram_waddr    <= wr_count[12:0];
                        ram_wdata    <= cmos_frame_data;
                        fifo_wen     <= 1'b1;
                        fifo_wdata   <= cmos_frame_data;
                        fifo_wused   <= wr_count + 1'b1;
                        dbg_wen_seen <= 1'b1;

                        if (wr_count >= 14'd79)  dbg_pix_80_seen  <= 1'b1;
                        if (wr_count >= 14'd239) dbg_pix_240_seen <= 1'b1;
                        if (wr_count >= 14'd799) dbg_pix_800_seen <= 1'b1;

                        if (wr_count == FRAME_WORDS - 14'd1) begin
                            pub_valid_cam    <= 1'b1;
                            pub_pending      <= 1'b1;
                            frame_locked_cam <= 1'b1;
                            busy             <= 1'b0;
                            st               <= S_IDLE;
                        end else begin
                            wr_count <= wr_count + 1'b1;
                        end
                    end

                    if (cmos_frame_valid) begin
                        if (dec_x_now == DEC_X - 1'b1)
                            dec_x_cnt <= 4'd0;
                        else
                            dec_x_cnt <= dec_x_now + 1'b1;

                        if (take_sample)
                            out_x <= out_x_now + 1'b1;
                    end

                    if (href_fall) begin
                        dec_x_cnt <= 4'd0;
                        take_line <= 1'b0;
                        if (take_line && (out_y < OUT_H))
                            out_y <= out_y + 1'b1;

                        if (dec_y_cnt == DEC_Y - 1'b1)
                            dec_y_cnt <= 4'd0;
                        else
                            dec_y_cnt <= dec_y_cnt + 1'b1;
                    end
                end else begin
                    busy <= 1'b0;
                end
            end
        end
    end
endmodule
