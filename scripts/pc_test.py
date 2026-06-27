#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""PC test tool for the FPGA Ethernet camera path."""

import json
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
CMD_CAM_ROI = 0x32
FPGA_ROI_PACKET_LEN = 24


def _env_int(name, default, minimum=1):
    try:
        return max(minimum, int(os.environ.get(name, str(default))))
    except ValueError:
        return default


def _env_float(name, default, minimum=0.0):
    try:
        return max(minimum, float(os.environ.get(name, str(default))))
    except ValueError:
        return default


def _env_path(name, default=""):
    return os.environ.get(name, default).strip().strip('"').strip("'")


def _opencv_model_pairs():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_dir = os.path.dirname(script_dir)
    roots = (script_dir, os.path.join(project_dir, "models"), os.path.join(project_dir, "weights"))
    pairs = []
    for root in roots:
        pairs.extend((
            (os.path.join(root, "yolov8n.onnx"), ""),
            (os.path.join(root, "yolov5n.onnx"), ""),
            (os.path.join(root, "yolov4-tiny.weights"), os.path.join(root, "yolov4-tiny.cfg")),
            (os.path.join(root, "yolov3-tiny.weights"), os.path.join(root, "yolov3-tiny.cfg")),
            (os.path.join(root, "yolov4.weights"), os.path.join(root, "yolov4.cfg")),
            (os.path.join(root, "yolov3.weights"), os.path.join(root, "yolov3.cfg")),
            (os.path.join(root, "ssd_mobilenet_v2_coco.pb"), os.path.join(root, "ssd_mobilenet_v2_coco.pbtxt")),
            (os.path.join(root, "frozen_inference_graph.pb"), os.path.join(root, "ssd_mobilenet_v2_coco_2018_03_29.pbtxt")),
            (os.path.join(root, "MobileNetSSD_deploy.caffemodel"), os.path.join(root, "MobileNetSSD_deploy.prototxt")),
            (os.path.join(root, "mobilenet_iter_73000.caffemodel"), os.path.join(root, "deploy.prototxt")),
        ))
    return pairs


def _default_opencv_pair():
    for model_path, config_path in _opencv_model_pairs():
        if os.path.exists(model_path) and (not config_path or os.path.exists(config_path)):
            return model_path, config_path
    for model_path, config_path in _opencv_model_pairs():
        if os.path.exists(model_path):
            return model_path, config_path if config_path and os.path.exists(config_path) else ""
    return "", ""


def _matching_opencv_config(model_path):
    if not model_path:
        return ""
    model_abs = os.path.abspath(model_path)
    for candidate_model, candidate_config in _opencv_model_pairs():
        if os.path.abspath(candidate_model) == model_abs and os.path.exists(candidate_config):
            return candidate_config
    model_dir = os.path.dirname(model_abs)
    model_name = os.path.basename(model_path).lower()
    if model_name.endswith(".pb"):
        candidates = ("ssd_mobilenet_v2_coco.pbtxt", "ssd_mobilenet_v2_coco_2018_03_29.pbtxt")
    elif model_name.endswith(".weights") and "yolo" in model_name:
        stem = os.path.splitext(os.path.basename(model_path))[0]
        candidates = (stem + ".cfg", "yolov4-tiny.cfg", "yolov3-tiny.cfg", "yolov4.cfg", "yolov3.cfg")
    elif model_name.endswith(".onnx"):
        candidates = ()
    else:
        candidates = ("MobileNetSSD_deploy.prototxt", "deploy.prototxt")
    for name in candidates:
        path = os.path.join(model_dir, name)
        if os.path.exists(path):
            return path
    return ""


def _matching_opencv_model(config_path):
    if not config_path:
        return ""
    config_abs = os.path.abspath(config_path)
    for candidate_model, candidate_config in _opencv_model_pairs():
        if os.path.abspath(candidate_config) == config_abs and os.path.exists(candidate_model):
            return candidate_model
    config_dir = os.path.dirname(config_abs)
    config_name = os.path.basename(config_path).lower()
    if config_name.endswith(".pbtxt") and "coco" in config_name:
        candidates = ("ssd_mobilenet_v2_coco.pb", "frozen_inference_graph.pb")
    elif config_name.endswith(".cfg") and "yolo" in config_name:
        stem = os.path.splitext(os.path.basename(config_path))[0]
        candidates = (stem + ".weights", "yolov4-tiny.weights", "yolov3-tiny.weights", "yolov4.weights", "yolov3.weights")
    else:
        candidates = ("MobileNetSSD_deploy.caffemodel", "mobilenet_iter_73000.caffemodel")
    for name in candidates:
        path = os.path.join(config_dir, name)
        if os.path.exists(path):
            return path
    return ""


def _default_opencv_model():
    return _default_opencv_pair()[0]


def _default_opencv_config():
    return _default_opencv_pair()[1]


RESULT_IP = os.environ.get("HXV2_RESULT_IP", "")
RESULT_PORT = _env_int("HXV2_RESULT_PORT", 9002, 1)
HXV2_DETECT_EVERY = _env_int("HXV2_DETECT_EVERY", 4, 1)
HXV2_DETECT_WIDTH = _env_int("HXV2_DETECT_WIDTH", 320, 160)
FPGA_ROI_MAX_AGE = _env_int("HXV2_FPGA_ROI_MAX_AGE", 8, 1)
HXV2_FAST_DETECT = os.environ.get("HXV2_FAST_DETECT", "0") == "1"
HXV2_DNN_TIMING = os.environ.get("HXV2_DNN_TIMING", "0") == "1"
_DEFAULT_OPENCV_MODEL, _DEFAULT_OPENCV_CONFIG = _default_opencv_pair()
HXV2_OPENCV_MODEL = _env_path("HXV2_OPENCV_MODEL", _env_path("HXV2_DNN_MODEL", "")) or _DEFAULT_OPENCV_MODEL
HXV2_OPENCV_CONFIG = _env_path("HXV2_OPENCV_CONFIG", _env_path("HXV2_DNN_CONFIG", "")) or _matching_opencv_config(HXV2_OPENCV_MODEL) or _DEFAULT_OPENCV_CONFIG
if HXV2_OPENCV_CONFIG and not HXV2_OPENCV_MODEL:
    HXV2_OPENCV_MODEL = _matching_opencv_model(HXV2_OPENCV_CONFIG) or HXV2_OPENCV_MODEL
if "HXV2_DETECT_EVERY" not in os.environ and ("yolo" in os.path.basename(HXV2_OPENCV_MODEL).lower() or HXV2_OPENCV_MODEL.lower().endswith(".onnx")):
    HXV2_DETECT_EVERY = max(HXV2_DETECT_EVERY, 8)
HXV2_LABELS = _env_path("HXV2_LABELS", "")
HXV2_OPENCV_SIZE = _env_int("HXV2_OPENCV_SIZE", 300, 160)
HXV2_OPENCV_CONF = _env_float("HXV2_OPENCV_CONF", 0.35, 0.01)
HXV2_OPENCV_NMS = _env_float("HXV2_OPENCV_NMS", 0.45, 0.01)
HXV2_OPENCV_MIN_AREA = _env_float("HXV2_OPENCV_MIN_AREA", 0.002, 0.0)
HXV2_OPENCV_MAX_AREA = _env_float("HXV2_OPENCV_MAX_AREA", 0.85, 0.01)
HXV2_OPENCV_MAX_OBJECTS = _env_int("HXV2_OPENCV_MAX_OBJECTS", 8, 1)
HXV2_YOLO_LETTERBOX = os.environ.get("HXV2_YOLO_LETTERBOX", "1") != "0"
HXV2_DNN_DEBUG = os.environ.get("HXV2_DNN_DEBUG", "0") == "1"
HXV2_DNN_TOP = _env_int("HXV2_DNN_TOP", 5, 1)
HXV2_THIN_FALLBACK = os.environ.get("HXV2_THIN_FALLBACK", "1") != "0"
HXV2_THIN_MIN_AREA = _env_float("HXV2_THIN_MIN_AREA", 0.0005, 0.0)
HXV2_THIN_MAX_AREA = _env_float("HXV2_THIN_MAX_AREA", 0.08, 0.001)
HXV2_THIN_MIN_ASPECT = _env_float("HXV2_THIN_MIN_ASPECT", 4.0, 1.0)
HXV2_THIN_MAX_OVERLAP = _env_float("HXV2_THIN_MAX_OVERLAP", 0.35, 0.0)
HXV2_CLASSIC_ONLY = os.environ.get("HXV2_CLASSIC_ONLY", "0") == "1"
HXV2_RULE_FALLBACK = os.environ.get("HXV2_RULE_FALLBACK", "0") == "1"
_FACE_CASCADE = None
_AI_NET = None
_AI_MODEL_KEY = None
_AI_LOAD_ERROR = None
_AI_LABELS = None


