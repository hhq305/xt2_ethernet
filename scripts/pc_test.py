#!/usr/bin/env python3
"""
选题二 PC 端测试工具
- 基础 : LED 控制
- Ext-1: 7-seg 控制
- Ext-2: 触发 FPGA 回传图像
用法:
    python pc_test.py led 7        # 全亮 3 个 LED
    python pc_test.py seg 1234     # 数码管显示 1234
    python pc_test.py pattern checker  # 发送棋盘格图案到 FPGA
    python pc_test.py pattern gradient # 发送渐变图案到 FPGA
    python pc_test.py pattern stripes  # 发送条纹图案到 FPGA
    python pc_test.py img          # 触发图像回传, 接收并打印前 16 字节
    python pc_test.py mode 0       # 设置 VGA 处理模式 0=RAW 1=GRAY 2=EDGE 3=INVERT
- Ext-6: TF 卡 BMP 照片回传 (64x64)
    python pc_test.py mkbmp a.jpg  # 任意图片 -> 640x480 24位 BMP(out.bmp), 拷进卡
    python pc_test.py findsector 1 # (管理员) 扫描物理盘1, 自动找 BMP 起始扇区
    python pc_test.py photo 40992  # 触发读卡, 接收 4 包重组 64x64 -> photo64.png
"""
import socket, sys, time, os, subprocess

FPGA_IP   = '192.168.240.1'
FPGA_PORT = 1                       # 协议栈硬编码监听 port 1 (与 verilog input_local_udp_port_num 设置无关)
PC_PORT   = 2                       # 协议栈期望源端口 = 2 (= DST_UDP_PORT_NUM)
PC_IP     = '192.168.240.2'         # 强制从这张网卡出, 否则 Windows 会选 WLAN/Hyper-V/VPN
FPGA_MAC  = '00-11-22-33-44-55'     # = verilog LOCAL_MAC_ADDRESS, FPGA 协议栈不回 ARP, 必须静态绑定
MAGIC0, MAGIC1 = 0xA5, 0x5A

_arp_warmed = False

def _arp_warmup():
    """FPGA 简易协议栈不回应 ARP, 且 Windows ARP 表闲置会过期 -> 必须每次确保静态 ARP.
    优先 netsh (覆盖式), 退回 arp -s; 两者都需管理员, 失败则 ping 兜底."""
    global _arp_warmed
    if _arp_warmed:
        return
    ok = False
    # 1) netsh: 把 FPGA 的 IP->MAC 静态绑定到本网卡 (覆盖已存在项)
    try:
        r = subprocess.run(
            ["netsh", "interface", "ip", "add", "neighbors",
             f"interface={PC_IP}", FPGA_IP, FPGA_MAC],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3,
        )
        ok = (r.returncode == 0)
    except Exception:
        pass
    # netsh 用接口名而非 IP 时上面会失败, 退回 arp -s (最后参数指定本网卡 IP)
    if not ok:
        try:
            subprocess.run(
                ["arp", "-s", FPGA_IP, FPGA_MAC, PC_IP],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3,
            )
        except Exception:
            pass
    # 2) ping 兜底 (即便没管理员权限, 也触发一次 OS ARP 解析)
    try:
        subprocess.run(
            ["ping", "-n", "1", "-w", "1000", "-S", PC_IP, FPGA_IP],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            timeout=3,
        )
    except Exception:
        pass
    _arp_warmed = True

def send_cmd(cmd, payload=b''):
    _arp_warmup()                        # 关键: 先把 ARP 解析做了
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        s.bind((PC_IP, PC_PORT))     # 必须 bind 到 ASIX 网卡的 IP, 不能用 0.0.0.0
    except OSError as e:
        print(f"[!!] bind {PC_IP}:{PC_PORT} 失败: {e}")
        print(f"[!!] 检查: 1) PC IP 是不是 {PC_IP}  2) < 1024 端口需要管理员")
        sys.exit(1)
    actual_src = s.getsockname()
    send_cmd_on_socket(s, cmd, payload, actual_src)
    s.close()

def send_cmd_on_socket(s, cmd, payload=b'', actual_src=None):
    if actual_src is None:
        actual_src = s.getsockname()
    pkt = bytes([MAGIC0, MAGIC1, cmd, (len(payload)>>8)&0xFF, len(payload)&0xFF]) + payload
    for _ in range(8):
        s.sendto(pkt, (FPGA_IP, FPGA_PORT))
        time.sleep(0.005)
    print(f"[+] sent CMD=0x{cmd:02X} payload={payload.hex()}  src={actual_src} -> {FPGA_IP}:{FPGA_PORT}")

