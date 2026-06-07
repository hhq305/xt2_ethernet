# FPGA VGA/SDRAM 图片上传调试会话交接文档

日期：2026-06-07

## 1. 工程路径

用户指定的关键路径：

- FPGA 资料：`F:\Verilog\final\HX4S20_Contest_2025_9`
- Verilog 代码：`F:\Verilog\final\xt2_ethernet\src`
- Python 脚本：`F:\Verilog\final\xt2_ethernet\scripts`
- 当前图片：`F:\Verilog\final\xt2_ethernet\scripts\photo2.jpg`
- 错误/现象照片目录：`F:\Verilog\final\error`

这些路径已经写入记忆：`fpga-project-paths.md`。

---

## 2. 用户目标

目标是：

> 将 PC 上的图片通过以太网 UDP 上传到 FPGA，写入 SDRAM，再从 SDRAM 读出显示到连接 FPGA 的 VGA 屏幕上。

当前关注点：

1. SDRAM 已经可以进入读状态 `R_RUN`。
2. 早期问题是读出的低 8 位一直为 0，怀疑 SDRAM 写入、byte lane 或对齐问题。
3. 后续图片已经能显示，但清晰度不足。
4. 已尝试从 Python 端调亮度/锐化。
5. 后来改 Verilog，从 RGB332 尝试提升到 RGB444，并进一步尝试 640x480。

---

## 3. Python 端状态

主要文件：

- `F:\Verilog\final\xt2_ethernet\scripts\pc_test.py`

### 3.1 当前上传协议

PC 发送 UDP 到：

- FPGA IP：`192.168.240.1`
- FPGA UDP 端口：`1`
- PC IP：`192.168.240.2`
- PC UDP 源端口：`2`

图像上传命令：`CMD=0x10`

UDP payload 格式：

```text
A5 5A 10 LEN_H LEN_L
FLAG YH YL XH XL R0 G0 B0 R1 G1 B1 ...
```

结束帧 marker：

```text
A5 5A 10 00 05
01 00 00 00 00
```

Python 会重复发送 32 次 end marker。

### 3.2 当前 Python 图像处理

曾经为了提升 VGA 清晰度，Python 端做过亮度/对比度/锐化调整。当前 `pc_test.py` 中已把注释和模式名从 RGB332 改为 RGB444，例如：

```python
VGA_FB_MODE = 'rgb444'
```

当前发送尺寸曾经被改到：

```text
640x480
```

终端输出示例：

```text
[+] sending VGA image pass 1/1: 7680 data pkts, gap=0.005s, chunk=40
row 480/480, sent 7680/7680 pkts
[+] color bars -> FPGA SDRAM VGA framebuf (640x480 RGB888 -> RGB444 color)
```

说明当前 Python 端已经按 640x480 发送，chunk=40 时一帧 7680 个数据包。

---

## 4. 已成功现象

### 4.1 320x240 / RGB444 阶段

曾经成功出现彩条，说明这条主链路曾经打通：

```text
PC UDP -> FPGA 接收 -> SDRAM 写 -> SDRAM 读 -> RGB444 -> VGA_D
```

随后 photo2 图片也能显示，但用户反馈：

- 比之前清晰，但仍然有点模糊。
- 细节不够。

### 4.2 TD 资源问题曾解决到可烧录

曾遇到：

```text
ERROR: Design's mslice number = 6128, exceeds the limit 4900
```

后来通过裁剪逻辑后，能继续 place/route 并能烧录。

裁剪过的内容包括：

- 关闭 `cmd_decode` 的 LED/SEG/SD/IMG_REQ 等命令解析。
- 裁剪 `img_tx_rom` FPGA->PC 图像回传。
- 关闭数码管扫描。
- 裁剪 TX FIFO，用静态 ARP，保留 PC->FPGA 接收路径。
- 固定 IP，裁掉动态 IP 扫描计数器。
- 简化 `img_rx_fb.v` 的地址计算。

---

## 5. Verilog 端重要修改历史

### 5.1 `img_rx_fb.v`

文件：

- `F:\Verilog\final\xt2_ethernet\src\app\img_rx_fb.v`

原来：

```verilog
wire [7:0] pix332 = {rch[7:5], gch[7:5], rx_data[7:6]};
```

后来改为 RGB444：

```verilog
wire [11:0] pix444 = {rch[7:4], gch[7:4], rx_data[7:4]};
```

输出改为：

```verilog
output reg [11:0] fb_wdata
```

为了省 MSlice，后续把原先的：

```verilog
fb_waddr <= yline_r * IMG_W + xpix;
```