VOC_LABELS = (
    "background", "aeroplane", "bicycle", "bird", "boat", "bottle", "bus", "car", "cat", "chair",
    "cow", "dining table", "dog", "horse", "motorbike", "person", "potted plant", "sheep", "sofa", "train", "tv monitor",
)

COCO_LABELS = (
    "background", "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck", "boat",
    "traffic light", "fire hydrant", "stop sign", "parking meter", "bench", "bird", "cat", "dog", "horse", "sheep",
    "cow", "elephant", "bear", "zebra", "giraffe", "backpack", "umbrella", "handbag", "tie", "suitcase",
    "frisbee", "skis", "snowboard", "sports ball", "kite", "baseball bat", "baseball glove", "skateboard", "surfboard", "tennis racket",
    "bottle", "wine glass", "cup", "fork", "knife", "spoon", "bowl", "banana", "apple", "sandwich",
    "orange", "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair", "couch", "potted plant",
    "bed", "dining table", "toilet", "tv", "laptop", "mouse", "remote", "keyboard", "cell phone", "microwave",
    "oven", "toaster", "sink", "refrigerator", "book", "clock", "vase", "scissors", "teddy bear", "hair drier", "toothbrush",
)

# TensorFlow COCO SSD returns sparse COCO category ids, not contiguous 0..80 ids.
# Keep missing ids as empty strings so class_id can be used directly.
COCO_TF_LABELS = [""] * 91
COCO_TF_LABELS[0] = "background"
for _cid, _label in {
    1: "person", 2: "bicycle", 3: "car", 4: "motorcycle", 5: "airplane", 6: "bus", 7: "train", 8: "truck", 9: "boat",
    10: "traffic light", 11: "fire hydrant", 13: "stop sign", 14: "parking meter", 15: "bench", 16: "bird",
    17: "cat", 18: "dog", 19: "horse", 20: "sheep", 21: "cow", 22: "elephant", 23: "bear", 24: "zebra", 25: "giraffe",
    27: "backpack", 28: "umbrella", 31: "handbag", 32: "tie", 33: "suitcase", 34: "frisbee", 35: "skis", 36: "snowboard",
    37: "sports ball", 38: "kite", 39: "baseball bat", 40: "baseball glove", 41: "skateboard", 42: "surfboard", 43: "tennis racket",
    44: "bottle", 46: "wine glass", 47: "cup", 48: "fork", 49: "knife", 50: "spoon", 51: "bowl", 52: "banana", 53: "apple",
    54: "sandwich", 55: "orange", 56: "broccoli", 57: "carrot", 58: "hot dog", 59: "pizza", 60: "donut", 61: "cake",
    62: "chair", 63: "couch", 64: "potted plant", 65: "bed", 67: "dining table", 70: "toilet", 72: "tv", 73: "laptop",
    74: "mouse", 75: "remote", 76: "keyboard", 77: "cell phone", 78: "microwave", 79: "oven", 80: "toaster", 81: "sink",
    82: "refrigerator", 84: "book", 85: "clock", 86: "vase", 87: "scissors", 88: "teddy bear", 89: "hair drier", 90: "toothbrush",
}.items():
    COCO_TF_LABELS[_cid] = _label


def _guess_opencv_label_set(model_path, config_path):
    name = (os.path.basename(model_path or "") + " " + os.path.basename(config_path or "")).lower()
    if model_path.lower().endswith(".pb"):
        return list(COCO_TF_LABELS)
    if "yolo" in name or "coco" in name:
        return list(COCO_LABELS)
    return list(VOC_LABELS)


def _is_coco_label_set(labels):
    return labels == list(COCO_LABELS) or labels == list(COCO_TF_LABELS)


def _is_yolo_model(model_path, config_path=""):
    name = (os.path.basename(model_path or "") + " " + os.path.basename(config_path or "")).lower()
    return "yolo" in name or model_path.lower().endswith(".onnx")


def _yolo_label(labels, class_id):
    # COCO YOLO class ids are 0..79, while COCO_LABELS[0] is "background".
    if labels == list(COCO_LABELS) and 0 <= class_id + 1 < len(labels):
        return labels[class_id + 1]
    if 0 <= class_id < len(labels):
        label = labels[class_id]
        if label.lower() != "background":
            return label
    return f"class_{class_id}"


def _opencv_detector_name():
    name = os.path.basename(HXV2_OPENCV_MODEL or "").lower()
    if "yolov8" in name:
        return "YOLOv8n" if "yolov8n" in name else "YOLOv8"
    if "yolo" in name or name.endswith(".onnx"):
        return "YOLO"
    labels = _load_opencv_labels(HXV2_OPENCV_MODEL, HXV2_OPENCV_CONFIG)
    return "COCO" if _is_coco_label_set(labels) else "VOC"


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


def _load_opencv_labels(model_path="", config_path=""):
    global _AI_LABELS
    if _AI_LABELS is not None:
        return _AI_LABELS
    labels = []
    if HXV2_LABELS and os.path.exists(HXV2_LABELS):
        try:
            with open(HXV2_LABELS, "r", encoding="utf-8") as f:
                labels = [line.strip() for line in f if line.strip() and not line.lstrip().startswith("#")]
        except OSError:
            labels = []
    _AI_LABELS = labels if labels else _guess_opencv_label_set(model_path, config_path)
    return _AI_LABELS


def _get_opencv_detector(cv2):
    global _AI_NET, _AI_MODEL_KEY, _AI_LOAD_ERROR
    model_path = HXV2_OPENCV_MODEL
    config_path = HXV2_OPENCV_CONFIG
    labels = _load_opencv_labels(model_path, config_path)
    if HXV2_CLASSIC_ONLY:
        _AI_LOAD_ERROR = "classic OpenCV mode"
        return None, labels, _AI_LOAD_ERROR
    model_key = (model_path, config_path, HXV2_LABELS)
    if not model_path:
        _AI_LOAD_ERROR = "classic OpenCV mode; set HXV2_OPENCV_MODEL for category names"
        return None, labels, _AI_LOAD_ERROR
    if _AI_NET is not None and _AI_MODEL_KEY == model_key:
        return _AI_NET, labels, None
    if not os.path.exists(model_path):
        _AI_LOAD_ERROR = f"OpenCV DNN model not found: {model_path}"
        return None, labels, _AI_LOAD_ERROR
    if config_path and not os.path.exists(config_path):
        _AI_LOAD_ERROR = f"OpenCV DNN config not found: {config_path}"
        return None, labels, _AI_LOAD_ERROR
    try:
        model_ext = os.path.splitext(model_path)[1].lower()
        config_ext = os.path.splitext(config_path)[1].lower() if config_path else ""
        if model_ext == ".caffemodel" and config_ext in (".prototxt", ".txt"):
            net = cv2.dnn.readNetFromCaffe(config_path, model_path)
        elif model_ext == ".pb" and config_ext == ".pbtxt":
            net = cv2.dnn.readNetFromTensorflow(model_path, config_path)
        elif model_ext == ".weights" and config_ext == ".cfg":
            net = cv2.dnn.readNetFromDarknet(config_path, model_path)
        else:
            net = cv2.dnn.readNet(model_path, config_path) if config_path else cv2.dnn.readNet(model_path)
        net.setPreferableBackend(cv2.dnn.DNN_BACKEND_OPENCV)
        net.setPreferableTarget(cv2.dnn.DNN_TARGET_CPU)
    except Exception as exc:
        _AI_LOAD_ERROR = f"OpenCV DNN load failed: {exc}"
        return None, labels, _AI_LOAD_ERROR
    _AI_NET = net
    _AI_MODEL_KEY = model_key
    _AI_LOAD_ERROR = None
    return _AI_NET, labels, None


def _classic_shape_label(w, h, fill, colored):
    aspect = h / max(w, 1)
    if colored:
        return "colored object"
    if aspect >= 1.55:
        return "vertical object"
    if aspect <= 0.58:
        return "wide object"
    if fill > 0.58:
        return "solid object"
    return "opencv object"


