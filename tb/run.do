vlib work
vmap work work
vlog -sv ../src/common/pkt_fmt.vh
vlog ../src/app/cmd_decode.v
vlog ../src/app/img_rx_fb.v
vlog ../src/app/img_tx_rom.v
vlog ../src/app/cam_eth_tx.v
vlog ../src/app/fpga_master.v
vlog ../src/disp/seg_drv.v
vlog ../src/disp/vga_ctrl.v
vlog ../src/disp/hdmi_tx.v
vlog ../src/mem/framebuf.v
vlog ../src/mem/line_buf.v
vlog ../src/proc/img_proc.v
vlog ../src/proc/obj_detect.v
vlog tb_top.v
vsim -voptargs=+acc work.tb_top
add wave -position insertpoint sim:/tb_top/*
run 5us
