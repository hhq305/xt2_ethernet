// =============================================================
// img_proc_inline.v
// 选题二 扩展④ : 在 VGA 显示通路上做轻量级图像处理
// 6-bit RGB222 (BRAM 输出) -> 处理 -> 6-bit RGB222 (送 vga_disp)
//
// proc_mode = 0 : RAW     直通
//             1 : GRAY    R/G/B 取平均, 复制三通道
//             2 : EDGE    |当前像素 - 上一像素| 超过阈值时置白, 否则黑
//             3 : INVERT  反色
//
// 1 级流水: rgb_o 在下一拍出现.
// =============================================================
`timescale 1ns/1ps

module img_proc_inline (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [1:0]  proc_mode,
    input  wire [5:0]  rgb_i,        // {R[1:0], G[1:0], B[1:0]}
    input  wire        edge_bit_2d,  // 来自 sobel_ondemand (2D Sobel 结果)
    output reg  [5:0]  rgb_o
);

    // 拆分 R/G/B (2 bit / 通道)
    wire [1:0] r_i = rgb_i[5:4];
    wire [1:0] g_i = rgb_i[3:2];
    wire [1:0] b_i = rgb_i[1:0];

    // 灰度: (R+G+B)/3 近似为 (R+G+B+1) >> 2 (放大一点更亮)
    wire [3:0] sum_rgb = r_i + g_i + b_i;       // 0..6
    wire [1:0] gray2   = (sum_rgb >= 4'd5) ? 2'b11 :
                         (sum_rgb >= 4'd3) ? 2'b10 :
                         (sum_rgb >= 4'd1) ? 2'b01 : 2'b00;

    // 边缘: 用上一像素值做差分 (1D, 沿扫描方向)
    reg [5:0] prev_rgb;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) prev_rgb <= 6'd0;
        else        prev_rgb <= rgb_i;

    wire [3:0] cur_sum  = r_i + g_i + b_i;
    wire [1:0] pr = prev_rgb[5:4];
    wire [1:0] pg = prev_rgb[3:2];
    wire [1:0] pb = prev_rgb[1:0];
    wire [3:0] prev_sum = pr + pg + pb;
    wire [3:0] diff     = (cur_sum > prev_sum) ? (cur_sum - prev_sum) : (prev_sum - cur_sum);
    wire       is_edge  = (diff >= 4'd2);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) rgb_o <= 6'd0;
        else case (proc_mode)
            2'd0: rgb_o <= rgb_i;                              // RAW
            2'd1: rgb_o <= {gray2, gray2, gray2};              // GRAY
            2'd2: rgb_o <= edge_bit_2d ? 6'b111111 : 6'b000000; // EDGE (2D Sobel)
            2'd3: rgb_o <= ~rgb_i;                             // INVERT
        endcase
    end

endmodule
