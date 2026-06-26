// =============================================================
// obj_detect.v
// 扩展要求 ③ : 阈值连通的简单目标检测。
// 算法 : 对二值前景像素计算包围盒 (xmin/xmax/ymin/ymax) 与质心。
// 一帧结束 (frame_end) 时输出结果, 通过 UDP 发给远端显示。
// =============================================================
`timescale 1ns/1ps
module obj_detect #(
    parameter IMG_W = 320,
    parameter IMG_H = 240
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire        is_obj,
    input  wire [9:0]  x_in,
    input  wire [8:0]  y_in,
    input  wire        frame_end,
    output reg  [9:0]  bbox_xmin, bbox_xmax,
    output reg  [8:0]  bbox_ymin, bbox_ymax,
    output reg  [9:0]  cx,
    output reg  [8:0]  cy,
    output reg  [19:0] obj_area,
    output reg         result_valid
);
    reg [9:0] xmin_r, xmax_r;
    reg [8:0] ymin_r, ymax_r;
    reg [29:0] sx;
    reg [28:0] sy;
    reg [19:0] cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            xmin_r<=10'd1023; xmax_r<=0;
            ymin_r<=9'd511;   ymax_r<=0;
            sx<=0; sy<=0; cnt<=0; result_valid<=0;
            bbox_xmin<=0;bbox_xmax<=0;bbox_ymin<=0;bbox_ymax<=0;
            cx<=0;cy<=0;obj_area<=0;
        end else begin
            result_valid<=1'b0;
            if (in_valid && is_obj) begin
                if (x_in<xmin_r) xmin_r<=x_in;
                if (x_in>xmax_r) xmax_r<=x_in;
                if (y_in<ymin_r) ymin_r<=y_in;
                if (y_in>ymax_r) ymax_r<=y_in;
                sx <= sx + x_in;
                sy <= sy + y_in;
                cnt<= cnt + 1'b1;
            end
            if (frame_end) begin
                bbox_xmin<=xmin_r; bbox_xmax<=xmax_r;
                bbox_ymin<=ymin_r; bbox_ymax<=ymax_r;
                obj_area <= cnt;
                cx <= (cnt==0)? 0 : sx[29:10];   // 近似除: sx/cnt → 这里仅取高位
                cy <= (cnt==0)? 0 : sy[28:9];
                result_valid <= 1'b1;
                // reset accumulators
                xmin_r<=10'd1023; xmax_r<=0;
                ymin_r<=9'd511;   ymax_r<=0;
                sx<=0; sy<=0; cnt<=0;
            end
        end
    end
endmodule
