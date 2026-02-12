"""
Offline MP4 processor for extremely low-light environments.

Pipeline:
  1. Gamma-only enhancement on full-res frame (fast, ~1ms) for output
  2. Downscale to 640px → Gamma + CLAHE enhancement for AI detection
  3. MediaPipe face landmarks + EAR drowsiness scoring every frame
  4. YOLO distraction detection every frame on small frame
  5. Annotations drawn on full-res frame with normalized coordinates
  6. Output encoded via ffmpeg H.264 pipe (~4-5x smaller than mp4v)

Usage:
    python process_lowlight.py input.mp4 -o output.mp4
    python process_lowlight.py input.mp4 -o output.mp4 --no-yolo
    python process_lowlight.py input.mp4 -o output.mp4 --side-by-side
    python process_lowlight.py input.mp4 -o output.mp4 --gamma 3.0 --clahe-clip 4.0
"""

import argparse
import math
import os
import shutil
import subprocess
import time
from collections import deque

import cv2
import mediapipe as mp_lib
import numpy as np
from dotenv import load_dotenv
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision

load_dotenv()

# ── Constants ─────────────────────────────────────────────────────────────────
COLOR_GREEN = (0, 255, 0)
COLOR_ORANGE = (0, 165, 255)
COLOR_RED = (0, 0, 255)
COLOR_WHITE = (255, 255, 255)
COLOR_DARK_RED = (0, 0, 128)
COLOR_DARK_ORANGE = (0, 80, 128)
COLOR_CYAN = (255, 255, 0)
COLOR_YELLOW = (0, 255, 255)
COLOR_MAGENTA = (255, 0, 255)
FONT = cv2.FONT_HERSHEY_PLAIN

DETECT_WIDTH = 640


# ── Fast 2D distance (replaces scipy.spatial.distance.euclidean) ──────────────

def _dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


# ── Low-light enhancement ─────────────────────────────────────────────────────

class LowLightEnhancer:
    """Split enhancement: gamma-only on full res, gamma+CLAHE on detection res."""

    def __init__(self, gamma=2.0, clahe_clip=3.0, clahe_grid=8, auto_brightness=True):
        self.auto_brightness = auto_brightness
        self._clahe = cv2.createCLAHE(clipLimit=clahe_clip, tileGridSize=(clahe_grid, clahe_grid))

        # Pre-build gamma LUTs for every value auto_gamma can return
        self._lut_cache = {}
        for g in [1.0, 1.2, 1.5, 1.8, 2.0, 2.5, 3.0, 3.5, 4.0]:
            self._lut_cache[g] = self._build_lut(g)
        self._default_lut = self._lut_cache.get(gamma, self._build_lut(gamma))
        self._last_lut = self._default_lut

    @staticmethod
    def _build_lut(gamma: float) -> np.ndarray:
        inv = 1.0 / max(gamma, 0.01)
        return np.array([((i / 255.0) ** inv) * 255 for i in range(256)], dtype=np.uint8)

    def _pick_lut(self, frame: np.ndarray) -> np.ndarray:
        """Pick gamma LUT. With auto_brightness, sample center patch."""
        if not self.auto_brightness:
            return self._default_lut
        h, w = frame.shape[:2]
        cy, cx = h // 2, w // 2
        s = 50
        mean_b = frame[cy - s : cy + s, cx - s : cx + s].mean()
        if mean_b < 8:
            g = 4.0
        elif mean_b < 25:
            g = 3.0
        elif mean_b < 50:
            g = 2.5
        elif mean_b < 80:
            g = 2.0
        elif mean_b < 120:
            g = 1.5
        else:
            g = 1.0
        lut = self._lut_cache.get(g, self._default_lut)
        self._last_lut = lut
        return lut

    def enhance_output(self, frame: np.ndarray) -> np.ndarray:
        """Gamma-only on full res (~1ms). Stores LUT for detection frame."""
        lut = self._pick_lut(frame)
        return cv2.LUT(frame, lut)

    def enhance_detect(self, small: np.ndarray) -> np.ndarray:
        """Gamma + CLAHE on already-downscaled frame (~2-3ms at 640px)."""
        # Gamma (reuse the LUT chosen for this frame)
        small = cv2.LUT(small, self._last_lut)
        # CLAHE on L channel
        lab = cv2.cvtColor(small, cv2.COLOR_BGR2LAB)
        l, a, b = cv2.split(lab)
        l = self._clahe.apply(l)
        return cv2.cvtColor(cv2.merge([l, a, b]), cv2.COLOR_LAB2BGR)


