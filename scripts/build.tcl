## ============================================================
##  build.tcl
##  HX4S20C (EG4S20BG256) �?閫夐�浜?浠ュお缃戞暟鎹�紶杈撶郴�?##  TD 6.2.1 鍏ㄨ嚜鍔?缁煎�?�?甯冨眬甯冪嚎 �?bitgen
##
##  椤跺眰妯″潡 : udp_transmit_test  (src/top/udp_transmit_test.v)
##  绾︽潫鏂囦欢 : sdc/xt2.adc
##
##  浣跨敤鏂规硶 :
##    1) GUI :  Tools �?Tcl Console �?source scripts/build.tcl
##    2) 鎵瑰�鐞?:  td.exe  -bat  scripts/build.tcl
##  鐢熸垚鐗?:
##    work/udp_transmit_test.bit       鈥斺�?鐑у綍�?bitstream
##    work/udp_transmit_test_phy.area  鈥斺�?璧勬�?IO 鎶ュ�?
##    work/udp_transmit_test_pr.timing 鈥斺�?鏃跺簭鎶ュ憡
##  鐑у綍:
##    td_load.exe work/udp_transmit_test.bit  (USB 鍦ㄧ嚎涓嬭浇�?SRAM)
##    td_prog.exe work/udp_transmit_test.bit  (�?SPI Flash, 涓婄數鑷�姩鍔犺�?
##  涔熷彲鍦?TD GUI �?鈥淒ownload�?闈㈡澘閫変腑 work/udp_transmit_test.bit 鐩存帴鐑у綍銆?##
##  娉ㄦ�? 鏃х殑 top_xt2.v / src/integ/*.v �?.bak 寮冪�?(�?SDRAM/HDMI/SD 閭ｆ潯绾?,
##  鏈�剼鏈�彧缂栬�?udp_transmit_test 鐪熸�鐢ㄥ埌鐨勬ā�? 鍑忓皯缁煎悎鏃堕棿鍜?IO 鍐茬�?
## ============================================================

# -------- 1. 宸ョ▼鍩烘湰淇℃�?--------
set PRJ        udp_transmit_test
set TOPMODULE  udp_transmit_test
set DEVICE     EG4S20BG256
set PACKAGE    BG256

# 鎺ㄦ柇褰撳墠宸ョ▼鏍圭洰�?(鑴氭湰浣嶄簬 xt2_ethernet/scripts/)
set SCRIPT_DIR [file dirname [file normalize [info script]]]
set PROJ_ROOT  [file normalize "$SCRIPT_DIR/.."]

set RUN_DIR    "$PROJ_ROOT/work"
file mkdir $RUN_DIR
cd $RUN_DIR

puts "## PRJ_ROOT = $PROJ_ROOT"
puts "## RUN_DIR  = $RUN_DIR"

# -------- 2. 璁惧�?/ 宸ョ�?--------
import_device $DEVICE -package $PACKAGE
new_project   $PRJ -dir $RUN_DIR -force

# -------- 3. 婧愭枃浠舵竻�?--------
# 3.1 椤跺�?+ 鑷�啓搴旂敤�?(src/app, src/top)
set DESIGN_FILES {
    src/app/cmd_decode.v
    src/app/seg_scan.v
    src/app/cam_to_bram.v
    src/app/cam_frame_capture.v
    src/app/cam_hxv2_tx.v
    src/app/stream_tx.v
    src/app/cam_pattern_tx.v
    src/app/cam_motion_track.v
    src/app/track_stream_tx.v
    src/app/img_rx_fb.v
    src/app/sdram_img_fb.v
    src/app/img_tx_rom.v
    src/app/sobel_ondemand.v
    src/app/img_proc_inline.v
    src/app/sd_photo64.v
    src/app/photo_tx.v
    src/app/dpram_64x64.v
    src/mem/framebuf.v
    src/top/udp_transmit_test.v
}
foreach f $DESIGN_FILES {
    add_file -type verilog "$PROJ_ROOT/$f"
}

# 3.1b 鎵╁睍鈶?TF �?SD-SPI + 50MHz PLL
foreach f {
    src/vendor/al_ip/pll_50.v
    src/vendor/sd/sd_ctrl_top.v
    src/vendor/sd/sd_init.v
    src/vendor/sd/sd_read.v
} {
    add_file -type verilog "$PROJ_ROOT/$f"
}

# 3.1c vendor SDRAM 鎺у埗�?(EG_PHY_SDRAM_2M_32 + encrypted controller)
foreach f {
    global_def.v
    sdr_as_ram.enc.v
    sdr_init_ref.enc.v
    sdr_wrrd.enc.v
    sdram.v
} {
    add_file -type verilog "$PROJ_ROOT/src/vendor/sdram/$f"
}

# 3.1d vendor SDRAM framebuffer FIFO/burst 鎺у埗�?(from HX4S20 reference)
foreach f {
    afifo_16_32_256.v
    afifo_32_16_256.v
    frame_fifo_write.v
    frame_fifo_read.v
    frame_read_write.v
} {
    add_file -type verilog "$PROJ_ROOT/src/vendor/sdram_fb/$f"
}

# 3.2 vendor app �?(VGA 鏄剧�?+ UDP 瑙ｅ寘鍐?SDRAM framebuffer)
foreach f {
    src/vendor/app/addr_crt.v
    src/vendor/app/vga_disp.v
    src/vendor/app/app.v
} {
    add_file -type verilog "$PROJ_ROOT/$f"
}

# 3.3 vendor 浠ュお缃戝崗璁��?(鏈�湴鍖? 鏉ヨ嚜娓╂晠 33_HX4S20_Ethernet_test)
#     注意: udp_ip_protocol_stack_merge.enc.v 是加�?IP, TD 可直接综合�?
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

# 3.4 vendor OV5640 鎽勫儚澶?(鎵╁睍鈶?
foreach f {
    i2c_dri.v
    i2c_ov5640_rgb565_cfg.v
    ov5640_delay.v
    cmos_capture_data.v
    ov5640_dri.v
} {
    add_file -type verilog "$PROJ_ROOT/src/vendor/ov5640/$f"
}

# -------- 4. 寮曡�?/ 鏃跺簭绾︽潫 --------
read_adc "$PROJ_ROOT/sdc/xt2.adc"
# 鑻ヤ互鍚庡啓鏃跺簭绾︽潫, �?read_sdc, 渚嬪�?
#   read_sdc "$PROJ_ROOT/sdc/xt2.sdc"

# -------- 5. 椤跺眰妯″潡 / 宸ョ▼鍙傛暟 --------
set_top_model  $TOPMODULE
set_option     -top $TOPMODULE
# �?`include "pkt_fmt.vh" / "global_def.v" 找到对应头文件�?
set_option     -include_path "$PROJ_ROOT/src/app;$PROJ_ROOT/src/vendor/sdram"

# -------- 6. 鑷�姩鍖栨祦�?(read_design �?bitgen) --------
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
puts "  鐑у綍鍛戒�? : td_load.exe $RUN_DIR/${PRJ}.bit"
puts "  鎴栧�?TD GUI �?Download 闈㈡澘閲岄€変腑�?.bit 鐑у埌 SRAM/Flash"
puts "================================================================"