改成：

```verilog
fb_we    <= 1'b1;
fb_waddr <= {AW{1'b0}};
fb_wdata <= pix444;
```

原因：SDRAM 写路径是顺序写，不使用 `fb_waddr`。

### 5.2 `app.v`

文件：

- `F:\Verilog\final\xt2_ethernet\src\vendor\app\app.v`

主显示数据线从 8bit 改为 12bit：

```verilog
wire [11:0] rgb;
wire [11:0] fb_wdata;
wire [11:0] fb_rgb444;
wire [11:0] sdram_dbg_rgb;
wire [11:0] rgb_diag;
```

`wr_data_o` 保持 6bit 兼容旧路径，RGB444 降采样到 RGB222：

```verilog
assign wr_data_o = {fb_wdata[11:10], fb_wdata[7:6], fb_wdata[3:2]};
```

### 5.3 `vga_disp.v`

文件：

- `F:\Verilog\final\xt2_ethernet\src\vendor\app\vga_disp.v`

输入从 RGB332 扩展改为 RGB444 直通：

```verilog
input [11:0] rgb;
...
VGA_D <= rgb;
```

### 5.4 `sdram_img_fb.v`

文件：

- `F:\Verilog\final\xt2_ethernet\src\app\sdram_img_fb.v`

这个文件改动最多。

#### 5.4.1 早期 RGB444 一像素一 word

最初 RGB444 用一像素一个 32bit SDRAM word：

```verilog
assign write_data_mux = {20'd0, fb_wdata};
```

`FRAME_LEN` 等于像素数。

#### 5.4.2 640x480 后出现异常

640x480 时彩条显示异常，屏幕出现大量黑白横纹/竖块，判断为：

> 640x480 一像素一 32bit word 对 SDRAM/FIFO 带宽压力太大，读出节奏和 VGA 像素节奏不匹配。

于是开始改成：

> RGB444 两个像素打包进一个 32bit SDRAM word。

当前这部分还没有完全收尾，是新会话首先要检查的重点。

---

## 6. 当前最重要的未完成状态

⚠️ 当前代码处于“正在改 RGB444 双像素打包”的中间状态，可能不能直接综合通过。

在 `sdram_img_fb.v` 里已经开始改：

```verilog
localparam [20:0] FRAME_PIXELS = FRAME_WORDS;
localparam [20:0] FRAME_LEN    = FRAME_WORDS >> 1; // two RGB444 pixels per 32-bit word
```

并新增/使用了这些信号：

```verilog
reg        pack_half;
reg [11:0] pack_pix;
wire       rx_pixel_avail;
wire       pad_pixel_avail;
wire       src_pixel_avail;
wire       take_pixel;
wire       write_word;
wire [11:0] src_pix;
```

写入打包当前方向是：

```verilog
assign write_en_mux   = write_word;
assign write_data_mux = {4'b0000, src_pix, 4'b0000, pack_pix};
```

含义：

```text
低 12bit：第一个像素
高 12bit：第二个像素
```

也定义了两个解包函数：

```verilog
function [11:0] word_to_rgb444_lo;
    input [31:0] word;
    begin
        word_to_rgb444_lo = word[11:0];
    end
endfunction

function [11:0] word_to_rgb444_hi;
    input [31:0] word;
    begin
        word_to_rgb444_hi = word[27:16];
    end
endfunction
```

但是当前读取 VGA 部分仍然残留旧逻辑，类似：

```verilog
if (read_valid)
    vga_rgb <= word_to_rgb444(read_data);
```

这是错误/未完成的，因为 `word_to_rgb444()` 已经被拆成 `word_to_rgb444_lo()` 和 `word_to_rgb444_hi()`。

新会话必须首先修复这一点。

---

## 7. 新会话继续时的首要任务

### 7.1 修完 `sdram_img_fb.v` 的双像素读出逻辑

目标：VGA 每两个像素只从 SDRAM read FIFO pop 一个 32bit word。

推荐逻辑：

```verilog
if (rst_read == R_RUN) begin
    if (!rd_pair_half) begin
        // 偶数像素：从 FIFO 取一个 word，显示低 12bit
        if (!read_empty) begin
            read_en <= 1'b1;
            rd_word <= read_data;
            vga_rgb <= word_to_rgb444_lo(read_data);
            rd_pair_half <= 1'b1;
        end else begin
            underflow <= 1'b1;
            vga_rgb <= 12'hF00;
        end
    end else begin
        // 奇数像素：使用上一拍保存的 word 高 12bit，不再 pop FIFO
        vga_rgb <= word_to_rgb444_hi(rd_word);
        rd_pair_half <= 1'b0;
    end
end
```