# ── Face analyzer ─────────────────────────────────────────────────────────────

class FaceAnalyzer:
    """MediaPipe face landmarks + EAR drowsiness. Returns normalized [0-1] coords."""

    def __init__(self):
        opts = vision.FaceLandmarkerOptions(
            base_options=mp_python.BaseOptions(model_asset_path="face_landmarker.task"),
            running_mode=vision.RunningMode.VIDEO,
            num_faces=5,
            min_face_detection_confidence=0.3,
            min_face_presence_confidence=0.3,
            min_tracking_confidence=0.3,
        )
        self.landmarker = vision.FaceLandmarker.create_from_options(opts)

        self.LEFT_EYE = [362, 385, 387, 263, 373, 380]
        self.RIGHT_EYE = [33, 160, 158, 133, 153, 144]
        self.EAR_THRESHOLD = 0.21
        self.DROWSINESS_FRAMES = 20
        self.BLINK_THRESHOLD = 30

        self.eye_closed_counter = 0
        self.blink_counter = 0
        self.blink_history = deque(maxlen=100)
        self.ear_history = deque(maxlen=50)

    @staticmethod
    def _ear(pts):
        A = _dist(pts[1], pts[5])
        B = _dist(pts[2], pts[4])
        C = _dist(pts[0], pts[3])
        return (A + B) / (2.0 * C)

    def _intox(self, left_ear, right_ear):
        avg = (left_ear + right_ear) / 2
        self.ear_history.append(avg)

        if avg < self.EAR_THRESHOLD:
            self.eye_closed_counter += 1
        else:
            if self.eye_closed_counter > 2:
                self.blink_counter += 1
                self.blink_history.append(1)
            self.eye_closed_counter = 0

        drowsy = self.eye_closed_counter >= self.DROWSINESS_FRAMES
        blinks = sum(self.blink_history) if self.blink_history else 0
        excess_blink = blinks > self.BLINK_THRESHOLD
        var = float(np.var(self.ear_history)) if len(self.ear_history) > 10 else 0.0
        unstable = var > 0.02

        score = (3 if drowsy else 0) + (2 if excess_blink else 0) + (1 if unstable else 0)
        return {
            "drowsy": drowsy,
            "excessive_blinking": excess_blink,
            "unstable_eyes": unstable,
            "score": score,
            "ear": avg,
        }

    def detect(self, frame: np.ndarray, timestamp_ms: int):
        h, w = frame.shape[:2]
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        mp_img = mp_lib.Image(image_format=mp_lib.ImageFormat.SRGB, data=rgb)
        results = self.landmarker.detect_for_video(mp_img, timestamp_ms)

        faces = []
        if not results.face_landmarks:
            return faces

        for fl in results.face_landmarks:
            xs = [lm.x for lm in fl]
            ys = [lm.y for lm in fl]
            nx_min, nx_max = min(xs), max(xs)
            ny_min, ny_max = min(ys), max(ys)

            le = [(int(fl[i].x * w), int(fl[i].y * h)) for i in self.LEFT_EYE]
            re = [(int(fl[i].x * w), int(fl[i].y * h)) for i in self.RIGHT_EYE]
            le_norm = [(fl[i].x, fl[i].y) for i in self.LEFT_EYE]
            re_norm = [(fl[i].x, fl[i].y) for i in self.RIGHT_EYE]

            l_ear = self._ear(le)
            r_ear = self._ear(re)
            l_state = "CLOSED" if l_ear < self.EAR_THRESHOLD else "OPEN"
            r_state = "CLOSED" if r_ear < self.EAR_THRESHOLD else "OPEN"
            intox = self._intox(l_ear, r_ear)

            faces.append({
                "norm_bbox": (nx_min, ny_min, nx_max, ny_max),
                "left_eye_norm": le_norm, "right_eye_norm": re_norm,
                "left_eye_state": l_state, "left_ear": l_ear,
                "right_eye_state": r_state, "right_ear": r_ear,
                "intox": intox,
            })

        return faces


