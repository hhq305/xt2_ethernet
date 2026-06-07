#!/usr/bin/env python3
"""LED 端口扫描 v2: 板上 LED 共阳低有效, 复位时全亮.
对每个端口连发 LED=0x07(全灭) -> 等 0.6s -> LED=0x00(全亮) -> 等 0.4s.
人眼盯 LED0/1/2 (D1/D2/D3): 看到 3 颗灯一起灭一下又亮 -> 当前端口就是真实监听端口.
"""
import socket, time
FPGA_IP = '192.168.240.1'
M0, M1 = 0xA5, 0x5A
def pkt(val): return bytes([M0, M1, 0x01, 0x00, 0x01, val])

s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
print("[*] 盯 LED0/1/2: 灭一下又亮 -> 记下当前端口")
for port in range(1, 257):
    s.sendto(pkt(0x07), (FPGA_IP, port))   # 全灭
    print(f"  port {port:3d}  LED=0x07 (灭)", flush=True); time.sleep(0.6)
    s.sendto(pkt(0x00), (FPGA_IP, port))   # 全亮
    time.sleep(0.4)
print("[*] done. 全程无变化 -> Wireshark 抓包")
