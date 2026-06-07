`timescale 1ns / 1ps
//********************************************************************** 
// -------------------------------------------------------------------
// >>>>>>>>>>>>>>>>>>>>>>>Copyright Notice<<<<<<<<<<<<<<<<<<<<<<<<<<<< 
// ------------------------------------------------------------------- 
//             /\ --------------- 
//            /  \ ------------- 
//           / /\ \ -----------
//          / /  \ \ ---------
//         / /    \ \ ------- 
//        / /      \ \ ----- `
//       / /_ _ _   \ \ --- 
//      /_ _ _ _ _\  \_\ -
//*********************************************************************** 
// Author: suluyang 
// Email:luyang.su@anlogic.com 
// Date:2020/11/17 
// Description: 
// 2022/03/10:  修改时钟结构
//              简化约束
//              添加 soft fifo 
//              添加 debug 功能
// 2023/02/16 :add dynamic_local_ip_address port
// 
// web：www.anlogic.com 
//------------------------------------------------------------------- 
//*********************************************************************/
    `define UDP_LOOP_BACK
//  `define DEBUG_UDP
// =============================================================
// 临时诊断开关 : 硬编码 LED 测试 (绕过 cmd_decode / UDP 协议栈)
//   2026-05-28 已验证: 不按 key1 全灭, 按 key1 全亮
//   -> 引脚 A4/A3/C10/B12 + active-high 极性 完全正确
//   -> 关掉这条 `define, 走正常 led = led_eth8[3:0] 路径
// =============================================================
//  `define LED_HARDCODE_TEST
// =============================================================
// 临时诊断开关 : UDP 路径分阶段 sticky 探针
//   LED1 = 任何 UDP 字节到达 app 层  (app_rx_data_valid 脉冲过)
//   LED2 = MAGIC0 (0xA5) 字节出现过
//   LED3 = MAGIC0 之后接 MAGIC1 (0x5A) 出现过 -> 协议头识别成功
//   LED4 = CMD_LED_SET (0x01) 帧完整解析过 (led_o 实际被写入)
//   按 key1 清零重测 (key1 active-low, 按下时复位探针)
//   2026-05-28 已验证: 4 LED 全亮 -> UDP 全程路径正常
// =============================================================
//  `define UDP_PATH_PROBE
// =============================================================
// 终极诊断 : RGMII 物理层探针 (绕过所有 PLL/TEMAC/协议栈)
//   LED1 = phy1_rgmii_rx_ctl 出现过 1 (sticky)
//   LED2 = phy1_rgmii_rx_clk toggle 过 (sticky)
//   LED3 = clk_25 toggle 过 (sticky)
//   LED4 = ~key1 (按 KEY1 全亮, 实时)
//   按 KEY2 清零重测
//   2026-05-28 已验证: port=1 时 LED2 亮 -> UDP 路径全通, 关闭探针看真实 led_eth8
// =============================================================
//  `define RGMII_PHYS_PROBE
// =============================================================
// 诊断 LAST_BYTE_PROBE : LED 直接显示 app_rx_data 最新字节低 4 bit
//   绕过 cmd_decode FSM, 判断是协议栈卡死 还是 cmd_decode 卡死.
//   每发 led 0xX, LED 末字节应跟随变化 (但末尾可能被 0x00 padding 覆盖)
// =============================================================
//  `define LAST_BYTE_PROBE
// =============================================================
// SD 照片诊断 : LED1=sd_init_done LED2=req到达 LED3=读卡完成 LED4=发送启动
//   (按 KEY1 清零 sticky). 定位 SD 照片卡在哪一阶段.
//   照片功能已验证通过, 平时关闭, 让 LED 恢复 PC 命令控制.
// =============================================================
//  `define SD_PHOTO_PROBE
// =============================================================
// 图像上传诊断 : 判断 sendvga_bars/sendvga 的 CMD_IMG_FRAME 是否到达
//   LED1 = 任意 UDP 字节到达 app 层
//   LED2 = 解析到 A5 5A 10 图像包头
//   LED3 = 进入图像 payload 的 FLAG 字节
//   LED4 = 看到最终包 FLAG[0]=1
// =============================================================
//  `define IMG_RX_PROBE
module udp_transmit_test(
        input               key1,
        input               key2,
        input               clk_25,//== 50M 
        
        input               phy1_rgmii_rx_clk,
        input               phy1_rgmii_rx_ctl,
        input [3:0]         phy1_rgmii_rx_data,
                                
        output wire         phy1_rgmii_tx_clk,
        output wire         phy1_rgmii_tx_ctl,
        output wire [3:0]   phy1_rgmii_tx_data,
        output rd_en,
        
        output [3:0]        led,
        output		 	   VGA_HSYNC,
	    output 		 	   VGA_VSYNC,
	    output [11:0]      VGA_D,
        // 选题二 扩展① : 4 位动态扫描数码管
        output [6:0]       seg,
        output [3:0]       seg_en,
        // 选题二 扩展⑤ : OV5640 摄像头接口
        input              cam_pclk,
        input              cam_vsync,
        input              cam_href,
        input  [7:0]       cam_data,
        output             cam_rst_n,
        output             cam_pwdn,
        output             cam_scl,
        inout              cam_sda,
        // 选题二 扩展⑥ : TF 卡 (SD SPI 模式)
        input              sd_miso,
        output             sd_clk,
        output             sd_cs,
        output             sd_mosi,
        
    `ifdef DEBUG_UDP
        output wire         debug_out,
    `endif
        output wire         phy_reset
);
parameter  DEVICE             = "EG4";//"PH1","EG4"
parameter  LOCAL_UDP_PORT_NUM = 16'h0001;       
parameter  LOCAL_IP_ADDRESS   = 32'hc0a8f001;       
parameter  LOCAL_MAC_ADDRESS  = 48'h001122334455;  // 00:11:22:33:44:55  (unicast, 第一字节 LSB=0)
parameter  DST_UDP_PORT_NUM   = 16'h0002;       
parameter  DST_IP_ADDRESS     = 32'hc0a8f002;
/*------------------------------*/
/*------------------------------*/