注意：如果 `read_buf` 是 `SHOW_AHEAD_EN=1`，则 `read_data` 在 `!read_empty` 时可用；如果不是 show-ahead，则需要用 `read_valid` 延迟一拍。当前 `frame_read_write.v` 又改回了：

```verilog
rfifo_32_32_512 #(
    .SHOW_AHEAD_EN(1'b1)
) read_buf (...)
```

所以可以按 show-ahead 方式处理。

### 7.2 检查 `pack_half` 写入逻辑

当前写入逻辑大致是：

```verilog
if (take_pixel) begin
    accepted_cnt <= accepted_next;
    if (!pack_half) begin
        pack_pix  <= src_pix;
        pack_half <= 1'b1;
    end else begin
        pack_half <= 1'b0;
    end
end
```

并且：

```verilog
wire write_word = take_pixel && pack_half;
assign write_data_mux = {4'b0000, src_pix, 4'b0000, pack_pix};
```

这表示第二个像素到来时写一个 word：

```text
word[11:0]  = 第一个像素 pack_pix
word[27:16] = 第二个像素 src_pix
```

要确认：

- `FRAME_PIXELS` 是偶数，640x480=307200，没问题。
- `FRAME_LEN = FRAME_PIXELS/2 = 153600`。
- `read_len` 和 `write_len` 都使用 `FRAME_LEN`。

### 7.3 修复 test pattern

`pat_write_data` 目前仍是单像素概念：

```verilog
pat_write_data <= {20'd0, pat_pix};
```

如果 `TEST_PATTERN=0`，暂时不影响 PC 上传显示。若想保留测试图案，需要改成两像素打包。优先级不高。

---

## 8. 当前现象解释

用户最近运行：

```powershell
cd F:\Verilog\final\xt2_ethernet\scripts
python pc_test.py sendvga_bars 1 0.005 40
```

VGA 显示了大量灰白横纹/竖块，不是彩条。

原因判断：

- Python 已经按 640x480 发送。
- FPGA 已经不再黄屏，说明写完/读出阶段能启动。
- 但 SDRAM/VGA 读写数据组织不匹配。
- 640x480 使用一像素一 32bit word 时读带宽太高，或者当前双像素打包尚未完成，导致 VGA 读出的 word 与像素节奏错位。

所以新会话重点不是 Python，而是修 `sdram_img_fb.v` 的双像素打包读写一致性。

---

## 9. TD / 综合相关提醒

用户自己运行 TD 和烧录，不希望助手运行 TD。

曾经出现过 routing 错误：

```text
ERROR: Location: (x18y12_local5), nets:
u_app/u_sdram_img_fb/u_frame_read_write/read_buf/ram_inst/ramread0_syn_...
ERROR: Incremental route failed.
```

为降低布线压力，曾做过：

- 关闭/打开 `SHOW_AHEAD_EN` 的尝试。
- 将 RGB444 从双副本改为低 12bit。
- 后来又为了 640x480 带宽，开始改成两个 RGB444 像素/32bit word。

重新跑 TD 时建议：

- 不要 incremental route。
- Clean / full rerun。
- 如果 route 又卡，优先检查 `read_buf` 和 RGB444 解包逻辑。

---

## 10. 推荐新会话第一句话

新会话可以直接说：

> 请读取 `F:\Verilog\final\xt2_ethernet\SESSION_HANDOFF.md`，继续修复 `sdram_img_fb.v` 中 RGB444 两像素打包读写逻辑。当前问题是 640x480 彩条显示灰白横纹/竖块，怀疑 SDRAM word 与 VGA 像素节奏错位。不要运行 TD，我会自己综合烧录。

---

## 11. 建议下一步实现概要

1. 打开 `sdram_img_fb.v`。
2. 修复 VGA 读路径：
   - 偶数像素 pop FIFO，显示低 12bit，并缓存整个 word。
   - 奇数像素不 pop FIFO，显示缓存 word 的高 12bit。
3. 确认写路径：
   - 每收到两个 RGB444 像素写一个 32bit word。
   - `FRAME_LEN = FRAME_PIXELS / 2`。
4. 暂时保持 `TEST_PATTERN=0`。
5. 用户重新综合/烧录。
6. 测试：

```powershell
cd F:\Verilog\final\xt2_ethernet\scripts
python pc_test.py sendvga_bars 1 0.005 40
```

7. 彩条正确后再测：

```powershell
python pc_test.py photo2 1 0.005 40
```
