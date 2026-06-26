module app (
    input                   sys_clk,
    input                   udp_rx_clk,
    input                   udp_tx_clk,
    input                   reset,
    input                   sdr_clk,
    input                   sdr_clk_sft,
    input                   sdr_rst,
    output                  sdr_init_done,
    output                  vga_underflow,

//udp2app signal
    input                   app_rx_data_valid,
    input  [7:0]            app_rx_data,
    input wire [15:0]       app_rx_data_length,
    input wire [15:0]       app_rx_port_num,
    // é€‰é¢˜äº?æ‰©å±•â‘?: å›¾åƒå¤„ç†æ¨¡å¼ (æ¥è‡ª cmd_decode)
    input  wire [1:0]       proc_mode_i,
    // é€‰é¢˜äº?æ‰©å±•â‘?: æŠŠå›¾åƒå†™ä¿¡å·å¯¼å‡ºç»?img_tx_rom ç»´æŠ¤é•œåƒ
    output wire             wr_en_o,
    output wire [7:0]       wr_addr_o,
    output wire [5:0]       wr_data_o,
    // é€‰é¢˜äº?æ‰©å±•â‘?: æ‘„åƒå¤´é•œåƒå¼‚æ­¥è¯»å‡?(udp_rx_clk åˆ·æ–°å¼•æ“ä½¿ç”¨)
    input  wire             cam_en_i,
    output wire [7:0]       cam_rd_addr_o,
    input  wire [5:0]       cam_rd_data_i,

    output [11:0]           VGA_D,
    output                  VGA_HSYNC,
    output                  VGA_VSYNC,
    output                  rd_en
);

reg       clk25M;
wire [11:0] rgb;
localparam IMG_W  = 400;
localparam IMG_H  = 288;
localparam IMG_AW = $clog2(IMG_W*IMG_H);

wire        fb_we;
wire [IMG_AW-1:0] fb_waddr;
wire [11:0] fb_wdata;
wire [11:0] fb_rgb444;
wire [11:0] sdram_dbg_rgb;
wire [11:0] rgb_diag;
wire        frame_done;
wire        vga_de;
wire [9:0]  vga_x;
wire [8:0]  vga_y;
wire        line_req;
wire [8:0]  line_req_y;
wire        vblank_pulse;
wire [18:0] vga_legacy_addr;

always @(posedge sys_clk or negedge reset) begin
    if (!reset)
        clk25M <= 0;
    else
        clk25M <= ~clk25M;
end

img_rx_fb #(
    .IMG_W(IMG_W),
    .IMG_H(IMG_H)
) u_img_rx_fb (
    .clk        (udp_rx_clk),
    .rst_n      (reset),
    .rx_data    (app_rx_data),
    .rx_valid   (app_rx_data_valid),
    .fb_we      (fb_we),
    .fb_waddr   (fb_waddr),
    .fb_wdata   (fb_wdata),
    .frame_done (frame_done)
);

// SDRAM å¸§ç¼“å­? 400x288 RGB444ï¼ŒVGA ç«¯å±…ä¸­åŸå°ºå¯¸æ˜¾ç¤ºã€?// TEST_PATTERN=0ï¼šæ¥æ”?PC é€šè¿‡ UDP ä¸Šä¼ çš„å›¾ç‰‡å¹¶å†™å…¥ SDRAMã€?
sdram_img_fb #(
    .IMG_W       (IMG_W),
    .IMG_H       (IMG_H),
    .AW          (IMG_AW),
    .FRAME_WORDS (IMG_W*IMG_H),
    .TEST_PATTERN(0)
) u_sdram_img_fb (
    .udp_clk       (udp_rx_clk),
    .udp_rst_n     (reset),
    .fb_we         (fb_we),
    .fb_waddr      (fb_waddr),
    .fb_wdata      (fb_wdata),
    .frame_done    (frame_done),

    .vga_clk       (clk25M),
    .vga_rst_n     (reset),
    .vga_de        (vga_de),
    .vga_x         (vga_x),
    .vga_y         (vga_y),
    .line_req      (line_req),
    .line_req_y    (line_req_y),
    .vblank_pulse  (vblank_pulse),
    .vga_rgb       (fb_rgb444),
    .underflow     (vga_underflow),

    .sdr_clk       (sdr_clk),
    .sdr_clk_sft   (sdr_clk_sft),
    .sdr_rst       (sdr_rst),
    .sdr_init_done (sdr_init_done),
    .dbg_rgb       (sdram_dbg_rgb)
);

 // ÉãÏñÍ·¿ªÆôÊ±£¬°Ñ 16x16 ÉãÏñÍ·¾µÏñ°áµ½ img_tx_rom µÄ 256 ×Ö½Ú¾µÏñ RAM¡£
