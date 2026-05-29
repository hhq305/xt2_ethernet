// =============================================================
// dpram_64x64.v
// 选题二 扩展⑥ : 64x64 RGB222 照片镜像缓存 (双时钟双口 BRAM)
//   写端口 : SD 域 (50MHz clk_ref) , sd_photo64 降采样写入
//   读端口 : udp_clk 域 , photo_tx 多包回传读取
//   4096 entry x 6 bit = 24 Kb , 可映射到 1 块 EG4S20 BRAM
// =============================================================
`timescale 1ns/1ps

module dpram_64x64 (
    // 写端口 (SD / clk_ref 域)
    input  wire        wclk,
    input  wire        wen,
    input  wire [11:0] waddr,    // {dst_y[5:0], dst_x[5:0]}
    input  wire [5:0]  wdata,
    // 读端口 (udp_clk 域)
    input  wire        rclk,
    input  wire [11:0] raddr,
    output reg  [5:0]  rdata
);
    reg [5:0] mem [0:4095];
    integer i;
    initial for (i=0; i<4096; i=i+1) mem[i] = 6'd0;

    always @(posedge wclk) begin
        if (wen) mem[waddr] <= wdata;
    end

    always @(posedge rclk) begin
        rdata <= mem[raddr];
    end
endmodule
