// =============================================================
// sd_photo64.v  (名称保留, 实为全分辨率流式生产者)
// 选题二 扩展⑥ : TF 卡 BMP(640x480x24) -> 全分辨率 RGB565 流式写入 FIFO
//
// 工作在 SD 参考时钟域 (clk = 50MHz clk_ref)。
// 流程:
//   1. 收到 start 脉冲(已同步到本域) 后, 从 start_sector 起逐扇区读取。
//   2. 每发起一次扇区读前检查 FIFO 已用量, 超过 ROOM_LIM 则暂缓 (反压),
//      防止 FIFO 溢出 —— 这是 "边读卡边发包" 的关键。
//   3. 跳过 54 字节 BMP 头; 像素 B,G,R 三字节/像素, 自底向上排列。
//   4. 不做降采样, 每个完整像素打包 RGB565 写入 FIFO, 直到取够 IMG_W*IMG_H 个。
//   5. 取够整图 / 扇区读尽 -> done 拉高一拍。
//   垂直翻转 (BMP bottom-up) 由 PC 端重组时处理。
// =============================================================
`timescale 1ns/1ps

module sd_photo64 #(
    parameter [9:0]  IMG_W    = 10'd640,    // 源 BMP 宽
    parameter [9:0]  IMG_H    = 10'd480,    // 源 BMP 高
    parameter [15:0] SEC_NUM  = 16'd1801,   // BMP 占用扇区数 (640*480*3+54)/512 上取整
    parameter [5:0]  HDR_LEN  = 6'd54,      // BMP 文件头+信息头 字节数
    parameter [11:0] ROOM_LIM = 12'd1792    // FIFO 已用 >= 此值则暂缓读卡 (留一扇区余量)
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
    // 异步 FIFO 写端口 (本域)
    output reg         fifo_wen,
    output reg  [15:0] fifo_wdata,
    input  wire [11:0] fifo_wused,
    // 完成脉冲 / 忙标志
    output reg         done,
    output wire        busy            // 读取进行中 (st != S_IDLE), 供 FIFO flush 门控
);
    localparam [19:0] TOTAL_PIX = IMG_W * IMG_H;   // 640*480 = 307200

    // ---------------- 扇区读取控制 FSM (带 FIFO 反压) ----------------
    localparam S_IDLE = 2'd0,
               S_ROOM = 2'd1,   // 检查 FIFO 余量, 决定是否发起下一扇区读
               S_REQ  = 2'd2,   // 发起一个扇区读
               S_WAIT = 2'd3;   // 等该扇区读完 (rd_busy 下降沿)

    reg [1:0]  st;
    assign busy = (st != S_IDLE);
    reg [15:0] sec_cnt;
    reg [19:0] pix_count;       // 已写入 FIFO 的像素数
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
            done        <= 1'b0;
        end else begin
            rd_start_en <= 1'b0;
            done        <= 1'b0;
            case (st)
                S_IDLE: begin
                    if (start) begin
                        sec_cnt     <= 16'd0;
                        rd_sec_addr <= start_sector;
                        st          <= S_ROOM;
                    end
                end
                S_ROOM: begin
                    if (pix_count >= TOTAL_PIX) begin
                        done <= 1'b1; st <= S_IDLE;          // 整图取够
                    end else if (sec_cnt == SEC_NUM) begin
                        done <= 1'b1; st <= S_IDLE;          // 扇区读尽 (异常保护)
                    end else if (fifo_wused < ROOM_LIM) begin
                        rd_start_en <= 1'b1; st <= S_REQ;    // FIFO 有空间, 发起扇区读
                    end
                end
                S_REQ: begin
                    if (rd_busy) st <= S_WAIT;
                end
                S_WAIT: begin
                    if (neg_rd_busy) begin
                        sec_cnt     <= sec_cnt + 16'd1;
                        rd_sec_addr <= rd_sec_addr + 32'd1;
                        st          <= S_ROOM;
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

    // ---------------- 像素解析 (全分辨率, 无降采样) -> FIFO ----------------
    reg [5:0]  hdr_cnt;        // 0..HDR_LEN-1, 头计数
    reg        hdr_done;
    reg [1:0]  pb;             // 像素内字节 0=B 1=G 2=R
    reg [7:0]  px_b, px_g;     // 暂存 B,G

    // RGB888 -> RGB565 (R[7:3]=5位, G[7:2]=6位, B[7:3]=5位); 当前字节正是 R
    // 注意: 蓝色必须取 5 位 [7:3], 否则 5+6+6=17 位会溢出 16 位并错位整个像素
    wire [15:0] rgb565 = {proc_byte[7:3], px_g[7:2], px_b[7:3]};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hdr_cnt    <= 6'd0;
            hdr_done   <= 1'b0;
            pb         <= 2'd0;
            px_b       <= 8'd0;
            px_g       <= 8'd0;
            fifo_wen   <= 1'b0;
            fifo_wdata <= 16'd0;
            pix_count  <= 20'd0;
        end else begin
            fifo_wen <= 1'b0;

            // 每次启动新读取, 复位解析状态
            if (start) begin
                hdr_cnt   <= 6'd0;
                hdr_done  <= 1'b0;
                pb        <= 2'd0;
                pix_count <= 20'd0;
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
                            // 此拍 proc_byte = R, 完整像素就绪 -> 写 FIFO
                            if (pix_count < TOTAL_PIX) begin
                                fifo_wen   <= 1'b1;
                                fifo_wdata <= rgb565;
                                pix_count  <= pix_count + 20'd1;
                            end
                        end
                    endcase
                end
            end
        end
    end
endmodule