wire         app_rx_data_valid; 
wire [7:0]   app_rx_data;       
wire [15:0]  app_rx_data_length;
wire [15:0]  app_rx_port_num;

wire         udp_tx_ready;
wire         app_tx_ack;
wire         app_tx_data_request;
wire         app_tx_data_valid; 
wire [7:0]   app_tx_data;       
wire  [15:0] udp_data_length;

wire  [7:0]  tpg_data           ;
wire         tpg_data_valid     ;
wire  [15:0] tpg_data_udp_length;

//temac signals
wire        tx_stop;
wire [7:0]  tx_ifg_val;
wire        pause_req;
wire [15:0] pause_val;
wire [47:0] pause_source_addr;
wire [47:0] unicast_address;
wire [19:0] mac_cfg_vector;  

wire        temac_tx_ready;
wire        temac_tx_valid;
wire [7:0]  temac_tx_data; 
wire        temac_tx_sof;
wire        temac_tx_eof;
            
wire        temac_rx_ready;
wire        temac_rx_valid;
wire [7:0]  temac_rx_data; 
wire        temac_rx_sof;
wire        temac_rx_eof;

wire        rx_correct_frame;
wire        rx_error_frame;
wire [1:0]  TRI_speed;

assign TRI_speed = 2'b10;//千兆2'b10 百兆2'b01 十兆2'b00

wire        rx_clk_int; 
wire        rx_clk_en_int;
wire        tx_clk_int; 
wire        tx_clk_en_int;

wire        temac_clk;
wire        udp_clk;
wire        temac_clk90;
wire        clk_125_out;
wire        clk_12_5_out;
wire        clk_1_25_out;
wire        rx_valid;   
wire [7:0]  rx_data;    
wire [7:0]  tx_data;
wire        tx_valid;
wire        tx_rdy;         
wire        tx_collision;   
wire        tx_retransmit;

wire        reset,reset_reg;
wire        clk_25_out;
reg [7:0]   phy_reset_cnt='d0;
reg [7:0]   soft_reset_cnt=8'hff;
always @(posedge clk_25_out or negedge key1)
begin
    if(~key1)
        phy_reset_cnt<='d0;
    else if(phy_reset_cnt < 255)
        phy_reset_cnt<= phy_reset_cnt+1;
    else
        phy_reset_cnt<=phy_reset_cnt;
end

