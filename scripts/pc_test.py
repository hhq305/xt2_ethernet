#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""PC test tool for the FPGA Ethernet camera path."""

import os
import socket
import subprocess
import sys
import time

FPGA_IP = "192.168.240.1"
FPGA_PORT = 1
PC_IP = "192.168.240.2"
PC_PORT = 2
FPGA_MAC = "00-11-22-33-44-55"
_ARP_WARNED = False

MAGIC0, MAGIC1 = 0xA5, 0x5A

CAM_W, CAM_H = 80, 60
CAM_PAY = 480
CAM_NPKT = (CAM_W * CAM_H * 2) // CAM_PAY
CAM_HDR = 17

HXV2_W, HXV2_H = 640, 480
HXV2_HDR = 20
HXV2_PACKET_LEN = HXV2_HDR + HXV2_W * 2


def arp_warmup():
    """Keep the static ARP entry present on Windows."""
    global _ARP_WARNED
    try:
        res = subprocess.run(
            ["arp", "-s", FPGA_IP, FPGA_MAC, PC_IP],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
            timeout=2,
        )
        if res.returncode != 0 and not _ARP_WARNED:
            print("[!] static ARP setup failed; run PowerShell as Administrator if UDP is unstable.")
            _ARP_WARNED = True
    except Exception as exc:
        if not _ARP_WARNED:
            print(f"[!] static ARP setup skipped: {exc}")
            _ARP_WARNED = True


def open_socket():
    arp_warmup()
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 1 << 20)
    s.bind((PC_IP, PC_PORT))
    return s


def send_cmd_on_socket(sock, cmd, payload=b"", repeat=8, delay=0.005, verbose=True):
    pkt = bytes([MAGIC0, MAGIC1, cmd, (len(payload) >> 8) & 0xFF, len(payload) & 0xFF]) + payload
    src = sock.getsockname()
    for _ in range(repeat):
        sock.sendto(pkt, (FPGA_IP, FPGA_PORT))
        time.sleep(delay)
    if verbose:
        print(f"[+] sent CMD=0x{cmd:02X} payload={payload.hex()} src={src} -> {FPGA_IP}:{FPGA_PORT}")


def send_cmd(cmd, payload=b""):
    s = open_socket()
    try:
        send_cmd_on_socket(s, cmd, payload)
    finally:
        s.close()


def cmd_led(val):
    send_cmd(0x01, bytes([val & 0xFF]))


def cmd_seg(text):
    h = text.rjust(4, "0")[-4:]
    payload = bytes(int(ch, 16) & 0xF for ch in reversed(h))
    send_cmd(0x02, payload)


def drain_udp(sock):
    old_timeout = sock.gettimeout()
    sock.settimeout(0.0)
    try:
        while True:
            try:
                sock.recvfrom(2048)
            except (BlockingIOError, socket.timeout):
                break
    finally:
        sock.settimeout(old_timeout)


def cmd_raw(seconds=8.0):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 1 << 20)
    s.bind(("0.0.0.0", PC_PORT))
    s.settimeout(0.5)
    end_time = time.time() + seconds
    total = 0
    print(f"[i] raw: listen {seconds:.1f}s on 0.0.0.0:{PC_PORT}")
    try:
        send_cmd_on_socket(s, 0x30, bytes([1]), repeat=3)
        while time.time() < end_time:
            send_cmd_on_socket(s, 0x31, b"", repeat=1, verbose=False)
            try:
                data, addr = s.recvfrom(2048)
            except socket.timeout:
                continue
            total += 1
            if total <= 8 or total % 100 == 0:
                print(f"  #{total} from {addr} len={len(data)} head={data[:32].hex(' ')}")
    finally:
        send_cmd_on_socket(s, 0x30, bytes([0]), repeat=3)
        s.close()
    print(f"[i] raw done: total={total}")


