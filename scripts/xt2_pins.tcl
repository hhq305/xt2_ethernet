## xt2_pins.tcl 鈥?HX4S20C 鐪熷疄寮曡剼 (Tcl 绛変环 .adc, 鍙洿鎺?source)
## 鐢ㄦ硶: TD Tcl Console 鈫?source scripts/xt2_pins.tcl

# 鏃堕挓/澶嶄綅/鎸夐敭
set_pin_assignment { clk_50 } { LOCATION = R7; IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }
set_pin_assignment { rst_n  } { LOCATION = A2; IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }
set_pin_assignment { key1   } { LOCATION = B2; IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }
set_pin_assignment { key2   } { LOCATION = B1; IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }

# 3 LED
set_pin_assignment { led[0] } { LOCATION = F16; IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 8; PULLTYPE = NONE; }
set_pin_assignment { led[1] } { LOCATION = E16; IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 8; PULLTYPE = NONE; }
set_pin_assignment { led[2] } { LOCATION = E12; IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 8; PULLTYPE = NONE; }

# 浠ュお缃?PHY1 RGMII
set_pin_assignment { phy1_rgmii_rx_clk    } { LOCATION = T14; IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }
set_pin_assignment { phy1_rgmii_rx_ctl    } { LOCATION = T13; IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }
set_pin_assignment { phy1_rgmii_rx_data[0]} { LOCATION = P6;  IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }
set_pin_assignment { phy1_rgmii_rx_data[1]} { LOCATION = M6;  IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }
set_pin_assignment { phy1_rgmii_rx_data[2]} { LOCATION = T9;  IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }
set_pin_assignment { phy1_rgmii_rx_data[3]} { LOCATION = N9;  IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }
set_pin_assignment { phy1_rgmii_tx_clk    } { LOCATION = T12; IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 16; SLEWRATE = FAST; }
set_pin_assignment { phy1_rgmii_tx_ctl    } { LOCATION = T7;  IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 16; SLEWRATE = FAST; }
set_pin_assignment { phy1_rgmii_tx_data[0]} { LOCATION = T4;  IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 16; SLEWRATE = FAST; }
set_pin_assignment { phy1_rgmii_tx_data[1]} { LOCATION = T6;  IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 16; SLEWRATE = FAST; }
set_pin_assignment { phy1_rgmii_tx_data[2]} { LOCATION = M7;  IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 16; SLEWRATE = FAST; }
set_pin_assignment { phy1_rgmii_tx_data[3]} { LOCATION = T8;  IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 16; SLEWRATE = FAST; }

# VGA 12bit (4:4:4)
set_pin_assignment { VGA_D[0] } { LOCATION = F6;  IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 8; }
set_pin_assignment { VGA_D[1] } { LOCATION = E6;  IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 8; }
set_pin_assignment { VGA_D[2] } { LOCATION = D6;  IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 8; }
set_pin_assignment { VGA_D[3] } { LOCATION = D5;  IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 8; }
set_pin_assignment { VGA_D[4] } { LOCATION = T5;  IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 8; }
set_pin_assignment { VGA_D[5] } { LOCATION = P5;  IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 8; }
set_pin_assignment { VGA_D[6] } { LOCATION = N5;  IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 8; }
set_pin_assignment { VGA_D[7] } { LOCATION = N6;  IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 8; }
set_pin_assignment { VGA_D[8] } { LOCATION = R5;  IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 8; }
set_pin_assignment { VGA_D[9] } { LOCATION = L7;  IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 8; }
set_pin_assignment { VGA_D[10]} { LOCATION = L8;  IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 8; }
set_pin_assignment { VGA_D[11]} { LOCATION = E13; IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 8; }
set_pin_assignment { VGA_HSYNC} { LOCATION = E7;  IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 8; }
set_pin_assignment { VGA_VSYNC} { LOCATION = F7;  IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 8; }

# HDMI (LVDS33)
set_pin_assignment { HDMI_CLK_P } { LOCATION = K1; IOSTANDARD = LVDS33; PULLTYPE = NONE; }
set_pin_assignment { HDMI_D0_P  } { LOCATION = F5; IOSTANDARD = LVDS33; PULLTYPE = NONE; }
set_pin_assignment { HDMI_D1_P  } { LOCATION = E3; IOSTANDARD = LVDS33; PULLTYPE = NONE; }
set_pin_assignment { HDMI_D2_P  } { LOCATION = B3; IOSTANDARD = LVDS33; PULLTYPE = NONE; }

# OV5640 camera (Ext-5)
set_pin_assignment { cam_xclk  } { LOCATION = J16; IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 8; PULLTYPE = NONE; }
set_pin_assignment { cam_pclk  } { LOCATION = H15; IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }
set_pin_assignment { cam_href  } { LOCATION = R15; IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }
set_pin_assignment { cam_vsync } { LOCATION = R14; IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }
set_pin_assignment { cam_data[0]} { LOCATION = P16; IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }
set_pin_assignment { cam_data[1]} { LOCATION = N14; IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }
set_pin_assignment { cam_data[2]} { LOCATION = N16; IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }
set_pin_assignment { cam_data[3]} { LOCATION = L16; IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }
set_pin_assignment { cam_data[4]} { LOCATION = M15; IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }
set_pin_assignment { cam_data[5]} { LOCATION = M16; IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }
set_pin_assignment { cam_data[6]} { LOCATION = K16; IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }
set_pin_assignment { cam_data[7]} { LOCATION = H16; IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
set_pin_assignment { cam_pwdn  } { LOCATION = K15; IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 8; }
set_pin_assignment { cam_rst_n } { LOCATION = P15; IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 8; }
set_pin_assignment { cam_scl   } { LOCATION = T15; IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 8; }
set_pin_assignment { cam_sda   } { LOCATION = R16; IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 8; }

# TF / SD (SPI)
set_pin_assignment { sd_clk  } { LOCATION = A14; IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }
set_pin_assignment { sd_miso } { LOCATION = B14; IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }
set_pin_assignment { sd_mosi } { LOCATION = A13; IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }
set_pin_assignment { sd_cs   } { LOCATION = A12; IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }

puts "## xt2_pins.tcl : 鍏ㄩ儴寮曡剼宸插簲鐢?(HX4S20C / EG4S20BG256)"
