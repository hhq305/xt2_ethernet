# add_all_sources.tcl
# ? TD GUI ? Tcl Console ???:
# source F:/Verilog/final/xt2_ethernet/scripts/add_all_sources.tcl
set PROJ_ROOT "F:/Verilog/final/xt2_ethernet"
set files {
    src/app/cmd_decode.v
    src/app/seg_scan.v
    src/app/cam_to_bram.v
    src/app/cam64_rgb565_bram.v
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
    src/vendor/al_ip/pll_50.v
    src/vendor/sd/sd_ctrl_top.v
    src/vendor/sd/sd_init.v
    src/vendor/sd/sd_read.v
    src/vendor/sdram/global_def.v
    src/vendor/sdram/sdr_as_ram.enc.v
    src/vendor/sdram/sdr_init_ref.enc.v
    src/vendor/sdram/sdr_wrrd.enc.v
    src/vendor/sdram/sdram.v
    src/vendor/sdram_fb/afifo_16_32_256.v
    src/vendor/sdram_fb/afifo_32_16_256.v
    src/vendor/sdram_fb/frame_fifo_write.v
    src/vendor/sdram_fb/frame_fifo_read.v
    src/vendor/sdram_fb/frame_read_write.v
    src/vendor/app/addr_crt.v
    src/vendor/app/vga_disp.v
    src/vendor/app/app.v
    src/vendor/eth/BUFGMUX.v
    src/vendor/eth/IDDR.v
    src/vendor/eth/ODDR.v
    src/vendor/eth/RAMB16_S9_S9.v
    src/vendor/eth/ram.v
    src/vendor/eth/TEMAC_CORE_gate.v
    src/vendor/eth/clk_gen_rst_gen.v
    src/vendor/eth/div_clk_gen.v
    src/vendor/eth/pll_gen.v
    src/vendor/eth/pll_gen_1.v
    src/vendor/eth/pll_gen_2.v
    src/vendor/eth/rx_pll.v
    src/vendor/eth/rgmii_interface.v
    src/vendor/eth/rx_client_fifo.v
    src/vendor/eth/tx_client_fifo.v
    src/vendor/eth/tx_clk_en_gen.v
    src/vendor/eth/temac_block.v
    src/vendor/eth/temac_clk_gen.v
    src/vendor/eth/udp_data_tpg.v
    src/vendor/eth/udp_loopback.v
    src/vendor/eth/udp_ip_protocol_stack_merge.enc.v
    src/vendor/ov5640/i2c_dri.v
    src/vendor/ov5640/i2c_ov5640_rgb565_cfg.v
    src/vendor/ov5640/ov5640_delay.v
    src/vendor/ov5640/cmos_capture_data.v
    src/vendor/ov5640/ov5640_dri.v
}
foreach f $files {
    set path "$PROJ_ROOT/$f"
    if {[file exists $path]} {
        if {[catch {add_file -type verilog $path} err]} {
            puts "skip/add exists: $path ($err)"
        } else {
            puts "added: $path"
        }
    } else {
        puts "missing: $path"
    }
}
catch {set_top_model udp_transmit_test}
catch {set_option -top udp_transmit_test}
catch {set_option -include_path "$PROJ_ROOT/src/app;$PROJ_ROOT/src/vendor/sdram"}
puts "DONE: all needed sources were added/enabled. Please rerun Synthesis."