assign  reset = ~key1 || reset_reg || (soft_reset_cnt != 'd0);
assign  phy_reset = phy_reset_cnt[7];


always @(posedge udp_clk or negedge key1)
begin
    if(~key1)
        soft_reset_cnt<=8'hff;
    else if(soft_reset_cnt > 0)
        soft_reset_cnt<= soft_reset_cnt-1;
    else
        soft_reset_cnt<=soft_reset_cnt;
end
`ifdef DEBUG_UDP
//=========================================================
//debug signal
//=========================================================
reg       debug_app_rx_data_valid   ;
reg [7:0] debug_app_rx_data         ;
reg       debug_app_tx_data_valid   ;
reg [7:0] debug_app_tx_data         ;
reg       debug_temac_tx_valid      ;
reg [7:0] debug_temac_tx_data       ;
reg       debug_temac_rx_valid      ;
reg [7:0] debug_temac_rx_data       ;
reg       debug_rx_valid            ;
reg [7:0] debug_rx_data             ;
reg       debug_tx_valid            ;
reg [7:0] debug_tx_data             ;

reg [31:0] debug_frame_temac_cnt_rx ;
reg [31:0] debug_frame_app_cnt_rx   ;
reg [31:0] debug_frame_fifo_cnt_rx  ;
reg [31:0] debug_frame_temac_cnt_tx ;
reg [31:0] debug_frame_app_cnt_tx   ;
reg [31:0] debug_frame_fifo_cnt_tx  ;

wire udp_debug_out;
// wire debug_out;
assign debug_out =   debug_app_rx_data_valid
                   | debug_app_rx_data      
                   | debug_app_tx_data_valid
                   | debug_app_tx_data      
                   | debug_temac_tx_valid   
                   | debug_temac_tx_data    
                   | debug_temac_rx_valid   
                   | debug_temac_rx_data    
                   | debug_rx_valid         
                   | debug_rx_data          
                   | debug_tx_valid       
                   | debug_tx_data
                   | debug_frame_temac_cnt_rx
                   | debug_frame_app_cnt_rx  
                   | debug_frame_fifo_cnt_rx 
                   | debug_frame_temac_cnt_tx
                   | debug_frame_app_cnt_tx  
                   | debug_frame_fifo_cnt_tx 
                   | udp_debug_out;

reg       debug_0;
reg [7:0] debug_1;
reg       debug_2;
reg [7:0] debug_3;
reg       debug_4;
reg [7:0] debug_5;
reg       debug_6;
reg [7:0] debug_7;
reg       debug_8;
reg [7:0] debug_9;
reg       debug_a;
reg [7:0] debug_b;

reg       debug_0_d;
reg [7:0] debug_1_d;
reg       debug_2_d;
reg [7:0] debug_3_d;
reg       debug_4_d;
reg [7:0] debug_5_d;
reg       debug_6_d;
reg [7:0] debug_7_d;
reg       debug_8_d;
reg [7:0] debug_9_d;
reg       debug_a_d;
reg [7:0] debug_b_d;

always @(posedge temac_clk or negedge key1)
begin
    if(~key1)
    begin
        debug_app_rx_data_valid <= 'd0;
        debug_app_rx_data       <= 'd0;
        debug_app_tx_data_valid <= 'd0;
        debug_app_tx_data       <= 'd0;
        debug_temac_tx_valid    <= 'd0;
        debug_temac_tx_data     <= 'd0;
        debug_temac_rx_valid    <= 'd0;
        debug_temac_rx_data     <= 'd0;
        debug_rx_valid          <= 'd0;
        debug_rx_data           <= 'd0;
        debug_tx_valid          <= 'd0;
        debug_tx_data           <= 'd0;
    end
    else
    begin
        debug_app_rx_data_valid <=debug_0_d;
        debug_app_rx_data       <=debug_1_d;
        debug_app_tx_data_valid <=debug_2_d;
        debug_app_tx_data       <=debug_3_d;
        debug_temac_tx_valid    <=debug_4_d;
        debug_temac_tx_data     <=debug_5_d;
        debug_temac_rx_valid    <=debug_6_d;
        debug_temac_rx_data     <=debug_7_d;
        debug_rx_valid          <=debug_8_d;
        debug_rx_data           <=debug_9_d;
        debug_tx_valid          <=debug_a_d;
        debug_tx_data           <=debug_b_d;
    end
end

always @(posedge temac_clk or negedge key1)
begin
    if(~key1)
    begin
        debug_0_d <= 'd0;
        debug_1_d <= 'd0;
        debug_2_d <= 'd0;
        debug_3_d <= 'd0;
        debug_4_d <= 'd0;
        debug_5_d <= 'd0;
        debug_6_d <= 'd0;
        debug_7_d <= 'd0;
        debug_8_d <= 'd0;
        debug_9_d <= 'd0;
        debug_a_d <= 'd0;
        debug_b_d <= 'd0;
    end
    else
    begin
        debug_0_d <= debug_0 ;
        debug_1_d <= debug_1 ;
        debug_2_d <= debug_2 ;
        debug_3_d <= debug_3 ;
        debug_4_d <= debug_4 ;
        debug_5_d <= debug_5 ;
        debug_6_d <= debug_6 ;
        debug_7_d <= debug_7 ;
        debug_8_d <= debug_8 ;
        debug_9_d <= debug_9 ;
        debug_a_d <= debug_a ;
        debug_b_d <= debug_b ;
    end
end

always @(posedge temac_clk or negedge key1)
begin
    if(~key1)
    begin
        debug_0 <= 'd0;
        debug_1 <= 'd0;
        debug_2 <= 'd0;
        debug_3 <= 'd0;
        debug_4 <= 'd0;
        debug_5 <= 'd0;
        debug_6 <= 'd0;
        debug_7 <= 'd0;
        debug_8 <= 'd0;
        debug_9 <= 'd0;
        debug_a <= 'd0;
        debug_b <= 'd0;
    end
    else
    begin
        debug_0 <= app_rx_data_valid   ;
        debug_1 <= app_rx_data         ;
        debug_2 <= app_tx_data_valid   ;
        debug_3 <= app_tx_data         ;
        debug_4 <= !temac_tx_valid     ;
        debug_5 <= temac_tx_data       ;
        debug_6 <= !temac_rx_valid     ;
        debug_7 <= temac_rx_data       ;
        debug_8 <= rx_valid            ;
        debug_9 <= rx_data             ;
        debug_a <= tx_valid            ;
        debug_b <= tx_data             ;
    end
end

always @(posedge temac_clk or negedge key1)
begin
    if(~key1)
    begin
        debug_frame_fifo_cnt_rx <= 'd0;
    end
    else if( !debug_6_d && debug_6)
    begin
        debug_frame_fifo_cnt_rx <= debug_frame_fifo_cnt_rx + 'd1;
    end
    else
    begin
        debug_frame_fifo_cnt_rx <=debug_frame_fifo_cnt_rx;
    end
end

always @(posedge temac_clk or negedge key1)
begin
    if(~key1)
    begin
        debug_frame_fifo_cnt_tx <= 'd0;
    end
    else if( !debug_4_d && debug_4)
    begin
        debug_frame_fifo_cnt_tx <= debug_frame_fifo_cnt_tx + 'd1;
    end
    else
    begin
        debug_frame_fifo_cnt_tx <=debug_frame_fifo_cnt_tx;
    end
end


always @(posedge temac_clk or negedge key1)
begin
    if(~key1)
    begin
        debug_frame_app_cnt_rx  <= 'd0;
    end
    else if( !debug_0_d && debug_0)
    begin
        debug_frame_app_cnt_rx  <= debug_frame_app_cnt_rx + 'd1;
    end
    else
    begin
        debug_frame_app_cnt_rx  <=debug_frame_app_cnt_rx;
    end
end

always @(posedge temac_clk or negedge key1)
begin
    if(~key1)
    begin
        debug_frame_app_cnt_tx  <= 'd0;
    end
    else if( !debug_2_d && debug_2)
    begin
        debug_frame_app_cnt_tx  <= debug_frame_app_cnt_tx + 'd1;
    end
    else
    begin
        debug_frame_app_cnt_tx  <=debug_frame_app_cnt_tx;
    end
end

always @(posedge temac_clk or negedge key1)
begin
    if(~key1)
    begin
        debug_frame_temac_cnt_rx    <= 'd0;
    end
    else if( !debug_8_d && debug_8)
    begin
        debug_frame_temac_cnt_rx    <= debug_frame_temac_cnt_rx + 'd1;
    end
    else
    begin
        debug_frame_temac_cnt_rx    <=debug_frame_temac_cnt_rx;
    end
end

always @(posedge temac_clk or negedge key1)
begin
    if(~key1)
    begin
        debug_frame_temac_cnt_tx    <= 'd0;
    end
    else if( !debug_a_d && debug_a)
    begin
        debug_frame_temac_cnt_tx    <= debug_frame_temac_cnt_tx + 'd1;
    end
    else
    begin
        debug_frame_temac_cnt_tx    <=debug_frame_temac_cnt_tx;
    end
end

`endif

//============================================================
// 参数配置逻辑
//============================================================
//需配置的客户端接口（初始默认值）
assign  tx_stop    = 1'b0;
assign  tx_ifg_val = 8'h00;
assign  pause_req  = 1'b0;
assign  pause_val  = 16'h0;
assign  pause_source_addr = 48'h5af1f2f3f4f5;
// assign  unicast_address   = 48'hab8967452301;
assign  unicast_address   = {   LOCAL_MAC_ADDRESS[7:0],
                                LOCAL_MAC_ADDRESS[15:8],
                                LOCAL_MAC_ADDRESS[23:16],
                                LOCAL_MAC_ADDRESS[31:24],
                                LOCAL_MAC_ADDRESS[39:32],
                                LOCAL_MAC_ADDRESS[47:40]
                            };


assign  mac_cfg_vector    = {1'b0,2'b00,TRI_speed,8'b00000010,7'b0000010}; //地址过滤模式、流控配置、速度配置、接收器配置、发送器配置
//assign  mac_cfg_vector    = {1'b0,2'b00,2'b10,8'b00000010,7'b0000010}; //地址过滤模式、流控配置、速度配置、接收器配置、发送器配置
//assign  mac_cfg_vector    = {1'b0,2'b00,2'b01,8'b00000010,7'b0000010}; //地址过滤模式、流控配置、速度配置、接收器配置、发送器配置
//assign  mac_cfg_vector    = {1'b0,2'b00,2'b00,8'b00000010,7'b0000010}; //地址过滤模式、流控配置、速度配置、接收器配置、发送器配置

//-----------------------------------------------------
//test dynamic_local_ip_address
//-----------------------------------------------------

// 上电自动复位 (POR): 开机后自动拉低 rst_n 约 1ms 再释放, 无需手按 KEY2
reg [15:0] por_cnt = 16'd0;
reg        por_n   = 1'b0;
always @(posedge udp_clk) begin
    if (por_cnt != 16'hFFFF) por_cnt <= por_cnt + 1'b1;
    por_n <= (por_cnt == 16'hFFFF);
end
wire rst_n = key2 & por_n;    // KEY2 手动复位 + 上电自动复位 (active-low)

// 固定本机 IP/端口，裁剪原 demo 的动态 IP 扫描计数器，节省 MSlice。
wire [31:0] input_local_ip_address       = LOCAL_IP_ADDRESS;
wire        input_local_ip_address_valid = 1'b1;

// =============================================================
// 选题二 基础要求 ① : UDP 命令解析 → LED  (替换原 demo 的 IP-LED)
// =============================================================
wire [7:0]  led_eth8;
wire [31:0] seg_bcd_eth;
wire [1:0]  proc_mode_eth;
wire        img_req_pulse;
wire        cam_en;
wire        sd_photo_req;          // 扩展⑥ : udp_clk 域单脉冲
wire [31:0] sd_sec_addr_cmd;       // 扩展⑥ : BMP 起始扇区号
// 基础要求 ①：恢复 PC UDP 命令控制 LED / 数码管。
// cmd_decode 是轻量字节流解析器；相比 SDRAM/VGA 主路径资源占用很小，
// 可以保留，为后续“全部基础功能 + 扩展 2”继续扩展命令入口。
cmd_decode u_cmd_decode (
    .clk             (udp_clk),
    .rst_n           (rst_n),
    .rx_data         (app_rx_data),
    .rx_valid        (app_rx_data_valid),
    .rx_length       (app_rx_data_length),
    .led_o           (led_eth8),
    .seg_bcd_o       (seg_bcd_eth),
    .proc_mode_o     (proc_mode_eth),
    .img_req_pulse_o (img_req_pulse),
    .cam_en_o        (cam_en),
    .sd_photo_req_o  (sd_photo_req),
    .sd_sec_addr_o   (sd_sec_addr_cmd),
    .ack_pulse_o     ()
);
// === LED 映射 (引脚已确认) ===
//  led[0] = A4  = 物理 LED1
//  led[1] = A3  = 物理 LED2
//  led[2] = C10 = 物理 LED3
//  led[3] = B12 = 物理 LED4
// PC 通过 CMD_LED_SET (0x01) 下发 1 字节, 低 4 bit 控制 4 颗 LED
`ifdef LED_HARDCODE_TEST
// 诊断: 不按 key1 全灭, 按 key1 全亮 (key1 active-low, A2 PULLUP)
assign led = ~key1 ? 4'b1111 : 4'b0000;
`else
`ifdef LAST_BYTE_PROBE
// =============================================================
// 对比模式: 同屏比较 cmd_decode 输出 vs raw last_byte
//   不按 KEY1 (默认): LED = led_eth8[3:0]   (cmd_decode 决出的 LED 值)
//   按下 KEY1       : LED = last_byte[3:0]  (协议栈送到 app 的最新一字节)
// 如果按下 KEY1 看到的值跟着命令变, 但不按看到的值卡死, 就是 cmd_decode 的 bug.
// 按 KEY2 清零探针.
// =============================================================
reg [7:0] last_byte;
always @(posedge udp_clk or negedge key2) begin
    if (!key2) begin
        last_byte <= 8'h00;
    end else if (app_rx_data_valid) begin
        last_byte <= app_rx_data;
    end
end
assign led = (~key1) ? last_byte[3:0] : led_eth8[3:0];
`else
`ifdef RGMII_PHYS_PROBE
// =============================================================
// 协议栈探针 (注意: 不能读 phy1_rgmii_tx_*, 会破坏 ODDR-PAD 直连)
//   LED1 = temac_rx_valid 出现过 1 (sticky) -> TEMAC 解出过完整 MAC 帧
//   LED2 = app_rx_data_valid 出现过 1 (sticky) -> 协议栈解出过 UDP payload
//   LED3 = temac_tx_valid 出现过 1 (sticky) -> TEMAC 在送出帧
//   LED4 = pll_locked 状态 (实时, ~reset_reg)
// 按 key2 清零探针
// =============================================================
reg phys_temac_rx_seen;     // LED1
reg phys_app_rx_seen;       // LED2
reg phys_temac_tx_seen;     // LED3
always @(posedge udp_clk or negedge key2) begin
    if (!key2) phys_temac_rx_seen <= 1'b0;
    else if (temac_rx_valid) phys_temac_rx_seen <= 1'b1;
end
always @(posedge udp_clk or negedge key2) begin
    if (!key2) phys_app_rx_seen <= 1'b0;
    else if (app_rx_data_valid) phys_app_rx_seen <= 1'b1;
end
always @(posedge udp_clk or negedge key2) begin
    if (!key2) phys_temac_tx_seen <= 1'b0;
    else if (temac_tx_valid) phys_temac_tx_seen <= 1'b1;
end
assign led = {~reset_reg, phys_temac_tx_seen, phys_app_rx_seen, phys_temac_rx_seen};
`else
`ifdef UDP_PATH_PROBE
// =============================================================
// UDP 路径分阶段 sticky 探针
// 按 key1 (active-low, A2 PULLUP) 清零重测; 否则上电后随各阶段亮灯
// =============================================================
reg probe_any_byte;     // LED1: 任意 UDP 字节到达 app 层
reg probe_magic0;       // LED2: 出现过 0xA5
reg probe_magic1;       // LED3: MAGIC0 后紧跟 0x5A (头匹配成功)
reg probe_led_cmd;      // LED4: CMD_LED_SET 完整帧解析过

// 与 cmd_decode 并行的小状态机, 仅用于探测 (不影响主逻辑)
reg [2:0] probe_st;
localparam P_IDLE=3'd0, P_GOT_M0=3'd1, P_GOT_M1=3'd2,
           P_GOT_CMD=3'd3, P_GOT_LH=3'd4, P_GOT_LL=3'd5;
reg [7:0] probe_cmd_r;

always @(posedge udp_clk or negedge key1) begin
    if (!key1) begin
        probe_any_byte <= 1'b0;
        probe_magic0   <= 1'b0;
        probe_magic1   <= 1'b0;
        probe_led_cmd  <= 1'b0;
        probe_st       <= P_IDLE;
        probe_cmd_r    <= 8'h00;
    end else begin
        if (app_rx_data_valid) begin
            probe_any_byte <= 1'b1;
            if (app_rx_data == 8'hA5) probe_magic0 <= 1'b1;
            case (probe_st)
                P_IDLE   : probe_st <= (app_rx_data == 8'hA5) ? P_GOT_M0 : P_IDLE;
                P_GOT_M0 : if (app_rx_data == 8'h5A) begin
                                probe_magic1 <= 1'b1;
                                probe_st     <= P_GOT_M1;
                           end else if (app_rx_data == 8'hA5) begin
                                probe_st <= P_GOT_M0;   // 连续 0xA5
                           end else begin
                                probe_st <= P_IDLE;
                           end
                P_GOT_M1 : begin probe_cmd_r <= app_rx_data; probe_st <= P_GOT_CMD; end
                P_GOT_CMD: probe_st <= P_GOT_LH;            // 跳过 LEN_HI
                P_GOT_LH : probe_st <= P_GOT_LL;            // 跳过 LEN_LO
                P_GOT_LL : begin                            // 第一个 payload byte
                                if (probe_cmd_r == 8'h01)   // CMD_LED_SET
                                    probe_led_cmd <= 1'b1;
                                probe_st <= P_IDLE;
                           end
                default  : probe_st <= P_IDLE;
            endcase
        end
    end
end

assign led = {probe_led_cmd, probe_magic1, probe_magic0, probe_any_byte};
`else
`ifdef IMG_RX_PROBE
// =============================================================
// 图像上传计数探针 (按 KEY1 清零)
//   LED 以二进制粗略显示已接收 RGB 像素数量:
//   LED1 >= 10000, LED2 >= 30000, LED3 >= 60000, LED4 >= 76800
//   如果 LED4 亮而 VGA 仍红色，说明包到达 img_rx_fb，但 sdram_img_fb 没有接收写入。
// =============================================================
reg [20:0] imgp_pix_cnt;
reg        imgp_in_frame;
reg [1:0]  imgp_rgb_phase;
reg [2:0]  imgp_st;
reg [7:0]  imgp_cmd;
reg [15:0] imgp_len;
reg [15:0] imgp_payload_left;
localparam IP_IDLE=3'd0, IP_M0=3'd1, IP_CMD=3'd2, IP_LH=3'd3,
           IP_LL=3'd4, IP_FLAG=3'd5, IP_SKIP=3'd6;

always @(posedge udp_clk or negedge key1) begin
    if (!key1) begin
        imgp_pix_cnt      <= 21'd0;
        imgp_in_frame     <= 1'b0;
        imgp_rgb_phase    <= 2'd0;
        imgp_st           <= IP_IDLE;
        imgp_cmd          <= 8'h00;
        imgp_len          <= 16'd0;
        imgp_payload_left <= 16'd0;
    end else if (app_rx_data_valid) begin
        case (imgp_st)
            IP_IDLE: imgp_st <= (app_rx_data == 8'hA5) ? IP_M0 : IP_IDLE;
            IP_M0: begin
                if (app_rx_data == 8'h5A)
                    imgp_st <= IP_CMD;
                else
                    imgp_st <= (app_rx_data == 8'hA5) ? IP_M0 : IP_IDLE;
            end
            IP_CMD: begin
                imgp_cmd <= app_rx_data;
                imgp_st <= IP_LH;
            end
            IP_LH: begin
                imgp_len[15:8] <= app_rx_data;
                imgp_st <= IP_LL;
            end
            IP_LL: begin
                imgp_len[7:0] <= app_rx_data;
                imgp_payload_left <= {imgp_len[15:8], app_rx_data};
                if (imgp_cmd == 8'h10 && {imgp_len[15:8], app_rx_data} >= 16'd5)
                    imgp_st <= IP_FLAG;
                else
                    imgp_st <= IP_SKIP;
            end
            IP_FLAG: begin
                if (app_rx_data[0]) begin
                    imgp_in_frame <= 1'b0;
                end else begin
                    imgp_in_frame <= 1'b1;
                    imgp_rgb_phase <= 2'd0;
                end
                imgp_payload_left <= imgp_payload_left - 1'b1;
                imgp_st <= IP_SKIP;
            end
            IP_SKIP: begin
                if (imgp_in_frame && imgp_payload_left > 16'd0) begin
                    if (imgp_rgb_phase == 2'd2) begin
                        imgp_pix_cnt <= imgp_pix_cnt + 1'b1;
                        imgp_rgb_phase <= 2'd0;
                    end else begin
                        imgp_rgb_phase <= imgp_rgb_phase + 1'b1;
                    end
                end
                if (imgp_payload_left <= 16'd1)
                    imgp_st <= IP_IDLE;
                else
                    imgp_payload_left <= imgp_payload_left - 1'b1;
            end
            default: imgp_st <= IP_IDLE;
        endcase
    end
end
assign led = {imgp_pix_cnt >= 21'd76800, imgp_pix_cnt >= 21'd60000,
              imgp_pix_cnt >= 21'd30000, imgp_pix_cnt >= 21'd10000};
`else
`ifdef SD_PHOTO_PROBE
// =============================================================
// SD 照片分阶段 sticky 探针 (按 KEY1 清零)
//   LED1 = sd_init_done (实时): SD 卡 SPI 初始化成功
//   LED2 = 并行解析到 A5 5A 50: CMD_SD_PHOTO 字节到达 app 层
//   LED3 = sd_photo_req 出现过: cmd_decode 解析出命令
//   LED4 = frame_ready 出现过: 读卡 + 降采样完成
// 判读: LED2灭=字节没到; LED2亮LED3灭=cmd_decode没解析; LED3亮LED4灭=读卡没完成
// =============================================================
reg [1:0] sdp_st;          // 0=idle 1=gotA5 2=got5A
reg       sdp_hdr_seen;    // LED2: 看到 A5 5A 50
reg       sdp_req_seen;    // LED3: cmd_decode sd_photo_req
reg       sdp_frame_seen;  // LED4: frame_ready
always @(posedge udp_clk or negedge key1) begin
    if (!key1) begin
        sdp_st         <= 2'd0;
        sdp_hdr_seen   <= 1'b0;
        sdp_req_seen   <= 1'b0;
        sdp_frame_seen <= 1'b0;
    end else begin
        if (sd_photo_req)    sdp_req_seen   <= 1'b1;
        if (frame_ready_udp) sdp_frame_seen <= 1'b1;
        if (app_rx_data_valid) begin
            case (sdp_st)
                2'd0: sdp_st <= (app_rx_data == 8'hA5) ? 2'd1 : 2'd0;
                2'd1: sdp_st <= (app_rx_data == 8'h5A) ? 2'd2 :
                                (app_rx_data == 8'hA5) ? 2'd1 : 2'd0;
                2'd2: begin
                          if (app_rx_data == 8'h50) sdp_hdr_seen <= 1'b1;
                          sdp_st <= (app_rx_data == 8'hA5) ? 2'd1 : 2'd0;
                      end
                default: sdp_st <= 2'd0;
            endcase
        end
    end
end
assign led = {sdp_frame_seen, sdp_req_seen, sdp_hdr_seen, sd_init_done};
`else
assign led = led_eth8[3:0];
`endif
`endif
`endif
`endif
`endif
`endif

// 基础要求 ①：PC 命令控制 4 位数码管显示。
seg_scan u_seg_scan (
    .clk    (clk_25_out),
    .rst_n  (rst_n),
    .bcd_in (seg_bcd_eth[15:0]),
    .seg    (seg),
    .en     (seg_en)
);

reg [15:0] input_local_udp_port_num;
reg        input_local_udp_port_num_valid;

// 协议栈实测硬编码监听 port 1, 这里只是做样子 (不影响实际行为)
always@(posedge udp_clk or posedge reset) begin
    if(reset) begin
        input_local_udp_port_num       <= LOCAL_UDP_PORT_NUM;
        input_local_udp_port_num_valid <= 1'b0;
    end else begin
        input_local_udp_port_num       <= LOCAL_UDP_PORT_NUM;
        input_local_udp_port_num_valid <= 1'b1;
    end
end

//-----------------------------------------------------

// PC 图片上传到 VGA 专用精简路径：
// 只保留 UDP 接收、img_rx_fb、EMB 帧缓存和 VGA 输出。
// 摄像头、TF 卡照片回传、FPGA->PC 图像回传会额外占用大量 EMB，
// 在本任务中不需要，先裁剪掉以满足 EG4S20/HX4S20 的 64 个 EMB 限制。
wire        img_wr_en;
wire [7:0]  img_wr_addr;
wire [5:0]  img_wr_data;
wire [7:0]  cam_rd_addr;
wire [5:0]  cam_rd_data = 6'd0;

// 未使用外设给安全默认电平，避免端口悬空。
assign cam_rst_n = 1'b0;
assign cam_pwdn  = 1'b1;
assign cam_scl   = 1'b1;
assign cam_sda   = 1'bz;
assign sd_clk    = 1'b0;
assign sd_cs     = 1'b1;
assign sd_mosi   = 1'b1;

// app
app u_app (
    .sys_clk                    (clk_25                 ),
    .udp_rx_clk                 (udp_clk                ),
    .udp_tx_clk                 (udp_clk                ),
    .reset                      (rst_n                  ),
    .sdr_clk                    (clk_125_out            ),
    .sdr_clk_sft                (temac_clk90            ),
    .sdr_rst                    (~rst_n | reset_reg     ),
    .sdr_init_done              (                       ),
    .vga_underflow              (                       ),
    .app_rx_data_valid          (app_rx_data_valid      ),
    .app_rx_data                (app_rx_data            ),
    .app_rx_data_length         (app_rx_data_length     ),
    .app_rx_port_num            (app_rx_port_num        ),
    .proc_mode_i                (proc_mode_eth          ),
    .wr_en_o                    (img_wr_en              ),
    .wr_addr_o                  (img_wr_addr            ),
    .wr_data_o                  (img_wr_data            ),
    .cam_en_i                   (cam_en                 ),
    .cam_rd_addr_o              (cam_rd_addr            ),
    .cam_rd_data_i              (cam_rd_data            ),
    .VGA_HSYNC                  (VGA_HSYNC              ),
    .VGA_VSYNC                  (VGA_VSYNC              ),
    .VGA_D                      (VGA_D                  ),
    .rd_en                      (rd_en                  )
);

clk_gen_rst_gen#(
    .DEVICE         (DEVICE     )
)u_clk_gen(
    .reset                (1'b0                   ),//~key1 
    .clk_in         (clk_25     ),
    .rst_out        (reset_reg  ),
    .clk_125_out0   (temac_clk  ),
    .clk_125_out1   (clk_125_out),
    .clk_125_out2   (temac_clk90),
    .clk_12_5_out   (clk_12_5_out),
    .clk_1_25_out   (clk_1_25_out),
    .clk_25_out     (clk_25_out )
);

// FPGA -> PC 图像回传暂时裁剪，节省 MSlice 给 SDRAM RGB444 VGA 主路径。
assign app_tx_data_request = 1'b0;
assign app_tx_data_valid   = 1'b0;
assign app_tx_data         = 8'h00;
assign udp_data_length     = 16'd0;

//------------------------------------------------------------  
//UDP
//------------------------------------------------------------       
udp_ip_protocol_stack #
(
    .DEVICE                     (DEVICE                 ),
    .LOCAL_UDP_PORT_NUM         (LOCAL_UDP_PORT_NUM     ),
    .LOCAL_IP_ADDRESS           (LOCAL_IP_ADDRESS       ),
    .LOCAL_MAC_ADDRESS          (LOCAL_MAC_ADDRESS      )
)   
u3_udp_ip_protocol_stack    
(   
    .udp_rx_clk                 (udp_clk                ),
    .udp_tx_clk                 (udp_clk                ),
    .reset                      (1'b0                  ), 
    .udp2app_tx_ready           (udp_tx_ready           ), 
    .udp2app_tx_ack             (app_tx_ack             ), 
    .app_tx_request             (app_tx_data_request    ), 
    .app_tx_data_valid          (app_tx_data_valid      ), 
    .app_tx_data                (app_tx_data            ), 
    .app_tx_data_length         (udp_data_length        ), 
    .app_tx_dst_port            (DST_UDP_PORT_NUM       ), 
    .ip_tx_dst_address          (DST_IP_ADDRESS         ), 
    
    .input_local_udp_port_num      (input_local_udp_port_num      ),
    .input_local_udp_port_num_valid(input_local_udp_port_num_valid),
    
    .input_local_ip_address     (input_local_ip_address     ),
    .input_local_ip_address_valid(input_local_ip_address_valid),
    
    .app_rx_data_valid          (app_rx_data_valid      ), 
    .app_rx_data                (app_rx_data            ), 
    .app_rx_data_length         (app_rx_data_length     ), 
    .app_rx_port_num            (app_rx_port_num        ), 
    .temac_rx_ready             (temac_rx_ready         ),//output
    .temac_rx_valid             (!temac_rx_valid        ),//input
    .temac_rx_data              (temac_rx_data          ),//input
    .temac_rx_sof               (temac_rx_sof           ),//input
    .temac_rx_eof               (temac_rx_eof           ),//input
    .temac_tx_ready             (temac_tx_ready         ),//input
    .temac_tx_valid             (temac_tx_valid         ),//output
    .temac_tx_data              (temac_tx_data          ),//output
    .temac_tx_sof               (temac_tx_sof           ),//output
    .temac_tx_eof               (temac_tx_eof           ),//output
`ifdef DEBUG_UDP
    .udp_debug_out              (udp_debug_out          ),
`endif
    .ip_rx_error                (                       ), 
    .arp_request_no_reply_error (                       )
);
wire phy1_rgmii_rx_clk_0;
wire phy1_rgmii_rx_clk_90;
rx_pll u_rx_pll(
	.refclk		(phy1_rgmii_rx_clk),
    .reset  (1'b0),
    .clk0_out	(phy1_rgmii_rx_clk_0),
	.clk1_out	(phy1_rgmii_rx_clk_90)
);
//------------------------------------------------------------  
//TEMAC
//------------------------------------------------------------  
temac_block#(
    .DEVICE               (DEVICE                   )
)  
u4_trimac_block
(
    .reset                (1'b0                    ),
    .gtx_clk              (clk_125_out                ),//input   125M
    .gtx_clk_90           (temac_clk90                ),//input   125M
    .rx_clk               (rx_clk_int               ),//output  125M 25M    2.5M
    .rx_clk_en            (rx_clk_en_int            ),//output  1    12.5M  1.25M
    .rx_data              (rx_data                  ),
    .rx_data_valid        (rx_valid                 ),
    .rx_correct_frame     (rx_correct_frame         ),
    .rx_error_frame       (rx_error_frame           ),
    .rx_status_vector     (                         ),
    .rx_status_vld        (                         ),
//  .tri_speed            (tri_speed                ),//output
    .tx_clk               (tx_clk_int               ),//output  125M
    .tx_clk_en            (tx_clk_en_int            ),//output  1    12.5M  1.25M 占空比不对
    .tx_data              (tx_data                  ),
    .tx_data_en           (tx_valid                 ),
    .tx_rdy               (tx_rdy                   ),//temac_tx_ready
    .tx_stop              (tx_stop                  ),//input
    .tx_collision         (tx_collision             ),
    .tx_retransmit        (tx_retransmit            ),
    .tx_ifg_val           (tx_ifg_val               ),//input
    .tx_status_vector     (                         ),
    .tx_status_vld        (                         ),
    .pause_req            (pause_req                ),//input
    .pause_val            (pause_val                ),//input
    .pause_source_addr    (pause_source_addr        ),//input
    .unicast_address      (unicast_address          ),//input
    .mac_cfg_vector       (mac_cfg_vector           ),//input
    .rgmii_txd            (phy1_rgmii_tx_data       ),
    .rgmii_tx_ctl         (phy1_rgmii_tx_ctl        ),
    .rgmii_txc            (phy1_rgmii_tx_clk        ),
    .rgmii_rxd            (phy1_rgmii_rx_data       ),
    .rgmii_rx_ctl         (phy1_rgmii_rx_ctl        ),
    .rgmii_rxc            (phy1_rgmii_rx_clk_90        ),
    .inband_link_status   (                         ),
    .inband_clock_speed   (                         ),
    .inband_duplex_status (                         )
);

udp_clk_gen#(
    .DEVICE               (DEVICE                   )
)           
u5_temac_clk_gen(           
    .reset                (1'b0                   ),//~key1 
    .tri_speed            (TRI_speed                ),
    .clk_125_in           (clk_125_out              ),//125M  
    .clk_12_5_in          (clk_12_5_out             ),//12.5M 
    .clk_1_25_in          (clk_1_25_out             ),//1.25M 
    .udp_clk_out          (udp_clk                  )
);

// TX FIFO 裁剪：当前只需要 PC->FPGA 接收图片，不需要 FPGA 主动发包。
// PC 端脚本已使用静态 ARP，所以上传图片不依赖 FPGA TX/ARP 回复。
assign tx_data         = 8'h00;
assign tx_valid        = 1'b0;
assign temac_tx_ready  = 1'b1;


rx_client_fifo# 
(
    .DEVICE               (DEVICE                   )
)                           
u7_rx_fifo                  
(                           
    .wr_clk               (rx_clk_int               ),
    .wr_enable            (rx_clk_en_int            ),
    .wr_sreset            (1'b0                    ),
    .rx_data              (rx_data                  ),
    .rx_data_valid        (rx_valid                 ),
    .rx_good_frame        (rx_correct_frame         ),
    .rx_bad_frame         (rx_error_frame           ),
    .overflow             (                         ),
    .rd_clk               (udp_clk                  ),
    .rd_sreset            (1'b0                    ),
    .rd_data_out          (temac_rx_data            ),//output reg [7:0] rd_data_out,
    .rd_sof_n             (temac_rx_sof             ),//output reg       rd_sof_n,
    .rd_eof_n             (temac_rx_eof             ),//output           rd_eof_n,
    .rd_src_rdy_n         (temac_rx_valid           ),//output reg       rd_src_rdy_n,
    .rd_dst_rdy_n         (temac_rx_ready           ),//input            rd_dst_rdy_n,
    .rx_fifo_status       (                         )
);



endmodule