# ── YOLO distraction detector ─────────────────────────────────────────────────

class DistractionDetector:
    # Class IDs for driver monitoring (COCO 80)
    PERSON = 0
    PHONE_CLASSES = {67}                     # cell phone
    DRINK_CLASSES = {39, 40, 41}             # bottle, wine glass, cup
    DEVICE_CLASSES = {63, 65, 67, 73}        # laptop, remote, cell phone, book
    ALL_TARGET = [0, 39, 40, 41, 63, 65, 67, 73]

    def __init__(self, model_path=None, enabled=True):
        self.enabled = enabled
        self.model = None

        if self.enabled:
            if model_path is None:
                model_path = os.environ.get("YOLO_MODEL_PATH", "yolo-models/yolo26m.pt")
            from ultralytics import YOLO
            print(f"Loading YOLO: {model_path}")
            self.model = YOLO(model_path)
            self.conf = 0.25
            print("YOLO loaded")

        self.phone_detected = False
        self.drinking_detected = False
        self.person_detected = False
        self.phone_bbox = None
        self.bottle_bbox = None
        self.phone_frames = 0
        self.drinking_frames = 0
        self.person_frames = 0
        self.threshold = 2

    def detect(self, frame):
        if not self.enabled or self.model is None:
            return
        h, w = frame.shape[:2]
        results = self.model(frame, verbose=False, conf=self.conf, classes=self.ALL_TARGET)
        cur_phone = cur_bottle = None
        saw_person = False

        for r in results:
            if r.boxes is None:
                continue
            for box in r.boxes:
                cls = int(box.cls[0])
                xy = box.xyxy[0].cpu().numpy()
                norm = (xy[0] / w, xy[1] / h, xy[2] / w, xy[3] / h)
                if cls == self.PERSON:
                    saw_person = True
                elif cls in self.PHONE_CLASSES or cls in self.DEVICE_CLASSES:
                    cur_phone = norm
                elif cls in self.DRINK_CLASSES:
                    cur_bottle = norm

        # Smoothing — require consecutive frames to confirm
        if cur_phone is not None:
            self.phone_bbox = cur_phone
            self.phone_frames += 1
        else:
            self.phone_frames = max(0, self.phone_frames - 1)
            if self.phone_frames == 0:
                self.phone_bbox = None

        if cur_bottle is not None:
            self.bottle_bbox = cur_bottle
            self.drinking_frames += 1
        else:
            self.drinking_frames = max(0, self.drinking_frames - 1)
            if self.drinking_frames == 0:
                self.bottle_bbox = None

        if saw_person:
            self.person_frames = min(self.person_frames + 1, 10)
        else:
            self.person_frames = max(0, self.person_frames - 1)

        self.phone_detected = self.phone_frames >= self.threshold
        self.drinking_detected = self.drinking_frames >= self.threshold
        self.person_detected = self.person_frames >= self.threshold


# ── Drawing helpers ───────────────────────────────────────────────────────────

