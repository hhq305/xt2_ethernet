"""端口扫描 + 联通诊断
向 FPGA 不同端口发 IMG_REQ (0x20), 看哪个端口会回包.
"""
import socket, time

FPGA_IP = '192.168.240.1'

# 1) 开本地接收 socket, 任意源端口
r = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
r.settimeout(0.5)
r.bind(('0.0.0.0', 2))   # 监听 PC 端口 2 (FPGA TX 默认目的端口)

s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
pkt = bytes([0xA5, 0x5A, 0x20, 0x00, 0x00])  # IMG_REQ, 0 字节 payload

print(f"[*] 向 {FPGA_IP} 端口 1..256 各发一次 IMG_REQ ...")
for port in range(1, 257):
    s.sendto(pkt, (FPGA_IP, port))
    time.sleep(0.05)
    try:
        data, addr = r.recvfrom(2048)
        print(f"  端口 {port:2d} -> 收到 {len(data)} 字节回包, 来自 {addr}")
    except socket.timeout:
        pass

print("[*] 完成. 没打印 '收到' 的端口 = 没回包.")
print("    如果一个都没回: UDP 应用层不通, 看 Wireshark 抓包.")
print("    如果某端口有回: 那就是 FPGA 真实监听端口.")
r.close(); s.close()
