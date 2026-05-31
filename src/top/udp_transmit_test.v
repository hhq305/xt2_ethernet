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

wire         app_rx_data_valid;//synthesis keep 
wire [7:0]   app_rx_data;//synthesis keep       
wire [15:0]  app_rx_data_length;//synthesis keep
wire [15:0]  app_rx_port_num;

wire         udp_tx_ready;
wire         app_tx_ack;
wire         app_tx_data_request;//synthesis keep
wire         app_tx_data_valid;//synthesis keep 
wire [7:0]   app_tx_data;//synthesis keep       
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

wire        temac_tx_ready;//synthesis keep
wire        temac_tx_valid;//synthesis keep
wire [7:0]  temac_tx_data;//synthesis keep 
wire        temac_tx_sof;
wire        temac_tx_eof;
            
wire        temac_rx_ready;
wire        temac_rx_valid;//synthesis keep
wire [7:0]  temac_rx_data;//synthesis keep 
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

wire        temac_clk;//synthesis keep
wire        udp_clk;  //synthesis keep
wire        temac_clk90;//synthesis keep
wire        clk_125_out;
wire        clk_12_5_out;
wire        clk_1_25_out;
wire        rx_valid;//synthesis keep   
wire [7:0]  rx_data;//synthesis keep    
wire [7:0]  tx_data; //synthesis keep   
wire        tx_valid; //synthesis keep  
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
reg       debug_app_rx_data_valid   ;//synthesis keep
reg [7:0] debug_app_rx_data         ;//synthesis keep
reg       debug_app_tx_data_valid   ;//synthesis keep
reg [7:0] debug_app_tx_data         ;//synthesis keep
reg       debug_temac_tx_valid      ;//synthesis keep
reg [7:0] debug_temac_tx_data       ;//synthesis keep
reg       debug_temac_rx_valid      ;//synthesis keep
reg [7:0] debug_temac_rx_data       ;//synthesis keep
reg       debug_rx_valid            ;//synthesis keep
reg [7:0] debug_rx_data             ;//synthesis keep
reg       debug_tx_valid            ;//synthesis keep
reg [7:0] debug_tx_data             ;//synthesis keep

reg [31:0] debug_frame_temac_cnt_rx ;//synthesis keep
reg [31:0] debug_frame_app_cnt_rx   ;//synthesis keep
reg [31:0] debug_frame_fifo_cnt_rx  ;//synthesis keep
reg [31:0] debug_frame_temac_cnt_tx ;//synthesis keep
reg [31:0] debug_frame_app_cnt_tx   ;//synthesis keep
reg [31:0] debug_frame_fifo_cnt_tx  ;//synthesis keep

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

//参数定义
reg [32:0] cnt0;
wire      end_cnt0;
wire      add_cnt0;
reg [7:0] cnt1;
wire      end_cnt1;
wire      add_cnt1;