def _box_iou_xywh(a, b):
    ax0, ay0, aw, ah = [float(v) for v in (a["x"], a["y"], a["w"], a["h"])]
    bx0, by0, bw, bh = [float(v) for v in (b["x"], b["y"], b["w"], b["h"])]
    ax1, ay1 = ax0 + aw, ay0 + ah
    bx1, by1 = bx0 + bw, by0 + bh
    ix0, iy0 = max(ax0, bx0), max(ay0, by0)
    ix1, iy1 = min(ax1, bx1), min(ay1, by1)
    iw, ih = max(0.0, ix1 - ix0), max(0.0, iy1 - iy0)
    inter = iw * ih
    union = aw * ah + bw * bh - inter
    return inter / union if union > 0 else 0.0


def _merge_detection_lists(primary, supplemental, max_overlap=0.35):
    merged = list(primary)
    for det in supplemental:
        if any(_box_iou_xywh(det, existing) > max_overlap for existing in merged):
            continue
        merged.append(det)
    merged.sort(key=lambda item: (item.get("detector") == "opencv-dnn", item.get("confidence", 0), item.get("area", 0)), reverse=True)
    return merged[:HXV2_OPENCV_MAX_OBJECTS]


def _classify_thin_object(aspect, short_side, fill, color_std, end_imbalance):
    if end_imbalance >= 0.45 or (fill <= 0.75 and color_std >= 55 and short_side >= 10):
        return "tool-like"
    if aspect >= 13.0 or (aspect >= 9.0 and short_side <= 14 and fill <= 0.65):
        return "chopstick-like"
    if 4.0 <= aspect <= 12.0 and short_side >= 5 and (fill >= 0.18 or color_std >= 12):
        return "pen-like"
    return "thin-object"


def _thin_end_imbalance(gray_roi, horizontal):
    h, w = gray_roi.shape[:2]
    if horizontal:
        span = max(2, w // 5)
        a = gray_roi[:, :span]
        b = gray_roi[:, w - span:]
    else:
        span = max(2, h // 5)
        a = gray_roi[:span, :]
        b = gray_roi[h - span:, :]
    return min(1.0, abs(float(a.mean()) - float(b.mean())) / 80.0)


def detect_thin_opencv_objects_bgr(frame_bgr, existing=None):
    import cv2
    import numpy as np

    existing = existing or []
    h_img, w_img = frame_bgr.shape[:2]
    frame_area = max(w_img * h_img, 1)
    min_area = frame_area * HXV2_THIN_MIN_AREA
    max_area = frame_area * HXV2_THIN_MAX_AREA
    gray = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2GRAY)
    blur = cv2.GaussianBlur(gray, (5, 5), 0)
    bg = cv2.GaussianBlur(gray, (31, 31), 0)
    contrast = cv2.absdiff(blur, bg)
    edges = cv2.Canny(blur, 35, 110)
    _, contrast_mask = cv2.threshold(contrast, 12, 255, cv2.THRESH_BINARY)
    mask = cv2.bitwise_or(cv2.dilate(edges, np.ones((3, 3), np.uint8), iterations=1), contrast_mask)
    mask[:24, :] = 0
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, np.ones((9, 3), np.uint8), iterations=1)
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8), iterations=1)
    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

    detections = []
    for contour in contours:
        area = float(cv2.contourArea(contour))
        if area < min_area or area > max_area:
            continue
        rect = cv2.minAreaRect(contour)
        (cx, cy), (rw, rh), _angle = rect
        long_side = max(rw, rh)
        short_side = max(1.0, min(rw, rh))
        aspect = long_side / short_side
        if aspect < HXV2_THIN_MIN_ASPECT:
            continue
        x, y, w, h = cv2.boundingRect(contour)
        box_area = max(w * h, 1)
        if x <= 2 or y <= 2 or x + w >= w_img - 3 or y + h >= h_img - 3:
            continue
        fill = min(1.0, area / box_area)
        if fill < 0.05:
            continue
        roi = frame_bgr[y:y + h, x:x + w]
        gray_roi = gray[y:y + h, x:x + w]
        color_std = float(roi.reshape(-1, 3).std()) if roi.size else 0.0
        horizontal = w >= h
        end_imbalance = _thin_end_imbalance(gray_roi, horizontal) if gray_roi.size else 0.0
        label = _classify_thin_object(aspect, short_side, fill, color_std, end_imbalance)
        det = {
            "x": int(x), "y": int(y), "w": int(w), "h": int(h),
            "area": int(area), "label": label,
            "confidence": int(max(1, min(99, round((0.35 + min(aspect / 12.0, 1.0) * 0.30 + fill * 0.22 + min(color_std / 80.0, 1.0) * 0.13) * 100)))),
            "detector": "opencv-thin", "aspect": round(float(aspect), 2),
            "thin_fill": round(float(fill), 2), "thin_color_std": round(float(color_std), 1),
        }
        if any(_box_iou_xywh(det, other) > HXV2_THIN_MAX_OVERLAP for other in existing):
            continue
        detections.append(det)

    detections.sort(key=lambda item: (item["confidence"], item["area"]), reverse=True)
    return detections[:HXV2_OPENCV_MAX_OBJECTS]


