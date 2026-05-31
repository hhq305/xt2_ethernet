// =============================================================
// dpram_64x64.v  (名称保留, 实为双时钟异步 FIFO)
// 流式照片: SD 域(clk_ref) 写入 RGB565 像素, udp_clk 域读出打包发送。
//   标准 gray 码指针 + 2FF 同步异步 FIFO。
//   DW=16, AW=11 -> 深度 2048, = 32Kb BRAM。
//   读: ren 当拍弹出, rdata 下一拍有效 (寄存输出, 延迟 1 拍)。
//   wused/rused 分别供生产者反压 / 消费者起包阈值判断 (均为保守值)。
// =============================================================
`timescale 1ns/1ps

module dpram_64x64 #(
    parameter DW = 16,
    parameter AW = 11               // 深度 2^11 = 2048
)(
    // 写端口 (SD / clk_ref 域)
    input  wire           wclk,
    input  wire           wrst_n,
    input  wire           wflush,    // 写端清空脉冲 (生产者 start 同域)
    input  wire           wen,
    input  wire [DW-1:0]  wdata,
    output reg            wfull,
    output wire [AW:0]    wused,     // 写端可见已用量 (保守偏大)
    // 读端口 (udp_clk 域)
    input  wire           rclk,
    input  wire           rrst_n,
    input  wire           rflush,    // 读端清空脉冲 (消费者 start 同域)
    input  wire           ren,
    output reg  [DW-1:0]  rdata,
    output wire           rempty,
    output wire [AW:0]    rused      // 读端可见可读量 (保守偏小)
);
    localparam DEPTH = (1 << AW);

    reg [DW-1:0] mem [0:DEPTH-1];

    // gray <-> bin
    function [AW:0] bin2gray(input [AW:0] b); bin2gray = (b >> 1) ^ b; endfunction
    function [AW:0] gray2bin(input [AW:0] g);
        integer k;
        begin
            gray2bin[AW] = g[AW];
            for (k = AW-1; k >= 0; k = k - 1) gray2bin[k] = gray2bin[k+1] ^ g[k];
        end
    endfunction

    // ---- 写指针 (写时钟域) ----
    reg  [AW:0] wbin, wgray;
    wire        wr_do    = wen & ~wfull;
    wire [AW:0] wbin_nxt = wbin + wr_do;
    wire [AW:0] wgray_nxt = bin2gray(wbin_nxt);

    // ---- 读指针 (读时钟域) ----
    reg  [AW:0] rbin, rgray;
    wire        rd_do    = ren & ~rempty;
    wire [AW:0] rbin_nxt = rbin + rd_do;
    wire [AW:0] rgray_nxt = bin2gray(rbin_nxt);

    // ---- 跨时钟同步 ----
    reg [AW:0] rgray_w1, rgray_w2;   // 读 gray -> 写时钟
    reg [AW:0] wgray_r1, wgray_r2;   // 写 gray -> 读时钟

    // 满标志 (寄存化, 打破 wfull->wr_do->wbin_nxt->wgray_nxt->wfull 组合环)
    //   递增用寄存后的 wfull, 满判定 wfull_nxt 仅驱动该寄存器输入
    wire wfull_nxt = (wgray_nxt == {~rgray_w2[AW:AW-1], rgray_w2[AW-2:0]});

    // 写时钟域逻辑 (wflush 同步清空: 指针/满标志/同步器归零)
    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n)      begin wbin <= 0; wgray <= 0; wfull <= 1'b0; end
        else if (wflush)  begin wbin <= 0; wgray <= 0; wfull <= 1'b0; end
        else              begin wbin <= wbin_nxt; wgray <= wgray_nxt; wfull <= wfull_nxt; end
    end
    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n)      begin rgray_w1 <= 0; rgray_w2 <= 0; end
        else if (wflush)  begin rgray_w1 <= 0; rgray_w2 <= 0; end
        else              begin rgray_w1 <= rgray; rgray_w2 <= rgray_w1; end
    end
    always @(posedge wclk) if (wr_do) mem[wbin[AW-1:0]] <= wdata;

    wire [AW:0] rbin_w = gray2bin(rgray_w2);
    assign wused = wbin - rbin_w;

    // 读时钟域逻辑 (rflush 同步清空: 指针/同步器归零)
    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n)     begin rbin <= 0; rgray <= 0; end
        else if (rflush) begin rbin <= 0; rgray <= 0; end
        else             begin rbin <= rbin_nxt; rgray <= rgray_nxt; end
    end
    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n)     begin wgray_r1 <= 0; wgray_r2 <= 0; end
        else if (rflush) begin wgray_r1 <= 0; wgray_r2 <= 0; end
        else             begin wgray_r1 <= wgray; wgray_r2 <= wgray_r1; end
    end
    assign rempty = (rgray == wgray_r2);
    always @(posedge rclk) if (rd_do) rdata <= mem[rbin[AW-1:0]];

    wire [AW:0] wbin_r = gray2bin(wgray_r2);
    assign rused = wbin_r - rbin;
endmodule
