#!/usr/bin/env python3
"""
选题二 PC 端测试工具
- 基础 : LED 控制
- Ext-1: 7-seg 控制
- Ext-2: 触发 FPGA 回传图像
用法:
    python pc_test.py led 7        # 全亮 3 个 LED
    python pc_test.py seg 1234     # 数码管显示 1234
    python pc_test.py img          # 触发图像回传, 接收并打印前 16 字节
    python pc_test.py mode 0       # 设置 VGA 处理模式 0=RAW 1=GRAY 2=EDGE 3=INVERT
"""
import socket, sys, time, os, subprocess

FPGA_IP   = '192.168.240.1'
FPGA_PORT = 1                       # 协议栈硬编码监听 port 1 (与 verilog input_local_udp_port_num 设置无关)
PC_PORT   = 2                       # 协议栈期望源端口 = 2 (= DST_UDP_PORT_NUM)
PC_IP     = '192.168.240.2'         # 强制从这张网卡出, 否则 Windows 会选 WLAN/Hyper-V/VPN
MAGIC0, MAGIC1 = 0xA5, 0x5A

_arp_warmed = False

def _arp_warmup():
    """触发 ARP 解析: ping 一次, 让 OS 填好 ARP 表; 否则首批 UDP 会被 OS 丢."""
    global _arp_warmed
    if _arp_warmed:
        return
    # Windows 静默 ping 一次, 1s 超时, 强制源 IP
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
    pkt = bytes([MAGIC0, MAGIC1, cmd, (len(payload)>>8)&0xFF, len(payload)&0xFF]) + payload
    # 连续发 8 次小间隔, 防止单包被丢
    for _ in range(8):
        s.sendto(pkt, (FPGA_IP, FPGA_PORT))
        time.sleep(0.005)
    print(f"[+] sent CMD=0x{cmd:02X} payload={payload.hex()}  src={actual_src} -> {FPGA_IP}:{FPGA_PORT}")
    s.close()

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
    r.settimeout(3.0)
    r.bind(('0.0.0.0', PC_PORT))
    send_cmd(0x20, b'')
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
    else:
        print(__doc__)
