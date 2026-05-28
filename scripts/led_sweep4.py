#!/usr/bin/env python3
"""扫描更大的端口范围, 同时绑定源端口 = 2.
验证猜测: 协议栈端口解析可能是小端, 实际端口可能是 0x0400=1024 或 0x0100=256.
扫到正确端口时 LED2 sticky 立刻亮起来.
"""
import socket, time
FPGA_IP = '192.168.240.1'
M0, M1 = 0xA5, 0x5A
def pkt(val): return bytes([M0, M1, 0x01, 0x00, 0x01, val])

# 先重点测几个高度怀疑的端口
candidates = [
    1, 2, 3, 4, 5,           # 参数和动态端口
    256, 1024,               # 字节序翻转的 1 和 4
    0x0001, 0x0100,          # 小端 / 大端的 1
    0x0004, 0x0400,          # 小端 / 大端的 4
    1234, 5678, 8080, 9999,  # 常见调试端口
]
print(f"[*] 重点扫: {sorted(set(candidates))}")
for port in sorted(set(candidates)):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind(('', 2))
    except OSError: pass
    s.sendto(pkt(0x03), (FPGA_IP, port))
    s.close()
    print(f"  port {port:5d}", flush=True)
    time.sleep(0.5)

print("\n[*] 全范围扫 1..2048")
for port in range(1, 2049):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind(('', 2))
    except OSError: pass
    s.sendto(pkt(0x03), (FPGA_IP, port))
    s.close()
    if port % 64 == 0: print(f"  扫到 port {port}", flush=True)
    time.sleep(0.005)
print("[*] done. 看 LED2 是否点亮.")
