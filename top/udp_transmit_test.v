`timescale 1ns / 1ps
`include "pkt_fmt.vh"
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
// 2022/03/10:  淇�敼鏃堕挓缁撴�?
//              绠€鍖栫害鏉?
//              娣诲�?soft fifo
//              娣诲�?debug 鍔熻�?
// 2023/02/16 :add dynamic_local_ip_address port
//
// web锛歸ww.anlogic.com
//------------------------------------------------------------------- 
//*********************************************************************/
    `define UDP_LOOP_BACK
//  `define DEBUG_UDP
// =============================================================
// 涓存椂璇婃柇寮€�?: 纭�紪鐮?LED 娴嬭�?(缁曡�?cmd_decode / UDP 鍗忚�鏍?
//   2026-05-28 宸查獙璇? 涓嶆�?key1 鍏ㄧ�? �?key1 鍏ㄤ�?
//   -> 寮曡�?A4/A3/C10/B12 + active-high 鏋佹�?瀹屽叏姝ｇ�?
//   -> 鍏虫帀杩欐�?`define, 璧版�甯?led = led_eth8[3:0] 璺��?
// =============================================================
//  `define LED_HARDCODE_TEST
// =============================================================
// 涓存椂璇婃柇寮€�?: UDP 璺�緞鍒嗛樁�?sticky 鎺㈤�?
//   LED1 = 浠讳�?UDP 瀛楄妭鍒拌揪 app �? (app_rx_data_valid 鑴夊啿杩?
//   LED2 = MAGIC0 (0xA5) 瀛楄妭鍑虹幇�?
//   LED3 = MAGIC0 涔嬪悗鎺?MAGIC1 (0x5A) 鍑虹幇杩?-> 鍗忚�澶磋瘑鍒�垚鍔?
//   LED4 = CMD_LED_SET (0x01) 甯у畬鏁磋В鏋愯�?(led_o 瀹為檯琚�啓�?
//   �?key1 娓呴浂閲嶆祴 (key1 active-low, 鎸変笅鏃跺�浣嶆帰閽?
//   2026-05-28 宸查獙璇? 4 LED 鍏ㄤ�?-> UDP 鍏ㄧ▼璺�緞姝ｅ�?
// =============================================================
//  `define UDP_PATH_PROBE
// =============================================================
// 缁堟瀬璇婃柇 : RGMII 鐗╃悊灞傛帰�?(缁曡繃鎵€鏈?PLL/TEMAC/鍗忚�鏍?
//   LED1 = phy1_rgmii_rx_ctl 鍑虹幇杩?1 (sticky)
//   LED2 = phy1_rgmii_rx_clk toggle �?(sticky)
//   LED3 = clk_25 toggle �?(sticky)
//   LED4 = ~key1 (�?KEY1 鍏ㄤ�? 瀹炴�?
//   �?KEY2 娓呴浂閲嶆祴
//   2026-05-28 宸查獙璇? port=1 �?LED2 �?-> UDP 璺�緞鍏ㄩ€? 鍏抽棴鎺㈤拡鐪嬬湡�?led_eth8
// =============================================================
//  `define RGMII_PHYS_PROBE
// =============================================================
// 璇婃�?LAST_BYTE_PROBE : LED 鐩存帴鏄剧ず app_rx_data 鏈€鏂板瓧鑺備綆 4 bit
//   缁曡�?cmd_decode FSM, 鍒ゆ柇鏄�崗璁�爤鍗℃� 杩樻�?cmd_decode 鍗℃�?
//   姣忓�?led 0xX, LED 鏈�瓧鑺傚簲璺熼殢鍙樺寲 (浣嗘湯灏惧彲鑳借� 0x00 padding 瑕嗙�?
// =============================================================
//  `define LAST_BYTE_PROBE
// =============================================================
// SD 鐓х墖璇婃�?: LED1=sd_init_done LED2=req鍒拌�?LED3=璇诲崱瀹屾�?LED4=鍙戦€佸惎鍔?
//   (�?KEY1 娓呴�?sticky). 瀹氫�?SD 鐓х墖鍗″湪鍝�竴闃舵�.
//   鐓х墖鍔熻兘宸查獙璇侀€氳�? 骞虫椂鍏抽棴, �?LED 鎭㈠�?PC 鍛戒护鎺у�?
// =============================================================
//  `define SD_PHOTO_PROBE
// =============================================================
// 鍥惧儚涓婁紶璇婃�?: 鍒ゆ�?sendvga_bars/sendvga �?CMD_IMG_FRAME 鏄�惁鍒拌揪
//   LED1 = 浠绘�?UDP 瀛楄妭鍒拌揪 app �?
//   LED2 = 瑙ｆ瀽鍒?A5 5A 10 鍥惧儚鍖呭ご
//   LED3 = 杩涘叆鍥惧儚 payload �?FLAG 瀛楄�?
//   LED4 = 鐪嬪埌鏈€缁堝寘 FLAG[0]=1
// =============================================================
//  `define IMG_RX_PROBE
// =============================================================
// CMD_IMG_REQ 鍥炲寘璇婃柇 : 瀹氫�?img 瓒呮椂鍗″湪鈥滃懡浠ゆ病瑙ｆ瀽鈥濊繕鏄�€淭X 娌℃彙鎵嬧€濄€?
//   LED1 = 瑙ｆ瀽鍒?CMD_IMG_REQ(0x20)
//   LED2 = udp_tx_ready 鍑虹幇杩?
//   LED3 = app_tx_ack 鍑虹幇杩?
//   LED4 = temac_tx_valid 鍑虹幇杩?
//   �?KEY1 娓呴浂銆傝瘖鏂��?LED 涓嶅啀鏄剧�?led 15/0 鐨勫懡浠ゅ€笺€?
// =============================================================
//  `define IMG_TX_PROBE
// =============================================================
// 摄像头视频回传诊�?(实际代码映射，LED[3:0] 高位在前):
// LED4 = cmos_frame_valid 出现过（有效像素�?
// LED3 = cmos_frame_href 出现过（行同步）
// LED2 = cmos_frame_vsync 出现过（帧同步）
// LED1 = cam_pclk 像素时钟在跳动（基准，udp_clk 域采样）
// �?KEY1 清零。诊断时 LED 不再显示普�?led 命令值�?
// `define CAM_TX_PROBE
`define CAM_INPUT_PROBE
`define BASIC4_CAMERA_ENABLE
`define CAM_REFERENCE_DIRECT_TX
// 临时诊断: �?0x31 发送固�?RGB565 测试图案，用于排除真实摄像头/缓存链路影响�?
// 0x31 多包回传链路已验证可达；正常实时视频时保持关闭�?
// `define CAM_USE_PATTERN_TX
// Reference working project uses live camera FIFO without frame-diff tracking.
// Keep motion tracking off by default for the PC camera-return bring-up path;
// enable this only after TD resource/timing is safely below device limits.
// `define CAM_MOTION_TRACK_ENABLE
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
        // 閫夐�浜?鎵╁睍鈶?: 4 浣嶅姩鎬佹壂鎻忔暟鐮佺�
        output [6:0]       seg,
        output [3:0]       seg_en,
        // 閫夐�浜?鎵╁睍鈶?: OV5640 鎽勫儚澶存帴�?
        input              cam_pclk,
        input              cam_vsync,
        input              cam_href,
        input  [7:0]       cam_data,
        output             cam_xclk,
        output             cam_rst_n,
        output             cam_pwdn,
        output             cam_scl,
        inout              cam_sda,
        // 閫夐�浜?鎵╁睍鈶?: TF �?(SD SPI 妯″紡)
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
parameter  LOCAL_MAC_ADDRESS  = 48'h001122334455;  // 00:11:22:33:44:55  (unicast, 绗�竴瀛楄�?LSB=0)
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
wire        udp_ip_rx_error;
wire        udp_arp_no_reply_error;

wire        rx_correct_frame;
wire        rx_error_frame;
wire [1:0]  TRI_speed;

assign TRI_speed = 2'b10;//鍗冨�?'b10 鐧惧�?'b01 鍗佸�?'b00

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

// Camera XCLK output: OV_XCLK -> J1-24(GPIOA_21/J16).
assign cam_xclk = clk_25_out;
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
// 鍙傛暟閰嶇疆閫昏�?
//============================================================
//闇€閰嶇疆鐨勫�鎴风�鎺ュ彛锛堝垵濮嬮粯璁ゅ€硷�?
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


assign  mac_cfg_vector    = {1'b0,2'b00,TRI_speed,8'b00000010,7'b0000010}; //鍦板潃杩囨护妯″紡銆佹祦鎺ч厤缃�€侀€熷害閰嶇疆銆佹帴鏀跺櫒閰嶇疆銆佸彂閫佸櫒閰嶇疆
//assign  mac_cfg_vector    = {1'b0,2'b00,2'b10,8'b00000010,7'b0000010}; //鍦板潃杩囨护妯″紡銆佹祦鎺ч厤缃�€侀€熷害閰嶇疆銆佹帴鏀跺櫒閰嶇疆銆佸彂閫佸櫒閰嶇疆
//assign  mac_cfg_vector    = {1'b0,2'b00,2'b01,8'b00000010,7'b0000010}; //鍦板潃杩囨护妯″紡銆佹祦鎺ч厤缃�€侀€熷害閰嶇疆銆佹帴鏀跺櫒閰嶇疆銆佸彂閫佸櫒閰嶇疆
//assign  mac_cfg_vector    = {1'b0,2'b00,2'b00,8'b00000010,7'b0000010}; //鍦板潃杩囨护妯″紡銆佹祦鎺ч厤缃�€侀€熷害閰嶇疆銆佹帴鏀跺櫒閰嶇疆銆佸彂閫佸櫒閰嶇疆

