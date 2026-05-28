#!/usr/bin/env python3
"""
端口扫描诊断脚本
按 KEY2 复位 LED 探针后, 运行此脚本.
脚本会向 FPGA 发送一系列 UDP 包到不同端口, 每发一组等 1 秒.
观察 LED2 (app_rx_data_valid sticky) 在哪一轮亮起.
"""
import socket, time

PC_IP   = '192.168.240.2'
PC_PORT = 2
FPGA_IP = '192.168.240.1'

# 候选端口: 文档说的 1, encrypt 默认 0xf000, 一些常见值
PORTS = [1, 2, 0xf000, 8080, 1234, 5000, 0x1234, 0x0a01, 0xc0a8]

PKT = bytes([0xA5, 0x5A, 0x01, 0x00, 0x01, 0x0F])  # CMD_LED_SET led=0x0F

s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind((PC_IP, PC_PORT))

print("[*] 先 KEY2 复位探针, 然后按 Enter 开始扫描...")
input()

for p in PORTS:
    print(f"[+] 发到 port=0x{p:04X} ({p})  -- 看 LED2 是否亮")
    for _ in range(5):
        s.sendto(PKT, (FPGA_IP, p))
        time.sleep(0.05)
    time.sleep(2.0)   # 给你时间观察

s.close()
print("[*] 全部端口发完. 哪一轮 LED2 亮起来就是真实监听端口.")
