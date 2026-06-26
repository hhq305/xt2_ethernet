// =============================================================
// cam_motion_track.v
// 实时帧差运动检测：与 cam_frame_capture 使用相同的 320x240->80x60
// 抽样，对每个下采样像素做帧间灰度差，超过阈值判为运动，统计运动
// 包围盒 (xmin/xmax/ymin/ymax) 与运动像素数 (area)，并按帧输出元数据。
// - 上一帧灰度缓存使用同步读写 reg 数组 (BRAM 推断风格)，约 4800x7bit。
// - 读端 (rclk 域) 仅保留接口，视频像素实际由 cam_frame_capture/FIFO 提供，
//   故 rdata 输出 0，ren/rclear 不使用。
// =============================================================
`timescale 1ns/1ps

module cam_motion_track #(
    parameter [10:0] SRC_W      = 11'd320,
    parameter [10:0] SRC_H      = 11'd240,
    parameter [6:0]  OUT_W      = 7'd80,
    parameter [6:0]  OUT_H      = 7'd60,
    parameter [3:0]  DEC_X      = 4'd4,
    parameter [3:0]  DEC_Y      = 4'd4,
    parameter [6:0]  MOTION_THR = 7'd6,
    parameter [12:0] MIN_AREA   = 13'd10,
    parameter [12:0] MAX_AREA   = 13'd3600,
    parameter        DIAG_OVERLAY = 1'b1
)(
    input  wire        cam_pclk,
    input  wire        rst_n,
    input  wire        cmos_frame_vsync,
    input  wire        cmos_frame_href,
    input  wire        cmos_frame_valid,
    input  wire [15:0] cmos_frame_data,

    input  wire        rclk,
    input  wire        rclear,
    input  wire        ren,
    output reg  [15:0] rdata,

    output reg  [6:0]  m_xmin,
    output reg  [6:0]  m_xmax,
    output reg  [6:0]  m_ymin,
    output reg  [6:0]  m_ymax,
    output reg  [12:0] m_area,
    output reg         m_valid,
    output reg         result_tog
);
    localparam [12:0] NPIX = 13'd4800;

    // -------------------------------------------------------------
    // 上一帧灰度缓存 (BRAM 推断风格: 同步写 + 同步读, 单写口单读口)
    // -------------------------------------------------------------
    reg [6:0]  gmem [0:8191];
    reg [12:0] raddr;          // 读地址 (取上一帧灰度)
    reg [12:0] waddr;          // 写地址 (存当前帧灰度)
    reg        we_g;
    reg [6:0]  wr_d;
    reg [6:0]  prev_q;         // 上一帧该像素灰度 (raddr 后两拍有效)
    always @(posedge cam_pclk) begin
        prev_q <= gmem[raddr];
        if (we_g) gmem[waddr] <= wr_d;
    end

    // -------------------------------------------------------------
    // 抽样计数器: 复刻 cam_frame_capture 的 320x240 -> 80x60 降采样
    // -------------------------------------------------------------
    reg        vsync_d, href_d;
    wire       vsync_rise = cmos_frame_vsync & ~vsync_d;
    wire       line_start = cmos_frame_href & ~href_d;

    reg [10:0] x_cnt;
    reg [3:0]  dec_x_cnt, dec_y_cnt;
    reg [6:0]  out_x, out_y;
    reg [12:0] pix_cnt;

    wire accept = cmos_frame_valid && (dec_x_cnt == 4'd0) && (dec_y_cnt == 4'd0)
                  && (out_x < OUT_W) && (out_y < OUT_H) && (pix_cnt < NPIX);

    // 当前像素灰度 (RGB565 -> r5+g6+b5, 0..125)
    wire [4:0] r5 = cmos_frame_data[15:11];
    wire [5:0] g6 = cmos_frame_data[10:5];
    wire [4:0] b5 = cmos_frame_data[4:0];
    wire [6:0] cur_gray = {2'd0, r5} + {1'd0, g6} + {2'd0, b5};

    // -------------------------------------------------------------
    // 两级流水: stage0 采样并发起 prev 读取, stage1 比较并回写当前灰度
    // (相邻被采样像素至少相隔 DEC_X 个 pclk, 流水无冒险)
    // -------------------------------------------------------------
    reg        v0, v1;
    reg [6:0]  g0, g1;
    reg [6:0]  px0, px1, py0, py1;
    reg [12:0] a0, a1;

    wire [6:0] diff_v  = (g1 > prev_q) ? (g1 - prev_q) : (prev_q - g1);
    wire       motion  = v1 && (diff_v > MOTION_THR);

    // 运动包围盒 / 面积累加器 (本帧进行中)
    reg [6:0]  xmin_r, xmax_r, ymin_r, ymax_r;
    reg [12:0] cnt_r;

    always @(posedge cam_pclk or negedge rst_n) begin
        if (!rst_n) begin
            vsync_d    <= 1'b0;  href_d <= 1'b0;
            x_cnt      <= 11'd0; dec_x_cnt <= 4'd0; dec_y_cnt <= 4'd0;
            out_x      <= 7'd0;  out_y <= 7'd0;     pix_cnt   <= 13'd0;
            raddr      <= 13'd0; waddr <= 13'd0;    we_g <= 1'b0; wr_d <= 7'd0;
            v0 <= 1'b0; v1 <= 1'b0;
            g0 <= 7'd0; g1 <= 7'd0;
            px0<= 7'd0; px1<= 7'd0; py0<= 7'd0; py1<= 7'd0;
            a0 <= 13'd0; a1 <= 13'd0;
            xmin_r <= OUT_W-7'd1; xmax_r <= 7'd0;
            ymin_r <= OUT_H-7'd1; ymax_r <= 7'd0; cnt_r <= 13'd0;
            m_xmin <= 7'd0; m_xmax <= 7'd0; m_ymin <= 7'd0; m_ymax <= 7'd0;
            m_area <= 13'd0; m_valid <= 1'b0; result_tog <= 1'b0;
        end else begin
            vsync_d <= cmos_frame_vsync;
            href_d  <= cmos_frame_href;
            we_g    <= 1'b0;

            // ---- 流水推进: stage0 -> stage1 ----
            v0  <= 1'b0;
            v1  <= v0;  g1 <= g0;  px1 <= px0;  py1 <= py0;  a1 <= a0;

            // ---- stage1: prev_q 与 g1/px1/py1/a1 此拍有效, 比较并回写 ----
            if (v1) begin
                we_g  <= 1'b1;
                waddr <= a1;
                wr_d  <= g1;
            end
            if (motion) begin
                if (px1 < xmin_r) xmin_r <= px1;
                if (px1 > xmax_r) xmax_r <= px1;
                if (py1 < ymin_r) ymin_r <= py1;
                if (py1 > ymax_r) ymax_r <= py1;
                if (cnt_r != 13'h1fff) cnt_r <= cnt_r + 1'b1;
            end

            if (vsync_rise) begin
                // ---- 帧结束: 锁存上一帧结果并复位累加器/抽样计数 ----
                m_area     <= cnt_r;
                m_valid    <= (cnt_r >= MIN_AREA) && (cnt_r <= MAX_AREA);
                m_xmin     <= xmin_r;
                m_xmax     <= xmax_r;
                m_ymin     <= ymin_r;
                m_ymax     <= ymax_r;
                result_tog <= ~result_tog;
                xmin_r <= OUT_W-7'd1; xmax_r <= 7'd0;
                ymin_r <= OUT_H-7'd1; ymax_r <= 7'd0; cnt_r <= 13'd0;
                x_cnt  <= 11'd0; dec_x_cnt <= 4'd0; dec_y_cnt <= 4'd0;
                out_x  <= 7'd0;  out_y <= 7'd0; pix_cnt <= 13'd0;
            end else begin
                if (line_start) begin
                    x_cnt     <= 11'd0;
                    dec_x_cnt <= 4'd0;
                    out_x     <= 7'd0;
                end

                if (cmos_frame_valid) begin
                    // ---- stage0: 被采样像素, 发起上一帧灰度读取 ----
                    if (accept) begin
                        raddr  <= pix_cnt;
                        v0     <= 1'b1;
                        g0     <= cur_gray;
                        px0    <= out_x;
                        py0    <= out_y;
                        a0     <= pix_cnt;
                        out_x  <= out_x + 1'b1;
                        pix_cnt<= pix_cnt + 1'b1;
                    end

                    // ---- 抽样计数推进 ----
                    if (x_cnt == SRC_W - 1'b1) begin
                        x_cnt     <= 11'd0;
                        dec_x_cnt <= 4'd0;
                        out_x     <= 7'd0;
                        if (dec_y_cnt == 4'd0 && out_y < OUT_H)
                            out_y <= out_y + 1'b1;     // 该行为被采样行, 行尾 out_y++
                        dec_y_cnt <= (dec_y_cnt == DEC_Y - 1'b1) ? 4'd0 : dec_y_cnt + 1'b1;
                    end else begin
                        x_cnt     <= x_cnt + 1'b1;
                        dec_x_cnt <= (dec_x_cnt == DEC_X - 1'b1) ? 4'd0 : dec_x_cnt + 1'b1;
                    end
                end
            end
        end
    end

    // -------------------------------------------------------------
    // 读端 (rclk 域): 视频像素由外部 FIFO 提供, 此处仅保留接口
    // -------------------------------------------------------------
    always @(posedge rclk or negedge rst_n) begin
        if (!rst_n) rdata <= 16'd0;
        else        rdata <= 16'd0;
    end
    // ren/rclear 在当前数据通路未使用 (视频走 cam_frame_capture/cam_fifo)
    wire _unused_rd = ren | rclear;

endmodule
