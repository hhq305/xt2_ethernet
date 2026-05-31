module app (
    input                   sys_clk,
    input                   udp_rx_clk,
    input                   udp_tx_clk,
    input                   reset,

//udp2app signal    
    input               app_rx_data_valid,
    input  [7:0]         app_rx_data,
    input wire [15:0]        app_rx_data_length,
    input wire [15:0]        app_rx_port_num,
    // 选题二 扩展④ : 图像处理模式 (来自 cmd_decode)
    input  wire [1:0]       proc_mode_i,
    // 选题二 扩展② : 把 addr_crt 的写信号导出给 img_tx_rom 维护镜像
    output wire             wr_en_o,
    output wire [7:0]       wr_addr_o,
    output wire [5:0]       wr_data_o,
    // 选题二 扩展⑤ : 摄像头镜像异步读出 (udp_rx_clk 刷新引擎使用)
    input  wire             cam_en_i,
    output wire [7:0]       cam_rd_addr_o,
    input  wire [5:0]       cam_rd_data_i,
    

    output [11:0]              VGA_D,
    output                     VGA_HSYNC,
    output                     VGA_VSYNC,
    output                     rd_en
);
wire        wr_en;

reg       clk25M;
wire [7:0]  ram_data;
wire [5:0]  rgb;
wire [16:0] wr_addr;
wire [16:0] addr;
wire [5:0] ram_data_1;

always @(posedge sys_clk or negedge reset) begin
	if (!reset)
		clk25M <= 0;
	else
		clk25M <= ~clk25M;
end

addr_crt u_addr_crt(
 .      clk   (udp_rx_clk),
 .      rst_n  (reset),
 .      udp_data (app_rx_data),
 .      udp_vaild  (app_rx_data_valid),
 .      udp_length (app_rx_data_length),
 .      wr_addr (wr_addr),
 .      wr_en  (wr_en),
 .      rd_en  (rd_en),
 .      ram_data (ram_data)
);
assign ram_data_1=ram_data[5:0];

// =====================================================================
// 选题二 扩展⑤ : 摄像头刷新引擎 (udp_rx_clk 域)
// cam_en=1 时, 持续把 cam_mirror[0..255] 写入主 BRAM, 覆盖 PC 上传内容
// =====================================================================
reg  [7:0] cam_refresh_cnt;
always @(posedge udp_rx_clk or negedge reset) begin
    if (!reset)        cam_refresh_cnt <= 8'd0;
    else if (cam_en_i) cam_refresh_cnt <= cam_refresh_cnt + 1'b1;
end
assign cam_rd_addr_o = cam_refresh_cnt;

// BRAM 写端口 mux : cam_en=1 用刷新引擎, 否则用 addr_crt
wire        bram_wr_en   = cam_en_i ? 1'b1                       : wr_en;
wire [14:0] bram_wr_addr = cam_en_i ? {7'b0, cam_refresh_cnt}    : wr_addr;
wire [5:0]  bram_wr_data = cam_en_i ? cam_rd_data_i              : ram_data_1;

// 导出写端口给 img_tx_rom + sobel_ondemand 的镜像 (扩展② / ④)
assign wr_en_o   = bram_wr_en;
assign wr_addr_o = bram_wr_addr[7:0];
assign wr_data_o = bram_wr_data;

wire [5:0] rgb_raw;
ram  u_ram (
	.dia(bram_wr_data), .addra (bram_wr_addr), .cea (bram_wr_en), .clka (udp_rx_clk), .wea (bram_wr_en),
	.dob (rgb_raw), .addrb (addr), .ceb (rd_en), .oceb (rd_en), .clkb (clk25M), .rstb (~reset)
);

// 选题二 扩展④ : 2D Sobel 边缘 (镜像 16x16 寄存器阵列, 异步组合查询)
wire edge_bit_2d;
sobel_ondemand u_sobel (
    .clk_wr  (udp_rx_clk),
    .wr_en   (bram_wr_en),
    .wr_addr (bram_wr_addr[7:0]),   // {y[3:0], x[3:0]}
    .wr_data (bram_wr_data),
    .q_x     (addr[3:0]),
    .q_y     (addr[7:4]),
    .edge_bit(edge_bit_2d)
);

// 选题二 扩展④ : 图像处理 (RAW/GRAY/EDGE/INVERT)
img_proc_inline u_img_proc (
    .clk         (clk25M),
    .rst_n       (reset),
    .proc_mode   (proc_mode_i),
    .rgb_i       (rgb_raw),
    .edge_bit_2d (edge_bit_2d),
    .rgb_o       (rgb)
);

vga_disp u_vga_disp(
	.	clk25M		(clk25M),
	.	reset_n     (reset),
	.   rgb	        (rgb),
	.	VGA_HSYNC	(VGA_HSYNC),
	. 	VGA_VSYNC 	(VGA_VSYNC),
	.	addr        (addr),
	.   VGA_D       (VGA_D)
);    
endmodule


