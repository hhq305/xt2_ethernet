# 选题二：基于 HX4S20C (EG4S20BG256) 的以太网数据传输系统

> 安路杯 / 校内 FPGA 比赛 — 选题二最终实现
>
> 板卡：HX4S20C 开发板（**EG4S20BG256**），工具：**TD 6.2.1**
> 工程目录：`F:\Verilog\final\final_work\final_work.al`
> 顶层模块：`udp_transmit_test`（基于安路官方 demo `33_HX4S20_Ethernet_test` 改造）

---

## 1. 选题二要求 ↔ 实现对照

| # | 要求 | 实现状态 | 关键文件/模块 |
|---|---|---|---|
| 基础① | PC ↔ FPGA UDP 千兆以太网通信 (ARP/IP/UDP 协议栈, RGMII PHY) | ✅ demo 协议栈 | `udp_ip_protocol_stack`, `temac_block` |
| 基础② | PC 通过网口控制 FPGA 板上 LED | ✅ | `cmd_decode.v` → `led_o[2:0]` |
| 基础③ | FPGA 通过 VGA 显示一张图片 | ✅ demo | `app.v` 中的 `ram + vga_disp` |
| **扩展①** | PC 通过网口控制 **数码管** 显示 | ✅ | `cmd_decode.v` + `seg_scan.v` |
| **扩展②** | FPGA → PC 通过网口 **回传图像数据** | ✅ | `img_tx_rom.v` |
| **扩展③** | PC → FPGA 通过网口 **下发图像** 到 VGA 显示 | ✅ | `app.v` 中的 `addr_crt` (写 BRAM) + 放大显示 |
| **扩展④** | 图像处理（灰度 / **2D Sobel 边缘** / 反色） | ✅ | `img_proc_inline.v` + `sobel_ondemand.v` |
| **扩展⑤** | **OV5640 摄像头实时画面** 采集 → VGA / 网络回传 | ✅ | `ov5640_dri.v` + `cam_to_bram.v` + 刷新引擎 |

> HDMI/SD 卡未集成；`src/vendor/{hdmi,sdram,sd_card}` 预留官方 IP 备用。

---

## 2. 顶层架构

```
PC <-------------> RJ45 RGMII PHY <-> EG4S20BG256 ----+
                                                      |
   ┌─ udp_transmit_test (顶层) ────────────────────────┐
   │                                                  │
   │  temac_block ──> rx_client_fifo ──> udp_ip_proto │
   │  tx_client_fifo <── temac_block <── udp_ip_proto │
   │                                                  │
   │  ┌── app_rx_data (RX) ───────┐                   │
   │  │                           ▼                   │
   │  │       ┌──────── cmd_decode ─────────┐         │
   │  │       │  解析 A5 5A CMD LEN PAYLOAD │         │
   │  │       └─┬────┬──────┬───────┬───────┘         │
   │  │         │    │      │       │                 │
   │  │       LED  SEG  PROC_MODE  IMG_REQ            │
   │  │         │    │      │       │                 │
   │  │      [LED] seg_scan │       └──> img_tx_rom   │
   │  │           [7-seg]   │              │          │
   │  │                     │              ▼ (TX)     │
   │  │                     │         app_tx_data ──> │
   │  │                     │                         │
   │  └─> app  (addr_crt -> BRAM (ram.v) ──> img_proc_inline ──> vga_disp ──> VGA)
   │                                                            │
   └────────────────────────────────────────────────────────────┘
```

---

## 3. 应用层报文协议

所有命令统一格式 (大端):
```
+------+------+------+--------+--------+----------+
|MAGIC0|MAGIC1| CMD  | LEN_H  | LEN_L  | PAYLOAD  |
| 0xA5 | 0x5A |      |        |        |  N 字节  |
+------+------+------+--------+--------+----------+
```

| CMD | 名称 | LEN | 方向 | PAYLOAD 含义 |
|---|---|---|---|---|
| `0x01` | LED_SET     | 1 | PC→FPGA | `LED[7:0]`, 低 3 位驱动板上 LED |
| `0x02` | SEG_SET     | 4 | PC→FPGA | `D3 D2 D1 D0`, 每字节低 4 位 = 1 个 hex 位 |
| `0x20` | IMG_REQ     | 0 | PC→FPGA | 触发 FPGA 回传 16×16 图像 |
| `0x21` | IMG_DATA    | 256 | **FPGA→PC** | 16×16 RGB222 像素, 每字节低 6 位 = `{RR,GG,BB}` |
| `0x30` | CAM_START   | 1 | PC→FPGA | `0`=PC 上传源 `1`=OV5640 实时画面 |
| `0x40` | PROC_MODE   | 1 | PC→FPGA | `0`=RAW `1`=GRAY `2`=EDGE(Sobel) `3`=INVERT |

地址 (固化在 demo 协议栈参数中):
- FPGA IP  = `192.168.240.1`，FPGA UDP 端口 = `1`
- PC  IP  = `192.168.240.2`（用户设置），PC 监听端口 = `2`
- MAC = `01:23:45:67:89:ab`