def cmd_led(val):
    send_cmd(0x01, bytes([val & 0xFF]))

def cmd_seg(hex_str):
    # hex_str 例 "1234" -> 数码管低位->高位 = 4,3,2,1
    h = hex_str.rjust(4, '0')[-4:]
    pl = bytes(int(c, 16) for c in h)   # buf0..buf3
    send_cmd(0x02, pl)

def cmd_img_req(save_path=None):
    """触发回传, 收到 256-byte payload 解码 16x16 RGB222 -> 终端 ASCII 预览, 可选存 PPM"""
    r = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    r.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    r.settimeout(3.0)
    try:
        r.bind((PC_IP, PC_PORT))
    except OSError as e:
        print(f"[!!] bind {PC_IP}:{PC_PORT} 失败: {e}")
        print(f"[!!] 检查: 1) PC IP 是不是 {PC_IP}  2) < 1024 端口需要管理员")
        sys.exit(1)
    _arp_warmup()
    send_cmd_on_socket(r, 0x20, b'')
    try:
        data, addr = r.recvfrom(2048)
    except socket.timeout:
        print("[!] 超时 -- FPGA 未回包, 检查网线/IP/网关/路由"); r.close(); return
    r.close()
    print(f"received {len(data)} bytes from {addr}")
    if len(data) < 5 or data[0] != 0xA5 or data[1] != 0x5A:
        print(f"  bad header: {data[:5].hex(' ')}"); return
    paylen = (data[3] << 8) | data[4]
    pay = data[5:5+paylen]
    print(f"  CMD={data[2]:#04x}  LEN={paylen}  pay_recv={len(pay)}")
    # 16x16 灰度 ASCII 预览 (RGB222 求和 -> 0..9 -> 字符)
    chars = " .:-=+*#%@"
    for y in range(16):
        row = ""
        for x in range(16):
            v6 = pay[y*16 + x] & 0x3F
            r2, g2, b2 = (v6>>4)&3, (v6>>2)&3, v6&3
            lum = r2 + g2 + b2          # 0..9
            row += chars[min(lum, 9)] * 2
        print(row)
    # 可选存 PPM (P3 ASCII 格式, 直接用图片查看器看)
    if save_path:
        with open(save_path, "w") as f:
            f.write("P3\n16 16\n255\n")
            for y in range(16):
                for x in range(16):
                    v6 = pay[y*16 + x] & 0x3F
                    r2, g2, b2 = (v6>>4)&3, (v6>>2)&3, v6&3
                    f.write(f"{r2*85} {g2*85} {b2*85}\n")
        print(f"saved -> {save_path}")

def send_raw_payload(payload):
    """直接发送原始 payload（addr_crt 格式：0x0F, ADDR_HI, ADDR_LO, LEN, DATA...）"""
    _arp_warmup()
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        s.bind((PC_IP, PC_PORT))
    except OSError as e:
        print(f"[!!] bind {PC_IP}:{PC_PORT} 失败: {e}")
        sys.exit(1)
    actual_src = s.getsockname()
    for _ in range(8):
        s.sendto(payload, (FPGA_IP, FPGA_PORT))
        time.sleep(0.005)
    print(f"[+] sent raw payload {len(payload)} bytes  src={actual_src} -> {FPGA_IP}:{FPGA_PORT}")
    s.close()

