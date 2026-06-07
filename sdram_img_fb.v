// =============================================================
// sdram_img_fb.v : SDRAM framebuffer using official FIFO/burst
// controller modules from HX4S20 reference design.
//
// Runtime mode: PC/UDP writes IMG_W x IMG_H RGB444 pixels into the official
// write FIFO. Two RGB444 pixels are packed into each 32-bit SDRAM word; after
// one full frame enters the FIFO, the burst reader streams it to VGA.
// =============================================================
`timescale 1ns/1ps

module sdram_img_fb #(
    parameter IMG_W = 320,
    parameter IMG_H = 240,
    parameter AW    = $clog2(IMG_W*IMG_H),
    parameter FRAME_WORDS = IMG_W*IMG_H,
    parameter TEST_PATTERN = 0
)(
    input  wire           udp_clk,
    input  wire           udp_rst_n,
    input  wire           fb_we,
    input  wire [AW-1:0]  fb_waddr,
    input  wire [11:0]    fb_wdata,
    input  wire           frame_done,

    input  wire           vga_clk,
    input  wire           vga_rst_n,
    input  wire           vga_de,
    input  wire [9:0]     vga_x,
    input  wire [8:0]     vga_y,
    input  wire           line_req,
    input  wire [8:0]     line_req_y,
    input  wire           vblank_pulse,
    output reg  [11:0]    vga_rgb,
    output reg            underflow,

    input  wire           sdr_clk,
    input  wire           sdr_clk_sft,
    input  wire           sdr_rst,
    output wire           sdr_init_done,
    output reg  [11:0]    dbg_rgb
);
    localparam [20:0] FRAME_PIXELS = FRAME_WORDS;      // visible pixels per frame
    localparam [20:0] FRAME_LEN    = FRAME_WORDS >> 1; // two RGB444 pixels per 32-bit word

    // ---------------------------------------------------------
    // SDRAM controller
    // ---------------------------------------------------------
    wire        Sdr_init_ref_vld;
    wire        Sdr_busy;
    wire        App_wr_en;
    wire [20:0] App_wr_addr;
    wire [3:0]  App_wr_dm;
    wire [31:0] App_wr_din;
    wire        App_rd_en;
    wire [20:0] App_rd_addr;
    wire        Sdr_rd_en;
    wire [31:0] Sdr_rd_dout;

    reg sdr_init_seen;
    reg write_finish_tgl_sdr;
    always @(posedge sdr_clk or posedge sdr_rst) begin
        if (sdr_rst) begin
            sdr_init_seen        <= 1'b0;
            write_finish_tgl_sdr <= 1'b0;
        end else begin
            if (sdr_init_done)
                sdr_init_seen <= 1'b1;
            // Convert each writer completion pulse into a CDC-safe event.
            // A sticky "seen" flag would make later frames finish immediately.
            if (write_finish_raw)
                write_finish_tgl_sdr <= ~write_finish_tgl_sdr;
        end
    end

    sdram u_sdram (
        .Clk             (sdr_clk),
        .Clk_sft         (sdr_clk_sft),
        .Rst             (sdr_rst),
        .Sdr_init_done   (sdr_init_done),
        .Sdr_init_ref_vld(Sdr_init_ref_vld),
        .Sdr_busy        (Sdr_busy),
        .App_wr_en       (App_wr_en),
        .App_wr_addr     (App_wr_addr),
        .App_wr_dm       (App_wr_dm),
        .App_wr_din      (App_wr_din),
        .App_rd_en       (App_rd_en),
        .App_rd_addr     (App_rd_addr),
        .Sdr_rd_en       (Sdr_rd_en),
        .Sdr_rd_dout     (Sdr_rd_dout)
    );

    // ---------------------------------------------------------
    // Official FIFO/burst SDRAM frame reader/writer
    // ---------------------------------------------------------
    reg        write_req;
    wire       write_req_ack_raw;
    wire       write_finish_raw;
    wire       write_en_mux;
    wire [31:0] write_data_mux;
    reg        pat_write_req;
    reg        pat_write_en;
    reg [31:0] pat_write_data;
    reg        pat_done_tgl_sdr;
    wire       write_req_sel;
    wire       write_en_sel;
    wire [31:0] write_data_sel;
    wire       write_clk_sel;
    assign write_req_sel  = TEST_PATTERN ? pat_write_req  : write_req;
    assign write_en_sel   = TEST_PATTERN ? pat_write_en   : write_en_mux;
    assign write_data_sel = TEST_PATTERN ? pat_write_data : write_data_mux;
    assign write_clk_sel  = TEST_PATTERN ? sdr_clk        : udp_clk;

    reg        read_req;
    wire       read_req_ack;
    reg        read_en;
    reg        rd_pair_half;
    reg [31:0] rd_word;
    wire [31:0] read_data;
    wire       read_empty;
    wire       write_full;

    frame_read_write #(
        .MEM_DATA_BITS  (32),
        .READ_DATA_BITS (32),
        .WRITE_DATA_BITS(32),
        .ADDR_BITS      (21),
        .BURST_BITS     (9),
        .BURST_SIZE     (256)
    ) u_frame_read_write (
        .rst             (sdr_rst),
        .mem_clk         (sdr_clk),
        .Sdr_init_done   (sdr_init_done),
        .Sdr_init_ref_vld(Sdr_init_ref_vld),
        .Sdr_busy        (Sdr_busy),

        .App_rd_en       (App_rd_en),
        .App_rd_addr     (App_rd_addr),
        .Sdr_rd_en       (Sdr_rd_en),
        .Sdr_rd_dout     (Sdr_rd_dout),

        .read_clk        (vga_clk),
        .read_req        (read_req),
        .read_req_ack    (read_req_ack),
        .read_finish     (),
        .read_addr_0     (21'd0),
        .read_addr_1     (21'd0),
        .read_addr_2     (21'd0),
        .read_addr_3     (21'd0),
        .read_addr_index (2'd0),
        .read_len        (FRAME_LEN),
        .read_en         (read_en),
        .read_data       (read_data),
        .read_empty      (read_empty),
        .read_valid      (),

        .App_wr_en       (App_wr_en),
        .App_wr_addr     (App_wr_addr),
        .App_wr_din      (App_wr_din),
        .App_wr_dm       (App_wr_dm),

        .write_clk       (write_clk_sel),
        .write_req       (write_req_sel),
        .write_req_ack   (write_req_ack_raw),
        .write_finish    (write_finish_raw),
        .write_addr_0    (21'd0),
        .write_addr_1    (21'd0),
        .write_addr_2    (21'd0),
        .write_addr_3    (21'd0),
        .write_addr_index(2'd0),
        .write_len       (FRAME_LEN),
        .write_en        (write_en_sel),
        .write_data      (write_data_sel),
        .write_full      (write_full)
    );

    // ---------------------------------------------------------
    // Write request control in UDP clock domain.
    // Keep a frame write transaction armed; after ack drops, pass fb_we
    // pixels into official write FIFO.  The SDRAM writer has a fixed FRAME_LEN,
    // so finish only when a complete frame has entered the FIFO; PC frame_done
    // repeats are diagnostic/protocol markers and must not stop the burst early.
    // ---------------------------------------------------------
    localparam U_IDLE      = 3'd0;
    localparam U_REQ       = 3'd1;
    localparam U_RX        = 3'd2;
    localparam U_PAD       = 3'd3;
    localparam U_WAIT_FIN  = 3'd4;
    localparam U_DONE      = 3'd5;

    reg [2:0] ust;
    reg       rx_accept;
    reg [2:0] init_sync_udp;
    wire      sdr_init_udp = init_sync_udp[2];
    reg       write_done_tgl_udp;
    reg [20:0] accepted_cnt; // counts pixels, not SDRAM words
    reg        pack_half;
    reg [11:0] pack_pix;
    reg [2:0] write_ack_sync_udp;
    reg [2:0] write_finish_sync_udp;
    reg       write_finish_seen_udp;
    reg [23:0] rx_idle_cnt;
    wire      rx_timeout = (ust == U_RX) && (rx_idle_cnt == 24'h3FFFFF);
    wire      rx_pixel_avail  = rx_accept & fb_we & (accepted_cnt < FRAME_PIXELS);
    wire      pad_pixel_avail = (ust == U_PAD) && (accepted_cnt < FRAME_PIXELS);
    wire      src_pixel_avail = rx_pixel_avail | pad_pixel_avail;
    wire      take_pixel      = src_pixel_avail && (!pack_half || !write_full);
    wire      write_word      = take_pixel && pack_half;
    wire [11:0] src_pix       = pad_pixel_avail ? 12'd0 : fb_wdata;
    wire [20:0] accepted_next = accepted_cnt + {20'd0, take_pixel};
    wire      write_ack_udp    = write_ack_sync_udp[2];
    wire      write_finish_evt_udp = write_finish_sync_udp[2] ^ write_finish_sync_udp[1];

    always @(posedge udp_clk or negedge udp_rst_n) begin
        if (!udp_rst_n) begin
            ust <= U_IDLE;
            write_req <= 1'b0;
            rx_accept <= 1'b0;
            write_done_tgl_udp <= 1'b0;
            accepted_cnt <= 21'd0;
            pack_half <= 1'b0;
            pack_pix <= 12'd0;
            write_ack_sync_udp <= 3'b000;
            write_finish_sync_udp <= 3'b000;
            write_finish_seen_udp <= 1'b0;
            rx_idle_cnt <= 24'd0;
            init_sync_udp <= 3'b000;
        end else begin
            init_sync_udp <= {init_sync_udp[1:0], sdr_init_seen};
            write_ack_sync_udp <= {write_ack_sync_udp[1:0], write_req_ack_raw};
            write_finish_sync_udp <= {write_finish_sync_udp[1:0], write_finish_tgl_sdr};
            if (write_finish_evt_udp)
                write_finish_seen_udp <= 1'b1;
            case (ust)
                U_IDLE: begin
                    if (sdr_init_udp) begin
                        write_req <= 1'b1;
                        rx_accept <= 1'b0;
                        accepted_cnt <= 21'd0;
                        pack_half <= 1'b0;
                        pack_pix <= 12'd0;
                        write_finish_seen_udp <= 1'b0;
                        rx_idle_cnt <= 24'd0;
                        ust <= U_REQ;
                    end
                end
                U_REQ: begin
                    if (write_ack_udp) begin
                        write_req <= 1'b0;
                        rx_accept <= 1'b0;
                        ust <= U_RX;
                    end
                end
                U_RX: begin
                    // Wait until ack is fully low; official module releases FIFO reset then.
                    if (!write_ack_udp)
                        rx_accept <= 1'b1;
                    if (fb_we || take_pixel)
                        rx_idle_cnt <= 24'd0;
                    else if (rx_accept && rx_idle_cnt != 24'h3FFFFF)
                        rx_idle_cnt <= rx_idle_cnt + 1'b1;
                    if (take_pixel) begin
                        accepted_cnt <= accepted_next;
                        if (!pack_half) begin
                            pack_pix  <= src_pix;
                            pack_half <= 1'b1;
                        end else begin
                            pack_half <= 1'b0;
                        end
                    end
                    // Commit when all expected pixels arrive.  If the PC end marker is
                    // seen after most of the frame, pad the short tail; this tolerates a
                    // few dropped UDP packets without staying yellow forever.  Very early
                    // frame_done pulses are ignored to avoid turning the image into a
                    // short top strip followed by black.
                    if (accepted_next == FRAME_PIXELS) begin
                        rx_accept <= 1'b0;
                        ust <= U_WAIT_FIN;
                    end else if (frame_done && (accepted_cnt > (FRAME_PIXELS - 21'd4096))) begin
                        rx_accept <= 1'b0;
                        ust <= U_PAD;
                    end else if (rx_timeout && accepted_cnt != 21'd0) begin
                        rx_accept <= 1'b0;
                        ust <= U_PAD;
                    end
                end
                U_PAD: begin
                    if (take_pixel) begin
                        accepted_cnt <= accepted_next;
                        if (!pack_half) begin
                            pack_pix  <= src_pix;
                            pack_half <= 1'b1;
                        end else begin
                            pack_half <= 1'b0;
                        end
                    end
                    if (accepted_next == FRAME_PIXELS)
                        ust <= U_WAIT_FIN;
                end
                U_WAIT_FIN: begin
                    if (write_finish_seen_udp) begin
                        write_done_tgl_udp <= ~write_done_tgl_udp;
                        ust <= U_DONE;
                    end
                end
                U_DONE: begin
                    // One frame has been committed and the VGA side has been notified.
                    // Re-arm for the next real image automatically.  Standalone repeated
                    // end markers are safe now because U_RX only pads/finishes when at
                    // least one pixel has been accepted in the new transaction.
                    ust <= U_IDLE;
                end
                default: ust <= U_IDLE;
            endcase
        end
    end

    assign write_en_mux   = write_word;
    // Pack two RGB444 pixels per 32-bit SDRAM word: low pixel first, high pixel second.
    // This halves SDRAM/FIFO bandwidth compared with one word per pixel.
    assign write_data_mux = {4'b0000, src_pix, 4'b0000, pack_pix};

    // Internal solid-red burst test. Used to re-establish the known-good
    // SDRAM baseline before reconnecting UDP image writes.
    localparam P_IDLE = 3'd0;
    localparam P_REQ  = 3'd1;
    localparam P_WAIT_ACK_LOW = 3'd2;
    localparam P_FEED = 3'd3;
    localparam P_WAIT_FIN = 3'd4;
    localparam P_DONE = 3'd5;
    reg [2:0]  pst;
    reg [20:0] pcnt;
    reg [2:0]  pfeed_gap;
    reg [8:0]  pat_x;
    reg [7:0]  pat_y;
    reg [11:0] pat_pix;

    always @(posedge sdr_clk or posedge sdr_rst) begin
        if (sdr_rst) begin
            pst <= P_IDLE;
            pcnt <= 21'd0;
            pat_x <= 9'd0;
            pat_y <= 8'd0;
            pat_pix <= 12'h000;
            pfeed_gap <= 3'd0;
            pat_write_req <= 1'b0;
            pat_write_en <= 1'b0;
            pat_write_data <= 32'h00000000;
            pat_done_tgl_sdr <= 1'b0;
        end else begin
            pat_write_en <= 1'b0;
            case (pst)
                P_IDLE: begin
                    if (TEST_PATTERN && sdr_init_seen) begin
                        pat_write_req <= 1'b1;
                        pst <= P_REQ;
                    end
                end
                P_REQ: begin
                    if (write_req_ack_raw) begin
                        pat_write_req <= 1'b0;
                        pcnt <= 21'd0;
                        pat_x <= 9'd0;
                        pat_y <= 8'd0;
                        pfeed_gap <= 3'd0;
                        pst <= P_WAIT_ACK_LOW;
                    end
                end
                P_WAIT_ACK_LOW: begin
                    if (!write_req_ack_raw)
                        pst <= P_FEED;
                end
                P_FEED: begin
                    if (pfeed_gap != 3'd0) begin
                        pfeed_gap <= pfeed_gap - 1'b1;
                    end else begin
                        pat_write_en <= 1'b1;
                        case (pat_x[8:6])
                            3'd0: pat_pix = 12'hF00; // red
                            3'd1: pat_pix = 12'h0F0; // green
                            3'd2: pat_pix = 12'h00F; // blue
                            3'd3: pat_pix = 12'hFFF; // white
                            3'd4: pat_pix = 12'h000; // black
                            3'd5: pat_pix = 12'hFF0; // yellow
                            3'd6: pat_pix = 12'h0FF; // cyan
                            default: pat_pix = 12'hF0F; // magenta
                        endcase
                        pat_write_data <= {4'b0000, pat_pix, 4'b0000, pat_pix};
                        pfeed_gap <= 3'd3;
                        if (pcnt == FRAME_LEN-1) begin
                            pst <= P_WAIT_FIN;
                        end else begin
                            pcnt <= pcnt + 1'b1;
                            if (pat_x == IMG_W-1) begin
                                pat_x <= 9'd0;
                                pat_y <= pat_y + 1'b1;
                            end else begin
                                pat_x <= pat_x + 1'b1;
                            end
                        end
                    end
                end
                P_WAIT_FIN: begin
                    if (write_finish_raw) begin
                        pat_done_tgl_sdr <= ~pat_done_tgl_sdr;
                        pst <= P_DONE;
                    end
                end
                default: pst <= P_DONE;
            endcase
        end
    end

    // ---------------------------------------------------------
    // Start continuous frame reads after the received frame is flushed.
    // ---------------------------------------------------------
    localparam R_IDLE = 2'd0;
    localparam R_REQ  = 2'd1;
    localparam R_WAIT = 2'd2;
    localparam R_RUN  = 2'd3;

    reg [1:0] rst_read;
    wire      write_done_src = TEST_PATTERN ? pat_done_tgl_sdr : write_done_tgl_udp;
    reg [2:0] write_done_sync_vga;
    reg       write_done_vga;
    reg [2:0] read_ack_sync_vga;
    reg [2:0] init_sync_vga;
    reg [2:0] ust_meta_vga;
    reg [2:0] ust_sync_vga;
    wire      sdr_init_vga = init_sync_vga[2];
    wire      read_ack_vga = read_ack_sync_vga[2];
    wire      frame_start_vga = vblank_pulse;

    // Packed RGB444 unpacking: one SDRAM word carries two pixels.
    function [11:0] word_to_rgb444_lo;
        input [31:0] word;
        begin
            word_to_rgb444_lo = word[11:0];
        end
    endfunction

    function [11:0] word_to_rgb444_hi;
        input [31:0] word;
        begin
            word_to_rgb444_hi = word[27:16];
        end
    endfunction

    always @(posedge vga_clk or negedge vga_rst_n) begin
        if (!vga_rst_n) begin
            rst_read <= R_IDLE;
            read_req <= 1'b0;
            write_done_sync_vga <= 3'b000;
            write_done_vga <= 1'b0;
            read_ack_sync_vga <= 3'b000;
            init_sync_vga <= 3'b000;
            ust_meta_vga <= U_IDLE;
            ust_sync_vga <= U_IDLE;
        end else begin
            init_sync_vga <= {init_sync_vga[1:0], sdr_init_seen};
            write_done_sync_vga <= {write_done_sync_vga[1:0], write_done_src};
            read_ack_sync_vga <= {read_ack_sync_vga[1:0], read_req_ack};
            ust_meta_vga <= ust;
            ust_sync_vga <= ust_meta_vga;
            if (write_done_sync_vga[2] ^ write_done_sync_vga[1])
                write_done_vga <= 1'b1;

            case (rst_read)
                R_IDLE: begin
                    // Start/restart SDRAM stream only during VGA blanking so
                    // SDRAM word 0 is ready before the active VGA image area.
                    if (write_done_vga && frame_start_vga) begin
                        read_req <= 1'b1;
                        rst_read <= R_REQ;
                    end
                end
                R_REQ: begin
                    if (read_ack_vga) begin
                        read_req <= 1'b0;
                        rst_read <= R_WAIT;
                    end
                end
                R_WAIT: begin
                    if (!read_empty)
                        rst_read <= R_RUN;
                end
                R_RUN: begin
                    // Refill from SDRAM once per VGA frame, during blanking.  The
                    // previous frame is fully consumed before this reset/restart.
                    if (frame_start_vga) begin
                        read_req <= 1'b1;
                        rst_read <= R_REQ;
                    end
                end
            endcase
        end
    end

    function [11:0] write_state_rgb;
        input [2:0] state;
        begin
            case (state)
                U_IDLE:     write_state_rgb = 12'h00F; // blue: waiting/re-arming write
                U_REQ:      write_state_rgb = 12'h80F; // purple: write request/ack
                U_RX:       write_state_rgb = 12'hFF0; // yellow: receiving UDP pixels
                U_PAD:      write_state_rgb = 12'h0FF; // cyan: padding missing tail pixels
                U_WAIT_FIN: write_state_rgb = 12'hFFF; // white: waiting SDRAM write finish
                U_DONE:     write_state_rgb = 12'h0F0; // green: one frame committed
                default:    write_state_rgb = 12'hF80; // orange: illegal state
            endcase
        end
    endfunction

    function [11:0] read_state_rgb;
        input [1:0] state;
        begin
            case (state)
                R_IDLE:  read_state_rgb = 12'h008; // dim blue: waiting vblank read start
                R_REQ:   read_state_rgb = 12'h80F; // purple: read request/ack
                R_WAIT:  read_state_rgb = 12'h0FF; // cyan: waiting read FIFO data
                R_RUN:   read_state_rgb = 12'h0F0; // green: reading/displaying frame
                default: read_state_rgb = 12'hF80; // orange: illegal state
            endcase
        end
    endfunction

    // Status colors until the frame is displayed.  Before a complete frame is
    // written, show the writer state; after completion, show the read state
    // until R_RUN starts producing actual pixels.
    always @(posedge vga_clk or negedge vga_rst_n) begin
        if (!vga_rst_n) begin
            read_en   <= 1'b0;
            rd_pair_half <= 1'b0;
            rd_word <= 32'd0;
            vga_rgb   <= 12'd0;
            dbg_rgb   <= 12'hF00;
            underflow <= 1'b0;
        end else begin
            read_en   <= 1'b0;
            underflow <= 1'b0;
            if (vga_de) begin
                if (sdr_rst) begin
                    dbg_rgb <= 12'hF00; // red: SDRAM reset asserted
                end else if (!sdr_init_vga) begin
                    dbg_rgb <= 12'hF0F; // magenta: SDRAM init not done
                end else if (!write_done_vga) begin
                    dbg_rgb <= write_state_rgb(ust_sync_vga);
                end else begin
                    dbg_rgb <= read_state_rgb(rst_read);
                end

                if (rst_read == R_RUN) begin
                    if (!rd_pair_half) begin
                        // Even source pixel: pop one 32-bit word and display its low RGB444 pixel.
                        if (!read_empty) begin
                            read_en      <= 1'b1;
                            rd_word      <= read_data;
                            vga_rgb      <= word_to_rgb444_lo(read_data);
                            rd_pair_half <= 1'b1;
                        end else begin
                            underflow <= 1'b1;
                            vga_rgb   <= 12'hF00; // red: read FIFO empty during active display
                        end
                    end else begin
                        // Odd source pixel: use cached high RGB444 pixel, no FIFO pop.
                        vga_rgb      <= word_to_rgb444_hi(rd_word);
                        rd_pair_half <= 1'b0;
                    end
                end else begin
                    rd_pair_half <= 1'b0;
                    vga_rgb <= dbg_rgb;
                end
            end else begin
                rd_pair_half <= 1'b0;
                vga_rgb <= 12'd0;
            end
        end
    end
endmodule