def draw_faces(frame, faces):
    h, w = frame.shape[:2]
    for f in faces:
        intox = f["intox"]
        score = intox["score"]

        if score >= 4:
            box_color, status_label = COLOR_RED, "IMPAIRED"
        elif score >= 2 or intox["drowsy"]:
            box_color, status_label = COLOR_ORANGE, "DROWSY"
        else:
            box_color, status_label = COLOR_GREEN, "ALERT"

        nx1, ny1, nx2, ny2 = f["norm_bbox"]
        x1, y1 = int(nx1 * w), int(ny1 * h)
        x2, y2 = int(nx2 * w), int(ny2 * h)
        face_w = x2 - x1

        cv2.rectangle(frame, (x1, y1), (x2, y2), box_color, 2)

        # Eye landmarks
        for norm_pts, state, c in [
            (f["left_eye_norm"], f["left_eye_state"], COLOR_CYAN),
            (f["right_eye_norm"], f["right_eye_state"], COLOR_MAGENTA),
        ]:
            pts = [(int(nx * w), int(ny * h)) for nx, ny in norm_pts]
            dc = COLOR_RED if state == "CLOSED" else c
            for px, py in pts:
                cv2.circle(frame, (px, py), 3, dc, -1)
            cv2.polylines(frame, [np.array(pts, dtype=np.int32)], True, dc, 1)

        # EAR text
        l_ear, r_ear = f["left_ear"], f["right_ear"]
        avg_ear = (l_ear + r_ear) / 2.0
        cv2.putText(frame, f"EAR L:{l_ear:.2f} R:{r_ear:.2f} avg:{avg_ear:.2f}",
                    (x1, y1 - 30), FONT, 1.1, COLOR_WHITE, 1)
        eye_txt = f"L:{f['left_eye_state']}  R:{f['right_eye_state']}"
        cv2.putText(frame, eye_txt, (x1, y1 - 12), FONT, 1.1,
                    COLOR_RED if "CLOSED" in eye_txt else COLOR_GREEN, 1)

        # EAR bar
        bar_x, bar_y = x1, y2 + 8
        bar_w = max(face_w, 120)
        bar_fill = int(min(avg_ear / 0.4, 1.0) * bar_w)
        thresh_x = int((0.21 / 0.4) * bar_w)
        cv2.rectangle(frame, (bar_x, bar_y), (bar_x + bar_w, bar_y + 10), (40, 40, 40), -1)
        cv2.rectangle(frame, (bar_x, bar_y), (bar_x + bar_fill, bar_y + 10),
                      COLOR_GREEN if avg_ear >= 0.21 else COLOR_RED, -1)
        cv2.line(frame, (bar_x + thresh_x, bar_y - 2), (bar_x + thresh_x, bar_y + 12), COLOR_YELLOW, 2)

        # Status label
        cv2.putText(frame, status_label, (x1, bar_y + 30), FONT, 2.0, box_color, 2)

        # Detail warnings
        details = []
        if intox["drowsy"]:
            details.append("Eyes Closed Too Long")
        if intox["excessive_blinking"]:
            details.append("Excessive Blinking")
        if intox["unstable_eyes"]:
            details.append("Unstable Eye Movement")
        if details:
            cv2.putText(frame, " | ".join(details), (x1, bar_y + 50), FONT, 1.0, box_color, 1)


def draw_yolo(frame, det):
    h, w = frame.shape[:2]
    for bbox, detected, label_on, label_off in [
        (det.phone_bbox, det.phone_detected, "PHONE - DISTRACTED!", "Phone"),
        (det.bottle_bbox, det.drinking_detected, "DRINKING!", "Bottle/Cup"),
    ]:
        if bbox is None:
            continue
        nx1, ny1, nx2, ny2 = bbox
        x1, y1 = int(nx1 * w), int(ny1 * h)
        x2, y2 = int(nx2 * w), int(ny2 * h)
        color = COLOR_RED if detected else COLOR_ORANGE
        cv2.rectangle(frame, (x1, y1), (x2, y2), color, 2)
        cv2.putText(frame, label_on if detected else label_off, (x1, y1 - 10), FONT, 1.2, color, 1)


