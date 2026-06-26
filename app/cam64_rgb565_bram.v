// =============================================================
// cam64_rgb565_bram.v
// 杩炵画鎶?OV5640 320x240 RGB565 闄嶉噰鏍峰埌 64x24 RGB565 灏忓抚缂撳瓨銆?// 璇荤鎸?UDP 鍙戦�佸櫒 fifo_ren 椤哄簭杈撳嚭锛岃寤惰繜 1 鎷嶄互鍖归厤 stream_tx銆?// =============================================================
`timescale 1ns/1ps

module cam64_rgb565_bram (
    input  wire        cam_pclk,
    input  wire        rst_n,
    input  wire        cmos_frame_vsync,
    input  wire        cmos_frame_href,
    input  wire        cmos_frame_valid,
    input  wire [15:0] cmos_frame_data,

    input  wire        rclk,
    input  wire        rclear,
    input  wire        ren,
    output reg  [15:0] rdata
);
    localparam [10:0] SRC_W = 11'd320;
    localparam [10:0] SRC_H = 11'd240;
    localparam [3:0]  DEC_X = 4'd5;    // 320 / 5 = 64
    localparam [3:0]  DEC_Y = 4'd10;   // 240 / 10 = 24

    reg [15:0] mem [0:1535];           // 64x24 RGB565

    reg [10:0] x_cnt;
    reg [10:0] y_cnt;
    reg [3:0]  dec_x_cnt;
    reg [3:0]  dec_y_cnt;
    reg [5:0]  dst_x;
    reg [4:0]  dst_y;
    reg        vsync_d;
    reg        href_d;

    wire [10:0] wr_addr    = {dst_y, dst_x};
    wire        line_start = cmos_frame_href & ~href_d;

    always @(posedge cam_pclk or negedge rst_n) begin
        if (!rst_n) begin
            x_cnt     <= 11'd0;
            y_cnt     <= 11'd0;
            dec_x_cnt <= 4'd0;
            dec_y_cnt <= 4'd0;
            dst_x     <= 6'd0;
            dst_y     <= 5'd0;
            vsync_d   <= 1'b0;
            href_d    <= 1'b0;
        end else begin
            vsync_d <= cmos_frame_vsync;
            href_d  <= cmos_frame_href;

            if (cmos_frame_vsync && !vsync_d) begin
                x_cnt     <= 11'd0;
                y_cnt     <= 11'd0;
                dec_x_cnt <= 4'd0;
                dec_y_cnt <= 4'd0;
                dst_x     <= 6'd0;
                dst_y     <= 5'd0;
            end else begin
                // 用 href 行起点校正横向计数。
                if (line_start) begin
                    x_cnt     <= 11'd0;
                    dec_x_cnt <= 4'd0;
                    dst_x     <= 6'd0;
                end

                if (cmos_frame_valid) begin
                    if ((dec_x_cnt == 4'd0) && (dec_y_cnt == 4'd0) &&
                        (dst_x < 6'd64) && (dst_y < 5'd24)) begin
                        mem[wr_addr] <= cmos_frame_data;
                        if (dst_x != 6'd63)
                            dst_x <= dst_x + 1'b1;
                    end

                    if (x_cnt == SRC_W - 1'b1) begin
                        x_cnt     <= 11'd0;
                        dec_x_cnt <= 4'd0;
                        dst_x     <= 6'd0;
                        if (y_cnt == SRC_H - 1'b1)
                            y_cnt <= 11'd0;
                        else
                            y_cnt <= y_cnt + 1'b1;

                        if (dec_y_cnt == DEC_Y - 1'b1) begin
                            dec_y_cnt <= 4'd0;
                            if (dst_y != 5'd23)
                                dst_y <= dst_y + 1'b1;
                        end else begin
                            dec_y_cnt <= dec_y_cnt + 1'b1;
                        end
                    end else begin
                        x_cnt <= x_cnt + 1'b1;
                        if (dec_x_cnt == DEC_X - 1'b1)
                            dec_x_cnt <= 4'd0;
                        else
                            dec_x_cnt <= dec_x_cnt + 1'b1;
                    end
                end
            end
        end
    end

    reg [10:0] rd_addr;
    always @(posedge rclk or negedge rst_n) begin
        if (!rst_n) begin
            rd_addr <= 11'd0;
            rdata   <= 16'd0;
        end else if (rclear) begin
            rd_addr <= 11'd0;
        end else if (ren) begin
            rdata   <= mem[rd_addr];
            rd_addr <= rd_addr + 1'b1;
        end
    end
endmodule