def recv_track_frame(sock, first_timeout=2.0, pkt_timeout=0.4):
    total_bytes = CAM_W * CAM_H * 2
    buf = bytearray(total_bytes)
    got = [False] * CAM_NPKT
    ngot = 0
    started = False
    meta = None
    first31 = None
    bad_shape = None
    short_pkt = None
    rx_total = 0
    cam_pkts = 0

    sock.settimeout(first_timeout)
    while ngot < CAM_NPKT:
        try:
            data, _ = sock.recvfrom(2048)
        except socket.timeout:
            break

        rx_total += 1
        sock.settimeout(pkt_timeout)

        if len(data) < CAM_HDR or data[0] != MAGIC0 or data[1] != MAGIC1 or data[2] != 0x31:
            continue

        seq = (data[3] << 8) | data[4]
        nall = (data[5] << 8) | data[6]
        plen = (data[7] << 8) | data[8]
        cam_pkts += 1

        if first31 is None:
            first31 = {
                "len": len(data),
                "seq": seq,
                "npkt": nall,
                "plen": plen,
                "head": data[:20].hex(" "),
            }

        if nall != CAM_NPKT or plen != CAM_PAY:
            if bad_shape is None:
                bad_shape = (len(data), seq, nall, plen)
            continue

        if len(data) < CAM_HDR + plen:
            if short_pkt is None:
                short_pkt = (len(data), seq, nall, plen)
            continue

        # 必须从 seq=0 开始拼帧；半路收到尾包时直接丢弃，
        # 避免不同请求的尾包和头包混成一帧。
        if not started:
            if seq != 0:
                continue
            started = True
            sock.settimeout(pkt_timeout)

        if meta is None:
            meta = {
                "xmin": data[9],
                "xmax": data[10],
                "ymin": data[11],
                "ymax": data[12],
                "area": (data[13] << 8) | data[14],
                "valid": data[15] & 1,
            }

        if seq < CAM_NPKT and not got[seq]:
            pay = data[CAM_HDR:CAM_HDR + plen]
            base = seq * CAM_PAY
            buf[base:base + len(pay)] = pay
            got[seq] = True
            ngot += 1

    info = {
        "ngot": ngot,
        "rx_total": rx_total,
        "cam_pkts": cam_pkts,
        "first31": first31,
        "bad_shape": bad_shape,
        "short_pkt": short_pkt,
    }
    return ngot == CAM_NPKT, buf, meta, info


def save_rgb565(buf, path):
    try:
        from PIL import Image
    except ImportError:
        ppm = os.path.splitext(path)[0] + ".ppm"
        with open(ppm, "w", encoding="ascii") as f:
            f.write(f"P3\n{CAM_W} {CAM_H}\n255\n")
            for i in range(CAM_W * CAM_H):
                v = (buf[2 * i] << 8) | buf[2 * i + 1]
                r = ((v >> 11) & 0x1F) << 3
                g = ((v >> 5) & 0x3F) << 2
                b = (v & 0x1F) << 3
                f.write(f"{r} {g} {b}\n")
        print(f"[+] saved -> {ppm}")
        return

    img = Image.new("RGB", (CAM_W, CAM_H))
    px = img.load()
    for i in range(CAM_W * CAM_H):
        v = (buf[2 * i] << 8) | buf[2 * i + 1]
        x = i % CAM_W
        y = i // CAM_W
        r = ((v >> 11) & 0x1F) << 3
        g = ((v >> 5) & 0x3F) << 2
        b = (v & 0x1F) << 3
        px[x, y] = (r, g, b)
    img.save(path)
    print(f"[+] saved -> {path}")


def cmd_camdebug(seconds=5.0):
    s = open_socket()
    try:
        send_cmd_on_socket(s, 0x30, bytes([1]), repeat=3)
        time.sleep(1.0)
        end_time = time.time() + seconds
        next_req = 0.0
        total = 0
        cam_pkts = 0
        s.settimeout(0.5)
        print(f"[i] camdebug: listen {seconds:.1f}s on {PC_IP}:{PC_PORT}")
        while time.time() < end_time:
            now = time.time()
            if now >= next_req:
                send_cmd_on_socket(s, 0x31, b"", repeat=1)
                next_req = now + 0.5
            try:
                data, addr = s.recvfrom(2048)
            except socket.timeout:
                continue
            total += 1
            if len(data) >= 9 and data[0] == MAGIC0 and data[1] == MAGIC1:
                cmd = data[2]
                seq = (data[3] << 8) | data[4]
                nall = (data[5] << 8) | data[6]
                plen = (data[7] << 8) | data[8]
                if cmd == 0x31:
                    cam_pkts += 1
                print(f"  from {addr} len={len(data)} cmd=0x{cmd:02X} seq={seq} npkt={nall} plen={plen} head={data[:20].hex(' ')}")
            else:
                print(f"  from {addr} len={len(data)} bad head={data[:20].hex(' ')}")
        print(f"[i] camdebug done: total={total}, cam_pkts={cam_pkts}")
    finally:
        send_cmd_on_socket(s, 0x30, bytes([0]), repeat=3)
        s.close()


def cmd_camcap(path="cam.png"):
    s = open_socket()
    try:
        drain_udp(s)
        send_cmd_on_socket(s, 0x30, bytes([1]), repeat=3)
        time.sleep(1.0)
        print("[i] camera enabled, waiting one frame...")
        send_cmd_on_socket(s, 0x31, b"", repeat=1)
        ok, buf, meta, info = recv_track_frame(s, first_timeout=5.0, pkt_timeout=1.5)
        print(f"[i] meta={meta}")
        if not ok:
            print(f"[!] incomplete frame: {info}")
        save_rgb565(buf, path)
    finally:
        send_cmd_on_socket(s, 0x30, bytes([0]), repeat=3)
        s.close()