//-----------------------------------------------------
//test dynamic_local_ip_address
//-----------------------------------------------------

// 涓婄數鑷�姩澶嶄�?(POR): 寮€鏈哄悗鑷�姩鎷変�?rst_n �?1ms 鍐嶉噴鏀? 鏃犻渶鎵嬫寜 KEY2
reg [15:0] por_cnt = 16'd0;
reg        por_n   = 1'b0;
always @(posedge udp_clk) begin
    if (por_cnt != 16'hFFFF) por_cnt <= por_cnt + 1'b1;
    por_n <= (por_cnt == 16'hFFFF);
end
wire rst_n = key2 & por_n;    // KEY2 鎵嬪姩澶嶄綅 + 涓婄數鑷�姩澶嶄�?(active-low)

// 鍥哄畾鏈�満 IP/绔�彛锛岃�鍓��?demo 鐨勫姩鎬?IP 鎵�弿璁℃暟鍣�紝鑺傜渷 MSlice�?
wire [31:0] input_local_ip_address       = LOCAL_IP_ADDRESS;
wire        input_local_ip_address_valid = 1'b1;

// =============================================================
// 閫夐�浜?鍩虹�瑕佹眰 �?: UDP 鍛戒护瑙ｆ�?�?LED  (鏇挎崲鍘?demo �?IP-LED)
// =============================================================
wire [7:0]  led_eth8;
wire [31:0] seg_bcd_eth;
wire [1:0]  proc_mode_eth;
wire        img_req_pulse;
wire        cam_frame_req_pulse;   // 鍩虹�瑕佹眰 �?: 杈冨ぇ鎽勫儚澶村抚鍥炰紶璇锋�?
wire        cam_en;
wire        sd_photo_req;          // 鍩虹�瑕佹眰 �?: udp_clk 鍩熷崟鑴夊啿
wire [31:0] sd_sec_addr_cmd;       // 鍩虹�瑕佹眰 �?: BMP 璧峰�鎵囧尯�?
wire        sd_init_done;          // 鍩虹�瑕佹眰 �?: TF/SD 鍒濆�鍖栧畬�?
wire        frame_ready_udp;       // 鍩虹�瑕佹眰 �?: 鐓х墖鍙戦€佸畬鎴愯皟璇曡剦鍐?
// 鍩虹�瑕佹眰 鈶狅細鎭㈠� PC UDP 鍛戒护鎺у�?LED / 鏁扮爜绠°�?
// cmd_decode 鏄�交閲忓瓧鑺傛祦瑙ｆ瀽鍣�紱鐩告�?SDRAM/VGA 涓昏矾寰勮祫婧愬崰鐢ㄥ緢灏忥�?
// 鍙�互淇濈暀锛屼负鍚庣画鈥滃叏閮ㄥ熀纭€鍔熻�?+ 鎵╁�?2鈥濈户缁�墿灞曞懡浠ゅ叆鍙ｃ�?
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
    .cam_frame_req_pulse_o (cam_frame_req_pulse),
    .cam_en_o        (cam_en),
    .sd_photo_req_o  (sd_photo_req),
    .sd_sec_addr_o   (sd_sec_addr_cmd),
    .ack_pulse_o     ()
);
// === LED 鏄犲�?(寮曡剼宸茬‘璁? ===
//  led[0] = A4  = 鐗╃�?LED1
//  led[1] = A3  = 鐗╃�?LED2
//  led[2] = C10 = 鐗╃�?LED3
//  led[3] = B12 = 鐗╃�?LED4
// PC 閫氳�?CMD_LED_SET (0x01) 涓嬪�?1 瀛楄�? �?4 bit 鎺у埗 4 �?LED
`ifdef LED_HARDCODE_TEST
// 璇婃�? 涓嶆�?key1 鍏ㄧ�? �?key1 鍏ㄤ�?(key1 active-low, A2 PULLUP)
assign led = ~key1 ? 4'b1111 : 4'b0000;
`else
`ifdef LAST_BYTE_PROBE
// =============================================================
// 瀵规瘮妯″紡: 鍚屽睆姣旇緝 cmd_decode 杈撳�?vs raw last_byte
//   涓嶆�?KEY1 (榛樿�?: LED = led_eth8[3:0]   (cmd_decode 鍐冲嚭鐨?LED �?
//   鎸変�?KEY1       : LED = last_byte[3:0]  (鍗忚�鏍堥€佸埌 app 鐨勬渶鏂颁竴瀛楄�?
// 濡傛灉鎸変笅 KEY1 鐪嬪埌鐨勫€艰窡鐫€鍛戒护鍙? 浣嗕笉鎸夌湅鍒扮殑鍊煎崱�? 灏辨�?cmd_decode �?bug.
// �?KEY2 娓呴浂鎺㈤拡.
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
// 鍗忚�鏍堟帰�?(娉ㄦ�? 涓嶈兘璇?phy1_rgmii_tx_*, 浼氱牬鍧?ODDR-PAD 鐩磋�?
//   LED1 = temac_rx_valid 鍑虹幇杩?1 (sticky) -> TEMAC 瑙ｅ嚭杩囧畬�?MAC �?
//   LED2 = app_rx_data_valid 鍑虹幇杩?1 (sticky) -> 鍗忚�鏍堣В鍑鸿繃 UDP payload
//   LED3 = temac_tx_valid 鍑虹幇杩?1 (sticky) -> TEMAC 鍦ㄩ€佸嚭甯?
//   LED4 = pll_locked 鐘舵�?(瀹炴�? ~reset_reg)
// �?key2 娓呴浂鎺㈤拡
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
    else if (!temac_tx_valid) phys_temac_tx_seen <= 1'b1;
end
assign led = {~reset_reg, phys_temac_tx_seen, phys_app_rx_seen, phys_temac_rx_seen};
`else
`ifdef UDP_PATH_PROBE
// =============================================================
// UDP 璺�緞鍒嗛樁�?sticky 鎺㈤�?
// �?key1 (active-low, A2 PULLUP) 娓呴浂閲嶆祴; 鍚﹀垯涓婄數鍚庨殢鍚勯樁娈典寒鐏?
// =============================================================
reg probe_any_byte;     // LED1: 浠绘�?UDP 瀛楄妭鍒拌揪 app �?
reg probe_magic0;       // LED2: 鍑虹幇杩?0xA5
reg probe_magic1;       // LED3: MAGIC0 鍚庣揣璺?0x5A (澶村尮閰嶆垚�?
reg probe_led_cmd;      // LED4: CMD_LED_SET 瀹屾暣甯цВ鏋愯�?

// �?cmd_decode 骞惰�鐨勫皬鐘舵€佹満, 浠呯敤浜庢帰�?(涓嶅奖鍝嶄富閫昏�?
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
                                probe_st <= P_GOT_M0;   // 杩炵�?0xA5
                           end else begin
                                probe_st <= P_IDLE;
                           end
                P_GOT_M1 : begin probe_cmd_r <= app_rx_data; probe_st <= P_GOT_CMD; end
                P_GOT_CMD: probe_st <= P_GOT_LH;            // 璺宠�?LEN_HI
                P_GOT_LH : probe_st <= P_GOT_LL;            // 璺宠�?LEN_LO
                P_GOT_LL : begin                            // 绗�竴涓?payload byte
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
// 鍥惧儚涓婁紶璁℃暟鎺㈤拡 (�?KEY1 娓呴�?
//   LED 浠ヤ簩杩涘埗绮楃暐鏄剧ず宸叉帴鏀?RGB 鍍忕礌鏁伴噺:
//   LED1 >= 10000, LED2 >= 30000, LED3 >= 60000, LED4 >= 76800
//   濡傛�?LED4 浜��?VGA 浠嶇孩鑹诧紝璇存槑鍖呭埌�?img_rx_fb锛屼�?sdram_img_fb 娌℃湁鎺ユ敹鍐欏叆銆?
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
`ifdef IMG_TX_PROBE
// =============================================================
// CMD_IMG_REQ 鍥炲寘鍒嗛樁�?sticky 鎺㈤�?(�?KEY1 娓呴�?
//   LED1 = cmd_decode 瑙ｆ瀽鍒?CMD_IMG_REQ(0x20)
//   LED2 = UDP TX ready 鍑虹幇杩?
//   LED3 = UDP TX ack 鍑虹幇杩?
//   LED4 = 搴曞�?TEMAC TX valid 鍑虹幇杩?
// 鍒よ�?
//   LED1�? CMD=0x20 娌¤�瑙ｆ瀽鍒帮紝闂��鍦?cmd_decode/鍖呮牸寮?
//   LED1浜甃ED2�? UDP 鍗忚�鏍?TX 渚т笉 ready
//   LED2浜甃ED3�? img_tx_rom 璇锋眰浜嗕絾鍗忚�鏍堜笉 ack
//   LED3浜甃ED4�? app 灞傜粰浜嗘暟鎹��?MAC 娌＄湡姝ｅ彂
//   LED4浜��?PC 瓒呮�? 鍖呭彂鍑轰絾 PC/ARP/杩囨�?鐩�殑绔�彛鎺ユ敹涓嶅埌
// =============================================================
reg imgtx_req_seen;
reg imgtx_ready_seen;
reg imgtx_ack_seen;
reg imgtx_temac_seen;
always @(posedge udp_clk or negedge key1) begin
    if (!key1) begin
        imgtx_req_seen   <= 1'b0;
        imgtx_ready_seen <= 1'b0;
        imgtx_ack_seen   <= 1'b0;
        imgtx_temac_seen <= 1'b0;
    end else begin
        if (img_req_pulse)  imgtx_req_seen   <= 1'b1;
        if (udp_tx_ready)   imgtx_ready_seen <= 1'b1;
        if (app_tx_ack)     imgtx_ack_seen   <= 1'b1;
        if (!temac_tx_valid) imgtx_temac_seen <= 1'b1;
    end
end
assign led = {imgtx_temac_seen, imgtx_ack_seen, imgtx_ready_seen, imgtx_req_seen};
`else
`ifdef CAM_TX_PROBE
// =============================================================
// 鎽勫儚澶磋�棰戝洖浼犲垎闃舵�?sticky 鎺㈤�?(�?KEY1 娓呴�?
//   LED1 = cmd_decode 瑙ｆ瀽鍒?CMD_CAM_FRAME(0x31)
//   LED2 = UDP TX ready 鍑虹幇杩?//   LED3 = UDP TX ack 鍑虹幇杩?//   LED4 = 搴曞�?TEMAC TX valid 鍑虹幇杩?// =============================================================
// �?udp_clk 域采�?cam_pclk / 帧信号，不把 cam_pclk 当时钟，
// 以便即使 cam_pclk 停了也能判断摄像头死活�?
reg [2:0] camtx_pclk_sync;
wire      camtx_pclk_edge = camtx_pclk_sync[2] ^ camtx_pclk_sync[1];

reg camtx_pclk_seen;    // LED1: cam_pclk 在跳动（基准�?
reg camtx_vsync_seen;   // LED2: cmos_frame_vsync 出现�?
reg camtx_href_seen;    // LED3: cmos_frame_href 出现�?
reg camtx_valid_seen;   // LED4: cmos_frame_valid 出现�?
always @(posedge udp_clk or negedge key1) begin
    if (!key1) begin
        camtx_pclk_sync  <= 3'b000;
        camtx_pclk_seen  <= 1'b0;
        camtx_vsync_seen <= 1'b0;
        camtx_href_seen  <= 1'b0;
        camtx_valid_seen <= 1'b0;
    end else begin
        camtx_pclk_sync <= {camtx_pclk_sync[1:0], cam_pclk};
        if (camtx_pclk_edge)   camtx_pclk_seen  <= 1'b1;
        if (cmos_frame_vsync)  camtx_vsync_seen <= 1'b1;
        if (cmos_frame_href)   camtx_href_seen  <= 1'b1;
        if (cmos_frame_valid)  camtx_valid_seen <= 1'b1;
    end
end
assign led = {camtx_valid_seen, camtx_href_seen, camtx_vsync_seen, camtx_pclk_seen};
`else
`ifdef CAM_INPUT_PROBE
// =============================================================
// 鎽勫儚澶磋緭鍏ヨ瘖鏂?sticky 鎺㈤�?(�?KEY1 娓呴�?
//   LED1 = OV5640 I2C 鍒濆�鍖栧畬�?cam_init_done
//   LED2 = 閲囬泦绔�嚭鐜拌�?cmos_frame_vsync
//   LED3 = 閲囬泦绔�嚭鐜拌�?cmos_frame_href
//   LED4 = 閲囬泦绔�嚭鐜拌�?cmos_frame_valid
// =============================================================
reg [2:0] camprobe_pclk_sync;
reg [2:0] camprobe_vsraw_sync;
reg [2:0] camprobe_hsraw_sync;
reg       camprobe_pclk_seen;
reg       camprobe_vsraw_seen;
reg       camprobe_hsraw_seen;
reg       camprobe_href_pclk_seen;
reg       camprobe_vsync_seen;
reg       camprobe_href_seen;
reg       camprobe_data_seen;
reg       camprobe_cvalid_seen;
reg       camprobe_cdata_seen;
reg       camprobe_tx_busy_seen;
reg       camprobe_tx_byte_seen;
reg       camprobe_cmd_seen;
reg       camprobe_start_seen;
reg       camprobe_tx_req_seen;
reg       camprobe_tx_ack_seen;
reg       camprobe_temac_tx_seen;
reg       camprobe_arp_err_seen;
reg       camprobe_rx_any_seen;
reg       camprobe_rx_magic_seen;
reg       camprobe_rx_cmd30_seen;
reg       camprobe_rx_cmd31_seen;
reg [1:0] camprobe_rx_st;
reg       camprobe_fifo_wen_seen;
reg       camprobe_capture_done_seen;
reg       camprobe_fifo_nonzero_seen;
reg       camprobe_fifo_ready_seen;
reg       camprobe_init_done;
reg       camprobe_init_udp_seen;
reg       camprobe_word_vsync_d;
reg [15:0] camprobe_frame_word_cnt;
reg       camprobe_word_any_seen;
reg       camprobe_word_240_seen;
reg       camprobe_word_800_seen;
reg       camprobe_word_4800_seen;
reg       camprobe_hxv2_ready_seen;
reg       camprobe_hxv2_rused_seen;
wire      camprobe_word_frame_start = cam_vsync & ~camprobe_word_vsync_d;
wire      camprobe_pclk_edge  = camprobe_pclk_sync[2] ^ camprobe_pclk_sync[1];
wire      camprobe_vsraw_edge = camprobe_vsraw_sync[2] ^ camprobe_vsraw_sync[1];
wire      camprobe_hsraw_edge = camprobe_hsraw_sync[2] ^ camprobe_hsraw_sync[1];

// 复刻 cmos_capture_data �?frame_val_flag 逻辑，用相同复位 (rst_n & cam_init_done)�?
// 判断该复位条件下 frame_val_flag 能否置位�?
wire       camprobe_cap_rst = rst_n & cam_init_done;
reg        rep_vs_d0, rep_vs_d1;
wire       rep_pos_vsync = (~rep_vs_d1) & rep_vs_d0;
reg [3:0]  rep_ps_cnt;
reg        rep_frame_val;
always @(posedge cam_pclk or negedge camprobe_cap_rst) begin
    if (!camprobe_cap_rst) begin
        rep_vs_d0     <= 1'b0;
        rep_vs_d1     <= 1'b0;
        rep_ps_cnt    <= 4'd0;
        rep_frame_val <= 1'b0;
    end else begin
        rep_vs_d0 <= cam_vsync;
        rep_vs_d1 <= rep_vs_d0;
        if (rep_pos_vsync && (rep_ps_cnt < 4'd10)) rep_ps_cnt <= rep_ps_cnt + 4'd1;
        if ((rep_ps_cnt == 4'd10) && rep_pos_vsync) rep_frame_val <= 1'b1;
    end
end
reg rep_fv_seen;
always @(posedge cam_pclk or negedge key1) begin
    if (!key1)            rep_fv_seen <= 1'b0;
    else if (rep_frame_val) rep_fv_seen <= 1'b1;
end

always @(posedge clk_25 or negedge key1) begin
    if (!key1) begin
        camprobe_pclk_sync  <= 3'b000;
        camprobe_vsraw_sync <= 3'b000;
        camprobe_hsraw_sync <= 3'b000;
        camprobe_pclk_seen  <= 1'b0;
        camprobe_vsraw_seen <= 1'b0;
        camprobe_hsraw_seen <= 1'b0;
        camprobe_vsync_seen <= 1'b0;
        camprobe_href_seen  <= 1'b0;
        camprobe_data_seen  <= 1'b0;
        camprobe_init_done  <= 1'b0;
    end else begin
        camprobe_pclk_sync  <= {camprobe_pclk_sync[1:0],  cam_pclk};
        camprobe_vsraw_sync <= {camprobe_vsraw_sync[1:0], cam_vsync};
        camprobe_hsraw_sync <= {camprobe_hsraw_sync[1:0], cam_href};
        if (camprobe_pclk_edge)  camprobe_pclk_seen  <= 1'b1;
        if (camprobe_vsraw_edge) camprobe_vsraw_seen <= 1'b1;
        if (camprobe_hsraw_edge) camprobe_hsraw_seen <= 1'b1;
        if (cmos_frame_vsync)    camprobe_vsync_seen <= 1'b1;
        if (cmos_frame_href)     camprobe_href_seen  <= 1'b1;
        if (|cam_data)           camprobe_data_seen  <= 1'b1;
        if (cam_init_done)       camprobe_init_done  <= 1'b1;
    end
end
always @(posedge cam_pclk or negedge key1) begin
    if (!key1) begin
        camprobe_cvalid_seen      <= 1'b0;
        camprobe_cdata_seen       <= 1'b0;
        camprobe_fifo_wen_seen    <= 1'b0;
        camprobe_href_pclk_seen   <= 1'b0;
        camprobe_word_vsync_d     <= 1'b0;
        camprobe_frame_word_cnt   <= 16'd0;
        camprobe_word_any_seen    <= 1'b0;
        camprobe_word_240_seen    <= 1'b0;
        camprobe_word_800_seen    <= 1'b0;
        camprobe_word_4800_seen   <= 1'b0;
    end else begin
        camprobe_word_vsync_d <= cam_vsync;

        if (cam_href) camprobe_href_pclk_seen <= 1'b1;
        if (cmos_frame_valid) begin
            camprobe_cvalid_seen   <= 1'b1;
            camprobe_word_any_seen <= 1'b1;
            if (camprobe_frame_word_cnt >= 16'd239)  camprobe_word_240_seen  <= 1'b1;
            if (camprobe_frame_word_cnt >= 16'd799)  camprobe_word_800_seen  <= 1'b1;
            if (camprobe_frame_word_cnt >= 16'd4799) camprobe_word_4800_seen <= 1'b1;
        end
        if (cmos_frame_valid && (|cmos_frame_data)) camprobe_cdata_seen <= 1'b1;
        if (cam_fifo_wen) camprobe_fifo_wen_seen <= 1'b1;

        if (camprobe_word_frame_start) begin
            camprobe_frame_word_cnt <= 16'd0;
        end else if (cmos_frame_valid && (camprobe_frame_word_cnt != 16'hffff)) begin
            camprobe_frame_word_cnt <= camprobe_frame_word_cnt + 1'b1;
        end
    end
end

always @(posedge udp_clk or negedge key1) begin
    if (!key1) begin
        camprobe_tx_busy_seen    <= 1'b0;
        camprobe_tx_byte_seen    <= 1'b0;
        camprobe_cmd_seen        <= 1'b0;
        camprobe_start_seen      <= 1'b0;
        camprobe_tx_req_seen     <= 1'b0;
        camprobe_tx_ack_seen     <= 1'b0;
        camprobe_temac_tx_seen   <= 1'b0;
        camprobe_arp_err_seen    <= 1'b0;
        camprobe_rx_any_seen     <= 1'b0;
        camprobe_rx_magic_seen   <= 1'b0;
        camprobe_rx_cmd30_seen   <= 1'b0;
        camprobe_rx_cmd31_seen   <= 1'b0;
        camprobe_rx_st             <= 2'd0;
        camprobe_capture_done_seen <= 1'b0;
        camprobe_fifo_nonzero_seen <= 1'b0;
        camprobe_fifo_ready_seen   <= 1'b0;
        camprobe_init_udp_seen     <= 1'b0;
        camprobe_hxv2_ready_seen   <= 1'b0;
        camprobe_hxv2_rused_seen   <= 1'b0;
    end else begin
        if (app_rx_data_valid) begin
            camprobe_rx_any_seen <= 1'b1;
            case (camprobe_rx_st)
                2'd0: camprobe_rx_st <= (app_rx_data == `MAGIC0) ? 2'd1 : 2'd0;
                2'd1: begin
                    if (app_rx_data == `MAGIC1) begin
                        camprobe_rx_magic_seen <= 1'b1;
                        camprobe_rx_st <= 2'd2;
                    end else begin
                        camprobe_rx_st <= (app_rx_data == `MAGIC0) ? 2'd1 : 2'd0;
                    end
                end
                2'd2: begin
                    if (app_rx_data == `CMD_CAM_START) camprobe_rx_cmd30_seen <= 1'b1;
                    if (app_rx_data == `CMD_CAM_FRAME) camprobe_rx_cmd31_seen <= 1'b1;
                    camprobe_rx_st <= 2'd0;
                end
                default: camprobe_rx_st <= 2'd0;
            endcase
        end
        if (cam_frame_req_pulse) camprobe_cmd_seen <= 1'b1;
        if (cam_init_udp) camprobe_init_udp_seen <= 1'b1;
        if (cam_start_pulse_udp) camprobe_start_seen <= 1'b1;
        if (cam_app_tx_request) camprobe_tx_req_seen <= 1'b1;
        if (cam_app_tx_ack) camprobe_tx_ack_seen <= 1'b1;
        if (cam_tx_busy) camprobe_tx_busy_seen <= 1'b1;
        if (cam_capture_done_udp) camprobe_capture_done_seen <= 1'b1;
        if (cam_fifo_rused != 14'd0) camprobe_fifo_nonzero_seen <= 1'b1;
        if (cam_capture_ready_udp && cam_frame_fifo_ready) camprobe_fifo_ready_seen <= 1'b1;
        if (cam_app_tx_data_valid) camprobe_tx_byte_seen <= 1'b1;
        if (cam_udp_tx_ready) camprobe_hxv2_ready_seen <= 1'b1;
        if (cam_hxv2_rused >= 12'd640) camprobe_hxv2_rused_seen <= 1'b1;
        if (cam_tx_busy && !temac_tx_valid) camprobe_temac_tx_seen <= 1'b1;
        if (udp_arp_no_reply_error) camprobe_arp_err_seen <= 1'b1;
    end
end
// CAM_INPUT_PROBE LED mux (KEY1 clears sticky LEDs):
//   LED1=cam_hxv2_tx saw >=640 FIFO words
//   LED2=cam_hxv2_tx entered S_REQ
//   LED3=cam_hxv2_tx saw app_tx_ack
//   LED4=cam_hxv2_tx entered S_SEND / output first byte
assign led = cam_hxv2_dbg_state_seen;
`else
`ifdef SD_PHOTO_PROBE
// =============================================================
// SD 鐓х墖鍒嗛樁娈?sticky 鎺㈤�?(�?KEY1 娓呴�?
//   LED1 = sd_init_done (瀹炴�?: SD �?SPI 鍒濆�鍖栨垚�?
//   LED2 = 骞惰�瑙ｆ瀽鍒?A5 5A 50: CMD_SD_PHOTO 瀛楄妭鍒拌揪 app �?
//   LED3 = sd_photo_req 鍑虹幇杩? cmd_decode 瑙ｆ瀽鍑哄懡�?
//   LED4 = frame_ready 鍑虹幇杩? 璇诲�?+ 闄嶉噰鏍峰畬�?
// 鍒よ�? LED2�?瀛楄妭娌″埌; LED2浜甃ED3�?cmd_decode娌¤В鏋? LED3浜甃ED4�?璇诲崱娌″畬�?
// =============================================================
reg [1:0] sdp_st;          // 0=idle 1=gotA5 2=got5A
reg       sdp_hdr_seen;    // LED2: 鐪嬪�?A5 5A 50
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
`endif

// 鍩虹�瑕佹眰 鈶狅細PC 鍛戒护鎺у�?4 浣嶆暟鐮佺�鏄剧ず銆?
`endif
`endif
seg_scan u_seg_scan (
    .clk    (clk_25_out),
    .rst_n  (rst_n),
    .bcd_in (seg_bcd_eth[15:0]),
    .seg    (seg),
    .en     (seg_en)
);

reg [15:0] input_local_udp_port_num;
reg        input_local_udp_port_num_valid;

// 鍗忚�鏍堝疄娴嬬‖缂栫爜鐩戝�?port 1, 杩欓噷鍙�槸鍋氭牱�?(涓嶅奖鍝嶅疄闄呰�涓?
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

// PC 鍥剧墖涓婁紶�?VGA 涓昏矾寰勭户缁�繚鐣欙紱鏂板�浣庤祫婧愭憚鍍忓ご闀滃儚鍥炰紶璺�緞鐢ㄤ簬鍩虹�瑕佹�?鈶ｃ�?
wire        img_wr_en;
wire [7:0]  img_wr_addr;
wire [5:0]  img_wr_data;
wire [7:0]  cam_rd_addr;
wire [5:0]  cam_rd_data;

// 鍩虹�瑕佹眰 �?: TF �?BMP 鐓х墖璇诲�?-> RGB565 FIFO -> UDP 鍥炰紶銆?
// PC 绔��?CMD_SD_PHOTO(0x50) 涓嬪�?BMP 璧峰�鎵囧尯锛孎PGA 鍥炰�?CMD_PHOTO_DATA(0x51)�?
wire        sd_clk_ref;
wire        sd_clk_ref_180;
wire        sd_pll_lock;
wire        sd_rst_n;
wire        sd_rd_start_en;
wire [31:0] sd_rd_sec_addr;
wire        sd_rd_busy;
wire        sd_rd_val_en;
wire [15:0] sd_rd_val_data;
wire        sd_fifo_wen;
wire [15:0] sd_fifo_wdata;
wire [11:0] sd_fifo_wused;
wire        sd_photo_done_sd;
wire        sd_photo_busy_sd;
wire        photo_fifo_ren;
wire [15:0] photo_fifo_rdata;
wire        photo_fifo_rempty;
wire [11:0] photo_fifo_rused;
wire        photo_start_udp;
wire        photo_start_sd;
wire        photo_tx_busy;
wire        photo_done_udp;

// 鍩虹�瑕佹眰 �?: 淇濈暀 OV5640 16x16 鏃ц矾寰勶紝鍚屾椂鎺ュ叆淇濆畧�?64x24 RGB565 camcap�?
wire        cam_init_done;
wire        cam_tx_busy;
wire        cam_done_udp;
wire        cam_fifo_ren;
wire [15:0] cam_fifo_rdata;
wire [13:0] cam_fifo_rused;
wire        cam_fifo_rempty;
wire        cam_fifo_wfull;
wire [13:0] cam_fifo_wused;
wire        cam_fifo_wen;
wire [15:0] cam_fifo_wdata;
wire        cam_fifo_wflush;
wire        cam_capture_busy;
wire        cam_capture_done_tog;
wire        cam_capture_overflow_tog;
wire        cam_cap_dbg_start_seen;
wire        cam_cap_dbg_vsync_seen;
wire        cam_cap_dbg_cap_seen;
wire        cam_cap_dbg_wen_seen;
wire        cam_cap_dbg_pix_80_seen;
wire        cam_cap_dbg_pix_240_seen;
wire        cam_cap_dbg_pix_800_seen;
wire        cam_cap_dbg_href_4_seen;
wire        cam_cap_dbg_href_16_seen;
reg         cam_init_meta;
reg         cam_init_udp;
reg         cam_active_udp;
reg         cam_seen_busy_udp;
reg         cam_start_pulse_udp;
reg         cam_stream_started;
wire        cam_capture_ready_udp;
wire [11:0] cam_hxv2_rused;
wire [3:0]  cam_hxv2_dbg_state_seen;
reg         cam_done_meta;
reg         cam_done_sync;
reg         cam_done_d;
reg         cam_ovf_meta;
reg         cam_ovf_sync;
reg         cam_ovf_d;
localparam [29:0] CAM_WAIT_MAX     = 30'd500000000;
localparam [13:0] CAM_FRAME_WORDS  = 14'd4800;      // 80x60 RGB565 pixels, one 16-bit word per pixel
reg  [29:0] cam_wait_cnt;
wire        cam_overflow_udp       = cam_ovf_sync ^ cam_ovf_d;
wire        cam_capture_done_udp   = cam_done_sync ^ cam_done_d;
wire        cam_frame_fifo_ready   = (cam_fifo_rused >= CAM_FRAME_WORDS);
wire        cam_timeout_udp        = (cam_active_udp && !cam_seen_busy_udp) &&
                                      (cam_wait_cnt == CAM_WAIT_MAX);
`ifdef CAM_USE_PATTERN_TX
wire        cam_stream_start       = cam_active_udp && !cam_stream_started && !photo_active_udp;
`else
// After CMD_CAM_FRAME, read_start freezes the completed BRAM frame; one
// clock later fifo_rused remains a full frame even though frame_ready has
// been consumed.
wire        cam_stream_start       = cam_active_udp && cam_frame_fifo_ready && !cam_stream_started && !photo_active_udp;
`endif

// ---- 杩愬姩鐩�爣妫€娴嬭拷韪? 瑙嗛�?BRAM 璇绘帴鍙?+ 妫€娴嬪厓鏁版嵁 (cam_motion_track) ----
wire        cam_trk_rclear;
wire        cam_trk_ren;
wire [15:0] cam_trk_rdata;
wire [6:0]  cam_m_xmin, cam_m_xmax, cam_m_ymin, cam_m_ymax;
wire [12:0] cam_m_area;
wire        cam_m_valid;
wire        cam_m_result_tog;
// udp_clk 鍩熼攣瀛樼殑妫€娴嬪厓鏁版�?(toggle 鍚屾�?
reg  [7:0]  trk_xmin, trk_xmax, trk_ymin, trk_ymax;
reg  [15:0] trk_area;
reg         trk_valid;
reg         m_tog_meta, m_tog_sync, m_tog_d;
always @(posedge udp_clk or negedge rst_n) begin
    if (!rst_n) begin
        m_tog_meta <= 1'b0; m_tog_sync <= 1'b0; m_tog_d <= 1'b0;
        trk_xmin <= 8'd0; trk_xmax <= 8'd0; trk_ymin <= 8'd0; trk_ymax <= 8'd0;
        trk_area <= 16'd0; trk_valid <= 1'b0;
    end else begin
        m_tog_meta <= cam_m_result_tog;
        m_tog_sync <= m_tog_meta;
        m_tog_d    <= m_tog_sync;
        if (m_tog_sync ^ m_tog_d) begin
            trk_xmin  <= {1'b0, cam_m_xmin};
            trk_xmax  <= {1'b0, cam_m_xmax};
            trk_ymin  <= {1'b0, cam_m_ymin};
            trk_ymax  <= {1'b0, cam_m_ymax};
            trk_area  <= {3'd0, cam_m_area};
            trk_valid <= cam_m_valid;
        end
    end
end

assign cam_done_udp  = cam_seen_busy_udp & ~cam_tx_busy;
assign sd_rst_n      = rst_n & sd_pll_lock;

pll_50 u_pll_50_sd (
    .refclk   (clk_25),
    .reset    (~rst_n),
    .extlock  (sd_pll_lock),
    .clk0_out (sd_clk_ref),
    .clk1_out (sd_clk_ref_180),
    .clk2_out ()
);

sd_ctrl_top u_sd_ctrl_top (
    .clk_ref        (sd_clk_ref),
    .clk_ref_180deg (sd_clk_ref_180),
    .rst_n          (sd_rst_n),
    .sd_miso        (sd_miso),
    .sd_clk         (sd_clk),
    .sd_cs          (sd_cs),
    .sd_mosi        (sd_mosi),
    .wr_busy        (),
    .rd_start_en    (sd_rd_start_en),
    .rd_sec_addr    (sd_rd_sec_addr),
    .rd_busy        (sd_rd_busy),
    .rd_val_en      (sd_rd_val_en),
    .rd_val_data    (sd_rd_val_data),
    .sd_init_done   (sd_init_done)
);

// UDP 鍛戒护鍩?-> SD 璇诲崱鍩熴€俻c_test.py 浼氶噸澶嶅彂 8 娆″懡浠わ紝photo_active_udp 闃叉�閲嶅�閲嶅惎銆?
reg        sd_init_meta;
reg        sd_init_udp;
reg        photo_active_udp;
reg        photo_seen_busy_udp;
reg [31:0] photo_sec_udp;
reg        photo_start_tog_udp;
reg        photo_start_pulse_udp;

assign photo_start_udp = photo_start_pulse_udp;
assign photo_done_udp  = photo_seen_busy_udp & ~photo_tx_busy;
assign frame_ready_udp = photo_done_udp;

always @(posedge udp_clk or negedge rst_n) begin
    if (!rst_n) begin
        sd_init_meta          <= 1'b0;
        sd_init_udp           <= 1'b0;
        photo_active_udp      <= 1'b0;
        photo_seen_busy_udp   <= 1'b0;
        photo_sec_udp         <= 32'd0;
        photo_start_tog_udp   <= 1'b0;
        photo_start_pulse_udp <= 1'b0;
    end else begin
        sd_init_meta          <= sd_init_done;
        sd_init_udp           <= sd_init_meta;
        photo_start_pulse_udp <= 1'b0;

        if (photo_active_udp && photo_tx_busy)
            photo_seen_busy_udp <= 1'b1;

        if (photo_done_udp) begin
            photo_active_udp    <= 1'b0;
            photo_seen_busy_udp <= 1'b0;
        end else if (sd_photo_req && sd_init_udp && !photo_active_udp && !cam_active_udp) begin
            photo_active_udp      <= 1'b1;
            photo_seen_busy_udp   <= 1'b0;
            photo_sec_udp         <= sd_sec_addr_cmd;
            photo_start_tog_udp   <= ~photo_start_tog_udp;
            photo_start_pulse_udp <= 1'b1;
        end
    end
end

reg        photo_start_sd_meta;
reg        photo_start_sd_sync;
reg        photo_start_sd_d;
reg        photo_start_sd_pulse;
reg [31:0] photo_sec_sd;
wire       photo_start_sd_edge = photo_start_sd_sync ^ photo_start_sd_d;

// 鍏堝�?SD 鏃堕挓鍩熼攣瀛樻墖鍖哄彿锛屽啀涓嬩竴鎷嶅惎鍔ㄨ�鍗°�?
// 鍚﹀�?sd_photo64 浼氬�?start 鍚屾媿閲囧埌�?start_sector锛屽�鏄撹��?0 鎵囧尯鑰岀敓鎴愰粦鍥俱�?
assign photo_start_sd = photo_start_sd_pulse;

always @(posedge sd_clk_ref or negedge sd_rst_n) begin
    if (!sd_rst_n) begin
        photo_start_sd_meta  <= 1'b0;
        photo_start_sd_sync  <= 1'b0;
        photo_start_sd_d     <= 1'b0;
        photo_start_sd_pulse <= 1'b0;
        photo_sec_sd         <= 32'd0;
    end else begin
        photo_start_sd_meta  <= photo_start_tog_udp;
        photo_start_sd_sync  <= photo_start_sd_meta;
        photo_start_sd_d     <= photo_start_sd_sync;
        photo_start_sd_pulse <= 1'b0;
        if (photo_start_sd_edge) begin
            photo_sec_sd         <= photo_sec_udp;
            photo_start_sd_pulse <= 1'b1;
        end
    end
end

dpram_64x64 #(
    .DW(16),
    .AW(11)
) u_photo_fifo (
    .wclk    (sd_clk_ref),
    .wrst_n  (sd_rst_n),
    .wflush  (photo_start_sd),
    .wen     (sd_fifo_wen),
    .wdata   (sd_fifo_wdata),
    .wfull   (),
    .wused   (sd_fifo_wused),
    .rclk    (udp_clk),
    .rrst_n  (rst_n),
    .rflush  (photo_start_udp),
    .ren     (photo_fifo_ren),
    .rdata   (photo_fifo_rdata),
    .rempty  (photo_fifo_rempty),
    .rused   (photo_fifo_rused)
);

sd_photo64 u_sd_photo64 (
    .clk          (sd_clk_ref),
    .rst_n        (sd_rst_n),
    .start        (photo_start_sd),
    .start_sector (photo_sec_sd),
    .rd_busy      (sd_rd_busy),
    .rd_val_en    (sd_rd_val_en),
    .rd_val_data  (sd_rd_val_data),
    .rd_start_en  (sd_rd_start_en),
    .rd_sec_addr  (sd_rd_sec_addr),
    .fifo_wen     (sd_fifo_wen),
    .fifo_wdata   (sd_fifo_wdata),
    .fifo_wused   (sd_fifo_wused),
    .done         (sd_photo_done_sd),
    .busy         (sd_photo_busy_sd)
);

// UDP 鍛戒护鍩熸憚鍍忓ご澶у浘璇锋眰鎺у埗銆侾C 浼氶噸澶嶅彂鍛戒护锛宑am_active_udp 闃叉�閲嶅�鍚�姩銆?
always @(posedge udp_clk or negedge rst_n) begin
    if (!rst_n) begin
        cam_init_meta        <= 1'b0;
        cam_init_udp         <= 1'b0;
        cam_active_udp       <= 1'b0;
        cam_seen_busy_udp    <= 1'b0;
        cam_start_pulse_udp  <= 1'b0;
        cam_stream_started   <= 1'b0;
        cam_done_meta        <= 1'b0;
        cam_done_sync        <= 1'b0;
        cam_done_d           <= 1'b0;
        cam_ovf_meta         <= 1'b0;
        cam_ovf_sync         <= 1'b0;
        cam_ovf_d            <= 1'b0;
        cam_wait_cnt         <= 30'd0;
    end else begin
        cam_init_meta       <= cam_init_done;
        cam_init_udp        <= cam_init_meta;
        cam_done_meta       <= cam_capture_done_tog;
        cam_done_sync       <= cam_done_meta;
        cam_done_d          <= cam_done_sync;
        cam_ovf_meta        <= cam_capture_overflow_tog;
        cam_ovf_sync        <= cam_ovf_meta;
        cam_ovf_d           <= cam_ovf_sync;
        cam_start_pulse_udp <= 1'b0;

        if (cam_active_udp && !cam_seen_busy_udp && cam_tx_busy)
            cam_wait_cnt <= 30'd0;
        else if ((cam_active_udp && !cam_seen_busy_udp) &&
                 (cam_wait_cnt != CAM_WAIT_MAX))
            cam_wait_cnt <= cam_wait_cnt + 1'b1;

        if (cam_stream_start)
            cam_stream_started <= 1'b1;

        if (cam_active_udp && cam_tx_busy)
            cam_seen_busy_udp <= 1'b1;

        if (img_req_pulse) begin
            // CMD_IMG_REQ has priority; abort only the camera UDP sender.
            // Continuous camera capture keeps the frame buffer logic alive.
            cam_active_udp     <= 1'b0;
            cam_seen_busy_udp  <= 1'b0;
            cam_stream_started <= 1'b0;
            cam_wait_cnt       <= 30'd0;
        end else if (!cam_en) begin
            cam_active_udp     <= 1'b0;
            cam_seen_busy_udp  <= 1'b0;
            cam_stream_started <= 1'b0;
            cam_wait_cnt       <= 30'd0;
        end else if (cam_done_udp || cam_timeout_udp) begin
            cam_active_udp     <= 1'b0;
            cam_seen_busy_udp  <= 1'b0;
            cam_stream_started <= 1'b0;
            cam_wait_cnt       <= 30'd0;
        end else if (cam_frame_req_pulse && cam_en && cam_capture_ready_udp && cam_frame_fifo_ready &&
                     !photo_active_udp && !cam_active_udp && !cam_tx_busy) begin
            // CMD_CAM_FRAME now freezes the completed BRAM frame and immediately
            // starts the UDP packetizer.  While UDP is reading it, new camera
            // frames are dropped instead of allocating a second full-frame bank.
            cam_active_udp      <= 1'b1;
            cam_seen_busy_udp   <= 1'b0;
            cam_stream_started  <= 1'b0;
            cam_start_pulse_udp <= 1'b1;
            cam_wait_cnt        <= 30'd0;
        end
    end
end

// 鏈€�?FPGA->PC 鍥炲寘閾捐矾宸查獙璇侀€氳繃锛屾墦寮€鎽勫儚澶寸‖浠舵帴鍏ュ�?16x16 蹇��?bring-up�?
// 鑻ュ惎鐢ㄥ悗 TD 璧勬�?鏃跺簭鎴?LED/UDP 鎺ユ敹寮傚父锛屽彲涓存椂娉ㄩ噴涓嬩竴琛屽洖閫€鍒板畨鍏ㄥ叧闂�姸鎬併�?
`ifdef BASIC4_CAMERA_ENABLE
wire        cmos_frame_vsync;
wire        cmos_frame_href;
wire        cmos_frame_valid;
wire [15:0] cmos_frame_data;

// OV5640 uses the same stable 640x480 timing as the working reference project;
// local paths downsample it to 16x16 preview and 80x60 PC-return frames.
ov5640_dri u_ov5640_dri (
    .clk              (clk_25),
    .rst_n            (rst_n),
    .cam_pclk         (cam_pclk),
    .cam_vsync        (cam_vsync),
    .cam_href         (cam_href),
    .cam_data         (cam_data),
    .cam_rst_n        (cam_rst_n),
    .cam_pwdn         (cam_pwdn),
    .cam_scl          (cam_scl),
    .cam_sda          (cam_sda),
    .cmos_h_pixel     (13'd640),
    .cmos_v_pixel     (13'd480),
    .total_h_pixel    (13'd1856),
    .total_v_pixel    (13'd984),
    .capture_start    (1'b1),
    .cam_init_done    (cam_init_done),
    .cmos_frame_vsync (cmos_frame_vsync),
    .cmos_frame_href  (cmos_frame_href),
    .cmos_frame_valid (cmos_frame_valid),
    .cmos_frame_data  (cmos_frame_data)
);

cam_to_bram #(
    .SRC_W (11'd640),
    .SRC_H (11'd480),
    .DST_W (5'd16),
    .DST_H (5'd16),
    .DEC_X (7'd40),
    .DEC_Y (7'd30)
) u_cam_to_bram (
    .cam_pclk          (cam_pclk),
    .rst_n             (rst_n),
    .cmos_frame_vsync  (cmos_frame_vsync),
    .cmos_frame_href   (cmos_frame_href),
    .cmos_frame_valid  (cmos_frame_valid),
    .cmos_frame_data   (cmos_frame_data),
    .rd_addr           (cam_rd_addr),
    .rd_data           (cam_rd_data)
);

// Optional motion metadata path.  The verified reference camera-return project
// streams only the camera pixels; disabling this path saves one 4800x7 frame
// history buffer and keeps the first bring-up focused on reliable PC return.
`ifdef CAM_MOTION_TRACK_ENABLE
cam_motion_track #(
    .SRC_W (11'd640),
    .SRC_H (11'd480),
    .OUT_W (7'd80),
    .OUT_H (7'd60),
    .DEC_X (4'd8),
    .DEC_Y (4'd8)
) u_cam_motion_track (
    .cam_pclk          (cam_pclk),
    .rst_n             (rst_n),
    .cmos_frame_vsync  (cmos_frame_vsync),
    .cmos_frame_href   (cmos_frame_href),
    .cmos_frame_valid  (cmos_frame_valid),
    .cmos_frame_data   (cmos_frame_data),
    .rclk              (udp_clk),
    .rclear            (cam_trk_rclear),
    .ren               (cam_trk_ren),
    .rdata             (cam_trk_rdata),
    .m_xmin            (cam_m_xmin),
    .m_xmax            (cam_m_xmax),
    .m_ymin            (cam_m_ymin),
    .m_ymax            (cam_m_ymax),
    .m_area            (cam_m_area),
    .m_valid           (cam_m_valid),
    .result_tog        (cam_m_result_tog)
);
`else
assign cam_trk_rdata    = 16'd0;
assign cam_m_xmin       = 7'd0;
assign cam_m_xmax       = 7'd0;
assign cam_m_ymin       = 7'd0;
assign cam_m_ymax       = 7'd0;
assign cam_m_area       = 13'd0;
assign cam_m_valid      = 1'b0;
assign cam_m_result_tog = 1'b0;
`endif

// 褰撳�?camcap 鍏堣蛋鍥哄畾鍥炬�鍙戦€佸櫒锛屼笉璇诲彇鐪熷疄鎽勫儚�?FIFO�?
// 鐪熷�?FIFO/閲囨牱璺�緞绛夊浐瀹氬浘妗?6 鍖呯ǔ瀹氬悗鍐嶆帴鍏ワ紝閬垮厤鍐嶆�褰卞搷�?img 鍥炲寘銆?
// 真实摄像头路径：OV5640 640x480 降采样到 80x60，写入单 BRAM 帧缓存，UDP 端按 20 包回传。
cam_frame_capture #(
    .SRC_W     (11'd640),
    .SRC_H     (11'd480),
    .OUT_W     (10'd80),
    .OUT_H     (10'd60),
    .DEC_X     (4'd8),
    .DEC_Y     (4'd8),
    .TOTAL_PIX (16'd4800),
    .FIFO_ROOM (14'd8000)
) u_cam_frame_capture (
    .cam_pclk          (cam_pclk),
    .rst_n             (rst_n),
    .capture_en        (cam_init_udp && cam_en),
    .cmos_frame_vsync  (cmos_frame_vsync),
    .cmos_frame_href   (cmos_frame_href),
    .cmos_frame_valid  (cmos_frame_valid),
    .cmos_frame_data   (cmos_frame_data),
    .rclk              (udp_clk),
    .read_start        (cam_start_pulse_udp),
    .read_abort        (img_req_pulse | !cam_en),
    .fifo_ren          (cam_fifo_ren),
    .fifo_rdata        (cam_fifo_rdata),
    .fifo_rused        (cam_fifo_rused),
    .fifo_rempty       (cam_fifo_rempty),
    .frame_ready       (cam_capture_ready_udp),
    .fifo_wfull        (cam_fifo_wfull),
    .fifo_wused        (cam_fifo_wused),
    .fifo_wen          (cam_fifo_wen),
    .fifo_wdata        (cam_fifo_wdata),
    .fifo_wflush       (cam_fifo_wflush),
    .busy              (cam_capture_busy),
    .done_toggle       (cam_capture_done_tog),
    .overflow_toggle   (cam_capture_overflow_tog),
    .dbg_start_seen    (cam_cap_dbg_start_seen),
    .dbg_vsync_seen    (cam_cap_dbg_vsync_seen),
    .dbg_cap_seen      (cam_cap_dbg_cap_seen),
    .dbg_wen_seen      (cam_cap_dbg_wen_seen),
    .dbg_pix_80_seen   (cam_cap_dbg_pix_80_seen),
    .dbg_pix_240_seen  (cam_cap_dbg_pix_240_seen),
    .dbg_pix_800_seen  (cam_cap_dbg_pix_800_seen),
    .dbg_href_4_seen   (cam_cap_dbg_href_4_seen),
    .dbg_href_16_seen  (cam_cap_dbg_href_16_seen)
);
`else
assign cam_init_done              = 1'b0;
assign cam_rd_data                = 6'd0;
assign cam_rst_n                  = 1'b0;
assign cam_pwdn                   = 1'b1;
assign cam_scl                    = 1'b1;
assign cam_sda                    = 1'bz;
assign cam_fifo_rdata             = 16'd0;
assign cam_fifo_rused             = 14'd0;
assign cam_fifo_rempty            = 1'b1;
assign cam_fifo_wfull             = 1'b0;
assign cam_fifo_wused             = 14'd0;
assign cam_fifo_wen               = 1'b0;
assign cam_fifo_wdata             = 16'd0;
assign cam_fifo_wflush            = 1'b0;
assign cam_capture_busy           = 1'b0;
assign cam_capture_done_tog       = 1'b0;
assign cam_capture_overflow_tog   = 1'b0;
assign cam_capture_ready_udp      = 1'b0;
assign cam_cap_dbg_start_seen     = 1'b0;
assign cam_cap_dbg_vsync_seen     = 1'b0;
assign cam_cap_dbg_cap_seen       = 1'b0;
assign cam_cap_dbg_wen_seen       = 1'b0;
assign cam_cap_dbg_pix_80_seen    = 1'b0;
assign cam_cap_dbg_pix_240_seen   = 1'b0;
assign cam_cap_dbg_pix_800_seen   = 1'b0;
assign cam_cap_dbg_href_4_seen    = 1'b0;
assign cam_cap_dbg_href_16_seen   = 1'b0;
assign cam_trk_rdata              = 16'd0;
assign cam_m_xmin                 = 7'd0;
assign cam_m_xmax                 = 7'd0;
assign cam_m_ymin                 = 7'd0;
assign cam_m_ymax                 = 7'd0;
assign cam_m_area                 = 13'd0;
assign cam_m_valid                = 1'b0;
assign cam_m_result_tog           = 1'b0;
`endif

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

// FPGA -> PC TX 浠茶�锛歍F 鐓х墖浼樺厛锛屽叾娆℃憚鍍忓ご澶у浘锛岀┖闂叉椂淇濈暀 16x16 img_tx_rom�?
wire        rom_app_tx_request;
wire        rom_app_tx_data_valid;
wire [7:0]  rom_app_tx_data;
wire [15:0] rom_udp_data_length;
wire        photo_app_tx_request;
wire        photo_app_tx_data_valid;
wire [7:0]  photo_app_tx_data;
wire [15:0] photo_udp_data_length;
wire        cam_app_tx_request;
wire        cam_app_tx_data_valid;
wire [7:0]  cam_app_tx_data;
wire [15:0] cam_udp_data_length;

// FPGA->PC TX 浠茶�锛歱hoto/cam 鍙��?active �?busy 鏃跺崰鐢�紱�?img 鍦ㄧ┖闂叉椂鐩撮€氥�?
// img_req_pulse 浼氬湪涓婇潰鐨勬帶鍒堕€昏緫涓�己鍒堕噴鏀?cam_active_udp锛岄伩鍏?camcap 寮傚父鍗℃�鏃ц矾寰勩�?
wire        tx_grant_photo = photo_active_udp | photo_tx_busy;
`ifdef CAM_REFERENCE_DIRECT_TX
wire        tx_grant_cam   = !tx_grant_photo & cam_en & cam_init_udp;
`else
wire        tx_grant_cam   = !tx_grant_photo & (cam_active_udp | cam_tx_busy | cam_app_tx_request | cam_app_tx_data_valid);
`endif
wire        rom_udp_tx_ready   = (!tx_grant_photo && !tx_grant_cam) ? udp_tx_ready : 1'b0;
wire        rom_app_tx_ack     = (!tx_grant_photo && !tx_grant_cam) ? app_tx_ack   : 1'b0;
wire        photo_udp_tx_ready = tx_grant_photo ? udp_tx_ready : 1'b0;
wire        photo_app_tx_ack   = tx_grant_photo ? app_tx_ack   : 1'b0;
wire        cam_udp_tx_ready   = tx_grant_cam   ? udp_tx_ready : 1'b0;
wire        cam_app_tx_ack     = tx_grant_cam   ? app_tx_ack   : 1'b0;

assign app_tx_data_request = tx_grant_photo ? photo_app_tx_request :
                             tx_grant_cam   ? cam_app_tx_request   : rom_app_tx_request;
assign app_tx_data_valid   = tx_grant_photo ? photo_app_tx_data_valid :
                             tx_grant_cam   ? cam_app_tx_data_valid   : rom_app_tx_data_valid;
assign app_tx_data         = tx_grant_photo ? photo_app_tx_data :
                             tx_grant_cam   ? cam_app_tx_data   : rom_app_tx_data;
assign udp_data_length     = tx_grant_photo ? photo_udp_data_length :
                             tx_grant_cam   ? cam_udp_data_length   : rom_udp_data_length;

// FPGA -> PC 鍥惧儚鍥炰紶锛欳MD_IMG_REQ 瑙﹀彂鍗曞寘 16x16 RGB222 鍥惧儚杩斿洖�?
// cam_en=0 鏃惰繑鍥?PC 涓婁紶鍥惧儚鐨勪綆鍒嗚鲸鐜囬暅鍍忥紱cam_en=1 鏃惰繑鍥炴憚鍍忓�?16x16 闀滃儚�?
img_tx_rom #(
    .PAY_LEN(16'd256)
) u_img_tx_rom (
    .clk                (udp_clk),
    .rst_n              (rst_n),
    .start              (img_req_pulse),
    .wr_en              (img_wr_en),
    .wr_addr            (img_wr_addr),
    .wr_data            (img_wr_data),
    .udp_tx_ready       (rom_udp_tx_ready),
    .app_tx_ack         (rom_app_tx_ack),
    .app_tx_data        (rom_app_tx_data),
    .app_tx_data_valid  (rom_app_tx_data_valid),
    .udp_data_length    (rom_udp_data_length),
    .app_tx_request     (rom_app_tx_request)
);

// TF 鍗＄収鐗囧洖浼狅細CMD_SD_PHOTO 瑙﹀彂鍚庯紝�?FIFO �?RGB565 骞跺�?600 �?UDP 鍖呭彂閫併€?
photo_tx u_photo_tx (
    .clk                (udp_clk),
    .rst_n              (rst_n),
    .start              (photo_start_udp),
    .fifo_ren           (photo_fifo_ren),
    .fifo_rdata         (photo_fifo_rdata),
    .fifo_rused         (photo_fifo_rused),
    .udp_tx_ready       (photo_udp_tx_ready),
    .app_tx_ack         (photo_app_tx_ack),
    .app_tx_data        (photo_app_tx_data),
    .app_tx_data_valid  (photo_app_tx_data_valid),
    .udp_data_length    (photo_udp_data_length),
    .app_tx_request     (photo_app_tx_request),
    .busy               (photo_tx_busy)
);

`ifdef CAM_REFERENCE_DIRECT_TX
assign cam_fifo_ren   = 1'b0;
assign cam_trk_rclear = 1'b0;
assign cam_trk_ren    = 1'b0;
cam_hxv2_tx u_cam_hxv2_tx (
    .cam_pclk           (cam_pclk),
    .rst_n              (rst_n),
    .enable             (cam_en & cam_init_udp),
    .cmos_frame_vsync   (cmos_frame_vsync),
    .cmos_frame_href    (cmos_frame_href),
    .cmos_frame_valid   (cmos_frame_valid),
    .cmos_frame_data    (cmos_frame_data),
    .clk                (udp_clk),
    .udp_tx_ready       (cam_udp_tx_ready),
    .app_tx_ack         (cam_app_tx_ack),
    .app_tx_data        (cam_app_tx_data),
    .app_tx_data_valid  (cam_app_tx_data_valid),
    .udp_data_length    (cam_udp_data_length),
    .app_tx_request     (cam_app_tx_request),
    .busy               (cam_tx_busy),
    .fifo_rused         (cam_hxv2_rused),
    .dbg_state_seen     (cam_hxv2_dbg_state_seen)
);
`else
`ifdef CAM_USE_PATTERN_TX
cam_pattern_tx #(
    .CMD_DATA (`CMD_CAM_FRAME),
    .PKT_PAY  (16'd480),
    .NPKT     (16'd20),
    .GAP_MAX  (24'd200000)
) u_cam_pattern_tx_diag (
    .clk                (udp_clk),
    .rst_n              (rst_n),
    .start              (cam_stream_start),
    .abort              (img_req_pulse),
    .udp_tx_ready       (cam_udp_tx_ready),
    .app_tx_ack         (cam_app_tx_ack),
    .app_tx_data        (cam_app_tx_data),
    .app_tx_data_valid  (cam_app_tx_data_valid),
    .udp_data_length    (cam_udp_data_length),
    .app_tx_request     (cam_app_tx_request),
    .busy               (cam_tx_busy)
);
assign cam_trk_rclear = 1'b0;
assign cam_trk_ren    = 1'b0;
`else
assign cam_trk_rclear = 1'b0;
assign cam_trk_ren    = 1'b0;
track_fifo_tx #(
    .CMD_DATA (`CMD_CAM_FRAME),
    .PKT_PAY  (16'd480),
    .NPKT     (16'd20),
    .START_TH (14'd16),
    .GAP_MAX  (24'd1000000),
    .WAIT_MAX (27'd125000000)
) u_track_fifo_tx (
    .clk                (udp_clk),
    .rst_n              (rst_n),
    .start              (cam_stream_start),
    .abort              (img_req_pulse),
    .fifo_ren           (cam_fifo_ren),
    .fifo_rdata         (cam_fifo_rdata),
    .fifo_rused         (cam_fifo_rused),
    .meta_xmin          (trk_xmin),
    .meta_xmax          (trk_xmax),
    .meta_ymin          (trk_ymin),
    .meta_ymax          (trk_ymax),
    .meta_area          (trk_area),
    .meta_valid         (trk_valid),
    .udp_tx_ready       (cam_udp_tx_ready),
    .app_tx_ack         (cam_app_tx_ack),
    .app_tx_data        (cam_app_tx_data),
    .app_tx_data_valid  (cam_app_tx_data_valid),
    .udp_data_length    (cam_udp_data_length),
    .app_tx_request     (cam_app_tx_request),
    .busy               (cam_tx_busy)
);
`endif
`endif

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
    .ip_rx_error                (udp_ip_rx_error        ),
    .arp_request_no_reply_error (udp_arp_no_reply_error )
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
    .tx_clk_en            (tx_clk_en_int            ),//output  1    12.5M  1.25M 鍗犵┖姣斾笉�?
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
    .rd_sreset            (reset                    ),
    .rd_enable            (tx_clk_en_int            ),
    .tx_data              (tx_data                  ),
    .tx_data_valid        (tx_valid                 ),
    .tx_ack               (tx_rdy                   ),
    .tx_collision         (tx_collision             ),
    .tx_retransmit        (tx_retransmit            ),
    .overflow             (                         ),

    .wr_clk               (udp_clk                  ),
    .wr_sreset            (reset                    ),
    .wr_data              (temac_tx_data            ),
    .wr_sof_n             (temac_tx_sof             ),
    .wr_eof_n             (temac_tx_eof             ),
    .wr_src_rdy_n         (temac_tx_valid           ),
    .wr_dst_rdy_n         (temac_tx_ready           ),
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

// =============================================================
// 内嵌摄像�?FIFO 发送器，避�?TD 工程漏加源文件时被识别成 black box�?
// =============================================================
// =============================================================
// track_fifo_tx.v
// 17-byte header RGB565 stream transmitter for PC track/camcap.
// Data source is an async FIFO read port. Header format matches
// pc_test.py _recv_track_frame().
// =============================================================

module track_fifo_tx #(
    parameter [7:0]  CMD_DATA = `CMD_CAM_FRAME,
    parameter [15:0] PKT_PAY  = 16'd128,
    parameter [15:0] NPKT     = 16'd75,
    parameter [13:0] START_TH = 14'd64,
    parameter [23:0] GAP_MAX  = 24'd8000,
    parameter [26:0] WAIT_MAX = 27'd125000000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire        abort,

    output wire        fifo_ren,
    input  wire [15:0] fifo_rdata,
    input  wire [13:0] fifo_rused,

    input  wire [7:0]  meta_xmin,
    input  wire [7:0]  meta_xmax,
    input  wire [7:0]  meta_ymin,
    input  wire [7:0]  meta_ymax,
    input  wire [15:0] meta_area,
    input  wire        meta_valid,

    input  wire        udp_tx_ready,
    input  wire        app_tx_ack,
    output reg  [7:0]  app_tx_data,
    output reg         app_tx_data_valid,
    output reg  [15:0] udp_data_length,
    output reg         app_tx_request,
    output wire        busy
);
    localparam [15:0] HDR_LEN  = 16'd17;
    localparam [15:0] TOT_LEN  = HDR_LEN + PKT_PAY;
    localparam [15:0] REN_LAST = HDR_LEN + PKT_PAY - 16'd3;

    localparam S_IDLE=3'd0, S_WAITDATA=3'd1, S_PREFETCH=3'd2,
               S_PREFETCH_WAIT=3'd3, S_REQ=3'd4, S_WAIT_ACK=3'd5,
               S_SEND=3'd6, S_GAP=3'd7;

    reg [2:0]  st;
    reg [15:0] cnt;
    reg [23:0] gap_cnt;
    reg [26:0] wait_cnt;
    reg [15:0] seq;
    reg [7:0]  pix_lo;
    reg [15:0] first_pix;
    reg [7:0]  lx0, lx1, ly0, ly1;
    reg [15:0] larea;
    reg        lvalid;

    assign busy = (st != S_IDLE);
    assign fifo_ren = (st==S_PREFETCH) ||
                      ((st==S_SEND) && (cnt>=HDR_LEN+16'd1) && (cnt<=REN_LAST) && (cnt[0]==1'b0));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st                <= S_IDLE;
            cnt               <= 16'd0;
            gap_cnt           <= 16'd0;
            wait_cnt          <= 27'd0;
            seq               <= 16'd0;
            pix_lo            <= 8'd0;
            first_pix         <= 16'd0;
            app_tx_request    <= 1'b0;
            app_tx_data_valid <= 1'b0;
            app_tx_data       <= 8'h00;
            udp_data_length   <= TOT_LEN;
            lx0<=0; lx1<=0; ly0<=0; ly1<=0; larea<=0; lvalid<=0;
        end else begin
            app_tx_data_valid <= 1'b0;
            if (abort) begin
                st             <= S_IDLE;
                app_tx_request <= 1'b0;
                cnt            <= 16'd0;
                gap_cnt        <= 16'd0;
                wait_cnt       <= 27'd0;
            end else begin
                case (st)
                    S_IDLE: begin
                        app_tx_request <= 1'b0;
                        if (start) begin
                            seq             <= 16'd0;
                            cnt             <= 16'd0;
                            wait_cnt        <= 27'd0;
                            udp_data_length <= TOT_LEN;
                            lx0   <= meta_xmin; lx1 <= meta_xmax;
                            ly0   <= meta_ymin; ly1 <= meta_ymax;
                            larea <= meta_area; lvalid <= meta_valid;
                            st    <= S_WAITDATA;
                        end
                    end
                    S_WAITDATA: begin
                        if ((fifo_rused >= START_TH) || (fifo_rused != 14'd0 && wait_cnt[20])) begin
                            cnt      <= 16'd0;
                            wait_cnt <= 27'd0;
                            st       <= S_PREFETCH;
                        end else if (wait_cnt == WAIT_MAX) begin
                            st       <= S_IDLE;
                            wait_cnt <= 27'd0;
                        end else begin
                            wait_cnt <= wait_cnt + 1'b1;
                        end
                    end
                    S_PREFETCH: begin
                        st <= S_PREFETCH_WAIT;
                    end
                    S_PREFETCH_WAIT: begin
                        first_pix <= fifo_rdata;
                        cnt       <= 16'd0;
                        st        <= S_REQ;
                    end
                    S_REQ: begin
                        if (udp_tx_ready) begin
                            app_tx_request <= 1'b1;
                            st             <= S_WAIT_ACK;
                        end
                    end
                    S_WAIT_ACK: begin
                        app_tx_request <= 1'b1;
                        if (app_tx_ack) begin
                            app_tx_request    <= 1'b0;
                            app_tx_data_valid <= 1'b1;
                            app_tx_data       <= `MAGIC0;
                            cnt               <= 16'd1;
                            st                <= S_SEND;
                        end
                    end
                    S_SEND: begin
                        app_tx_data_valid <= 1'b1;
                        case (cnt)
                            16'd1:  app_tx_data <= `MAGIC1;
                            16'd2:  app_tx_data <= CMD_DATA;
                            16'd3:  app_tx_data <= seq[15:8];
                            16'd4:  app_tx_data <= seq[7:0];
                            16'd5:  app_tx_data <= NPKT[15:8];
                            16'd6:  app_tx_data <= NPKT[7:0];
                            16'd7:  app_tx_data <= PKT_PAY[15:8];
                            16'd8:  app_tx_data <= PKT_PAY[7:0];
                            16'd9:  app_tx_data <= lx0;
                            16'd10: app_tx_data <= lx1;
                            16'd11: app_tx_data <= ly0;
                            16'd12: app_tx_data <= ly1;
                            16'd13: app_tx_data <= larea[15:8];
                            16'd14: app_tx_data <= larea[7:0];
                            16'd15: app_tx_data <= {7'd0, lvalid};
                            16'd16: app_tx_data <= 8'd0;
                            default: begin
                                if (cnt[0])
                                    app_tx_data <= (cnt == HDR_LEN) ? first_pix[15:8] : fifo_rdata[15:8];
                                else
                                    app_tx_data <= pix_lo;
                            end
                        endcase
                        if (cnt[0])
                            pix_lo <= (cnt == HDR_LEN) ? first_pix[7:0] : fifo_rdata[7:0];
                        cnt <= cnt + 16'd1;
                        if (cnt == TOT_LEN - 16'd1) begin
                            if (seq == NPKT - 16'd1) begin
                                st <= S_IDLE;
                            end else begin
                                seq     <= seq + 1'b1;
                                cnt     <= 16'd0;
                                gap_cnt <= 16'd0;
                                st      <= S_GAP;
                            end
                        end
                    end
                    S_GAP: begin
                        if (gap_cnt == GAP_MAX) begin
                            wait_cnt <= 27'd0;
                            st       <= (fifo_rused != 14'd0) ? S_PREFETCH : S_WAITDATA;
                        end else begin
                            gap_cnt <= gap_cnt + 1'b1;
                        end
                    end
                    default: st <= S_IDLE;
                endcase
            end
        end
    end
endmodule
