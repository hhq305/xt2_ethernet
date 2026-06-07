#!/usr/bin/env python3
"""综合 sweep: 同时扫 PC 源端口 + FPGA 目的端口.
每发一组停 2 秒, 让你看 LED2 (A3, dbg_app_rx_sticky) 在哪一组亮起.
LED2 是 sticky, 一旦亮就保持. 看到 LED2 亮后立刻记下当时控制台打印的组合."""
import socket, time

FPGA_IP = '192.168.240.1'
M = bytes([0xA5, 0x5A, 0x01, 0x00, 0x01, 0x07])

# 候选源端口 (FPGA 协议栈可能要求源端口固定 = byte-swap(DST_UDP_PORT_NUM))
src_ports = [2, 4, 0x0200, 0x0400, 1234, 50001, 0]   # 0 = 不指定 (随机)

# 候选目的端口 (FPGA 协议栈监听端口可能 byte-swap)
dst_ports = [1, 4, 256, 1024, 0x0001, 0x0100, 0x0400]

print("[*] 按 KEY2 复位板子, 然后回车开始扫描...")
input()

for src in src_ports:
    for dst in dst_ports:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        if src != 0:
            try:
                s.bind(('0.0.0.0', src))
            except OSError as e:
                print(f"  [bind src={src} 失败: {e}, skip]")
                s.close()
                continue
        for _ in range(3):
            s.sendto(M, (FPGA_IP, dst))
        print(f"  src={src:5d} -> {FPGA_IP}:{dst:5d}    (LED2 亮 -> 记下这一组!)", flush=True)
        s.close()
        time.sleep(2.0)
print("[*] sweep 结束.")
