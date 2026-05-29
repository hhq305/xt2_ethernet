// =============================================================
// sd_photo64.v
// 选题二 扩展⑥ : TF 卡 BMP(640x480x24) -> 64x64 RGB222 降采样
//
// 工作在 SD 参考时钟域 (clk = 50MHz clk_ref)。
// 流程:
//   1. 收到 start 脉冲(已同步到本域) 后, 从 start_sector 起逐扇区读取,
//      共 SEC_NUM 个扇区, 覆盖整幅 BMP。
//   2. 驱动 sd_ctrl_top 读接口 (rd_start_en/rd_sec_addr), 监听 rd_busy
//      下降沿判断单扇区读完, 监听 rd_val_en/rd_val_data(16bit=2字节) 取流。
//   3. 跳过 54 字节 BMP 头; 像素数据按 B,G,R 三字节/像素, 自底向上排列。
//   4. 列每 DEC_X 取 1, 行每 DEC_Y 取 1, 取每通道高 2 位 -> RGB222,
//      垂直翻转(BMP bottom-up) 后写入 64x64 BRAM。
//   5. 全部扇区读完 -> frame_ready 拉高一拍。
// =============================================================
`timescale 1ns/1ps

module sd_photo64 #(
    parameter [15:0] SEC_NUM = 16'd1801,   // BMP 占用扇区数 (640*480*3+54)/512 上取整
    parameter [6:0]  DEC_X   = 7'd10,      // 640/64 = 10
    parameter [6:0]  DEC_Y   = 7'd7,       // 480/64 ~ 7 (取 448 行)
    parameter [5:0]  HDR_LEN = 6'd54       // BMP 文件头+信息头 字节数
)(
    input  wire        clk,            // = clk_ref (50MHz, SD 域)
    input  wire        rst_n,
    input  wire        start,          // 单脉冲 (本域), 触发一次完整读取
    input  wire [31:0] start_sector,   // BMP 起始扇区号
    // sd_ctrl_top 读接口
    input  wire        rd_busy,
    input  wire        rd_val_en,
    input  wire [15:0] rd_val_data,
    output reg         rd_start_en,
    output reg  [31:0] rd_sec_addr,
    // 64x64 BRAM 写端口
    output reg         bram_wen,
    output reg  [11:0] bram_waddr,
    output reg  [5:0]  bram_wdata,
    // 完成标志
    output reg         frame_ready
);
    // ---------------- 扇区读取控制 FSM ----------------
    localparam S_IDLE = 2'd0,
               S_REQ  = 2'd1,   // 发起一个扇区读
               S_WAIT = 2'd2;   // 等该扇区读完 (rd_busy 下降沿)

    reg [1:0]  st;
    reg [15:0] sec_cnt;
    reg        rd_busy_d0, rd_busy_d1;
    wire       neg_rd_busy = rd_busy_d1 & ~rd_busy_d0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_busy_d0 <= 1'b0;
            rd_busy_d1 <= 1'b0;
        end else begin
            rd_busy_d0 <= rd_busy;
            rd_busy_d1 <= rd_busy_d0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st          <= S_IDLE;
            sec_cnt     <= 16'd0;
            rd_start_en <= 1'b0;
            rd_sec_addr <= 32'd0;
            frame_ready <= 1'b0;
        end else begin
            rd_start_en <= 1'b0;
            frame_ready <= 1'b0;
            case (st)
                S_IDLE: begin
                    if (start) begin
                        sec_cnt     <= 16'd0;
                        rd_sec_addr <= start_sector;
                        rd_start_en <= 1'b1;
                        st          <= S_REQ;
                    end
                end
                S_REQ: begin
                    // 等 rd_busy 起来后转入等待结束
                    if (rd_busy) st <= S_WAIT;
                end
                S_WAIT: begin
                    if (neg_rd_busy) begin
                        if (sec_cnt == SEC_NUM - 16'd1) begin
                            frame_ready <= 1'b1;
                            st          <= S_IDLE;
                        end else begin
                            sec_cnt     <= sec_cnt + 16'd1;
                            rd_sec_addr <= rd_sec_addr + 32'd1;
                            rd_start_en <= 1'b1;
                            st          <= S_REQ;
                        end
                    end
                end
                default: st <= S_IDLE;
            endcase
        end
    end

    // ---------------- 字节流拆分 (16bit -> 2 字节) ----------------
    // sd_read 输出 rd_val_data[15:8]=先收到字节, [7:0]=后收到字节
    reg        byte_pend;
    reg [7:0]  byte1_r;
    wire       proc_en   = rd_val_en | byte_pend;
    wire [7:0] proc_byte = rd_val_en ? rd_val_data[15:8] : byte1_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            byte_pend <= 1'b0;
            byte1_r   <= 8'd0;
        end else begin
            if (rd_val_en) begin
                byte1_r   <= rd_val_data[7:0];
                byte_pend <= 1'b1;
            end else begin
                byte_pend <= 1'b0;
            end
        end
    end

    // ---------------- 像素解析 + 降采样 ----------------
    reg [5:0]  hdr_cnt;        // 0..HDR_LEN-1, 头计数
    reg        hdr_done;
    reg [1:0]  pb;             // 像素内字节 0=B 1=G 2=R
    reg [7:0]  px_b, px_g;     // 暂存 B,G

    reg [9:0]  px;             // 列 0..639
    reg [6:0]  col_dec;        // 列抽样计数 0..DEC_X-1
    reg [6:0]  dst_x;          // 目标列 0..63
    reg [6:0]  row_dec;        // 行抽样计数 0..DEC_Y-1
    reg [6:0]  dst_y;          // 目标行(BMP 自底向上) 0..63

    wire is_col_sample = (col_dec == 7'd0);
    wire is_row_sample = (row_dec == 7'd0);
    wire do_sample = is_col_sample & is_row_sample & (dst_x < 7'd64) & (dst_y < 7'd64);

    // RGB888 高 2 位 -> RGB222 (R 在高位)
    wire [1:0] px_r2 = proc_byte[7:6];   // 当前字节正是 R
    wire [1:0] px_g2 = px_g[7:6];
    wire [1:0] px_b2 = px_b[7:6];
    wire [5:0] rgb222 = {px_r2, px_g2, px_b2};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hdr_cnt    <= 6'd0;
            hdr_done   <= 1'b0;
            pb         <= 2'd0;
            px_b       <= 8'd0;
            px_g       <= 8'd0;
            px         <= 10'd0;
            col_dec    <= 7'd0;
            dst_x      <= 7'd0;
            row_dec    <= 7'd0;
            dst_y      <= 7'd0;
            bram_wen   <= 1'b0;
            bram_waddr <= 12'd0;
            bram_wdata <= 6'd0;
        end else begin
            bram_wen <= 1'b0;

            // 每次启动新读取, 复位解析状态
            if (start) begin
                hdr_cnt  <= 6'd0;
                hdr_done <= 1'b0;
                pb       <= 2'd0;
                px       <= 10'd0;
                col_dec  <= 7'd0;
                dst_x    <= 7'd0;
                row_dec  <= 7'd0;
                dst_y    <= 7'd0;
            end else if (proc_en) begin
                if (!hdr_done) begin
                    // 跳过 BMP 头
                    if (hdr_cnt == HDR_LEN - 6'd1) hdr_done <= 1'b1;
                    hdr_cnt <= hdr_cnt + 6'd1;
                end else begin
                    // 像素数据 : B,G,R
                    case (pb)
                        2'd0: begin px_b <= proc_byte; pb <= 2'd1; end
                        2'd1: begin px_g <= proc_byte; pb <= 2'd2; end
                        2'd2: begin
                            pb <= 2'd0;
                            // 此拍 proc_byte = R, 完整像素就绪
                            if (do_sample) begin
                                bram_wen   <= 1'b1;
                                // 垂直翻转: 显示行 = 63 - dst_y
                                bram_waddr <= {(6'd63 - dst_y[5:0]), dst_x[5:0]};
                                bram_wdata <= rgb222;
                            end
                            // 列推进
                            if (is_col_sample && dst_x < 7'd64)
                                dst_x <= dst_x + 7'd1;
                            if (col_dec == DEC_X - 7'd1) col_dec <= 7'd0;
                            else                         col_dec <= col_dec + 7'd1;
                            // 行结束?
                            if (px == 10'd639) begin
                                px      <= 10'd0;
                                col_dec <= 7'd0;
                                dst_x   <= 7'd0;
                                if (is_row_sample && dst_y < 7'd64)
                                    dst_y <= dst_y + 7'd1;
                                if (row_dec == DEC_Y - 7'd1) row_dec <= 7'd0;
                                else                         row_dec <= row_dec + 7'd1;
                            end else begin
                                px <= px + 10'd1;
                            end
                        end
                    endcase
                end
            end
        end
    end
endmodule
