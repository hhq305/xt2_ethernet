// =============================================================
// cam_to_bram.v
// 选题�?扩展�?: OV5640 摄像头实时画�?�?16x16 RGB222 BRAM
//
// 输入: ov5640_dri 输出�?cmos_frame_data[15:0] (RGB565), 1024x768 raster
// 处理: 64 列采 1 / 48 行采 1, �?RGB 高位 -> RGB222
// 输出: wr_en/wr_addr/wr_data 写入�?BRAM, 替换 PC 上传
// 时钟: cam_pclk (~96 MHz) �?�?udp_clk 异步, 由顶�?mux 切换写源即可
// =============================================================
`timescale 1ns/1ps

module cam_to_bram #(
    parameter SRC_W   = 11'd1024,
    parameter SRC_H   = 11'd768,
    parameter DST_W   = 5'd16,       // 目标 16x16
    parameter DST_H   = 5'd16,
    parameter DEC_X   = 7'd64,       // 1024/16 = 64
    parameter DEC_Y   = 7'd48        // 768/16 = 48
)(
    input  wire        cam_pclk,
    input  wire        rst_n,
    input  wire        cmos_frame_vsync,
    input  wire        cmos_frame_href,
    input  wire        cmos_frame_valid,
    input  wire [15:0] cmos_frame_data,    // RGB565
    // 异步读端�?(�?udp_rx_clk 域的 BRAM 刷新引擎使用)
    input  wire [7:0]  rd_addr,
    output wire [5:0]  rd_data
);
    // 256 entry x 6 bit 镜像
    reg [5:0] mem [0:255];
    integer i;
    initial for (i=0; i<256; i=i+1) mem[i] = 6'd0;
    assign rd_data = mem[rd_addr];

    reg [10:0] x_cnt;       // 0..1023
    reg [10:0] y_cnt;       // 0..767
    reg [6:0]  dec_x_cnt;   // 0..DEC_X-1
    reg [6:0]  dec_y_cnt;
    reg [3:0]  dst_x;       // 0..15
    reg [3:0]  dst_y;
    reg        prev_vsync;

    // RGB565 -> RGB222: ȡÿͨ���� 2 λ
    wire [1:0] r2 = cmos_frame_data[15:14];
    wire [1:0] g2 = cmos_frame_data[10:9];
    wire [1:0] b2 = cmos_frame_data[ 4:3];
    wire [5:0] rgb222 = {r2, g2, b2};

    always @(posedge cam_pclk or negedge rst_n) begin
        if (!rst_n) begin
            x_cnt <= 0; y_cnt <= 0; dec_x_cnt <= 0; dec_y_cnt <= 0;
            dst_x <= 0; dst_y <= 0; prev_vsync <= 0;
        end else begin
            prev_vsync <= cmos_frame_vsync;

            if (cmos_frame_vsync && !prev_vsync) begin
                x_cnt <= 0; y_cnt <= 0;
                dec_x_cnt <= 0; dec_y_cnt <= 0;
                dst_x <= 0; dst_y <= 0;
            end else if (cmos_frame_valid) begin
                if (x_cnt == SRC_W-1) begin
                    x_cnt     <= 0;
                    dec_x_cnt <= 0;
                    dst_x     <= 0;
                    if (y_cnt == SRC_H-1) y_cnt <= 0;
                    else                  y_cnt <= y_cnt + 1'b1;
                    if (dec_y_cnt == DEC_Y-1) begin
                        dec_y_cnt <= 0;
                        if (dst_y != DST_H-1) dst_y <= dst_y + 1'b1;
                    end else begin
                        dec_y_cnt <= dec_y_cnt + 1'b1;
                    end
                end else begin
                    x_cnt <= x_cnt + 1'b1;
                    // 在降采样网格点采�? 写入内部镜像
                    if (dec_x_cnt == 0 && dec_y_cnt == 0 && dst_x < DST_W) begin
                        mem[{dst_y, dst_x}] <= rgb222;
                        if (dst_x != DST_W-1) dst_x <= dst_x + 1'b1;
                    end
                    if (dec_x_cnt == DEC_X-1) dec_x_cnt <= 0;
                    else                      dec_x_cnt <= dec_x_cnt + 1'b1;
                end
            end
        end
    end
endmodule
