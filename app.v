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
    // 选题二 扩展④ : 图像处理模式 (来自 cmd_decode)
    input  wire [1:0]       proc_mode_i,
    // 选题二 扩展② : 把图像写信号导出给 img_tx_rom 维护镜像
    output wire             wr_en_o,
    output wire [7:0]       wr_addr_o,
    output wire [5:0]       wr_data_o,
    // 选题二 扩展⑤ : 摄像头镜像异步读出 (udp_rx_clk 刷新引擎使用)
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

// SDRAM 帧缓存: 400x288 RGB444，VGA 端居中原尺寸显示。
// TEST_PATTERN=0：接收 PC 通过 UDP 上传的图片并写入 SDRAM。
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

assign cam_rd_addr_o = 8'd0;
assign wr_en_o       = fb_we;
assign wr_addr_o     = fb_waddr[7:0];
assign wr_data_o     = {fb_wdata[11:10], fb_wdata[7:6], fb_wdata[3:2]};
// SDRAM 帧缓存内部已经在未进入读显示状态时输出诊断色；进入读显示后直接显示 RGB444，
// 避免把图片里的合法黑色像素误判成“读数据为 0”并替换为诊断色。
assign rgb_diag      = sdr_rst       ? 12'hF00 :   // red: SDRAM reset asserted
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

// 本文件内置一份双时钟帧缓存，避免 TD 工程没有单独加入 src/mem/framebuf.v
// 时把 framebuf 识别成 black box。
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
