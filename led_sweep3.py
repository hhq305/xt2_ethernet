#!/usr/bin/env python3
"""端口扫描 v3:
板上 LED active-HIGH (1=亮 0=灭).
对每个端口发 LED=0x03 (点亮 LED3+LED4), 一直发到 256 端口.
扫完后:  LED3 + LED4 同时亮 -> 找到 FPGA 真实监听端口.
扫描中也发 LED=0x00 让 LED 闪烁 (LED2 也会因 dbg_rx_seen 翻转闪烁).
"""
import socket, time
FPGA_IP = '192.168.240.1'
M0, M1 = 0xA5, 0x5A
def pkt(val): return bytes([M0, M1, 0x01, 0x00, 0x01, val])

s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
print("[*] 扫 1..256 各发 LED=0x03 (点亮 LED3+LED4)")
print("[*] 看到 LED3+LED4 亮的瞬间, 当前端口就是真实监听端口")
print("[*] LED2 应该频繁闪 (验 UDP 接收), 否则 UDP 完全没到")
for port in range(1, 257):
    s.sendto(pkt(0x03), (FPGA_IP, port))      # 点亮 LED3+4
    time.sleep(0.15)
    s.sendto(pkt(0x00), (FPGA_IP, port))      # 灭
    time.sleep(0.05)
    if port % 8 == 0: print(f"  扫到 port {port}", flush=True)
print("[*] 扫描结束. 把所有端口都发了 LED=0x03 一次. 此刻最后发的是 port 256 的 LED=0x00.")
print("[*] 现在再发 1 次 LED=0x03 到所有端口, 看 LED3+4 最终状态:")
for port in range(1, 257):
    s.sendto(pkt(0x03), (FPGA_IP, port))
print("[*] done. 观察 LED3 + LED4: 亮=有 1 个端口生效; 灭=UDP 完全没到")