reg [7:0] cam_scan_addr;
reg [7:0] cam_wr_addr;
reg [5:0] cam_wr_data;
reg       cam_wr_en;

always @(posedge udp_rx_clk or negedge reset) begin
    if (!reset) begin
        cam_scan_addr <= 8'd0;
        cam_wr_addr   <= 8'd0;
        cam_wr_data   <= 6'd0;
        cam_wr_en     <= 1'b0;
    end else if (cam_en_i) begin
        cam_scan_addr <= cam_scan_addr + 1'b1;
        cam_wr_addr   <= cam_scan_addr;
        cam_wr_data   <= cam_rd_data_i;
        cam_wr_en     <= 1'b1;
    end else begin
        cam_scan_addr <= 8'd0;
        cam_wr_en     <= 1'b0;
    end
end

assign cam_rd_addr_o = cam_scan_addr;
assign wr_en_o       = cam_en_i ? cam_wr_en   : fb_we;
assign wr_addr_o     = cam_en_i ? cam_wr_addr : fb_waddr[7:0];
assign wr_data_o     = cam_en_i ? cam_wr_data : {fb_wdata[11:10], fb_wdata[7:6], fb_wdata[3:2]};
 // SDRAM Î´¾ÍĞ÷Ê±ÏÔÊ¾Õï¶ÏÉ«£»½øÈë¶ÁÏÔÊ¾ºóÖ±½ÓÏÔÊ¾ RGB444¡£
assign rgb_diag      = sdr_rst       ? 12'hF00 :
                       !sdr_init_done ? 12'hF0F :   // magenta: SDRAM init not done
                       fb_rgb444;
assign rgb           = rgb_diag;
assign rd_en         = 1'b1;

vga_disp u_vga_disp (
    .clk25M      (clk25M),
    .reset_n     (reset),
    .rgb         (rgb),
    .VGA_HSYNC   (VGA_HSYNC),
    .VGA_VSYNC   (VGA_VSYNC),
    .de          (vga_de),
    .img_x       (vga_x),
    .img_y       (vga_y),
    .line_req    (line_req),
    .line_req_y  (line_req_y),
    .vblank_pulse(vblank_pulse),
    .addr        (vga_legacy_addr),
    .VGA_D       (VGA_D)
);

endmodule

// æœ¬æ–‡ä»¶å†…ç½®ä¸€ä»½åŒæ—¶é’Ÿå¸§ç¼“å­˜ï¼Œé¿å… TD å·¥ç¨‹æ²¡æœ‰å•ç‹¬åŠ å…¥ src/mem/framebuf.v
// æ—¶æŠŠ framebuf è¯†åˆ«æˆ?black boxã€?
module app_framebuf #(
    parameter W   = 320,
    parameter H   = 240,
    parameter DW  = 8,
    parameter AW  = $clog2(W*H)
)(
    input  wire           wclk,
    input  wire           wen,
    input  wire [AW-1:0]  waddr,
    input  wire [DW-1:0]  wdata,

    input  wire           rclk,
    input  wire           ren,
    input  wire [AW-1:0]  raddr,
    output reg  [DW-1:0]  rdata
);
    reg [DW-1:0] mem [0:W*H-1];

    always @(posedge wclk) begin
        if (wen)
            mem[waddr] <= wdata;
    end

    always @(posedge rclk) begin
        if (ren)
            rdata <= mem[raddr];
    end
endmodule