def rgb565_to_rgb(buf):
    import numpy as np
    arr = np.frombuffer(bytes(buf), dtype=np.uint8).reshape(CAM_H, CAM_W, 2).astype(np.uint16)
    v = (arr[:, :, 0] << 8) | arr[:, :, 1]
    out = np.zeros((CAM_H, CAM_W, 3), dtype=np.uint8)
    out[:, :, 0] = ((v >> 11) & 0x1F) << 3
    out[:, :, 1] = ((v >> 5) & 0x3F) << 2
    out[:, :, 2] = (v & 0x1F) << 3
    return out


def hxv2_rgb565_to_rgb(buf):
    import numpy as np
    arr = np.frombuffer(bytes(buf), dtype=np.uint8).reshape(HXV2_H, HXV2_W, 2).astype(np.uint16)
    v = (arr[:, :, 0] << 8) | arr[:, :, 1]
    out = np.zeros((HXV2_H, HXV2_W, 3), dtype=np.uint8)
    out[:, :, 0] = (v & 0x1F) << 3
    out[:, :, 1] = ((v >> 5) & 0x3F) << 2
    out[:, :, 2] = ((v >> 11) & 0x1F) << 3
    return out


def recv_hxv2_frame(sock, frame=None, first_timeout=5.0, pkt_timeout=1.0):
    clear_on_start = frame is None
    if frame is None:
        frame = bytearray(HXV2_W * HXV2_H * 2)
    got = [False] * HXV2_H
    ngot = 0
    frame_id = None
    started = False
    rx_total = 0
    hxv2_pkts = 0
    other_pkts = 0
    first_hxv2 = None
    first_other = None

    deadline = time.time() + first_timeout
    sock.settimeout(min(0.2, first_timeout))
    while time.time() < deadline and ngot < HXV2_H:
        try:
            data, addr = sock.recvfrom(2048)
        except socket.timeout:
            remain = deadline - time.time()
            if remain <= 0:
                break
            sock.settimeout(min(0.2, remain))
            continue

        rx_total += 1
        deadline = time.time() + pkt_timeout
        sock.settimeout(pkt_timeout)

        if len(data) != HXV2_PACKET_LEN or data[:4] != b"HXV2":
            other_pkts += 1
            if first_other is None:
                first_other = {
                    "addr": addr,
                    "len": len(data),
                    "head": data[:20].hex(" "),
                }
            continue

        hxv2_pkts += 1
        deadline = time.time() + pkt_timeout
        fid = (data[4] << 8) | data[5]
        row = (data[6] << 8) | data[7]
        width = (data[8] << 8) | data[9]
        height = (data[10] << 8) | data[11]

        if first_hxv2 is None:
            first_hxv2 = {
                "addr": addr,
                "len": len(data),
                "frame": fid,
                "row": row,
                "width": width,
                "height": height,
                "head": data[:20].hex(" "),
            }

        if width != HXV2_W or height != HXV2_H or row >= HXV2_H:
            continue

        if not started:
            if row != 0:
                continue
            if clear_on_start:
                frame[:] = b"\x00" * len(frame)
            started = True

        if frame_id is None:
            frame_id = fid
        elif fid != frame_id and ngot == 0:
            frame_id = fid
        elif fid != frame_id:
            break

        if not got[row]:
            base = row * HXV2_W * 2
            frame[base:base + HXV2_W * 2] = data[HXV2_HDR:HXV2_PACKET_LEN]
            got[row] = True
            ngot += 1

    info = {
        "ngot": ngot,
        "rx_total": rx_total,
        "hxv2_pkts": hxv2_pkts,
        "other_pkts": other_pkts,
        "first_hxv2": first_hxv2,
        "first_other": first_other,
    }
    return ngot > 0, frame, info


