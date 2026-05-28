## ============================================================
##  program.tcl
##  使用 TD 的 td_load / td_prog 把 top_xt2.bit 下载到 HX4S20C
##
##  使用方法 :
##    td.exe -bat scripts/program.tcl                 (默认下载到 SRAM)
##    td.exe -bat scripts/program.tcl flash           (烧到 SPI Flash)
##
##  说明 :
##    SRAM 模式  : 速度快, 掉电丢失。调试用。
##    Flash 模式 : 上电自加载, 适合演示/验收。
## ============================================================

set SCRIPT_DIR [file dirname [file normalize [info script]]]
set PROJ_ROOT  [file normalize "$SCRIPT_DIR/.."]
set BITFILE    "$PROJ_ROOT/work/top_xt2.bit"

if { ![file exists $BITFILE] } {
    puts "ERROR: bitstream not found: $BITFILE"
    puts "       请先运行 source scripts/build.tcl 完成综合."
    exit 1
}

# 命令行第一个参数: ram (默认) / flash
set MODE [expr { [llength $argv] > 0 ? [lindex $argv 0] : "ram" }]

if { $MODE eq "flash" } {
    puts "## 烧写 SPI Flash : $BITFILE"
    # TD 自带的 SPI Flash 烧写工具
    catch { exec td_prog -mode flash -file $BITFILE -device EG4S20BG256 } out
    puts $out
} else {
    puts "## 下载到 SRAM    : $BITFILE"
    catch { exec td_load -mode sram  -file $BITFILE -device EG4S20BG256 } out
    puts $out
}

puts "================================================================"
puts "  PROGRAM DONE.  请在板上观察 LED / VGA / HDMI / 网口运行情况."
puts "================================================================"