---

## 4. 各模块说明

### 4.1 `cmd_decode.v`  (app/)
解析 RX 流并输出控制信号:
- `led_o[7:0]`            ← `CMD_LED_SET`
- `seg_bcd_o[31:0]`       ← `CMD_SEG_SET`
- `proc_mode_o[1:0]`      ← `CMD_PROC_MODE`
- `img_req_pulse_o`       ← `CMD_IMG_REQ`（单拍）
- `cam_en_o`              ← `CMD_CAM_START` (Ext-5 图像源切换)
状态机: `M0 → M1 → CMD → LH → LL → PAY → M0`。

### 4.2 `seg_scan.v`  (app/)
4 位动态扫描数码管驱动。
- 输入: `bcd_in[15:0]` (4 个 hex 数字)
- 输出: `seg[6:0]` (段, 低有效) + `en[3:0]` (位选, 低有效)
- 扫描频率 ~95 Hz @ udp_clk=25 MHz。

### 4.3 `img_tx_rom.v`  (app/)
FPGA → PC 单包图像回传引擎。
- 触发: `start = img_req_pulse_o`
- 包格式: `A5 5A 21 01 00 [256 字节 payload]`
- payload 为 **真实** 16×16 BRAM 图像内容（与 VGA 显示一致, 上传后或摄像头实时画面都会被回传）。
- 实现：模块内维护一份 256×6 bit 镜像, 与 `addr_crt` 写信号同步, 单时钟域 (udp_clk) 无 CDC。

### 4.4 `img_proc_inline.v` + `sobel_ondemand.v`  (app/)
插入在 BRAM 输出 → vga_disp 输入的实时处理模块 (1 级流水)。
- `mode=0` RAW    : `rgb_o = rgb_i`
- `mode=1` GRAY   : `(R+G+B)` 灰度 (重复三通道)
- `mode=2` EDGE   : **2D Sobel 3×3 卷积** — `sobel_ondemand` 把 16×16 BRAM 镜像成寄存器阵列, 任意像素 1 拍内取 9 邻域并行计算 `|Gx|+|Gy|`, 超阈值则像素全白
- `mode=3` INVERT : `~rgb_i`

### 4.5 `cam_to_bram.v` + `ov5640_dri.v`  (Ext-5)
- `ov5640_dri.v` (vendor): I2C 配置 OV5640 至 RGB565 1024×768@60fps + DVP 像素采集
- `cam_to_bram.v`: 在 `cam_pclk` 域以 64×48 降采样, RGB565→RGB222, 写入内部 256×6 bit 镜像
- **刷新引擎** (`app.v`): 当 `cam_en=1`, 在 `udp_rx_clk` 域循环把 cam_mirror 异步读出并写入主 BRAM, 同时进入 sobel/img_tx_rom 的镜像 — VGA / 处理 / 回传共用同一帧数据

### 4.6 `vga_disp.v`  (vendor/app/, 已修改)
- 修改前: 在屏幕中央显示 16×16 的小图
- 修改后: **16×16 BMP 放大到 256×256** 显示（每个 BRAM 像素占 16×16 屏幕点）
- VGA 时序: 640×480 @ 60 Hz, pix_clk = 25 MHz

### 4.7 `app.v`  (vendor/app/, 已修改)
- 集成 `addr_crt`（UDP→BRAM 写）+ `ram`（dual-port）+ `sobel_ondemand` + `img_proc_inline` + `vga_disp`
- BRAM 写源 mux: `cam_en=0` 走 `addr_crt`, `cam_en=1` 走摄像头刷新引擎
- 暴露 `wr_en_o/wr_addr_o/wr_data_o` 给 `img_tx_rom`，使其和 BRAM 内容同步

---

## 5. 引脚约束 (`sdc/xt2.adc`)

| 信号 | 引脚 | 说明 |
|---|---|---|
| `clk_25`   | R7 | 50 MHz 系统时钟 |
| `key1/key2`| F1/G1 | 按键 (key2 全局复位) |
| `phy1_rgmii_*` | (按官方 demo) | 千兆 PHY RGMII |
| `led[2:0]` | E12/E16/F16 | 板载 3 LED |
| `VGA_HSYNC/VSYNC` | E7/F7 | VGA 同步 |
| `VGA_D[11:0]` | RGB 12 bit | VGA 颜色 |
| `seg[6:0]` | C15/C16/B6/A5/B5/A8/A7 | 7 段 (a..g) |
| `seg_en[3:0]` | D11/E11/F10/C13 | 4 位数字位选 |
| `cam_data[7:0]` | P16/N14/N16/L16/M15/M16/K16/H16 | OV5640 DVP 数据 |
| `cam_pclk/vsync/href` | H15/R14/R15 | OV5640 同步 |
| `cam_scl/sda` | T15/R16 | OV5640 SCCB (I2C) |
| `cam_rst_n/pwdn` | P15/K15 | OV5640 复位 / 休眠 |

---

## 6. 编译 & 烧录