// 上电自动复位 (POR): 开机后自动拉低 rst_n 约 1ms 再释放, 无需手按 KEY2
reg [15:0] por_cnt = 16'd0;
reg        por_n   = 1'b0;
always @(posedge udp_clk) begin
    if (por_cnt != 16'hFFFF) por_cnt <= por_cnt + 1'b1;
    por_n <= (por_cnt == 16'hFFFF);
end
wire rst_n = key2 & por_n;    // KEY2 手动复位 + 上电自动复位 (active-low)
//计数器2
 always @(posedge udp_clk or negedge rst_n)begin
     if(!rst_n)begin
         cnt0 <= 0;
     end
     else if(add_cnt0)begin
         if(end_cnt0)
             cnt0 <= 0;
         else
             cnt0 <= cnt0 + 1;
     end
 end

 assign add_cnt0 = 1;
 assign end_cnt0 = add_cnt0 && 0;

 always @(posedge udp_clk or negedge rst_n)begin 
     if(!rst_n)begin
         cnt1 <= 0;
     end
     else if(add_cnt1)begin
         if(end_cnt1)
             cnt1 <= 0;
         else
             cnt1 <= cnt1 + 1;
     end
 end

 assign add_cnt1 = end_cnt0;
 assign end_cnt1 = add_cnt1 && cnt1== 15;  

reg [31:0]  input_local_ip_address;
reg         input_local_ip_address_valid;

always@(posedge udp_clk or posedge reset)
begin
    if(reset) 
    begin
        input_local_ip_address      <= LOCAL_IP_ADDRESS;
        input_local_ip_address_valid<= 1'b0;
    end
    else if(end_cnt0 == 1'b1)
    begin
        input_local_ip_address      <= {LOCAL_IP_ADDRESS[31:8],cnt1};
        input_local_ip_address_valid<= 1'b1;
    end
    else
    begin
        input_local_ip_address      <= input_local_ip_address;
        input_local_ip_address_valid<= 1'b1;
    end
end

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
cmd_decode u_cmd_decode (
    .clk            (udp_clk),
    .rst_n          (rst_n),                    // = key2
    .rx_data        (app_rx_data),
    .rx_valid       (app_rx_data_valid),
    .rx_length      (app_rx_data_length),
    .led_o          (led_eth8),
    .seg_bcd_o      (seg_bcd_eth),
    .proc_mode_o    (proc_mode_eth),
    .img_req_pulse_o(img_req_pulse),
    .cam_en_o       (cam_en),
    .sd_photo_req_o (sd_photo_req),
    .sd_sec_addr_o  (sd_sec_addr_cmd),
    .ack_pulse_o    ()
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

// 选题二 扩展① : 数码管扫描显示 (复用 udp_clk, 25/50MHz 均可)
seg_scan u_seg_scan (
    .clk    (udp_clk),
    .rst_n  (rst_n),
    .bcd_in (seg_bcd_eth[15:0]),   // 取低 16 bit = 4 位 16 进制数字
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

// 扩展② : 暴露给 img_tx_rom 的图像写信号
wire        img_wr_en;
wire [7:0]  img_wr_addr;
wire [5:0]  img_wr_data;

// 扩展⑤ : OV5640 摄像头 -> 16x16 RGB222 镜像
wire        cam_init_done;
wire        cmos_frame_vsync;
wire        cmos_frame_href;
wire        cmos_frame_valid;
wire [15:0] cmos_frame_data;
wire [7:0]  cam_rd_addr;
wire [5:0]  cam_rd_data;

ov5640_dri u_ov5640 (
    .clk              (clk_25),               // 50MHz 板载晶振
    .rst_n            (rst_n),
    .cam_pclk         (cam_pclk),
    .cam_vsync        (cam_vsync),
    .cam_href         (cam_href),
    .cam_data         (cam_data),
    .cam_rst_n        (cam_rst_n),
    .cam_pwdn         (cam_pwdn),
    .cam_scl          (cam_scl),
    .cam_sda          (cam_sda),
    .cmos_h_pixel     (13'd1024),
    .cmos_v_pixel     (13'd768),
    .total_h_pixel    (13'd2240),
    .total_v_pixel    (13'd1272),
    .capture_start    (cam_en),
    .cam_init_done    (cam_init_done),
    .cmos_frame_vsync (cmos_frame_vsync),
    .cmos_frame_href  (cmos_frame_href),
    .cmos_frame_valid (cmos_frame_valid),
    .cmos_frame_data  (cmos_frame_data)
);

cam_to_bram u_cam_to_bram (
    .cam_pclk         (cam_pclk),
    .rst_n            (rst_n),
    .cmos_frame_vsync (cmos_frame_vsync),
    .cmos_frame_href  (cmos_frame_href),
    .cmos_frame_valid (cmos_frame_valid),
    .cmos_frame_data  (cmos_frame_data),
    .rd_addr          (cam_rd_addr),
    .rd_data          (cam_rd_data)
);

//app
app u_app (
    .sys_clk                    (clk_25                 ),
    .udp_rx_clk                 (udp_clk                ),
    .udp_tx_clk                 (udp_clk                ),
    .reset                      (key2                   ),
    .app_rx_data_valid          (app_rx_data_valid      ),
    .app_rx_data                (app_rx_data            ),
    .app_rx_data_length         (app_rx_data_length     ),
    .app_rx_port_num            (app_rx_port_num        ),
    .proc_mode_i                (proc_mode_eth          ),   // 扩展④
    .wr_en_o                    (img_wr_en              ),   // 扩展②
    .wr_addr_o                  (img_wr_addr            ),
    .wr_data_o                  (img_wr_data            ),
    .cam_en_i                   (cam_en                 ),   // 扩展⑤
    .cam_rd_addr_o              (cam_rd_addr            ),
    .cam_rd_data_i              (cam_rd_data            ),
    .VGA_HSYNC	                (VGA_HSYNC              ),
	.VGA_VSYNC 	                (VGA_VSYNC              ),
	.VGA_D                      (VGA_D                  ),
    .rd_en                      (rd_en                  )
);

/*vga_bmp u_vga_bmp
(   .VGA_HSYNC	                (VGA_HSYNC              ),
	.VGA_VSYNC 	                (VGA_VSYNC              ),
	.VGA_D                      (VGA_D                  ),
    .sys_clk                    (clk_25                ),
    .reset                      (key2                  )
);*/

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


udp_data_tpg u1_udp_data_tpg(
    .clk                (udp_clk            ),
    .reset              (~key2              ),

    .tpg_data           (tpg_data           ),//数据输出
    .tpg_data_valid     (tpg_data_valid     ),//数据有效信号
    .tpg_data_udp_length(tpg_data_udp_length),//数据长度（包含帧头）
    .tpg_data_done      (tpg_data_done      ),
    
    .tpg_data_enable    (phy_reset          ),
    .tpg_data_header0   (16'haabb           ),//帧头0
    .tpg_data_header1   (16'hccdd           ),//帧头1
    .tpg_data_type      (16'ha8b8           ),//数据帧类垿
    .tpg_data_length    (16'h00ff           ),//数据长度500
    .tpg_data_num       (16'h000a           ),//产生的帧个数10
    .tpg_data_ifg       (8'd130             )
);

//------------------------------------------------------------
// 选题二 扩展② : FPGA -> PC 主动回传图像 (替换 udp_loopback)
//------------------------------------------------------------
wire [7:0]  img_app_tx_data;
wire        img_app_tx_data_valid;
wire [15:0] img_udp_data_length;
wire        img_app_tx_request;
img_tx_rom #(
    .PAY_LEN (16'd256)
) u2_img_tx_rom (
    .clk                 (udp_clk            ),
    .rst_n               (rst_n              ),
    .start               (img_req_pulse      ),
    .wr_en               (img_wr_en          ),   // 监听 addr_crt 写图像
    .wr_addr             (img_wr_addr        ),
    .wr_data             (img_wr_data        ),
    .udp_tx_ready        (udp_tx_ready       ),
    .app_tx_ack          (app_tx_ack         ),
    .app_tx_data         (img_app_tx_data        ),
    .app_tx_data_valid   (img_app_tx_data_valid  ),
    .udp_data_length     (img_udp_data_length    ),
    .app_tx_request      (img_app_tx_request     )
);

//------------------------------------------------------------
// 选题二 扩展⑥ : TF 卡 BMP 照片 -> 64x64 RGB222 -> 多包回传
//------------------------------------------------------------
// 50MHz 0deg/180deg SD 参考时钟 (由 50MHz 板载晶振 clk_25 生成)
wire sd_clk_ref;
wire sd_clk_ref_180;
pll_50 u_pll_50 (
    .refclk   (clk_25         ),
    .reset    (1'b0           ),
    .extlock  (               ),
    .clk0_out (sd_clk_ref      ),   // 50MHz 0deg
    .clk1_out (sd_clk_ref_180  ),   // 50MHz 180deg
    .clk2_out (               )
);

// --- 跨时钟: sd_photo_req(udp_clk 脉冲) -> sd_clk_ref 域 start 脉冲 ---
reg        sd_req_tgl;
always @(posedge udp_clk or negedge rst_n) begin
    if (!rst_n) sd_req_tgl <= 1'b0;
    else if (sd_photo_req) sd_req_tgl <= ~sd_req_tgl;
end
reg [2:0] sd_req_sync;
always @(posedge sd_clk_ref or negedge rst_n) begin
    if (!rst_n) sd_req_sync <= 3'd0;
    else        sd_req_sync <= {sd_req_sync[1:0], sd_req_tgl};
end
wire sd_start = sd_req_sync[2] ^ sd_req_sync[1];

// --- SD 卡 SPI 顶层 ---
wire        sd_rd_busy;
wire        sd_rd_val_en;
wire [15:0] sd_rd_val_data;
wire        sd_rd_start_en;
wire [31:0] sd_rd_sec_addr;
wire        sd_init_done;
sd_ctrl_top u_sd_ctrl_top (
    .clk_ref        (sd_clk_ref     ),
    .clk_ref_180deg (sd_clk_ref_180 ),
    .rst_n          (rst_n          ),
    .sd_miso        (sd_miso        ),
    .sd_clk         (sd_clk         ),
    .sd_cs          (sd_cs          ),
    .sd_mosi        (sd_mosi        ),
    .wr_busy        (               ),
    .rd_start_en    (sd_rd_start_en ),
    .rd_sec_addr    (sd_rd_sec_addr ),
    .rd_busy        (sd_rd_busy     ),
    .rd_val_en      (sd_rd_val_en   ),
    .rd_val_data    (sd_rd_val_data ),
    .sd_init_done   (sd_init_done   )
);

// --- BMP 像素流 -> 全分辨率 RGB565 流式写入异步 FIFO (sd_clk_ref 域) ---
wire        ph_fifo_wen;
wire [15:0] ph_fifo_wdata;
wire [11:0] ph_fifo_wused;
wire        ph_fifo_wfull;
wire        photo_done_sd;
sd_photo64 u_sd_photo64 (
    .clk          (sd_clk_ref     ),
    .rst_n        (rst_n          ),
    .start        (sd_start       ),
    .start_sector (sd_sec_addr_cmd),   // 准静态: 命令早于 start 锁存
    .rd_busy      (sd_rd_busy     ),
    .rd_val_en    (sd_rd_val_en   ),
    .rd_val_data  (sd_rd_val_data ),
    .rd_start_en  (sd_rd_start_en ),
    .rd_sec_addr  (sd_rd_sec_addr ),
    .fifo_wen     (ph_fifo_wen    ),
    .fifo_wdata   (ph_fifo_wdata  ),
    .fifo_wused   (ph_fifo_wused  ),
    .done         (photo_done_sd  ),
    .busy         (photo_prod_busy)
);

// FIFO flush 门控: 只在生产者/消费者空闲时清空, 屏蔽 8x 重复命令/补包重传的多余脉冲
wire photo_prod_busy;
wire fifo_wflush = sd_start    & ~photo_prod_busy;
wire fifo_rflush = sd_photo_req & ~photo_busy;

// --- 双时钟异步 FIFO (SD 域写 -> udp 域读) ---
wire        ph_fifo_ren;
wire [15:0] ph_fifo_rdata;
wire [11:0] ph_fifo_rused;
wire        ph_fifo_rempty;
dpram_64x64 #(.DW(16), .AW(11)) u_dpram_64x64 (
    .wclk   (sd_clk_ref    ),
    .wrst_n (rst_n         ),
    .wflush (fifo_wflush   ),   // 生产者 start(SD域,空闲时): 清空写端, 保证每次传输 FIFO 空
    .wen    (ph_fifo_wen   ),
    .wdata  (ph_fifo_wdata ),
    .wfull  (ph_fifo_wfull ),
    .wused  (ph_fifo_wused ),
    .rclk   (udp_clk       ),
    .rrst_n (rst_n         ),
    .rflush (fifo_rflush   ),   // 消费者 start(udp域,空闲时): 清空读端, 与写端对齐到 pix0
    .ren    (ph_fifo_ren   ),
    .rdata  (ph_fifo_rdata ),
    .rempty (ph_fifo_rempty),
    .rused  (ph_fifo_rused )
);

// --- 全分辨率照片流式发送 (start 直接用 udp 域的 sd_photo_req 脉冲) ---
wire [7:0]  ph_app_tx_data;
wire        ph_app_tx_data_valid;
wire [15:0] ph_udp_data_length;
wire        ph_app_tx_request;
wire        photo_busy;
photo_tx #(
    .PKT_PAY  (16'd1024),
    .NPKT     (16'd600 ),
    .START_TH (12'd512 )
) u_photo_tx (
    .clk               (udp_clk             ),
    .rst_n             (rst_n               ),
    .start             (sd_photo_req        ),
    .fifo_ren          (ph_fifo_ren         ),
    .fifo_rdata        (ph_fifo_rdata       ),
    .fifo_rused        (ph_fifo_rused       ),
    .udp_tx_ready      (udp_tx_ready        ),
    .app_tx_ack        (app_tx_ack          ),
    .app_tx_data       (ph_app_tx_data      ),
    .app_tx_data_valid (ph_app_tx_data_valid),
    .udp_data_length   (ph_udp_data_length  ),
    .app_tx_request    (ph_app_tx_request   ),
    .busy              (photo_busy          )
);

// --- 跨时钟: 生产者 done(sd_clk_ref 脉冲) -> udp 域电平 (供 LED4 探针) ---
reg pd_sticky_sd;
always @(posedge sd_clk_ref or negedge rst_n) begin
    if (!rst_n)             pd_sticky_sd <= 1'b0;
    else if (sd_start)      pd_sticky_sd <= 1'b0;   // 新一次读卡清零
    else if (photo_done_sd) pd_sticky_sd <= 1'b1;
end
reg [2:0] pd_sync;
always @(posedge udp_clk or negedge rst_n) begin
    if (!rst_n) pd_sync <= 3'd0;
    else        pd_sync <= {pd_sync[1:0], pd_sticky_sd};
end
wire frame_ready_udp = pd_sync[2];   // 电平: 整图取数完成 (沿用旧名供 LED 探针)

// --- TX 多路选择: photo 占用时走 photo_tx, 否则走 img_tx_rom ---
assign app_tx_data         = photo_busy ? ph_app_tx_data       : img_app_tx_data;
assign app_tx_data_valid   = photo_busy ? ph_app_tx_data_valid : img_app_tx_data_valid;
assign udp_data_length     = photo_busy ? ph_udp_data_length   : img_udp_data_length;
assign app_tx_data_request = photo_busy ? ph_app_tx_request     : img_app_tx_request;

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

tx_client_fifo #
(
    .DEVICE               (DEVICE                   )
)
u6_tx_fifo
(
    .rd_clk               (tx_clk_int               ),
    .rd_sreset            (1'b0                    ),
    .rd_enable            (tx_clk_en_int            ),
    .tx_data              (tx_data                  ),
    .tx_data_valid        (tx_valid                 ),
    .tx_ack               (tx_rdy                   ),
    .tx_collision         (tx_collision             ),
    .tx_retransmit        (tx_retransmit            ),
    .overflow             (                         ),
                            
    .wr_clk               (udp_clk                  ),
    .wr_sreset            (1'b0                    ),
    .wr_data              (temac_tx_data            ),
    .wr_sof_n             (temac_tx_sof             ),
    .wr_eof_n             (temac_tx_eof             ),
    .wr_src_rdy_n         (temac_tx_valid           ),
    .wr_dst_rdy_n         (temac_tx_ready           ),//temac_tx_ready
    .wr_fifo_status       (                         )
);

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