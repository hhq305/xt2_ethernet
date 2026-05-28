#!/usr/bin/env python3
"""向 1..256 每个 UDP 端口都发一次 LED=0x07 命令.
人眼盯板子: 看到 LED0/1/2 同时亮的瞬间, 当前打印的端口号就是 FPGA 真实监听端口.
"""
import socket, time
FPGA_IP = '192.168.240.1'
MAGIC0, MAGIC1 = 0xA5, 0x5A
pkt = bytes([MAGIC0, MAGIC1, 0x01, 0x00, 0x01, 0x07])

s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
print("[*] 盯板子 LED, 看到 3 个 LED 同时亮时记下当前打印的端口号")
for port in range(1, 257):
    s.sendto(pkt, (FPGA_IP, port))
    print(f"  port {port:3d} -> LED=0x07", flush=True)
    time.sleep(0.25)              # 给眼睛 0.25s 看
print("[*] done. 若全程无变化 -> FPGA 根本没收到 UDP, 用 Wireshark 抓包")
