// =============================================================
// pkt_fmt.vh : 应用层 UDP 报文格式
// =============================================================
`ifndef PKT_FMT_VH
`define PKT_FMT_VH

`define MAGIC0          8'hA5
`define MAGIC1          8'h5A

// CMD codes
`define CMD_LED_SET     8'h01
`define CMD_SEG_SET     8'h02
`define CMD_IMG_FRAME   8'h10
`define CMD_IMG_REQ     8'h20
`define CMD_IMG_DATA    8'h21
`define CMD_CAM_START   8'h30
`define CMD_CAM_FRAME   8'h31
`define CMD_PROC_MODE   8'h40
// 扩展⑥ : TF 卡 BMP 照片 -> PC (64x64 RGB222, 多包)
`define CMD_SD_PHOTO    8'h50
`define CMD_PHOTO_DATA  8'h51

// 图像参数 (默认 320x240 RGB332，可选 RGB565/灰度)
`define IMG_W           10'd320
`define IMG_H            9'd240

// 处理模式
`define PROC_RAW        2'd0
`define PROC_GRAY       2'd1
`define PROC_EDGE       2'd2
`define PROC_DETECT     2'd3

`endif
