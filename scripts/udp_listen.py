#!/usr/bin/env python3
"""监听 FPGA 主动发的 UDP 包. FPGA 默认会通过 udp_data_tpg/img_tx_rom 发包到 PC.
如果能在端口 2 收到任何包, 说明 FPGA TX 通路工作.
"""
import socket, time
PC_PORT = 2
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    s.bind(('0.0.0.0', PC_PORT))
except PermissionError:
    print(f"[!] bind {PC_PORT} 需要管理员. 退出.")
    raise SystemExit(1)
print(f"[*] 监听 UDP 端口 {PC_PORT} (10秒)")
print(f"[*] 看 FPGA 是否主动发包过来")
s.settimeout(10.0)
try:
    cnt = 0
    t0 = time.time()
    while time.time() - t0 < 10:
        try:
            data, addr = s.recvfrom(2048)
            cnt += 1
            print(f"[{cnt:3d}] from {addr}, {len(data)} bytes: {data[:32].hex(' ')}{'...' if len(data)>32 else ''}")
        except socket.timeout:
            break
    if cnt == 0:
        print("[!] 10 秒内没收到任何包 -> FPGA TX 路径也不工作")
    else:
        print(f"[*] 共收到 {cnt} 个包")
finally:
    s.close()