def generate_pattern(name):
    """生成 16x16 RGB222 图案 (256 字节)"""
    data = bytearray(256)
    for y in range(16):
        for x in range(16):
            idx = y * 16 + x
            if name == 'checker':
                # 棋盘格：8x8 块交替黑/白
                is_white = ((x // 8) + (y // 8)) % 2 == 0
                v6 = 0x3F if is_white else 0x00
            elif name == 'gradient':
                # 渐变：从左上到右下，亮度增加
                lum = (x + y) // 3
                lum = min(lum, 3)
                v6 = (lum << 4) | (lum << 2) | lum
            elif name == 'stripes':
                # 条纹：4 像素宽竖条纹
                is_white = (x // 4) % 2 == 0
                v6 = 0x3F if is_white else 0x00
            else:
                v6 = 0x00
            data[idx] = v6 & 0x3F
    return data

def cmd_pattern(name):
    """发送 16x16 图案到 FPGA BRAM (标准 A5 5A 10 格式)"""
    img_data = generate_pattern(name)
    send_cmd(0x10, img_data)
    print(f"[+] pattern '{name}' sent (16x16 RGB222, 256 bytes) via CMD_IMG_FRAME")

# ============================================================
# Ext-6 : TF 卡 BMP 照片 -> 64x64 RGB222 多包回传
# ============================================================
PHOTO_W, PHOTO_H = 64, 64
PHOTO_NPKT, PHOTO_PAY = 4, 1024     # 4 包 x 1024 = 4096 字节

def cmd_photo(sector, save_path="photo64.png"):
    """触发 FPGA 读 TF 卡 BMP, 接收 4 个 UDP 包重组 64x64 RGB222 -> PNG"""
    # 先绑定接收 socket, 防止丢包 (SD 读卡有几百 ms 延迟)
    r = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    r.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    r.bind(('0.0.0.0', PC_PORT))
    r.settimeout(8.0)               # 首包等久点 (等读卡)
    # 发送 CMD_SD_PHOTO (0x50) + 4 字节起始扇区 (大端)
    sec = int(sector) & 0xFFFFFFFF
    send_cmd(0x50, bytes([(sec>>24)&0xFF, (sec>>16)&0xFF, (sec>>8)&0xFF, sec&0xFF]))
    print(f"[+] CMD_SD_PHOTO sent, start_sector={sec} (0x{sec:08x}); 等待 FPGA 读卡回传...")

    buf = bytearray(PHOTO_W * PHOTO_H)
    got = [False] * PHOTO_NPKT
    while not all(got):
        try:
            data, addr = r.recvfrom(2048)
        except socket.timeout:
            print(f"[!] 超时, 已收到包: {[i for i,g in enumerate(got) if g]}"); break
        r.settimeout(3.0)
        if len(data) < 7 or data[0] != 0xA5 or data[1] != 0x5A or data[2] != 0x51:
            continue
        seq, nseq = data[3], data[4]
        plen = (data[5] << 8) | data[6]
        pay = data[5+2 : 5+2+plen]
        if seq < PHOTO_NPKT and not got[seq]:
            base = seq * PHOTO_PAY
            buf[base:base+len(pay)] = pay
            got[seq] = True
            print(f"  recv pkt seq={seq}/{nseq} len={plen} from {addr}")
    r.close()

    # ASCII 预览
    chars = " .:-=+*#%@"
    for y in range(0, PHOTO_H, 2):     # 隔行, 终端不至于太高
        row = ""
        for x in range(PHOTO_W):
            v6 = buf[y*PHOTO_W + x] & 0x3F
            lum = ((v6>>4)&3) + ((v6>>2)&3) + (v6&3)
            row += chars[min(lum, 9)]
        print(row)

    # 存 PNG (有 PIL 用 PIL, 否则存 PPM)
    try:
        from PIL import Image
        img = Image.new("RGB", (PHOTO_W, PHOTO_H))
        px = img.load()
        for y in range(PHOTO_H):
            for x in range(PHOTO_W):
                v6 = buf[y*PHOTO_W + x] & 0x3F
                px[x, y] = (((v6>>4)&3)*85, ((v6>>2)&3)*85, (v6&3)*85)
        img = img.resize((PHOTO_W*6, PHOTO_H*6), Image.NEAREST)
        img.save(save_path)
        print(f"[+] saved -> {save_path}")
    except ImportError:
        ppm = save_path.rsplit('.',1)[0] + ".ppm"
        with open(ppm, "w") as f:
            f.write(f"P3\n{PHOTO_W} {PHOTO_H}\n255\n")
            for y in range(PHOTO_H):
                for x in range(PHOTO_W):
                    v6 = buf[y*PHOTO_W + x] & 0x3F
                    f.write(f"{((v6>>4)&3)*85} {((v6>>2)&3)*85} {(v6&3)*85}\n")
        print(f"[+] 未装 PIL, 存为 {ppm} (pip install pillow 可直接出 PNG)")

def make_bmp(infile, outfile="out.bmp"):
    """把任意图片转成 640x480 24位 BMP, 供拷进 TF 卡 (硬件按 640x480 降采样)"""
    try:
        from PIL import Image
    except ImportError:
        print("[!!] 需要 Pillow: pip install pillow"); return
    try:
        img = Image.open(infile).convert("RGB")
    except FileNotFoundError:
        print(f"[!!] 找不到输入文件: {infile}"); return
    img = img.resize((640, 480), Image.LANCZOS)
    # PIL 对 RGB 图默认存 24bit、无压缩 BMP (BI_RGB), 正是硬件要的格式
    img.save(outfile, format="BMP")
    print(f"[+] {infile} -> {outfile} (640x480 24bit BMP)")
    print(f"    把 {outfile} 拷到 TF 卡根目录, 再用 findsector / photo 读取")

def find_sector(drive_num):
    """扫描 TF 卡物理盘, 找到第一个 BMP(BM 头) 的起始扇区号 (需管理员权限)"""
    path = rf"\\.\PhysicalDrive{drive_num}"
    print(f"[+] 扫描 {path} 寻找 BMP 起始扇区 (Ctrl-C 中止)...")
    try:
        f = open(path, "rb", buffering=0)
    except PermissionError:
        print("[!!] 权限不足: 请用管理员身份运行 PowerShell/CMD 再执行"); return
    except FileNotFoundError:
        print(f"[!!] 找不到 PhysicalDrive{drive_num}, 用 'wmic diskdrive list brief' 确认盘号"); return
    sec = 0
    SECTOR = 512
    try:
        while True:
            blk = f.read(SECTOR * 2048)     # 每次读 1MB
            if not blk:
                break
            for off in range(0, len(blk) - 54, SECTOR):
                # BMP: 'BM' + 文件大小, DIB 头 width/height
                if blk[off:off+2] == b'BM':
                    import struct
                    w = struct.unpack('<i', blk[off+18:off+22])[0]
                    h = struct.unpack('<i', blk[off+22:off+26])[0]
                    bpp = struct.unpack('<H', blk[off+28:off+30])[0]
                    if 0 < w <= 4096 and 0 < abs(h) <= 4096 and bpp in (24, 32):
                        found = sec + off // SECTOR
                        print(f"[+] 找到 BMP: 起始扇区={found}  ({w}x{abs(h)}, {bpp}bpp)")
                        print(f"    -> 运行: python pc_test.py photo {found}")
                        f.close(); return found
            sec += len(blk) // SECTOR
    except KeyboardInterrupt:
        print("\n[!] 已中止")
    f.close()
    print("[!] 未找到 BMP"); return None

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(__doc__); sys.exit(0)
    op = sys.argv[1]
    if op == 'led':
        cmd_led(int(sys.argv[2], 0)); print(f"LED <- {sys.argv[2]}")
    elif op == 'seg':
        cmd_seg(sys.argv[2]);          print(f"SEG <- {sys.argv[2]}")
    elif op == 'img':
        save = sys.argv[2] if len(sys.argv) >= 3 else None
        cmd_img_req(save)
    elif op == 'mode':
        m = int(sys.argv[2], 0) & 3
        send_cmd(0x40, bytes([m]))
        print(f"PROC_MODE <- {m} (0=RAW 1=GRAY 2=EDGE 3=INVERT)")
    elif op == 'cam':
        v = int(sys.argv[2], 0) & 1
        send_cmd(0x30, bytes([v]))
        print(f"CAM_EN <- {v} (0=PC上传图像 1=摄像头实时)")
    elif op == 'pattern':
        if len(sys.argv) < 3:
            print("Usage: python pc_test.py pattern checker|gradient|stripes")
            sys.exit(1)
        cmd_pattern(sys.argv[2])
    elif op == 'photo':
        if len(sys.argv) < 3:
            print("Usage: python pc_test.py photo <起始扇区> [out.png]")
            print("  起始扇区可先用 'python pc_test.py findsector <盘号>' 自动找")
            sys.exit(1)
        sec = int(sys.argv[2], 0)
        out = sys.argv[3] if len(sys.argv) >= 4 else "photo64.png"
        cmd_photo(sec, out)
    elif op == 'mkbmp':
        if len(sys.argv) < 3:
            print("Usage: python pc_test.py mkbmp <输入图片> [out.bmp]")
            sys.exit(1)
        out = sys.argv[3] if len(sys.argv) >= 4 else "out.bmp"
        make_bmp(sys.argv[2], out)
    elif op == 'findsector':
        if len(sys.argv) < 3:
            print("Usage (管理员): python pc_test.py findsector <物理盘号>")
            print("  盘号用 'wmic diskdrive list brief' 查看 (TF 卡一般是最后一个)")
            sys.exit(1)
        find_sector(int(sys.argv[2], 0))
    else:
        print(__doc__)