def draw_banner(frame, det):
    h, w = frame.shape[:2]
    if det.phone_detected:
        frame[h - 80 : h, 0:w] = COLOR_DARK_RED
        cv2.putText(frame, "WARNING: PHONE DETECTED", (w // 2 - 200, h - 35), FONT, 1.8, COLOR_WHITE, 2)
    elif det.drinking_detected:
        frame[h - 60 : h, 0:w] = COLOR_DARK_ORANGE
        cv2.putText(frame, "WARNING: DRINKING DETECTED", (w // 2 - 220, h - 20), FONT, 1.8, COLOR_WHITE, 2)


def draw_hud(frame, idx, total, fps, enhanced):
    h, w = frame.shape[:2]
    pct = idx / total * 100 if total else 0
    txt = f"{idx}/{total} ({pct:.0f}%)  {fps:.0f} FPS"
    if enhanced:
        txt += "  LOW-LIGHT"
    frame[0:28, 0:w] = (0, 0, 0)
    cv2.putText(frame, txt, (8, 20), FONT, 1.2, COLOR_CYAN, 1)
    bar = int(w * idx / total) if total else 0
    frame[26:28, 0:bar] = COLOR_CYAN


# ── ffmpeg output writer ─────────────────────────────────────────────────────

class FFmpegWriter:
    """Pipe raw BGR frames to ffmpeg for H.264 encoding (much smaller files)."""

    def __init__(self, output_path, width, height, fps, crf=23):
        self.proc = subprocess.Popen(
            [
                "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                "-f", "rawvideo", "-vcodec", "rawvideo",
                "-s", f"{width}x{height}", "-pix_fmt", "bgr24",
                "-r", str(fps),
                "-i", "-",
                "-c:v", "libx264", "-crf", str(crf), "-preset", "fast",
                "-pix_fmt", "yuv420p",
                output_path,
            ],
            stdin=subprocess.PIPE,
        )

    def write(self, frame: np.ndarray):
        self.proc.stdin.write(frame.tobytes())

    def release(self):
        self.proc.stdin.close()
        self.proc.wait()


class CV2Writer:
    """Fallback if ffmpeg is not installed."""

    def __init__(self, output_path, width, height, fps):
        self.w = cv2.VideoWriter(output_path, cv2.VideoWriter_fourcc(*"mp4v"), fps, (width, height))

    def write(self, frame):
        self.w.write(frame)

    def release(self):
        self.w.release()


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    p = argparse.ArgumentParser(description="Low-light MP4 processor with driver monitoring")
    p.add_argument("input", help="Input MP4 path")
    p.add_argument("-o", "--output", default=None, help="Output MP4 path")
    p.add_argument("--no-yolo", action="store_true", help="Disable YOLO distraction detection")
    p.add_argument("--no-enhance", action="store_true", help="Skip low-light enhancement")
    p.add_argument("--gamma", type=float, default=2.0, help="Gamma correction (default: 2.0)")
    p.add_argument("--clahe-clip", type=float, default=3.0, help="CLAHE clip limit (default: 3.0)")
    p.add_argument("--no-auto-brightness", action="store_true", help="Disable auto gamma per frame")
    p.add_argument("--side-by-side", action="store_true", help="Original + enhanced side by side")
    p.add_argument("--detect-width", type=int, default=DETECT_WIDTH, help="AI detection width (default: 640)")
    p.add_argument("--crf", type=int, default=23, help="H.264 quality 0-51 (lower=better, default: 23)")
    args = p.parse_args()

    input_path = os.path.abspath(args.input)
    if not os.path.isfile(input_path):
        print(f"Error: file not found: {input_path}")
        return

    output_path = os.path.abspath(args.output) if args.output else (
        os.path.splitext(input_path)[0] + "_processed.mp4"
    )

    cap = cv2.VideoCapture(input_path)
    if not cap.isOpened():
        print(f"Error: cannot open {input_path}")
        return

    W = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    H = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fps_in = cap.get(cv2.CAP_PROP_FPS) or 30.0
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

    det_w = args.detect_width
    scale = det_w / W
    det_h = int(H * scale)

    print(f"Input:  {input_path}")
    print(f"Output: {output_path}")
    print(f"Source: {W}x{H} @ {fps_in:.1f} FPS  ({total} frames, {total/fps_in:.1f}s)")
    print(f"Detect: {det_w}x{det_h} ({scale:.2f}x)")

    out_w = W * 2 if args.side_by_side else W

    # Use ffmpeg for H.264 if available, otherwise fall back to cv2
    has_ffmpeg = shutil.which("ffmpeg") is not None
    if has_ffmpeg:
        writer = FFmpegWriter(output_path, out_w, H, fps_in, crf=args.crf)
        print(f"Encoder: ffmpeg H.264 (CRF {args.crf})")
    else:
        writer = CV2Writer(output_path, out_w, H, fps_in)
        print("Encoder: cv2 mp4v (ffmpeg not found, output will be larger)")

    enhancer = LowLightEnhancer(
        gamma=args.gamma, clahe_clip=args.clahe_clip,
        auto_brightness=not args.no_auto_brightness,
    )
    analyzer = FaceAnalyzer()

    enable_yolo = not args.no_yolo
    if enable_yolo:
        try:
            detector = DistractionDetector(enabled=True)
        except Exception as e:
            print(f"YOLO unavailable: {e}")
            detector = DistractionDetector(enabled=False)
            enable_yolo = False
    else:
        detector = DistractionDetector(enabled=False)

    do_enhance = not args.no_enhance

    print()
    if do_enhance:
        print(f"Enhancement: ON  (gamma={args.gamma}, clahe={args.clahe_clip}, "
              f"auto={'on' if not args.no_auto_brightness else 'off'})")
        print(f"  Full-res: gamma only (~1ms)  |  Detect-res: gamma+CLAHE (~3ms)")
    else:
        print("Enhancement: OFF")
    print(f"Face detect: every frame")
    print(f"YOLO: {'every frame' if enable_yolo else 'OFF'}")
    print(f"Side-by-side: {'ON' if args.side_by_side else 'OFF'}")
    print()

    idx = 0
    times = deque(maxlen=200)
    t_print = time.time()
    t_wall_start = time.time()

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        t0 = time.time()
        idx += 1
        ts_ms = int(idx * (1000.0 / fps_in))

        original = frame.copy() if args.side_by_side else None

        # Gamma on full-res (every frame — cheap, ~1ms)
        if do_enhance:
            frame = enhancer.enhance_output(frame)

        # Downscale for AI detection
        small = cv2.resize(frame, (det_w, det_h), interpolation=cv2.INTER_LINEAR)
        if do_enhance:
            small = enhancer.enhance_detect(small)

        # Face detection every frame
        faces = analyzer.detect(small, ts_ms)

        # YOLO detection every frame
        if enable_yolo:
            detector.detect(small)

        # Draw results
        draw_faces(frame, faces)
        draw_yolo(frame, detector)
        draw_banner(frame, detector)

        avg_t = sum(times) / len(times) if times else 0.033
        draw_hud(frame, idx, total, 1.0 / avg_t if avg_t > 0 else 0, do_enhance)

        if args.side_by_side:
            cv2.putText(original, "ORIGINAL", (10, 30), FONT, 1.6, COLOR_WHITE, 2)
            writer.write(np.hstack([original, frame]))
        else:
            writer.write(frame)

        t1 = time.time()
        times.append(t1 - t0)

        if t1 - t_print >= 2.0:
            avg_ms = (sum(times) / len(times)) * 1000
            remaining = (total - idx) * avg_ms / 1000
            m, s = divmod(int(remaining), 60)
            print(f"  [{idx/total*100:5.1f}%] {idx}/{total}  | {avg_ms:.0f} ms/frame  | ETA {m}m{s:02d}s")
            t_print = t1

    cap.release()
    writer.release()

    wall = time.time() - t_wall_start
    out_size = os.path.getsize(output_path) / (1024 * 1024)
    print(f"\nDone — {idx} frames in {wall:.1f}s ({idx/wall:.0f} FPS)")
    print(f"Saved: {output_path} ({out_size:.1f} MB)")


if __name__ == "__main__":
    main()
