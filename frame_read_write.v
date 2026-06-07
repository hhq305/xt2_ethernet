`timescale 1ns/1ps
module frame_read_write
#
(
	parameter MEM_DATA_BITS          = 32,
	parameter READ_DATA_BITS         = 32,
	parameter WRITE_DATA_BITS        = 32,
	parameter ADDR_BITS              = 21,
	parameter BURST_BITS             = 9,
	parameter BURST_SIZE             = 256
)
(
	input                            rst,
	input                            mem_clk,
	input                            Sdr_init_done,
	input                            Sdr_init_ref_vld,
    input                            Sdr_busy,

	output                           App_rd_en,
	output[ADDR_BITS - 1:0]           App_rd_addr,
	input                            Sdr_rd_en,
	input[MEM_DATA_BITS - 1:0]        Sdr_rd_dout,

	input                            read_clk,
	input                            read_req,
	output                           read_req_ack,
	output                           read_finish,
	input[ADDR_BITS - 1:0]            read_addr_0,
	input[ADDR_BITS - 1:0]            read_addr_1,
	input[ADDR_BITS - 1:0]            read_addr_2,
	input[ADDR_BITS - 1:0]            read_addr_3,
	input[1:0]                        read_addr_index,
	input[ADDR_BITS - 1:0]            read_len,
	input                            read_en,
	output[READ_DATA_BITS  - 1:0]     read_data,
	output                           read_empty,
	output                           read_valid,

	output                           App_wr_en,
	output[ADDR_BITS - 1:0]           App_wr_addr,
	output[MEM_DATA_BITS - 1:0]       App_wr_din,
	output[3:0]                       App_wr_dm,

	input                            write_clk,
	input                            write_req,
	output                           write_req_ack,
	output                           write_finish,
	input[ADDR_BITS - 1:0]            write_addr_0,
	input[ADDR_BITS - 1:0]            write_addr_1,
	input[ADDR_BITS - 1:0]            write_addr_2,
	input[ADDR_BITS - 1:0]            write_addr_3,
	input[1:0]                        write_addr_index,
	input[ADDR_BITS - 1:0]            write_len,
	input                            write_en,
	input[WRITE_DATA_BITS - 1:0]      write_data,
	output                           write_full
);
wire[BURST_BITS - 1:0] wrusedw;
wire[BURST_BITS - 1:0] rdusedw;
wire App_rd_busy;
wire App_wr_busy;
wire read_fifo_aclr;
wire write_fifo_aclr;
wire read_empty_w;
wire read_valid_w;
wire write_full_w;
wire O_wr_busy;
wire O_rd_busy;

assign App_wr_busy = O_wr_busy;
assign App_rd_busy = O_rd_busy;
assign App_wr_dm = 4'b0000;
assign read_empty = read_empty_w;
assign read_valid = read_valid_w;
assign write_full = write_full_w;

wfifo_32_32_512 write_buf (
	.clkr       (mem_clk),
	.clkw       (write_clk),
	.rst        (write_fifo_aclr),
	.we         (write_en),
	.re         (App_wr_en),
	.di         (write_data),
	.empty_flag (),
	.full_flag  (write_full_w),
	.wrusedw    (),
	.rdusedw    (rdusedw),
	.dout       (App_wr_din)
);

frame_fifo_write #(
	.MEM_DATA_BITS(MEM_DATA_BITS),
	.ADDR_BITS    (ADDR_BITS),
	.BURST_BITS   (BURST_BITS),
	.BURST_SIZE   (BURST_SIZE)
) frame_fifo_write_m0 (
	.rst             (rst),
	.mem_clk         (mem_clk),
	.Sdr_init_done   (Sdr_init_done),
	.Sdr_init_ref_vld(Sdr_init_ref_vld),
	.Sdr_busy        (Sdr_busy),
	.App_rd_busy     (App_rd_busy),
	.O_wr_busy       (O_wr_busy),
	.App_wr_en       (App_wr_en),
	.App_wr_addr     (App_wr_addr),
	.write_req       (write_req),
	.write_req_ack   (write_req_ack),
	.write_finish    (write_finish),
	.write_addr_0    (write_addr_0),
	.write_addr_1    (write_addr_1),
	.write_addr_2    (write_addr_2),
	.write_addr_3    (write_addr_3),
	.write_addr_index(write_addr_index),
	.write_len       (write_len),
	.fifo_aclr       (write_fifo_aclr),
	.rdusedw         (rdusedw)
);

rfifo_32_32_512 #(
	.SHOW_AHEAD_EN(1'b1)
) read_buf (
	.clkr       (read_clk),
	.clkw       (mem_clk),
	.rst        (read_fifo_aclr),
	.we         (Sdr_rd_en),
	.re         (read_en),
	.di         (Sdr_rd_dout),
	.valid      (read_valid_w),
	.empty_flag (read_empty_w),
	.full_flag  (),
	.afull      (),
	.aempty     (),
	.wrusedw    (wrusedw),
	.rdusedw    (),
	.dout       (read_data)
);

frame_fifo_read #(
	.MEM_DATA_BITS(MEM_DATA_BITS),
	.ADDR_BITS    (ADDR_BITS),
	.BURST_BITS   (BURST_BITS),
	.BURST_SIZE   (BURST_SIZE)
) frame_fifo_read_m0 (
	.rst             (rst),
	.mem_clk         (mem_clk),
	.Sdr_init_done   (Sdr_init_done),
	.Sdr_init_ref_vld(Sdr_init_ref_vld),
	.Sdr_busy        (Sdr_busy),
	.Sdr_rd_en       (Sdr_rd_en),
	.App_wr_busy     (App_wr_busy),
	.O_rd_busy       (O_rd_busy),
	.App_rd_en       (App_rd_en),
	.App_rd_addr     (App_rd_addr),
	.read_req        (read_req),
	.read_req_ack    (read_req_ack),
	.read_finish     (read_finish),
	.read_addr_0     (read_addr_0),
	.read_addr_1     (read_addr_1),
	.read_addr_2     (read_addr_2),
	.read_addr_3     (read_addr_3),
	.read_addr_index (read_addr_index),
	.read_len        (read_len),
	.fifo_aclr       (read_fifo_aclr),
	.wrusedw         (wrusedw)
);
endmodule
