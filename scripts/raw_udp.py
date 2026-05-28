#!/usr/bin/env python3
"""手工构造 UDP 包, 包括正确的 UDP checksum.
Windows raw socket 限制多, 改用 socket 默认 (OS 会算 checksum).
该脚本只是显示当前 socket 行为.
"""
import socket, struct
FPGA_IP   = '192.168.240.1'
FPGA_PORT = 4
PC_PORT   = 2
M0, M1 = 0xA5, 0x5A
pay = bytes([M0, M1, 0x01, 0x00, 0x01, 0x03])

s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    s.bind(('0.0.0.0', PC_PORT))
    print(f"[*] 绑定源端口 {PC_PORT} 成功")
except OSError as e:
    print(f"[!] 绑定失败: {e}")

# 多发几次, 增加观察机会
for i in range(20):
    s.sendto(pay, (FPGA_IP, FPGA_PORT))
print(f"[*] 已向 {FPGA_IP}:{FPGA_PORT} 发了 20 次 LED=0x03")
s.close()