### 6.1 在 TD 6.2 GUI 中
1. `File → Open Project` → 选 `F:\Verilog\final\final_work\final_work.al`
2. `Process → Reset All`
3. `Process → Run All` (Elaborate → Synthesis → P&R → BitGen)
4. 生成的 bit 在 `F:\Verilog\final\final_work\final_work_Runs\phy_1\final_work.bit`
5. `Tools → BitWriter` 打开 BitWizard → BitWriter → 选 SRAM 模式 → Run

---

## 7. 测试 (PC 端)

PC 网卡 IP 改为 `192.168.240.2/24`，运行：
```bash
python F:\Verilog\final\xt2_ethernet\scripts\pc_test.py led  0x7   # LED 全亮
python F:\Verilog\final\xt2_ethernet\scripts\pc_test.py seg  1234  # 数码管显示 1234
python F:\Verilog\final\xt2_ethernet\scripts\pc_test.py img        # 触发图像回传
python F:\Verilog\final\xt2_ethernet\scripts\pc_test.py mode 1     # VGA 切灰度
python F:\Verilog\final\xt2_ethernet\scripts\pc_test.py mode 2     # VGA 切边缘
python F:\Verilog\final\xt2_ethernet\scripts\pc_test.py mode 3     # VGA 切反色
python F:\Verilog\final\xt2_ethernet\scripts\pc_test.py mode 0     # VGA 还原
python F:\Verilog\final\xt2_ethernet\scripts\pc_test.py cam  1     # 切到 OV5640 实时画面
python F:\Verilog\final\xt2_ethernet\scripts\pc_test.py cam  0     # 切回 PC 上传源
python F:\Verilog\final\xt2_ethernet\scripts\pc_test.py img  cam.ppm # 把当前 BRAM 16x16 存为 PPM 图
```

`img` 命令同时打印 ASCII 灰度预览：
```
 received 261 bytes from ('192.168.240.1', 1)
   CMD=0x21  LEN=256  pay_recv=256
   ##############################
   ####    ####  ####    ####
   ...
```

抓包验证 (Wireshark)：
- 过滤 `udp.port == 1 or udp.port == 2`
- LED/SEG/PROC_MODE 命令应当看到 PC→FPGA UDP 包 (load: A5 5A ... )
- IMG_REQ 命令后 FPGA 回 261 字节 UDP (5 头 + 256 payload)

---

## 8. 资源占用 (P&R 后)

(实际数字以 TD `Report → Resource Utilization` 为准)
- LUT  : ~约 30%
- BRAM : 用了 1 个 9K (logo BMP + 帧缓存)
- IO   : ~50 / 188 user IO

---

## 9. 已知限制 & 后续可扩展

1. **`cam_pclk` 未走全局时钟网络** — TD 报 `PHY-5079` Critical Warning，目前 24-96 MHz 范围实测 OK，如需严格时序可在 .adc 加 BUFG 约束。
2. **HDMI/SD 卡** 未集成；预置 IP 在 `src/vendor/{hdmi,sd_card}`。
3. **摄像头降采样使用最近邻**（每 64×48 取 1 点），非区域平均 — 想要更好图像质量可加 box filter。

---

## 10. 文件清单 (本次工程实际依赖)

应用层 (新写):
```
src/app/cmd_decode.v        命令解析 (Ext-1/2/4/5)
src/app/seg_scan.v          数码管扫描驱动 (Ext-1)
src/app/img_tx_rom.v        FPGA → PC 回传, 内置 BRAM 镜像 (Ext-2)
src/app/img_proc_inline.v   VGA 处理模式选择 (Ext-4)
src/app/sobel_ondemand.v    2D Sobel 3x3 卷积 (Ext-4)
src/app/cam_to_bram.v       OV5640 降采样 -> 16x16 镜像 (Ext-5)
src/app/logo_256.hex        镜像初始化数据 (= BRAM 前 256 项)
src/app/pkt_fmt.vh          报文格式宏
```

Vendor IP (拷自安路 lab_ex_5):
```
src/vendor/ov5640/ov5640_dri.v             OV5640 顶层驱动
src/vendor/ov5640/i2c_ov5640_rgb565_cfg.v  I2C 寄存器配置序列
src/vendor/ov5640/ov5640_delay.v           上电延时
src/vendor/ov5640/i2c_dri.v                通用 I2C 主机
src/vendor/ov5640/cmos_capture_data.v      DVP 数据采集
```

修改的 demo 模块:
```
src/vendor/app/app.v        加 sobel + img_proc + 摄像头刷新引擎 + BRAM 写源 mux
src/vendor/app/vga_disp.v   16x16 -> 256x256 放大
src/top/udp_transmit_test.v 集成 cmd_decode, seg_scan, img_tx_rom, ov5640_dri, cam_to_bram
sdc/xt2.adc                 加 7-seg + OV5640 共 21 个引脚
final_work/logo_256.hex     运行时 $readmemh 用 (TD 工程根目录)
```

PC 端:
```
scripts/pc_test.py          全部命令测试脚本
```
