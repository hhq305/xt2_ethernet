// =============================================================
// framebuf.v : 双口 BRAM 帧缓存 (320x240, 8bit 灰度)。
// 大图请改用 src/integ/sdram_fb.v (接口完全一致, 后端为片上 SDRAM)。
// =============================================================
`timescale 1ns/1ps
module framebuf #(
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
    always @(posedge wclk) if (wen) mem[waddr] <= wdata;
    always @(posedge rclk) if (ren) rdata      <= mem[raddr];
endmodule
