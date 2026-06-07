// =============================================================
// sobel_ondemand.v
// 选题二 扩展④ 升级版: 真 2D Sobel 边缘检测 (3x3 卷积)
//
// 思路: 因为显示图像只有 16x16=256 像素, 把整张图镜像到 256x6bit 寄存器阵列,
//       VGA 扫描时任意像素 1 拍内取出 9 邻域并并行计算 Sobel, 无需 line buffer.
//
// 写端口 (clk_wr, udp_rx_clk) 与 addr_crt -> BRAM 写并行写入 mem.
// 读端口 (异步) 由 VGA 通路在 clk25M 域查询.
// 跨时钟域: mem 写后稳定数毫秒, 读侧不需同步 (允许偶发单像素瞬态).
// =============================================================
`timescale 1ns/1ps

module sobel_ondemand #(
    parameter THRESH = 8'd6           // |Gx|+|Gy| > THRESH 即认为是边缘
)(
    // 写端口 (同 addr_crt -> BRAM)
    input  wire        clk_wr,
    input  wire        wr_en,
    input  wire [7:0]  wr_addr,       // {y[3:0], x[3:0]}
    input  wire [5:0]  wr_data,       // {R[1:0], G[1:0], B[1:0]}
    // 查询端口 (clk25M 域, 组合输出)
    input  wire [3:0]  q_x,
    input  wire [3:0]  q_y,
    output wire        edge_bit
);

    // 256 entry x 6 bit 镜像存储
    reg [5:0] mem [0:255];

    // 初始内容 = demo logo 的前 256 项 (与 BRAM 同步), 上电即有边缘可见
    // logo_256.hex 拷贝在 final_work/ (TD 工程根, $readmemh 默认查找位置)
    initial $readmemh("logo_256.hex", mem);

    always @(posedge clk_wr) begin
        if (wr_en) mem[wr_addr] <= wr_data;
    end

    // ----------- 3x3 邻域取数 (边界外置 0) -----------
    function [5:0] pix;
        input [4:0] xi;     // 5 位有符号, 允许 -1
        input [4:0] yi;
        begin
            if (xi[4] || yi[4] || xi >= 5'd16 || yi >= 5'd16)
                pix = 6'd0;
            else
                pix = mem[{yi[3:0], xi[3:0]}];
        end
    endfunction

    // 灰度 (R+G+B), 每通道 2 bit, 和最大 9 (4 bit)
    function [3:0] lum;
        input [5:0] rgb;
        begin
            lum = rgb[5:4] + rgb[3:2] + rgb[1:0];
        end
    endfunction

    // 中心是 (q_x, q_y), 取 (q_x-1..q_x+1, q_y-1..q_y+1)
    wire [4:0] xm1 = {1'b0, q_x} - 5'd1;
    wire [4:0] xp1 = {1'b0, q_x} + 5'd1;
    wire [4:0] ym1 = {1'b0, q_y} - 5'd1;
    wire [4:0] yp1 = {1'b0, q_y} + 5'd1;

    wire [3:0] p00 = lum(pix(xm1, ym1));
    wire [3:0] p10 = lum(pix({1'b0,q_x}, ym1));
    wire [3:0] p20 = lum(pix(xp1, ym1));
    wire [3:0] p01 = lum(pix(xm1, {1'b0,q_y}));
    wire [3:0] p21 = lum(pix(xp1, {1'b0,q_y}));
    wire [3:0] p02 = lum(pix(xm1, yp1));
    wire [3:0] p12 = lum(pix({1'b0,q_x}, yp1));
    wire [3:0] p22 = lum(pix(xp1, yp1));

    // Sobel Gx = (p20 + 2*p21 + p22) - (p00 + 2*p01 + p02)
    // Sobel Gy = (p02 + 2*p12 + p22) - (p00 + 2*p10 + p20)
    // 每项最大 9*4 = 36, 差值范围 [-72..72], 用 8 位有符号
    wire signed [8:0] gx = $signed({1'b0, p20 + (p21<<1) + p22})
                         - $signed({1'b0, p00 + (p01<<1) + p02});
    wire signed [8:0] gy = $signed({1'b0, p02 + (p12<<1) + p22})
                         - $signed({1'b0, p00 + (p10<<1) + p20});
    wire [8:0] abs_gx = gx[8] ? (~gx + 1'b1) : gx;
    wire [8:0] abs_gy = gy[8] ? (~gy + 1'b1) : gy;
    wire [9:0] mag    = abs_gx + abs_gy;

    assign edge_bit = (mag > {2'b00, THRESH});

endmodule