def cmd_hxv2(scale=1):
    try:
        import cv2
        import numpy as np
    except ImportError:
        print("[!!] need numpy and opencv-python")
        return

    s = open_socket()
    frame_no = 0
    miss = 0
    last = time.time()
    frame_buf = bytearray(HXV2_W * HXV2_H * 2)
    last_rgb = None
    try:
        drain_udp(s)
        send_cmd_on_socket(s, 0x30, bytes([1]), repeat=3)
        time.sleep(1.0)
        send_cmd_on_socket(s, 0x31, b"", repeat=3, delay=0.02, verbose=False)
        print("[i] camera enabled, receiving HXV2 row packets. Press q to exit.")

        while True:
            ok, buf, info = recv_hxv2_frame(s, frame_buf, first_timeout=0.6, pkt_timeout=0.12)
            if ok and info["ngot"] >= HXV2_H:
                miss = 0
                frame_no += 1
                last_rgb = hxv2_rgb565_to_rgb(buf)
                if scale != 1:
                    last_rgb = cv2.resize(last_rgb, (HXV2_W * scale, HXV2_H * scale), interpolation=cv2.INTER_NEAREST)
            else:
                miss += 1
                if miss % 3 == 0:
                    print(f"[!] incomplete HXV2 frame x{miss}, info={info}")
                if last_rgb is None:
                    wait = np.zeros((HXV2_H * scale, HXV2_W * scale, 3), dtype=np.uint8)
                    cv2.putText(wait, "waiting for HXV2 video...", (24, 40), cv2.FONT_HERSHEY_SIMPLEX, 1.0, (0, 255, 255), 2)
                    cv2.imshow("FPGA HXV2 Camera", wait)
                    if cv2.waitKey(1) & 0xFF == ord("q"):
                        break
                    continue

            rgb = last_rgb.copy()
            now = time.time()
            fps = 1.0 / max(now - last, 1e-6)
            last = now
            cv2.putText(rgb, f"frame={frame_no} fps={fps:.1f}", (8, 24), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 0), 2)
            cv2.imshow("FPGA HXV2 Camera", rgb)
            if cv2.waitKey(1) & 0xFF == ord("q"):
                break
    finally:
        send_cmd_on_socket(s, 0x30, bytes([0]), repeat=3)
        s.close()
        try:
            import cv2
            cv2.destroyAllWindows()
        except Exception:
            pass


def cmd_track(scale=8):
    try:
        import cv2
        import numpy as np
    except ImportError:
        print("[!!] need numpy and opencv-python")
        return

    s = open_socket()
    frame_no = 0
    miss = 0
    last = time.time()
    try:
        drain_udp(s)
        send_cmd_on_socket(s, 0x30, bytes([1]), repeat=3)
        time.sleep(1.0)
        print("[i] camera enabled, realtime tracking. Press q to exit.")

        while True:
            send_cmd_on_socket(s, 0x31, b"", repeat=1)
            ok, buf, meta, info = recv_track_frame(s, first_timeout=5.0, pkt_timeout=2.0)
            if not ok:
                miss += 1
                if miss % 5 == 0:
                    print(f"[!] no complete frame x{miss}, info={info}")
                wait = np.zeros((CAM_H * scale, CAM_W * scale, 3), dtype=np.uint8)
                cv2.putText(wait, "waiting for FPGA video...", (12, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 255), 2)
                cv2.imshow("FPGA Motion Tracking", wait)
                if cv2.waitKey(1) & 0xFF == ord("q"):
                    break
                continue

            miss = 0
            frame_no += 1
            rgb = rgb565_to_rgb(buf)
            big = cv2.resize(rgb, (CAM_W * scale, CAM_H * scale), interpolation=cv2.INTER_NEAREST)
            now = time.time()
            fps = 1.0 / max(now - last, 1e-6)
            last = now
            status = "no motion"
            if meta and meta.get("valid"):
                x0 = meta["xmin"] * scale
                x1 = meta["xmax"] * scale
                y0 = meta["ymin"] * scale
                y1 = meta["ymax"] * scale
                cv2.rectangle(big, (x0, y0), (x1, y1), (0, 255, 0), 2)
                status = f"motion area={meta['area']}"
            cv2.putText(big, status, (6, 18), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 0), 1)
            cv2.putText(big, f"fps={fps:.1f}", (6, CAM_H * scale - 8), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 0), 1)
            cv2.imshow("FPGA Motion Tracking", big)
            if cv2.waitKey(1) & 0xFF == ord("q"):
                break
    finally:
        send_cmd_on_socket(s, 0x30, bytes([0]), repeat=3)
        s.close()
        try:
            import cv2
            cv2.destroyAllWindows()
        except Exception:
            pass


def main():
    if len(sys.argv) < 2:
        print("Usage: python pc_test.py led|seg|camdebug|camcap|track|hxv2|raw ...")
        return
    op = sys.argv[1].lower()
    if op == "led":
        cmd_led(int(sys.argv[2], 0))
    elif op == "seg":
        cmd_seg(sys.argv[2])
    elif op == "camdebug":
        cmd_camdebug(float(sys.argv[2]) if len(sys.argv) > 2 else 5.0)
    elif op == "camcap":
        cmd_camcap(sys.argv[2] if len(sys.argv) > 2 else "cam.png")
    elif op == "track":
        cmd_track(int(sys.argv[2], 0) if len(sys.argv) > 2 else 8)
    elif op == "hxv2":
        cmd_hxv2(int(sys.argv[2], 0) if len(sys.argv) > 2 else 1)
    elif op == "raw":
        cmd_raw(float(sys.argv[2]) if len(sys.argv) > 2 else 8.0)
    else:
        print(f"unknown command: {op}")


if __name__ == "__main__":
    main()