def detect_classic_opencv_objects_bgr(frame_bgr):
    import cv2
    import numpy as np

    h_img, w_img = frame_bgr.shape[:2]
    frame_area = max(w_img * h_img, 1)
    gray = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2GRAY)
    hsv = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2HSV)
    blur = cv2.GaussianBlur(gray, (5, 5), 0)
    bg = cv2.GaussianBlur(gray, (45, 45), 0)
    contrast = cv2.absdiff(blur, bg)
    edges = cv2.Canny(blur, 35, 110)
    _, contrast_mask = cv2.threshold(contrast, 13, 255, cv2.THRESH_BINARY)
    edge_mask = cv2.dilate(edges, np.ones((3, 3), np.uint8), iterations=1)
    color_mask = cv2.inRange(hsv[:, :, 1], 55, 255)
    color_mask = cv2.bitwise_and(color_mask, cv2.inRange(hsv[:, :, 2], 40, 255))
    fg_mask = cv2.bitwise_or(cv2.bitwise_or(contrast_mask, edge_mask), color_mask)
    fg_mask[:24, :] = 0
    fg_mask = cv2.morphologyEx(fg_mask, cv2.MORPH_CLOSE, np.ones((7, 7), np.uint8), iterations=1)
    fg_mask = cv2.morphologyEx(fg_mask, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8), iterations=1)
    contours, _ = cv2.findContours(fg_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

    boxes = []
    scores = []
    raw = []
    for contour in contours:
        area = int(cv2.contourArea(contour))
        if area < max(280, frame_area * 0.0012):
            continue
        x, y, w, h = cv2.boundingRect(contour)
        box_area = max(w * h, 1)
        if box_area > frame_area * 0.62 or box_area < frame_area * 0.0015:
            continue
        if x <= 3 or y <= 3 or x + w >= w_img - 3 or y + h >= h_img - 3:
            if box_area > frame_area * 0.12:
                continue
        roi_color = color_mask[y:y + h, x:x + w]
        color_ratio = float(cv2.countNonZero(roi_color)) / box_area
        fill = min(1.0, area / box_area)
        center_dist = (((x + w / 2.0) - w_img / 2.0) ** 2 + ((y + h / 2.0) - h_img / 2.0) ** 2) ** 0.5
        center_weight = max(0.0, 1.0 - center_dist / max(w_img, h_img))
        score = min(0.99, 0.22 + fill * 0.35 + color_ratio * 0.25 + min(box_area / (frame_area * 0.16), 1.0) * 0.22 + center_weight * 0.12)
        label = _classic_shape_label(w, h, fill, color_ratio > 0.28)
        boxes.append([x, y, w, h])
        scores.append(score)
        raw.append((label, area))

    if not boxes:
        return []
    keep = cv2.dnn.NMSBoxes(boxes, scores, 0.20, HXV2_OPENCV_NMS)
    if len(keep) == 0:
        return []
    detections = []
    for i in np.array(keep).reshape(-1)[:10]:
        x, y, w, h = boxes[int(i)]
        label, area = raw[int(i)]
        detections.append({
            "x": int(x), "y": int(y), "w": int(w), "h": int(h),
            "area": int(area), "label": label,
            "confidence": int(max(1, min(99, round(scores[int(i)] * 100)))),
            "detector": "opencv-classic",
        })
    detections.sort(key=lambda item: (item["confidence"], item["area"]), reverse=True)
    return detections


def _parse_yolo_output(output, labels, w_img, h_img, cv2, np, yolo_scale=1.0, yolo_pad_x=0.0, yolo_pad_y=0.0):
    boxes = []
    scores = []
    class_ids = []
    top_raw = []
    rejected = {"conf": 0, "class": 0, "area": 0, "edge": 0}
    frame_area = max(w_img * h_img, 1)
    min_box_area = frame_area * HXV2_OPENCV_MIN_AREA
    max_box_area = frame_area * HXV2_OPENCV_MAX_AREA
    outputs = output if isinstance(output, (list, tuple)) else [output]

    for out in outputs:
        arr = np.asarray(out)
        if arr.size == 0:
            continue
        arr = np.squeeze(arr)
        if arr.ndim == 2 and arr.shape[0] in (84, 85) and arr.shape[1] != arr.shape[0]:
            rows = arr.T  # YOLOv8 ONNX: [84, 8400] -> [8400, 84]
            has_objectness = arr.shape[0] == 85
        else:
            rows = arr.reshape(-1, arr.shape[-1]) if arr.ndim >= 2 else arr.reshape(1, -1)
            has_objectness = rows.shape[-1] >= 85
        for row in rows:
            if row.size < 6:
                continue
            if has_objectness:
                obj_conf = float(row[4])
                class_scores = row[5:]
            else:
                obj_conf = 1.0
                class_scores = row[4:]
            if class_scores.size == 0:
                continue
            class_id = int(np.argmax(class_scores))
            conf = obj_conf * float(class_scores[class_id])
            label = _yolo_label(labels, class_id)
            top_raw.append((conf, label))
            if conf < HXV2_OPENCV_CONF:
                rejected["conf"] += 1
                continue
            if len(boxes) >= 600:
                break
            if label.lower() == "background":
                rejected["class"] += 1
                continue
            cx, cy, bw, bh = [float(v) for v in row[:4]]
            if max(abs(cx), abs(cy), abs(bw), abs(bh)) <= 2.0:
                cx *= w_img
                cy *= h_img
                bw *= w_img
                bh *= h_img
            elif HXV2_YOLO_LETTERBOX:
                cx = (cx - yolo_pad_x) / max(yolo_scale, 1e-6)
                cy = (cy - yolo_pad_y) / max(yolo_scale, 1e-6)
                bw = bw / max(yolo_scale, 1e-6)
                bh = bh / max(yolo_scale, 1e-6)
            x0 = int(cx - bw / 2.0)
            y0 = int(cy - bh / 2.0)
            x1 = int(cx + bw / 2.0)
            y1 = int(cy + bh / 2.0)
            x0 = max(0, min(x0, w_img - 1))
            y0 = max(0, min(y0, h_img - 1))
            x1 = max(x0, min(x1, w_img - 1))
            y1 = max(y0, min(y1, h_img - 1))
            w = x1 - x0 + 1
            h = y1 - y0 + 1
            box_area = w * h
            if box_area < min_box_area or box_area > max_box_area:
                rejected["area"] += 1
                continue
            if (x0 <= 2 or y0 <= 2 or x1 >= w_img - 3 or y1 >= h_img - 3) and box_area > frame_area * 0.45:
                rejected["edge"] += 1
                continue
            boxes.append([x0, y0, w, h])
            scores.append(conf)
            class_ids.append(class_id)

    debug_note = None
    if HXV2_DNN_DEBUG:
        top_raw.sort(key=lambda item: item[0], reverse=True)
        top_text = ", ".join(f"{label}:{conf * 100:.1f}%" for conf, label in top_raw[:HXV2_DNN_TOP])
        debug_note = f"YOLO raw {top_text or 'none'} reject={rejected}"
    if not boxes:
        return [], debug_note
    if len(scores) > 300:
        order = np.argsort(scores)[-300:]
        boxes = [boxes[int(i)] for i in order]
        scores = [scores[int(i)] for i in order]
        class_ids = [class_ids[int(i)] for i in order]
    keep = cv2.dnn.NMSBoxes(boxes, scores, HXV2_OPENCV_CONF, HXV2_OPENCV_NMS)
    if len(keep) == 0:
        return [], debug_note or "YOLO DNN: all boxes removed by NMS"
    detections = []
    for i in np.array(keep).reshape(-1)[:HXV2_OPENCV_MAX_OBJECTS]:
        x, y, w, h = boxes[int(i)]
        class_id = class_ids[int(i)]
        detections.append({
            "x": int(x), "y": int(y), "w": int(w), "h": int(h),
            "area": int(w * h), "label": _yolo_label(labels, class_id),
            "confidence": int(max(1, min(99, round(scores[int(i)] * 100)))),
            "detector": "opencv-dnn", "class_id": int(class_id),
        })
    detections.sort(key=lambda item: (item["confidence"], item["area"]), reverse=True)
    return detections, None


def detect_opencv_dnn_objects_bgr(frame_bgr):
    import cv2
    import numpy as np

    net, labels, err = _get_opencv_detector(cv2)
    if net is None:
        return [], err

    h_img, w_img = frame_bgr.shape[:2]
    model_ext = os.path.splitext(HXV2_OPENCV_MODEL)[1].lower()
    yolo_model = _is_yolo_model(HXV2_OPENCV_MODEL, HXV2_OPENCV_CONFIG)
    inp = int(HXV2_OPENCV_SIZE)
    yolo_scale = 1.0
    yolo_pad_x = 0.0
    yolo_pad_y = 0.0
    if yolo_model:
        # YOLOv8n ONNX is exported for 640x640 by default.  Letterbox keeps the
        # camera aspect ratio, so decoded boxes line up with the original frame.
        inp = int(os.environ.get("HXV2_OPENCV_SIZE", "640"))
        inp = max(320, ((inp + 31) // 32) * 32)
        if HXV2_YOLO_LETTERBOX:
            yolo_scale = min(inp / float(w_img), inp / float(h_img))
            new_w = max(1, int(round(w_img * yolo_scale)))
            new_h = max(1, int(round(h_img * yolo_scale)))
            yolo_pad_x = (inp - new_w) / 2.0
            yolo_pad_y = (inp - new_h) / 2.0
            resized = cv2.resize(frame_bgr, (new_w, new_h), interpolation=cv2.INTER_LINEAR)
            canvas = np.full((inp, inp, 3), 114, dtype=np.uint8)
            px = int(round(yolo_pad_x))
            py = int(round(yolo_pad_y))
            canvas[py:py + new_h, px:px + new_w] = resized
            blob = cv2.dnn.blobFromImage(canvas, 1.0 / 255.0, (inp, inp), (0, 0, 0), swapRB=True, crop=False)
        else:
            blob = cv2.dnn.blobFromImage(frame_bgr, 1.0 / 255.0, (inp, inp), (0, 0, 0), swapRB=True, crop=False)
    elif model_ext == ".pb":
        # TensorFlow COCO SSD models were trained on RGB 0..255 input.  Caffe
        # MobileNetSSD uses the 0.007843 / 127.5 normalization below.
        blob = cv2.dnn.blobFromImage(frame_bgr, 1.0, (inp, inp), (0, 0, 0), swapRB=True, crop=False)
    else:
        blob = cv2.dnn.blobFromImage(frame_bgr, 0.007843, (inp, inp), 127.5, swapRB=False, crop=False)
    try:
        t0 = time.time()
        net.setInput(blob)
        if yolo_model:
            output_names = net.getUnconnectedOutLayersNames()
            output = net.forward(output_names) if output_names else net.forward()
        else:
            output = net.forward()
        infer_ms = (time.time() - t0) * 1000.0
    except Exception as exc:
        return [], f"OpenCV DNN forward failed: {exc}"

    if yolo_model:
        detections, note = _parse_yolo_output(output, labels, w_img, h_img, cv2, np, yolo_scale, yolo_pad_x, yolo_pad_y)
        if HXV2_DNN_TIMING:
            timing_note = f"{_opencv_detector_name()} infer={infer_ms:.0f}ms size={inp}"
            note = f"{timing_note}; {note}" if note else timing_note
        return detections, note

    arr = np.asarray(output)
    if arr.size == 0 or arr.shape[-1] < 7:
        return [], f"unsupported OpenCV DNN output shape: {arr.shape}"
    rows = arr.reshape(-1, arr.shape[-1])
    boxes = []
    scores = []
    class_ids = []
    top_raw = []
    rejected = {"conf": 0, "class": 0, "area": 0, "edge": 0}
    frame_area = max(w_img * h_img, 1)
    min_box_area = frame_area * HXV2_OPENCV_MIN_AREA
    max_box_area = frame_area * HXV2_OPENCV_MAX_AREA
    for row in rows:
        conf = float(row[2])
        class_id = int(row[1])
        label = labels[class_id] if 0 <= class_id < len(labels) else f"class_{class_id}"
        if class_id > 0 and label.lower() != "background":
            top_raw.append((conf, label))
        if conf < HXV2_OPENCV_CONF:
            rejected["conf"] += 1
            continue
        if class_id <= 0:
            rejected["class"] += 1
            continue
        if label.lower() == "background":
            rejected["class"] += 1
            continue
        x0 = int(float(row[3]) * w_img)
        y0 = int(float(row[4]) * h_img)
        x1 = int(float(row[5]) * w_img)
        y1 = int(float(row[6]) * h_img)
        x0 = max(0, min(x0, w_img - 1))
        y0 = max(0, min(y0, h_img - 1))
        x1 = max(x0, min(x1, w_img - 1))
        y1 = max(y0, min(y1, h_img - 1))
        w = x1 - x0 + 1
        h = y1 - y0 + 1
        box_area = w * h
        if box_area < min_box_area or box_area > max_box_area:
            rejected["area"] += 1
            continue
        if (x0 <= 2 or y0 <= 2 or x1 >= w_img - 3 or y1 >= h_img - 3) and box_area > frame_area * 0.45:
            rejected["edge"] += 1
            continue
        boxes.append([x0, y0, w, h])
        scores.append(conf)
        class_ids.append(class_id)

    debug_note = None
    if HXV2_DNN_DEBUG:
        top_raw.sort(key=lambda item: item[0], reverse=True)
        top_text = ", ".join(f"{label}:{conf * 100:.1f}%" for conf, label in top_raw[:HXV2_DNN_TOP])
        debug_note = f"DNN raw {top_text or 'none'} reject={rejected}"
    if not boxes:
        return [], debug_note
    keep = cv2.dnn.NMSBoxes(boxes, scores, HXV2_OPENCV_CONF, HXV2_OPENCV_NMS)
    if len(keep) == 0:
        return [], debug_note or "OpenCV DNN: all boxes removed by NMS"
    detections = []
    for i in np.array(keep).reshape(-1)[:HXV2_OPENCV_MAX_OBJECTS]:
        x, y, w, h = boxes[int(i)]
        class_id = class_ids[int(i)]
        label = labels[class_id] if class_id < len(labels) else f"class_{class_id}"
        detections.append({
            "x": int(x), "y": int(y), "w": int(w), "h": int(h),
            "area": int(w * h), "label": label,
            "confidence": int(max(1, min(99, round(scores[int(i)] * 100)))),
            "detector": "opencv-dnn", "class_id": int(class_id),
        })
    detections.sort(key=lambda item: (item["confidence"], item["area"]), reverse=True)
    return detections, None


def detect_opencv_objects_bgr(frame_bgr):
    detections, note = detect_opencv_dnn_objects_bgr(frame_bgr)
    if HXV2_THIN_FALLBACK:
        thin = detect_thin_opencv_objects_bgr(frame_bgr, detections)
        if thin:
            merged = _merge_detection_lists(detections, thin, HXV2_THIN_MAX_OVERLAP)
            return merged, None
    if detections:
        return detections, None
    if _AI_NET is not None and not HXV2_RULE_FALLBACK:
        labels = _load_opencv_labels(HXV2_OPENCV_MODEL, HXV2_OPENCV_CONFIG)
        model_name = "COCO" if _is_coco_label_set(labels) else "VOC"
        return [], note or f"OpenCV DNN: no {model_name} object"
    classic = detect_classic_opencv_objects_bgr(frame_bgr)
    if HXV2_THIN_FALLBACK:
        classic = _merge_detection_lists(classic, detect_thin_opencv_objects_bgr(frame_bgr, classic), HXV2_THIN_MAX_OVERLAP)
    if classic:
        return classic, note or "classic OpenCV mode: shape/color/edge/thin detection"
    return [], note


def draw_fpga_rois_bgr(frame_bgr, roi_meta):
    import cv2

    if not roi_meta or not roi_meta.get("valid") or roi_meta.get("roi_count", 0) <= 0:
        return None
    h_img, w_img = frame_bgr.shape[:2]
    grid_w = max(1, int(roi_meta.get("grid_w", 80)))
    grid_h = max(1, int(roi_meta.get("grid_h", 60)))
    x0 = int(roi_meta["xmin"] * w_img / grid_w)
    y0 = int(roi_meta["ymin"] * h_img / grid_h)
    x1 = int((roi_meta["xmax"] + 1) * w_img / grid_w) - 1
    y1 = int((roi_meta["ymax"] + 1) * h_img / grid_h) - 1
    x0 = max(0, min(x0, w_img - 1))
    y0 = max(0, min(y0, h_img - 1))
    x1 = max(x0, min(x1, w_img - 1))
    y1 = max(y0, min(y1, h_img - 1))
    color = (0, 255, 255)
    cv2.rectangle(frame_bgr, (x0, y0), (x1, y1), color, 2)
    cv2.drawMarker(frame_bgr, ((x0 + x1) // 2, (y0 + y1) // 2), (0, 0, 255), cv2.MARKER_CROSS, 16, 2)
    label = f"FPGA ROI area={roi_meta.get('area', 0)} score={roi_meta.get('score', 0)}"
    ty = y0 - 6 if y0 > 18 else y1 + 18
    cv2.putText(frame_bgr, label, (x0, min(max(ty, 18), h_img - 8)), cv2.FONT_HERSHEY_SIMPLEX, 0.52, color, 2)
    return {
        "x": x0,
        "y": y0,
        "w": x1 - x0 + 1,
        "h": y1 - y0 + 1,
        "area": int(roi_meta.get("area", 0)),
        "label": "FPGA motion ROI",
        "confidence": int(roi_meta.get("score", 0)),
        "detector": "fpga-roi",
    }


def draw_opencv_detections_bgr(frame_bgr, detections):
    import cv2

    palette = ((0, 255, 0), (255, 0, 0), (0, 165, 255), (255, 0, 255), (0, 255, 255), (255, 255, 0))
    for idx, det in enumerate(detections):
        x0 = max(0, int(det["x"]))
        y0 = max(0, int(det["y"]))
        x1 = min(frame_bgr.shape[1] - 1, x0 + int(det["w"]) - 1)
        y1 = min(frame_bgr.shape[0] - 1, y0 + int(det["h"]) - 1)
        color = palette[idx % len(palette)]
        cv2.rectangle(frame_bgr, (x0, y0), (x1, y1), color, 2)
        detector = det.get("detector")
        tag = "DNN" if detector == "opencv-dnn" else ("THIN" if detector == "opencv-thin" else "CV")
        text = f"{tag} {det['label']} {det['confidence']}%"
        ty = y0 - 6 if y0 > 18 else y0 + 18
        cv2.putText(frame_bgr, text, (x0, ty), cv2.FONT_HERSHEY_SIMPLEX, 0.55, color, 2)


def detect_primary_object_bgr(frame_bgr):
    import cv2
    import numpy as np

    global _FACE_CASCADE
    h_img, w_img = frame_bgr.shape[:2]
    gray = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2GRAY)
    hsv = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2HSV)
    blur = cv2.GaussianBlur(gray, (5, 5), 0)
    bg = cv2.GaussianBlur(gray, (45, 45), 0)
    contrast = cv2.absdiff(blur, bg)
    edges = cv2.Canny(blur, 45, 120)
    cx_img = w_img / 2.0
    cy_img = h_img / 2.0
    center_roi = (int(w_img * 0.30), int(h_img * 0.12), int(w_img * 0.70), int(h_img * 0.82))
    rx0, ry0, rx1, ry1 = center_roi
    frame_area = max(w_img * h_img, 1)
    candidates = []

    def add_candidate(x, y, w, h, area, label, detector, base_conf, bias=0.0, fill=None, thin_ok=False):
        x = max(0, min(int(x), w_img - 1))
        y = max(0, min(int(y), h_img - 1))
        w = max(1, min(int(w), w_img - x))
        h = max(1, min(int(h), h_img - y))
        area = int(max(area, 1))
        box_area = max(w * h, 1)
        if thin_ok:
            if max(w, h) < 24 or min(w, h) < 2 or area < 12:
                return
        elif w < 10 or h < 10 or area < 120:
            return
        if box_area > frame_area * 0.62:
            return
        cx = x + w / 2.0
        cy = y + h / 2.0
        center_dist = ((cx - cx_img) ** 2 + (cy - cy_img) ** 2) ** 0.5
        center_weight = max(0.0, 1.0 - center_dist / (max(w_img, h_img) * 0.62))
        ix0 = max(rx0, x)
        iy0 = max(ry0, y)
        ix1 = min(rx1, x + w - 1)
        iy1 = min(ry1, y + h - 1)
        roi_overlap = max(0, ix1 - ix0 + 1) * max(0, iy1 - iy0 + 1) / box_area
        center_inside = rx0 <= cx <= rx1 and ry0 <= cy <= ry1
        near_center = center_dist < max(w_img, h_img) * 0.20
        if not center_inside and roi_overlap < 0.45:
            return
        if box_area > frame_area * 0.22:
            return
        edge_penalty = 0.18 if x <= 8 or y <= 8 or x + w >= w_img - 8 or y + h >= h_img - 8 else 1.0
        fill = area / box_area if fill is None else fill
        size_score = min(box_area / (frame_area * 0.16), 1.0)
        center_bonus = 3.2 if near_center else 0.0
        score = bias + center_weight * 4.6 + roi_overlap * 3.4 + min(fill, 0.85) * 0.55 + size_score * 0.25 + center_bonus
        if center_inside:
            score += 1.8
        if detector in ("foreground", "color") and roi_overlap < 0.45:
            score *= 0.45
        if detector == "foreground" and box_area > frame_area * 0.18:
            score *= 0.55
        score *= edge_penalty
        candidates.append({
            "x": x, "y": y, "w": w, "h": h,
            "area": area, "label": label, "confidence": int(max(1, min(99, base_conf + center_weight * 18 + roi_overlap * 12))),
            "score": score, "detector": detector, "fill": fill,
            "center_inside": center_inside, "roi_overlap": roi_overlap,
        })

    # 1) Semantic naming is intentionally disabled here.
    # In cluttered scenes, cascade/skin rules often mislabel bottles, clothes, and text.
    # This demo is now a practical center-target localization/alignment system.
    kernel5 = np.ones((5, 5), np.uint8)
    b, g, r = cv2.split(frame_bgr)
    skin_mask = (((hsv[:, :, 0] < 25) | (hsv[:, :, 0] > 165)) &
                 (hsv[:, :, 1] > 22) & (hsv[:, :, 1] < 195) &
                 (hsv[:, :, 2] > 50) &
                 (r.astype(np.int16) > b.astype(np.int16) + 8) &
                 (r.astype(np.int16) >= g.astype(np.int16) - 12)).astype(np.uint8) * 255
    skin_mask[:30, :] = 0
    skin_mask = cv2.morphologyEx(skin_mask, cv2.MORPH_CLOSE, kernel5, iterations=2)
    skin_mask = cv2.morphologyEx(skin_mask, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8), iterations=1)
    skin_contours, _ = cv2.findContours(skin_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    for contour in skin_contours:
        area = int(cv2.contourArea(contour))
        if area < 1500:
            continue
        x, y, w, h = cv2.boundingRect(contour)
        add_candidate(x, y, w, h, area, "skin-tone target", "skin", 58, bias=2.8)

    # 2) Tool/pen detector: center ROI, line-like colored/dark/edge regions.
    roi_hsv = hsv[ry0:ry1 + 1, rx0:rx1 + 1]
    roi_gray = gray[ry0:ry1 + 1, rx0:rx1 + 1]
    roi_edges = cv2.Canny(roi_gray, 25, 85)
    red_mask = (((roi_hsv[:, :, 0] < 14) | (roi_hsv[:, :, 0] > 165)) &
                (roi_hsv[:, :, 1] > 35) & (roi_hsv[:, :, 2] > 35)).astype(np.uint8) * 255
    dark_mask = ((roi_gray < 95) & (roi_hsv[:, :, 1] > 16)).astype(np.uint8) * 255
    color_line_mask = cv2.bitwise_or(red_mask, dark_mask)
    line_mask = cv2.bitwise_or(roi_edges, color_line_mask)
    line_mask = cv2.morphologyEx(line_mask, cv2.MORPH_CLOSE, np.ones((11, 3), np.uint8), iterations=1)
    line_mask = cv2.bitwise_or(line_mask, cv2.morphologyEx(line_mask, cv2.MORPH_CLOSE, np.ones((3, 11), np.uint8), iterations=1))
    line_mask = cv2.dilate(line_mask, np.ones((3, 3), np.uint8), iterations=1)
    roi_sat = roi_hsv[:, :, 1]
    roi_val = roi_hsv[:, :, 2]
    pen_color_mask = (((roi_gray < 110) & (roi_val < 160)) |
                      ((roi_sat > 45) & (roi_val > 35))).astype(np.uint8) * 255
    pen_color_mask = cv2.bitwise_and(pen_color_mask, cv2.dilate(roi_edges, np.ones((3, 3), np.uint8), iterations=1))
    line_mask = cv2.bitwise_or(line_mask, pen_color_mask)
    line_contours, _ = cv2.findContours(line_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    for contour in line_contours:
        lx, ly, lw, lh = cv2.boundingRect(contour)
        area = int(cv2.contourArea(contour))
        length = max(lw, lh)
        thickness = max(1, min(lw, lh))
        rect = cv2.minAreaRect(contour)
        rw, rh = rect[1]
        rlen = max(rw, rh)
        rthick = max(1.0, min(rw, rh))
        slender = max(length / max(thickness, 1), rlen / rthick)
        if length < 24 or area < 18:
            continue
        if thickness > 72 and rthick > 26:
            continue
        if slender < 1.75:
            continue
        add_candidate(rx0 + lx, ry0 + ly, lw, lh, max(area, lw * lh // 4), "slender target", "tool_line", 82, bias=11.0, thin_ok=True)

    # 3) Colored object detector.
    sat_mask = cv2.inRange(hsv[:, :, 1], 70, 255)
    sat_mask = cv2.morphologyEx(sat_mask, cv2.MORPH_CLOSE, kernel5, iterations=1)
    color_contours, _ = cv2.findContours(sat_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    for contour in color_contours:
        area = int(cv2.contourArea(contour))
        if area < 900:
            continue
        x, y, w, h = cv2.boundingRect(contour)
        if not (rx0 <= x + w / 2.0 <= rx1 and ry0 <= y + h / 2.0 <= ry1):
            continue
        add_candidate(x, y, w, h, area, "color target", "color", 58, bias=3.2)

    # 4) Generic foreground detector, deliberately lower priority.
    _, contrast_mask = cv2.threshold(contrast, 12, 255, cv2.THRESH_BINARY)
    edge_mask = cv2.dilate(edges, np.ones((3, 3), np.uint8), iterations=1)
    fg_mask = cv2.bitwise_or(contrast_mask, edge_mask)
    fg_mask[:28, :] = 0
    fg_mask = cv2.morphologyEx(fg_mask, cv2.MORPH_CLOSE, kernel5, iterations=1)
    fg_contours, _ = cv2.findContours(fg_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    for contour in fg_contours:
        area = int(cv2.contourArea(contour))
        if area < 1400:
            continue
        x, y, w, h = cv2.boundingRect(contour)
        box_area = w * h
        if box_area > frame_area * 0.42:
            continue
        label = "vertical target" if h / max(w, 1) >= 1.45 else "wide target" if h / max(w, 1) <= 0.65 else "locked target"
        add_candidate(x, y, w, h, area, label, "foreground", 50, bias=2.0)

    if not candidates:
        return None
    center_candidates = [item for item in candidates if item.get("center_inside") or item.get("roi_overlap", 0.0) >= 0.55]
    center_slender = [item for item in center_candidates if item.get("label") == "slender target"]
    pool = center_slender if center_slender else center_candidates if center_candidates else candidates
    best = max(pool, key=lambda item: item["score"])
    for key in ("score", "center_inside", "roi_overlap", "fill"):
        best.pop(key, None)
    return best


def _track_iou(a, b):
    ax0, ay0 = a["x"], a["y"]
    ax1, ay1 = ax0 + a["w"] - 1, ay0 + a["h"] - 1
    bx0, by0 = b["x"], b["y"]
    bx1, by1 = bx0 + b["w"] - 1, by0 + b["h"] - 1
    ix0, iy0 = max(ax0, bx0), max(ay0, by0)
    ix1, iy1 = min(ax1, bx1), min(ay1, by1)
    inter = max(0, ix1 - ix0 + 1) * max(0, iy1 - iy0 + 1)
    area_a = max(1, a["w"] * a["h"])
    area_b = max(1, b["w"] * b["h"])
    return inter / max(area_a + area_b - inter, 1)


def update_stable_track(state, candidate):
    if candidate is None:
        track = state.get("track")
        if track and state.get("lost", 0) < 6:
            state["lost"] = state.get("lost", 0) + 1
            out = track.copy()
            out["confidence"] = max(1, int(out.get("confidence", 1) * 0.92))
            return out
        state.clear()
        return None

    track = state.get("track")
    if track is None:
        candidate = candidate.copy()
        candidate["stable"] = 1
        state["track"] = candidate
        state["lost"] = 0
        return candidate

    old_cx = track["x"] + track["w"] / 2.0
    old_cy = track["y"] + track["h"] / 2.0
    new_cx = candidate["x"] + candidate["w"] / 2.0
    new_cy = candidate["y"] + candidate["h"] / 2.0
    center_dist = ((old_cx - new_cx) ** 2 + (old_cy - new_cy) ** 2) ** 0.5
    same_target = _track_iou(track, candidate) > 0.10 or center_dist < max(track["w"], track["h"], candidate["w"], candidate["h"]) * 0.55
    if not same_target:
        pending = state.get("pending")
        if pending and _track_iou(pending, candidate) > 0.12:
            candidate = candidate.copy()
            candidate["stable"] = 1
            state["track"] = candidate
            state["pending"] = None
            state["lost"] = 0
            return candidate
        state["pending"] = candidate.copy()
        out = track.copy()
        out["stable"] = track.get("stable", 1)
        return out

    alpha = 0.65
    merged = candidate.copy()
    for key in ("x", "y", "w", "h"):
        merged[key] = int(track[key] * alpha + candidate[key] * (1.0 - alpha))
    merged["area"] = int(track.get("area", candidate["area"]) * alpha + candidate["area"] * (1.0 - alpha))
    merged["confidence"] = max(track.get("confidence", 0), candidate.get("confidence", 0))
    merged["stable"] = min(track.get("stable", 1) + 1, 99)
    state["track"] = merged
    state["pending"] = None
    state["lost"] = 0
    return merged


def send_result_udp(sock, frame_no, track, align_info, net_state, rows, loss_rate):
    if not sock or not RESULT_IP:
        return
    if track:
        box = [track["x"], track["y"], track["x"] + track["w"] - 1, track["y"] + track["h"] - 1]
        label = track.get("label", "object")
        confidence = int(track.get("confidence", 0))
        detector = track.get("detector", "pc")
    else:
        box = None
        label = "none"
        confidence = 0
        detector = "none"
    payload = {
        "frame": int(frame_no),
        "label": label,
        "confidence": confidence,
        "detector": detector,
        "box": box,
        "align": align_info or {},
        "network": net_state,
        "rows": int(rows),
        "loss": round(float(loss_rate), 2),
    }
    try:
        sock.sendto(json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8"), (RESULT_IP, RESULT_PORT))
    except OSError:
        pass


def make_opencv_process_view(frame_bgr, track=None):
    import cv2
    import numpy as np

    gray = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2GRAY)
    blur = cv2.GaussianBlur(gray, (5, 5), 0)
    bg = cv2.GaussianBlur(gray, (41, 41), 0)
    contrast = cv2.absdiff(blur, bg)
    edges = cv2.Canny(blur, 45, 120)
    _, contrast_mask = cv2.threshold(contrast, 16, 255, cv2.THRESH_BINARY)
    view = cv2.cvtColor(edges, cv2.COLOR_GRAY2BGR)
    view[:, :, 1] = np.maximum(view[:, :, 1], contrast_mask)
    if track:
        x0 = max(0, int(track["x"]))
        y0 = max(0, int(track["y"]))
        x1 = min(frame_bgr.shape[1] - 1, x0 + int(track["w"]) - 1)
        y1 = min(frame_bgr.shape[0] - 1, y0 + int(track["h"]) - 1)
        cv2.rectangle(view, (x0, y0), (x1, y1), (0, 255, 255), 2)
    cv2.putText(view, "OpenCV edge/mask", (8, 22), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 255), 2)
    return view


def target_alignment_status(frame_bgr, track):
    h, w = frame_bgr.shape[:2]
    cx0 = w // 2
    cy0 = h // 2
    guide_w = max(48, int(w * 0.16))
    guide_h = max(48, int(h * 0.16))
    guide = (cx0 - guide_w // 2, cy0 - guide_h // 2, cx0 + guide_w // 2, cy0 + guide_h // 2)
    if not track:
        return guide, {
            "valid": False,
            "dx": 0,
            "dy": 0,
            "size_pct": 0.0,
            "centered": False,
            "text": "ALIGN: no target",
        }

    tx = int(track["x"] + track["w"] / 2)
    ty = int(track["y"] + track["h"] / 2)
    dx = tx - cx0
    dy = ty - cy0
    size_pct = 100.0 * float(track["w"] * track["h"]) / max(w * h, 1)
    centered = abs(dx) <= guide_w // 2 and abs(dy) <= guide_h // 2
    direction = []
    if dx < -guide_w // 2:
        direction.append("move right")
    elif dx > guide_w // 2:
        direction.append("move left")
    if dy < -guide_h // 2:
        direction.append("move down")
    elif dy > guide_h // 2:
        direction.append("move up")
    hint = "OK centered" if centered else ", ".join(direction) if direction else "near center"
    return guide, {
        "valid": True,
        "dx": dx,
        "dy": dy,
        "size_pct": size_pct,
        "centered": centered,
        "text": f"ALIGN: {hint}  dx={dx:+d} dy={dy:+d} size={size_pct:.1f}%",
    }


def parse_fpga_roi_packet(data):
    if len(data) != FPGA_ROI_PACKET_LEN:
        return None
    if data[0] != MAGIC0 or data[1] != MAGIC1 or data[2] != CMD_CAM_ROI:
        return None
    if data[3] != 0x01 or data[23] != 0x0D:
        return None
    checksum = 0
    for b in data[:22]:
        checksum ^= b
    if checksum != data[22]:
        return None
    grid_w = int(data[8])
    grid_h = int(data[9])
    if grid_w <= 0 or grid_h <= 0:
        return None
    xmin = int(data[10])
    ymin = int(data[11])
    xmax = int(data[12])
    ymax = int(data[13])
    if xmin > xmax or ymin > ymax:
        return None
    if xmax >= grid_w or ymax >= grid_h:
        return None
    return {
        "frame": (data[4] << 8) | data[5],
        "valid": bool(data[6] & 0x01),
        "roi_count": int(data[7]),
        "grid_w": grid_w,
        "grid_h": grid_h,
        "xmin": xmin,
        "ymin": ymin,
        "xmax": xmax,
        "ymax": ymax,
        "area": (data[14] << 8) | data[15],
        "score": int(data[16]),
    }


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
    track_meta = None
    fpga_roi = None
    fpga_roi_pkts = 0

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
            roi_meta = parse_fpga_roi_packet(data)
            if roi_meta is not None:
                fpga_roi = roi_meta
                fpga_roi_pkts += 1
            else:
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

        if row == 0:
            track_meta = {
                "valid": data[12] & 1,
                "xmin": data[13],
                "xmax": data[14],
                "ymin": data[15],
                "ymax": data[16],
                "area": (data[17] << 8) | data[18],
            }

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
        "track": track_meta,
        "fpga_roi": fpga_roi,
        "fpga_roi_pkts": fpga_roi_pkts,
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
    result_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM) if RESULT_IP else None
    track_state = {}
    last_pc_track = None
    last_opencv_detections = []
    last_opencv_note = None
    frame_no = 0
    miss = 0
    incomplete_total = 0
    last_ngot = 0
    last_hxv2_pkts = 0
    last = time.time()
    frame_buf = bytearray(HXV2_W * HXV2_H * 2)
    last_rgb = None
    last_track = None
    last_fpga_roi = None
    last_fpga_roi_frame = -999999
    last_fpga_roi_pkts = 0
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
                last_ngot = info["ngot"]
                last_hxv2_pkts = info["hxv2_pkts"]
                last_rgb = hxv2_rgb565_to_rgb(buf)
                last_track = info.get("track")
                if scale != 1:
                    last_rgb = cv2.resize(last_rgb, (HXV2_W * scale, HXV2_H * scale), interpolation=cv2.INTER_NEAREST)
            else:
                miss += 1
                incomplete_total += 1
                last_ngot = info["ngot"]
                last_hxv2_pkts = info["hxv2_pkts"]
                if miss % 3 == 0:
                    print(f"[!] incomplete HXV2 frame x{miss}, info={info}")
                if info["rx_total"] == 0 and miss % 3 == 0:
                    print("[i] no UDP packets, resend camera start/request")
                    send_cmd_on_socket(s, 0x30, bytes([1]), repeat=8, delay=0.03, verbose=False)
                    send_cmd_on_socket(s, 0x31, b"", repeat=8, delay=0.03, verbose=False)
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
            roi_meta = info.get("fpga_roi")
            if roi_meta is not None:
                last_fpga_roi = roi_meta
                last_fpga_roi_frame = frame_no
            last_fpga_roi_pkts = info.get("fpga_roi_pkts", 0)

            status = "localization: searching center target"
            process_track = None
            safety_track = None
            fpga_track = None
            if last_track and last_track.get("valid"):
                sx = (HXV2_W * scale) // CAM_W
                sy = (HXV2_H * scale) // CAM_H
                x0 = last_track["xmin"] * sx
                x1 = min((last_track["xmax"] + 1) * sx - 1, HXV2_W * scale - 1)
                y0 = last_track["ymin"] * sy
                y1 = min((last_track["ymax"] + 1) * sy - 1, HXV2_H * scale - 1)
                cv2.rectangle(rgb, (x0, y0), (x1, y1), (0, 255, 0), 1)
                fpga_track = {"x": x0, "y": y0, "w": x1 - x0 + 1, "h": y1 - y0 + 1}
                safety_track = fpga_track

            recent_fpga_roi = (
                last_fpga_roi
                if last_fpga_roi is not None and frame_no - last_fpga_roi_frame <= FPGA_ROI_MAX_AGE
                else None
            )
            fpga_roi_track = draw_fpga_rois_bgr(rgb, recent_fpga_roi)
            if fpga_roi_track:
                safety_track = fpga_roi_track

            if frame_no % HXV2_DETECT_EVERY == 0 or not last_opencv_detections:
                last_opencv_detections, last_opencv_note = detect_opencv_objects_bgr(rgb)

            if last_opencv_detections:
                draw_opencv_detections_bgr(rgb, last_opencv_detections)
                best = last_opencv_detections[0]
                model_name = _opencv_detector_name()
                note_text = f" {last_opencv_note}" if HXV2_DNN_TIMING and last_opencv_note else ""
                status = f"OpenCV {model_name}: {best['label']} {best['confidence']}% objects={len(last_opencv_detections)} every={HXV2_DETECT_EVERY}{note_text}"
                process_track = best
                safety_track = best
            else:
                if last_opencv_note:
                    status = f"OpenCV detect: {last_opencv_note}"
                else:
                    status = "OpenCV detect: no object"

                if HXV2_RULE_FALLBACK:
                    pc_track = last_pc_track
                    if frame_no % HXV2_DETECT_EVERY == 0 or last_pc_track is None:
                        detect_rgb = rgb
                        det_scale_x = 1.0
                        det_scale_y = 1.0
                        if rgb.shape[1] > HXV2_DETECT_WIDTH:
                            detect_h = max(1, int(rgb.shape[0] * HXV2_DETECT_WIDTH / rgb.shape[1]))
                            detect_rgb = cv2.resize(rgb, (HXV2_DETECT_WIDTH, detect_h), interpolation=cv2.INTER_AREA)
                            det_scale_x = rgb.shape[1] / float(HXV2_DETECT_WIDTH)
                            det_scale_y = rgb.shape[0] / float(detect_h)
                        candidate = detect_primary_object_bgr(detect_rgb)
                        if candidate:
                            candidate = candidate.copy()
                            candidate["x"] = int(candidate["x"] * det_scale_x)
                            candidate["y"] = int(candidate["y"] * det_scale_y)
                            candidate["w"] = max(1, int(candidate["w"] * det_scale_x))
                            candidate["h"] = max(1, int(candidate["h"] * det_scale_y))
                            candidate["area"] = int(candidate["area"] * det_scale_x * det_scale_y)
                        pc_track = update_stable_track(track_state, candidate)
                        last_pc_track = pc_track
                    if pc_track:
                        x0 = pc_track["x"]
                        y0 = pc_track["y"]
                        x1 = x0 + pc_track["w"] - 1
                        y1 = y0 + pc_track["h"] - 1
                        cv2.rectangle(rgb, (x0, y0), (x1, y1), (255, 0, 0), 2)
                        cv2.drawMarker(rgb, (x0 + pc_track["w"] // 2, y0 + pc_track["h"] // 2), (0, 0, 255), cv2.MARKER_CROSS, 16, 2)
                        status = f"rule fallback: {pc_track['label']} conf={pc_track['confidence']}% stable={pc_track.get('stable', 1)}"
                        process_track = pc_track
                        safety_track = pc_track

            if fpga_roi_track and process_track:
                status = f"FPGA ROI + {status}"
            elif fpga_roi_track:
                status = f"FPGA ROI: area={fpga_roi_track['area']} score={fpga_roi_track['confidence']}"
            elif fpga_track and not process_track:
                status = f"fpga detect: area={last_track['area']} box=({last_track['xmin']},{last_track['ymin']})-({last_track['xmax']},{last_track['ymax']})"
            if not HXV2_OPENCV_MODEL and not HXV2_CLASSIC_ONLY:
                cv2.putText(rgb, "OpenCV DNN: add MobileNetSSD .caffemodel + .prototxt for class names", (8, 128), cv2.FONT_HERSHEY_SIMPLEX, 0.48, (0, 165, 255), 2)
            guide_x0 = int(rgb.shape[1] * 0.30)
            guide_y0 = int(rgb.shape[0] * 0.12)
            guide_x1 = int(rgb.shape[1] * 0.70)
            guide_y1 = int(rgb.shape[0] * 0.82)
            if HXV2_RULE_FALLBACK:
                cv2.rectangle(rgb, (guide_x0, guide_y0), (guide_x1, guide_y1), (255, 255, 0), 1)
                cv2.putText(rgb, "rule fallback ROI", (guide_x0 + 4, max(guide_y0 - 6, 16)), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (255, 255, 0), 1)
            align_guide, align_info = target_alignment_status(rgb, process_track or safety_track)
            ax0, ay0, ax1, ay1 = align_guide
            align_color = (0, 255, 0) if align_info.get("centered") else (0, 255, 255)
            cv2.rectangle(rgb, (ax0, ay0), (ax1, ay1), align_color, 2)
            cv2.line(rgb, (rgb.shape[1] // 2 - 14, rgb.shape[0] // 2), (rgb.shape[1] // 2 + 14, rgb.shape[0] // 2), align_color, 2)
            cv2.line(rgb, (rgb.shape[1] // 2, rgb.shape[0] // 2 - 14), (rgb.shape[1] // 2, rgb.shape[0] // 2 + 14), align_color, 2)
            cv2.putText(rgb, align_info["text"], (8, 104), cv2.FONT_HERSHEY_SIMPLEX, 0.55, align_color, 2)
            loss_rate = incomplete_total * 100.0 / max(frame_no + incomplete_total, 1)
            if miss >= 3:
                net_state = "DISCONNECTED"
                net_color = (0, 0, 255)
            elif last_ngot < HXV2_H or loss_rate > 5.0:
                net_state = "LOSS"
                net_color = (0, 255, 255)
            else:
                net_state = "GOOD"
                net_color = (0, 255, 0)
            send_result_udp(result_sock, frame_no, process_track or safety_track, align_info, net_state, last_ngot, loss_rate)
            cv2.putText(rgb, f"Smart Ethernet Vision Monitor  frame={frame_no} fps={fps:.1f}", (8, 24), cv2.FONT_HERSHEY_SIMPLEX, 0.65, (255, 255, 0), 2)
            cv2.putText(rgb, status, (8, 52), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 255), 2)
            cv2.putText(rgb, f"Network={net_state} rows={last_ngot}/{HXV2_H} pkts={last_hxv2_pkts} roi={last_fpga_roi_pkts} incomplete={incomplete_total} loss={loss_rate:.1f}%", (8, 78), cv2.FONT_HERSHEY_SIMPLEX, 0.55, net_color, 2)
            cv2.imshow("FPGA HXV2 Camera", rgb)
            if cv2.waitKey(1) & 0xFF == ord("q"):
                break
    finally:
        send_cmd_on_socket(s, 0x30, bytes([0]), repeat=3)
        s.close()
        if result_sock:
            result_sock.close()
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
