## ============================================================
##  build.tcl
##  HX4S20C (EG4S20BG256) — 选题二 以太网数据传输系统
##  TD 6.2.1 全自动 综合 → 布局布线 → bitgen
##
##  顶层模块 : udp_transmit_test  (src/top/udp_transmit_test.v)
##  约束文件 : sdc/xt2.adc
##
##  使用方法 :
##    1) GUI :  Tools → Tcl Console → source scripts/build.tcl
##    2) 批处理 :  td.exe  -bat  scripts/build.tcl
##  生成物 :
##    work/udp_transmit_test.bit       —— 烧录用 bitstream
##    work/udp_transmit_test_phy.area  —— 资源/IO 报告
##    work/udp_transmit_test_pr.timing —— 时序报告
##  烧录:
##    td_load.exe work/udp_transmit_test.bit  (USB 在线下载到 SRAM)
##    td_prog.exe work/udp_transmit_test.bit  (烧 SPI Flash, 上电自动加载)
##  也可在 TD GUI 的 “Download” 面板选中 work/udp_transmit_test.bit 直接烧录。
##
##  注意: 旧的 top_xt2.v / src/integ/*.v 已 .bak 弃用 (走 SDRAM/HDMI/SD 那条线),
##  本脚本只编译 udp_transmit_test 真正用到的模块, 减少综合时间和 IO 冲突.
## ============================================================

# -------- 1. 工程基本信息 --------
set PRJ        udp_transmit_test
set TOPMODULE  udp_transmit_test
set DEVICE     EG4S20BG256
set PACKAGE    BG256

# 推断当前工程根目录 (脚本位于 xt2_ethernet/scripts/)
set SCRIPT_DIR [file dirname [file normalize [info script]]]
set PROJ_ROOT  [file normalize "$SCRIPT_DIR/.."]

set RUN_DIR    "$PROJ_ROOT/work"
file mkdir $RUN_DIR
cd $RUN_DIR

puts "## PRJ_ROOT = $PROJ_ROOT"
puts "## RUN_DIR  = $RUN_DIR"

# -------- 2. 设备 / 工程 --------
import_device $DEVICE -package $PACKAGE
new_project   $PRJ -dir $RUN_DIR -force

# -------- 3. 源文件清单 --------
# 3.1 顶层 + 自写应用层 (src/app, src/top)
set DESIGN_FILES {
    src/app/cmd_decode.v
    src/app/seg_scan.v
    src/app/cam_to_bram.v
    src/app/img_tx_rom.v
    src/app/sobel_ondemand.v
    src/app/img_proc_inline.v
    src/app/sd_photo64.v
    src/app/photo_tx.v
    src/app/dpram_64x64.v
    src/top/udp_transmit_test.v
}
foreach f $DESIGN_FILES {
    add_file -type verilog "$PROJ_ROOT/$f"
}

# 3.1b 扩展⑥ TF 卡 SD-SPI + 50MHz PLL
foreach f {
    src/vendor/al_ip/pll_50.v
    src/vendor/sd/sd_ctrl_top.v
    src/vendor/sd/sd_init.v
    src/vendor/sd/sd_read.v
} {
    add_file -type verilog "$PROJ_ROOT/$f"
}

# 3.2 vendor app 层 (VGA 显示 + UDP 解包写 BRAM)
foreach f {
    src/vendor/app/addr_crt.v
    src/vendor/app/vga_disp.v
    src/vendor/app/app.v
} {
    add_file -type verilog "$PROJ_ROOT/$f"
}

# 3.3 vendor 以太网协议栈 (本地化, 来自温故 33_HX4S20_Ethernet_test)
#     注意: udp_ip_protocol_stack_merge.enc.v 是加密 IP, TD 直接吃
set ETH_FILES {
    BUFGMUX.v
    IDDR.v
    ODDR.v
    RAMB16_S9_S9.v
    ram.v
    TEMAC_CORE_gate.v
    clk_gen_rst_gen.v
    div_clk_gen.v
    pll_gen.v
    pll_gen_1.v
    pll_gen_2.v
    rx_pll.v
    rgmii_interface.v
    rx_client_fifo.v
    tx_client_fifo.v
    tx_clk_en_gen.v
    temac_block.v
    temac_clk_gen.v
    udp_data_tpg.v
    udp_loopback.v
    udp_ip_protocol_stack_merge.enc.v
}
foreach f $ETH_FILES {
    add_file -type verilog "$PROJ_ROOT/src/vendor/eth/$f"
}

# 3.4 vendor OV5640 摄像头 (扩展⑤)
foreach f {
    i2c_dri.v
    i2c_ov5640_rgb565_cfg.v
    ov5640_delay.v
    cmos_capture_data.v
    ov5640_dri.v
} {
    add_file -type verilog "$PROJ_ROOT/src/vendor/ov5640/$f"
}

# -------- 4. 引脚 / 时序约束 --------
read_adc "$PROJ_ROOT/sdc/xt2.adc"
# 若以后写时序约束, 用 read_sdc, 例如:
#   read_sdc "$PROJ_ROOT/sdc/xt2.sdc"

# -------- 5. 顶层模块 / 工程参数 --------
set_top_model  $TOPMODULE
set_option     -top $TOPMODULE
# 让 `include "pkt_fmt.vh" 找到 src/app/pkt_fmt.vh
set_option     -include_path "$PROJ_ROOT/src/app"

# -------- 6. 自动化流程 (read_design → bitgen) --------
puts "##############  STEP 1/6 elaborate  ##############"
elaborate          -top $TOPMODULE
export_db          ${PRJ}_elaborate.db

puts "##############  STEP 2/6 optimize_rtl  ##############"
optimize_rtl
report_area        -file ${PRJ}_rtl.area
export_db          ${PRJ}_rtl.db

puts "##############  STEP 3/6 optimize_gate  ##############"
optimize_gate      -area ${PRJ}_gate.area
legalize_phy_inst
update_timing
report_timing_summary -file ${PRJ}_gate.timing
export_db          ${PRJ}_gate.db

puts "##############  STEP 4/6 place  ##############"
place
update_timing      -mode manhattan
report_timing_summary -file ${PRJ}_place.timing
report_area        -io_info -file ${PRJ}_phy.area
export_db          ${PRJ}_place.db

puts "##############  STEP 5/6 route  ##############"
route
update_timing      -mode final
report_timing_summary -file ${PRJ}_pr.timing
report_timing_status  -file ${PRJ}_phy.ts
export_db          ${PRJ}_pr.db

puts "##############  STEP 6/6 bitgen  ##############"
bitgen -bit ${PRJ}.bit

puts ""
puts "================================================================"
puts "  BUILD DONE."
puts "  Bitstream : $RUN_DIR/${PRJ}.bit"
puts "  烧录命令  : td_load.exe $RUN_DIR/${PRJ}.bit"
puts "  或在 TD GUI 的 Download 面板里选中此 .bit 烧到 SRAM/Flash"
puts "================================================================"
