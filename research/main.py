import argparse
import json
import math
import multiprocessing
import os
import platform
import random
import signal
import sys
import threading
import time
import urllib.request
import uuid
from collections import deque
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone

# PST timezone (UTC-8)
PST = timezone(timedelta(hours=-8))

# Platform detection — used for choosing onnxruntime execution providers.
# RPi4 is aarch64 Linux (ARM, no GPU), Mac is arm64 Darwin (Apple Silicon).
_IS_ARM_LINUX = platform.machine() in ("aarch64", "armv7l") and sys.platform == "linux"
_IS_MACOS = sys.platform == "darwin"

# Suppress onnxruntime GPU discovery on devices without a discrete GPU.
# Without this, ort prints "GPU device discovery failed" errors on RPi.
if _IS_ARM_LINUX:
    os.environ.setdefault("ORT_DISABLE_GPU_DISCOVERY", "1")
    # ORT 1.24+ ignores the above; raise log severity to suppress the warning.
    os.environ.setdefault("ORT_LOG_LEVEL", "ERROR")

# Force unbuffered stdout so prints appear even if the process crashes
sys.stdout.reconfigure(line_buffering=True)
_startup_t0 = time.time()
print("Starting main.py...")

import cv2
import numpy as np
from dotenv import load_dotenv

from components.buzzer import BuzzerController
from components.gps import GPSReader
from components.microphone import MicrophoneController
from components.shazam import ShazamRecognizer
from components.speed_limit import SpeedLimitChecker

GYRO_AVAILABLE = False
try:
    from components.gyroscope import CrashDetector, GyroReader

    GYRO_AVAILABLE = True
except ImportError:
    pass

BLE_AVAILABLE = False
try:
    from components.bluetooth import BluetoothServer

    BLE_AVAILABLE = True
except ImportError:
    pass

print("  Components loaded")

# MediaPipe is loaded lazily inside FaceAnalyzer.__init__() to avoid
# segfaults from protobuf conflicts on RPi (a segfault bypasses try/except).
_MEDIAPIPE_AVAILABLE = None  # determined at runtime in _check_mediapipe()


def _get_ort_providers():
    """Return the best available onnxruntime execution providers for this platform.

    - macOS (Apple Silicon): CoreMLExecutionProvider → CPUExecutionProvider
    - RPi / ARM Linux:       CPUExecutionProvider only
    - Other:                 CPUExecutionProvider only
    """
    if _IS_MACOS:
        try:
            import onnxruntime as _ort

            available = _ort.get_available_providers()
            if "CoreMLExecutionProvider" in available:
                return ["CoreMLExecutionProvider", "CPUExecutionProvider"]
        except Exception:
            pass
    return ["CPUExecutionProvider"]


def _check_mediapipe():
    """Test whether MediaPipe can be imported.

    On ARM Linux (RPi), runs the import in a subprocess to survive segfaults
    from protobuf conflicts.  On other platforms, imports directly (much faster).
    """
    global _MEDIAPIPE_AVAILABLE
    if _MEDIAPIPE_AVAILABLE is not None:
        return _MEDIAPIPE_AVAILABLE
    print("  Checking MediaPipe availability...", end=" ", flush=True)

    if _IS_ARM_LINUX:
        # RPi: subprocess check to survive potential protobuf segfaults
        try:
            import subprocess

            result = subprocess.run(
                [sys.executable, "-c", "import mediapipe"],
                capture_output=True,
                timeout=15,
            )
            _MEDIAPIPE_AVAILABLE = result.returncode == 0
            if not _MEDIAPIPE_AVAILABLE:
                stderr = result.stderr.decode(errors="replace").strip()
                print(f"FAILED (exit {result.returncode})")
                if stderr:
                    print(f"    {stderr[:200]}")
            else:
                print("ok")
        except Exception as e:
            _MEDIAPIPE_AVAILABLE = False
            print(f"FAILED ({e})")
    else:
        # macOS / x86: direct import (no segfault risk, avoids ~15s subprocess)
        try:
            import mediapipe as _mp_test  # noqa: F401

            _MEDIAPIPE_AVAILABLE = True
            print("ok")
        except Exception as e:
            _MEDIAPIPE_AVAILABLE = False
            print(f"FAILED ({e})")

    if not _MEDIAPIPE_AVAILABLE:
        print("  Will use OpenCV fallback face detector")
    return _MEDIAPIPE_AVAILABLE


# Performance optimization constants
# Pre-computed color tuples for faster drawing (avoids tuple creation overhead)
COLOR_GREEN = (0, 255, 0)
COLOR_ORANGE = (0, 165, 255)
COLOR_RED = (0, 0, 255)
COLOR_WHITE = (255, 255, 255)
COLOR_GRAY = (200, 200, 200)
COLOR_DARK_RED = (0, 0, 128)
COLOR_DARK_ORANGE = (0, 80, 128)

# Pre-computed font constant (FONT_HERSHEY_PLAIN is 2x faster than SIMPLEX/DUPLEX)
FONT_FAST = cv2.FONT_HERSHEY_PLAIN

# Load environment variables from .env file
load_dotenv()


def _check_yolo():
    """Test whether ultralytics YOLO can be imported.

    On ARM Linux (RPi), runs the import in a subprocess to survive segfaults.
    On other platforms, imports directly (much faster — avoids ~30s subprocess).
    """
    global YOLO_AVAILABLE, YOLO_ONNX_AVAILABLE
    print("  Checking YOLO...", end=" ", flush=True)

    if _IS_ARM_LINUX:
        # RPi: subprocess check to survive potential segfaults
        try:
            import subprocess

            _yolo_check = subprocess.run(
                [sys.executable, "-c", "from ultralytics import YOLO"],
                capture_output=True,
                timeout=30,
            )
            if _yolo_check.returncode == 0:
                from ultralytics import YOLO

                globals()["YOLO"] = YOLO
                YOLO_AVAILABLE = True
                print("ok (ultralytics)")
            else:
                _yolo_err = (
                    _yolo_check.stderr.decode(errors="replace").strip().split("\n")[-1]
                )
                print(f"ultralytics unavailable ({_yolo_err[:80]})")
        except Exception as e:
            print(f"ultralytics unavailable ({e})")
    else:
        # macOS / x86: direct import (avoids ~30s subprocess)
        try:
            from ultralytics import YOLO

            globals()["YOLO"] = YOLO
            YOLO_AVAILABLE = True
            print("ok (ultralytics)")
        except Exception as e:
            print(f"ultralytics unavailable ({e})")

    # Check for ONNX fallback (also used as primary on macOS for speed)
    _onnx_candidates = [
        "yolo-models/yolo26n.onnx",
        "yolo-models/yolo26s.onnx",
        "yolo-models/yolo26m.onnx",
    ]
    _has_onnx_model = any(os.path.isfile(p) for p in _onnx_candidates)
    if _has_onnx_model:
        try:
            import onnxruntime

            YOLO_ONNX_AVAILABLE = True
            if not YOLO_AVAILABLE:
                print(
                    f"  YOLO ONNX fallback available (onnxruntime {onnxruntime.__version__})"
                )
        except ImportError:
            if not YOLO_AVAILABLE:
                print("  No ONNX fallback (onnxruntime not installed)")
    elif not YOLO_AVAILABLE:
        print(
            "  No ONNX models found in yolo-models/ (run export_driver.py to generate)"
        )


# Deferred to main() — run in parallel with Supabase network init.
YOLO_AVAILABLE = False
YOLO_ONNX_AVAILABLE = False


# .env overrides: if explicitly set in .env, these take priority over Supabase.
# If not set, Supabase value is used. Format: {key: (value, is_explicitly_set)}
def _parse_env_bool(key, default):
    """Return (bool_value, was_explicitly_set)."""
    raw = os.environ.get(key)
    if raw is None:
        return default, False
    return raw.lower() in ("true", "1", "yes"), True


_ENV_ENABLE_STREAM, _ENV_STREAM_SET = _parse_env_bool("ENABLE_STREAM", False)
_ENV_ENABLE_SHAZAM, _ENV_SHAZAM_SET = _parse_env_bool("ENABLE_SHAZAM", True)
_ENV_ENABLE_MICROPHONE, _ENV_MIC_SET = _parse_env_bool("ENABLE_MICROPHONE", True)
_ENV_ENABLE_DASHCAM, _ENV_DASHCAM_SET = _parse_env_bool("ENABLE_DASHCAM", True)
_ENV_ENABLE_CUSTOM_MODELS, _ = _parse_env_bool("ENABLE_CUSTOM_MODELS", False)
_ENV_MIRROR_CAMERA, _ = _parse_env_bool("MIRROR_CAMERA", False)

# Stream / Shazam parameters (always from .env)
STREAM_QUALITY = int(os.environ.get("STREAM_QUALITY", "50"))
STREAM_FPS = int(os.environ.get("STREAM_FPS", "3"))
STREAM_WIDTH = int(os.environ.get("STREAM_WIDTH", "640"))
SHAZAM_INTERVAL = int(os.environ.get("SHAZAM_INTERVAL", "20"))
SHAZAM_DEBUG = os.environ.get("SHAZAM_DEBUG", "false").lower() in ("true", "1", "yes")

# Custom ONNX model paths — try INT8 first (fastest on RPi4), fall back to FP32
_EYE_CANDIDATES = [
    "models/checkpoints/eye_state_distilled_int8_dynamic.onnx",
    "models/checkpoints/eye_state_distilled_fp32.onnx",
]
_ACTIVITY_CANDIDATES = [
    "models/checkpoints/driver_activity_distilled_int8_dynamic.onnx",
    "models/checkpoints/driver_activity_distilled_fp32.onnx",
]


def _find_model(candidates):
    """Return the first model path that exists, or None."""
    for path in candidates:
        if os.path.exists(path):
            return path
    return None


# ---------------------------------------------------------------------------
# Multiprocessing workers — run FaceAnalyzer and DistractionDetector on
# separate CPU cores to bypass the GIL.  On RPi4 this roughly doubles
# throughput because the two heaviest models (MediaPipe + YOLO ONNX) no
# longer compete for the same core.
#
# Communication uses multiprocessing.Queue:
#   main → worker:  (frame_bytes, shape, timestamp_ms, extra)
#   worker → main:  result dict (detection_data / distraction_data)
#
# Frame data is sent as raw bytes (tobytes/frombuffer) — faster than pickle
# for large numpy arrays.
# ---------------------------------------------------------------------------


def _face_worker_process(in_q, out_q, mp_max_dim):
    """Standalone process that runs FaceAnalyzer inference.

    On Linux (fork), parent's imports are already in memory.
    On other platforms, re-imports as needed.
    Reads (frame_bytes, shape, timestamp_ms) from in_q, writes
    (annotated_frame_bytes, shape, detection_data) to out_q.
    """
    # Suppress signals in worker — main process handles shutdown
    signal.signal(signal.SIGINT, signal.SIG_IGN)

    # Build a FaceAnalyzer inside this process's own memory
    try:
        if _check_mediapipe():
            try:
                analyzer = FaceAnalyzer()
                print("[FaceWorker] FaceAnalyzer loaded in subprocess", flush=True)
            except Exception as e:
                print(
                    f"[FaceWorker] FaceAnalyzer failed ({e}), using fallback",
                    flush=True,
                )
                analyzer = FallbackFaceDetector()
        else:
            analyzer = FallbackFaceDetector()
    except Exception as e:
        print(f"[FaceWorker] FATAL: could not load analyzer: {e}", flush=True)
        return

    while True:
        try:
            msg = in_q.get()
            if msg is None:  # shutdown sentinel
                break
            frame_bytes, shape, timestamp_ms = msg
            frame = np.frombuffer(frame_bytes, dtype=np.uint8).reshape(shape).copy()
            annotated, det_data = analyzer._analyze_frame_sync(frame, timestamp_ms)
            # Send back: annotated frame as bytes + detection data
            # detection_data contains numpy face_crop — convert to bytes too
            if det_data and det_data.get("face_crop") is not None:
                crop = det_data["face_crop"]
                det_data = dict(det_data)  # shallow copy
                det_data["_face_crop_bytes"] = crop.tobytes()
                det_data["_face_crop_shape"] = crop.shape
                det_data["face_crop"] = None  # placeholder, rebuilt in main
            out_q.put((annotated.tobytes(), annotated.shape, det_data))
        except Exception as e:
            print(f"[FaceWorker] error: {e}", flush=True)
            try:
                out_q.put(None)
            except Exception:
                pass


def _yolo_worker_process(in_q, out_q, enabled):
    """Standalone process that runs DistractionDetector (YOLO) inference.

    On Linux (fork), parent's imports (onnxruntime etc.) are already available.
    Reads (frame_bytes, shape, face_bbox) from in_q, writes
    (phone_bbox, bottle_bbox, hand_at_ear) to out_q.
    """
    signal.signal(signal.SIGINT, signal.SIG_IGN)

    try:
        # On Linux (fork), YOLO_AVAILABLE / YOLO_ONNX_AVAILABLE globals are
        # inherited from the parent — skip the expensive re-check.
        if not (YOLO_AVAILABLE or YOLO_ONNX_AVAILABLE):
            _check_yolo()
        detector = DistractionDetector(enabled=enabled)
        print("[YOLOWorker] DistractionDetector loaded in subprocess", flush=True)
    except Exception as e:
        print(f"[YOLOWorker] FATAL: could not load detector: {e}", flush=True)
        return

    while True:
        try:
            msg = in_q.get()
            if msg is None:
                break
            frame_bytes, shape, face_bbox = msg
            frame = np.frombuffer(frame_bytes, dtype=np.uint8).reshape(shape).copy()
            # Run synchronous YOLO inference directly (not the async wrapper)
            if face_bbox is not None:
                detector._last_face_bbox = face_bbox
            result = detector._run_yolo_inference(frame)
            out_q.put(result)  # (phone_bbox, bottle_bbox, hand_at_ear)
        except Exception as e:
            print(f"[YOLOWorker] error: {e}", flush=True)
            try:
                out_q.put(None)
            except Exception:
                pass


class FaceAnalyzerProxy:
    """Drop-in replacement for FaceAnalyzer that delegates to a subprocess.

    Keeps the same process_frame() / shutdown() API so the main loop
    doesn't need to change.  Internally, sends frames to _face_worker_process
    via a Queue and polls for results.
    """

    def __init__(self, mp_max_dim=640):
        self._in_q = multiprocessing.Queue(maxsize=2)
        self._out_q = multiprocessing.Queue(maxsize=2)
        self._proc = multiprocessing.Process(
            target=_face_worker_process,
            args=(self._in_q, self._out_q, mp_max_dim),
            daemon=True,
        )
        self._proc.start()
        self._cached_frame = None
        self._cached_detection = None
        self._pending = False
        self._last_ts = -1

    def process_frame(self, frame, timestamp_ms):
        """Send frame to worker, return latest cached result (non-blocking)."""
        # Check for completed result
        if self._pending:
            try:
                result = self._out_q.get_nowait()
                if result is not None:
                    frame_bytes, shape, det_data = result
                    self._cached_frame = (
                        np.frombuffer(frame_bytes, dtype=np.uint8).reshape(shape).copy()
                    )
                    # Rebuild face_crop from bytes
                    if det_data and det_data.get("_face_crop_bytes") is not None:
                        det_data["face_crop"] = (
                            np.frombuffer(det_data["_face_crop_bytes"], dtype=np.uint8)
                            .reshape(det_data["_face_crop_shape"])
                            .copy()
                        )
                        del det_data["_face_crop_bytes"]
                        del det_data["_face_crop_shape"]
                    self._cached_detection = det_data
                self._pending = False
            except Exception:
                pass  # queue empty, still waiting

        # Submit new frame if worker is free
        if not self._pending and timestamp_ms > self._last_ts:
            self._last_ts = timestamp_ms
            try:
                self._in_q.put_nowait((frame.tobytes(), frame.shape, timestamp_ms))
                self._pending = True
            except Exception:
                pass  # queue full, skip this frame

        if self._cached_frame is not None:
            return self._cached_frame, self._cached_detection
        return frame, None

    def shutdown(self):
        try:
            self._in_q.put_nowait(None)
        except Exception:
            pass
        self._proc.join(timeout=3)
        if self._proc.is_alive():
            self._proc.terminate()


class DistractionDetectorProxy:
    """Drop-in replacement for DistractionDetector that delegates YOLO to a subprocess.

    The main-process side handles smoothing state (sliding windows, cooldowns,
    drawing) — only the heavy _run_yolo_inference runs in the subprocess.
    """

    def __init__(self, enabled=True):
        self.enabled = enabled
        self._in_q = multiprocessing.Queue(maxsize=2)
        self._out_q = multiprocessing.Queue(maxsize=2)
        self._proc = multiprocessing.Process(
            target=_yolo_worker_process,
            args=(self._in_q, self._out_q, enabled),
            daemon=True,
        )
        self._proc.start()

        # All smoothing/drawing state lives in the main process
        self.phone_detected = False
        self.drinking_detected = False
        self.phone_bbox = None
        self.bottle_bbox = None
        self.hand_at_ear = False

        self._PHONE_WINDOW = 6
        self._PHONE_MIN_HITS = 2
        self._phone_window = deque(maxlen=self._PHONE_WINDOW)
        self._drink_window = deque(maxlen=self._PHONE_WINDOW)
        self.phone_frames = 0
        self.drinking_frames = 0
        self._PHONE_COOLDOWN_SECS = 3.0
        self._phone_last_seen = 0.0

        self._pending = False
        self._yolo_times = deque(maxlen=50)
        self._yolo_completions = 0
        self._submit_time = 0.0
        self._yolo_upscale = 1.0
        self._onnx_img_size = 640

    def detect(self, frame, face_bbox=None):
        """Submit frame to YOLO subprocess, return smoothed cached results."""
        if not self.enabled:
            return {
                "phone_detected": False,
                "drinking_detected": False,
                "phone_bbox": None,
                "bottle_bbox": None,
                "phone_frames": 0,
                "drinking_frames": 0,
                "hand_at_ear": False,
            }

        # Check for completed result
        new_phone = None
        new_bottle = None
        is_hand_at_ear = False
        has_result = False

        if self._pending:
            try:
                result = self._out_q.get_nowait()
                if result is not None:
                    new_phone, new_bottle, is_hand_at_ear = result
                    elapsed = time.time() - self._submit_time
                    self._yolo_times.append(elapsed)
                    self._yolo_completions += 1
                has_result = True
                self._pending = False
            except Exception:
                pass

        # Submit new frame
        if not self._pending:
            h, w = frame.shape[:2]
            max_dim = max(h, w)
            if max_dim > self._onnx_img_size:
                self._yolo_upscale = max_dim / self._onnx_img_size
                yolo_frame = cv2.resize(
                    frame,
                    (int(w / self._yolo_upscale), int(h / self._yolo_upscale)),
                    interpolation=cv2.INTER_LINEAR,
                )
            else:
                self._yolo_upscale = 1.0
                yolo_frame = frame

            try:
                self._in_q.put_nowait(
                    (yolo_frame.tobytes(), yolo_frame.shape, face_bbox)
                )
                self._pending = True
                self._submit_time = time.time()
            except Exception:
                pass

        # Update smoothing
        if has_result:
            s = self._yolo_upscale
            if s != 1.0:
                if new_phone is not None:
                    new_phone = tuple(int(v * s) for v in new_phone)
                if new_bottle is not None:
                    new_bottle = tuple(int(v * s) for v in new_bottle)
            now = time.time()

            self._phone_window.append(new_phone is not None)
            self._drink_window.append(new_bottle is not None)

            if new_phone is not None:
                self.phone_bbox = new_phone
                self.hand_at_ear = is_hand_at_ear
                self._phone_last_seen = now
            elif not any(self._phone_window):
                self.phone_bbox = None
                self.hand_at_ear = False

            if new_bottle is not None:
                self.bottle_bbox = new_bottle
            elif not any(self._drink_window):
                self.bottle_bbox = None

            self.phone_frames = sum(self._phone_window)
            self.drinking_frames = sum(self._drink_window)

            raw_phone = self.phone_frames >= self._PHONE_MIN_HITS
            if raw_phone:
                self.phone_detected = True
                self._phone_last_seen = now
            elif now - self._phone_last_seen < self._PHONE_COOLDOWN_SECS:
                self.phone_detected = True
            else:
                self.phone_detected = False

            self.drinking_detected = self.drinking_frames >= self._PHONE_MIN_HITS

        return {
            "phone_detected": self.phone_detected,
            "drinking_detected": self.drinking_detected,
            "phone_bbox": self.phone_bbox,
            "bottle_bbox": self.bottle_bbox,
            "phone_frames": self.phone_frames,
            "drinking_frames": self.drinking_frames,
            "hand_at_ear": self.hand_at_ear,
        }

    def get_yolo_stats(self):
        if not self._yolo_times:
            return 0.0, 0.0, self._yolo_completions
        avg = sum(self._yolo_times) / len(self._yolo_times)
        fps = 1.0 / avg if avg > 0 else 0.0
        return avg * 1000, fps, self._yolo_completions

    def reset_yolo_stats(self):
        self._yolo_completions = 0

    def draw_detections(self, frame):
        """Draw detection boxes on frame."""
        if self.phone_bbox:
            x1, y1, x2, y2 = self.phone_bbox
            color = COLOR_RED if self.phone_detected else COLOR_ORANGE
            cv2.rectangle(frame, (x1, y1), (x2, y2), color, 2)
            hits = f"{self.phone_frames}/{self._PHONE_WINDOW}"
            if self.hand_at_ear:
                label = (
                    f"PHONE (HAND {hits})!"
                    if self.phone_detected
                    else f"Hand near face ({hits})"
                )
            else:
                label = (
                    f"PHONE ({hits}) - DISTRACTED!"
                    if self.phone_detected
                    else f"Phone ({hits})"
                )
            cv2.putText(frame, label, (x1, y1 - 10), FONT_FAST, 1.0, color, 1)

        if self.bottle_bbox:
            x1, y1, x2, y2 = self.bottle_bbox
            color = COLOR_ORANGE if self.drinking_detected else (255, 165, 0)
            cv2.rectangle(frame, (x1, y1), (x2, y2), color, 2)
            label = "DRINKING!" if self.drinking_detected else "Bottle/Cup"
            cv2.putText(frame, label, (x1, y1 - 10), FONT_FAST, 1.0, color, 1)

        return frame

    def shutdown(self):
        try:
            self._in_q.put_nowait(None)
        except Exception:
            pass
        self._proc.join(timeout=3)
        if self._proc.is_alive():
            self._proc.terminate()


class ThreadedCamera:
    """Threaded camera capture for non-blocking frame reads.

    Reads frames in a dedicated background thread so the main processing
    loop never blocks waiting for the next camera frame from the sensor.
    This decouples capture rate from processing rate.
    """

    def __init__(self, camera_index=0):
        self.cap = cv2.VideoCapture(camera_index)
        self.cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
        self._frame = None
        self._ret = False
        self._lock = threading.Lock()
        self._running = False
        self._thread = None
        self._frame_seq = 0  # incremented on each new camera frame

    def isOpened(self):
        return self.cap.isOpened()

    def start(self):
        """Read first frame synchronously, then start background capture."""
        self._ret, self._frame = self.cap.read()
        self._running = True
        self._thread = threading.Thread(target=self._capture_loop, daemon=True)
        self._thread.start()
        return self

    def _capture_loop(self):
        while self._running:
            ret, frame = self.cap.read()
            with self._lock:
                self._ret = ret
                self._frame = frame
                if ret:
                    self._frame_seq += 1

    def read(self):
        """Return the latest frame instantly (non-blocking)."""
        with self._lock:
            return self._ret, self._frame

    @property
    def frame_count(self):
        """Number of unique frames captured from the camera hardware."""
        with self._lock:
            return self._frame_seq

    def get(self, prop):
        return self.cap.get(prop)

    def set(self, prop, val):
        return self.cap.set(prop, val)

    def release(self):
        self._running = False
        if self._thread:
            self._thread.join(timeout=2)
        self.cap.release()


class VideoStreamer:
    """Uploads annotated video frames to Supabase Storage for remote viewing.

    After each upload, broadcasts a Realtime notification so the iOS app
    can fetch the new frame immediately instead of polling.
    """

    BUCKET = "live-frames"

    def __init__(
        self,
        supabase_client,
        vehicle_id: str,
        quality: int = 50,
        fps: int = 3,
        width: int = 640,
    ):
        self.client = supabase_client
        self.vehicle_id = vehicle_id
        self.quality = quality
        self.min_interval = 1.0 / fps
        self.target_width = width
        self._path = f"{vehicle_id}/latest.jpg"
        self._last_upload = 0
        self._uploading = False
        self._lock = threading.Lock()

        # Realtime broadcast endpoint for notifying iOS clients
        supabase_url = os.environ.get("SUPABASE_URL", "")
        supabase_key = os.environ.get("SUPABASE_SECRET_KEY", "")
        self._broadcast_url = f"{supabase_url}/realtime/v1/api/broadcast"
        self._broadcast_headers = {
            "apikey": supabase_key,
            "Content-Type": "application/json",
        }
        self._broadcast_topic = f"live-frames:{vehicle_id}"

    def start(self):
        # Ensure the storage bucket exists (requires service-role key)
        try:
            self.client.storage.create_bucket(
                self.BUCKET,
                options={"public": True, "file_size_limit": 1_000_000},
            )
            print(f"Created storage bucket: {self.BUCKET}")
        except Exception:
            pass  # Bucket already exists

        fps_display = 1.0 / self.min_interval
        print(
            f"Video stream active — uploading to Supabase Storage "
            f"(bucket={self.BUCKET}, ~{fps_display:.0f} fps, "
            f"quality={self.quality}, width={self.target_width})"
        )

    def stop(self):
        # Wait for any in-flight upload to finish
        for _ in range(20):
            with self._lock:
                if not self._uploading:
                    break
            time.sleep(0.1)

        # Remove the live frame on shutdown
        try:
            self.client.storage.from_(self.BUCKET).remove([self._path])
        except Exception:
            pass
        print("Video stream stopped")

    def update_frame(self, frame):
        """Queue frame for background encode + upload (non-blocking)."""
        current_time = time.time()
        if current_time - self._last_upload < self.min_interval:
            return

        with self._lock:
            if self._uploading:
                return  # Previous upload still in progress
            self._uploading = True

        self._last_upload = current_time

        # Encode + upload entirely in background thread to avoid blocking main loop
        threading.Thread(
            target=self._encode_and_upload, args=(frame,), daemon=True
        ).start()

    def _encode_and_upload(self, frame):
        """Resize, JPEG-encode, and upload — runs in background thread."""
        try:
            h, w = frame.shape[:2]
            if w > self.target_width:
                scale = self.target_width / w
                frame = cv2.resize(
                    frame,
                    (self.target_width, int(h * scale)),
                    interpolation=cv2.INTER_AREA,
                )

            _, buffer = cv2.imencode(
                ".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, self.quality]
            )
            image_bytes = buffer.tobytes()
            self._upload(image_bytes)
        except Exception:
            with self._lock:
                self._uploading = False

    def _upload(self, image_bytes: bytes):
        try:
            self.client.storage.from_(self.BUCKET).upload(
                path=self._path,
                file=image_bytes,
                file_options={"content-type": "image/jpeg", "x-upsert": "true"},
            )
            # Notify iOS clients via Realtime broadcast (fire-and-forget)
            self._broadcast_new_frame()
        except Exception:
            pass  # Silently skip failed uploads to avoid log spam
        finally:
            with self._lock:
                self._uploading = False

    def _broadcast_new_frame(self):
        """Send a lightweight Realtime broadcast so iOS clients fetch immediately."""
        try:
            body = json.dumps(
                {
                    "messages": [
                        {
                            "topic": self._broadcast_topic,
                            "event": "new_frame",
                            "payload": {},
                        }
                    ]
                }
            ).encode()
            req = urllib.request.Request(
                self._broadcast_url,
                data=body,
                headers=self._broadcast_headers,
                method="POST",
            )
            urllib.request.urlopen(req, timeout=2)
        except Exception:
            pass  # Non-critical — iOS falls back to polling


class DashcamRecorder:
    """Records annotated camera frames to a local MP4 file.

    Uses a single background writer thread with a queue. Records all frames
    continuously without time-gating to ensure smooth, real-time playback.
    """

    def __init__(self, output_dir="recordings", fps=30, max_width=640):
        self.output_dir = output_dir
        self.fps = fps  # Target FPS for video writer (should match camera)
        self.max_width = max_width
        self.writer = None
        self.filepath = None
        self._queue = None  # set in start()
        self._thread = None
        self._running = False
        self._frame_count = 0

    def start(self, trip_id, width, height):
        """Start recording to {output_dir}/{trip_id}.mp4"""
        import queue as _queue_mod

        os.makedirs(self.output_dir, exist_ok=True)
        self.filepath = os.path.join(self.output_dir, f"{trip_id}.mp4")

        # Downscale recording resolution to reduce I/O + CPU
        if width > self.max_width:
            scale = self.max_width / width
            rec_w = self.max_width
            rec_h = int(height * scale)
        else:
            rec_w, rec_h = width, height
        self._rec_size = (rec_w, rec_h)
        self._need_resize = rec_w != width or rec_h != height

        # Use H.264 codec for better compatibility and performance
        fourcc = cv2.VideoWriter_fourcc(*"mp4v")
        self.writer = cv2.VideoWriter(self.filepath, fourcc, self.fps, (rec_w, rec_h))
        self._queue = _queue_mod.Queue(maxsize=120)  # Increased buffer for 30 FPS
        self._running = True
        self._frame_count = 0
        self._thread = threading.Thread(target=self._writer_loop, daemon=True)
        self._thread.start()
        print(f"Dashcam recording: {self.filepath} ({rec_w}x{rec_h} @ {self.fps} fps)")

    def write_frame(self, frame, hud_data=None):
        """Accept a frame for recording (non-blocking).

        Enqueues every frame for continuous recording without time-gating.
        Drops frames only if the queue is full.
        """
        if not self._running or self._queue is None:
            return

        try:
            self._queue.put_nowait((frame.copy(), hud_data))
            self._frame_count += 1
        except Exception:
            pass  # queue full — drop frame

    def _writer_loop(self):
        """Background thread: drain queue and write frames to disk."""
        while self._running or (self._queue and not self._queue.empty()):
            try:
                frame, hud_data = self._queue.get(timeout=0.5)
            except Exception:
                continue
            try:
                if self._need_resize:
                    frame = cv2.resize(
                        frame, self._rec_size, interpolation=cv2.INTER_AREA
                    )
                if hud_data:
                    draw_dashcam_hud(frame, **hud_data)
                if self.writer and self.writer.isOpened():
                    self.writer.write(frame)
            except Exception as e:
                print(f"[Dashcam] write error: {e}")

    def stop(self):
        """Stop recording — drain remaining frames then release."""
        self._running = False
        if self._thread:
            self._thread.join(timeout=5)
            self._thread = None
        if self.writer:
            self.writer.release()
            self.writer = None
            if self.filepath and os.path.exists(self.filepath):
                size_mb = os.path.getsize(self.filepath) / (1024 * 1024)
                print(f"Dashcam saved: {self.filepath} ({size_mb:.1f} MB)")


class SupabaseUploader:
    """Handles uploading face detection data and vehicle telemetry to Supabase"""

    def __init__(self, buzzer_controller=None):
        # Load from environment variables
        supabase_url = os.environ.get("SUPABASE_URL")
        supabase_key = os.environ.get("SUPABASE_SECRET_KEY")
        self.vehicle_id = os.environ.get("VEHICLE_ID")
        self.vehicle_name = os.environ.get("VEHICLE_NAME", "Unknown Vehicle")
        self.buzzer = buzzer_controller

        if not supabase_url:
            raise RuntimeError(
                "SUPABASE_URL not found. Please set it in your .env file."
            )
        if not supabase_key:
            raise RuntimeError(
                "SUPABASE_KEY not found. Please set it in your .env file."
            )
        if not self.vehicle_id:
            raise RuntimeError("VEHICLE_ID not found. Please set it in your .env file.")

        from supabase import create_client

        self.client = create_client(supabase_url, supabase_key)
        self.session_id = str(uuid.uuid4())
        self.last_upload_time = 0
        self.last_realtime_update = 0
        self.upload_cooldown = 2.0  # Minimum seconds between face uploads
        self.realtime_cooldown = 0.5  # Update realtime every 500ms

        # Shared thread pool for all background I/O (replaces per-call Thread spawns)
        self._executor = ThreadPoolExecutor(max_workers=4)

        # Background thread guards to prevent blocking the main loop
        self._realtime_busy = False
        self._upload_busy = False
        self._buzzer_check_busy = False
        self._trip_sync_busy = False
        self._music_upload_busy = False

        # Latest records for BLE relay (iOS uploads to Supabase on Pi's behalf)
        self.latest_realtime_record = {}
        self.latest_trip_record = {}

        # Trip tracking
        self.trip_id = None
        self.trip_max_speed = 0
        self.trip_max_intox_score = 0
        self.trip_speeding_events = 0
        self.trip_drowsy_events = 0
        self.trip_excessive_blinking_events = 0
        self.trip_unstable_eyes_events = 0
        self.trip_face_detections = 0
        self.trip_speed_samples = []
        self.trip_waypoints = []
        self.last_trip_update = 0
        self.trip_update_cooldown = 5.0  # Update trip stats every 5 seconds
        self.was_speeding = False  # Track speeding state changes
        self.was_drowsy = False  # Track drowsy state changes
        self.was_excessive_blinking = False  # Track excessive blinking state changes
        self.was_unstable_eyes = False  # Track unstable eyes state changes
        self.trip_crash_detected = False
        self.trip_crash_severity = None

        # Register vehicle on startup — allow offline operation
        try:
            self._register_vehicle()
            # After vehicle registered, these two are independent — run in parallel
            with ThreadPoolExecutor(max_workers=2) as pool:
                futures = [
                    pool.submit(self._fetch_feature_settings),
                    pool.submit(self._create_trip),
                ]
                for f in futures:
                    f.result()
            self._subscribe_to_buzzer_commands()
            self._connected = True
            print(
                f"Supabase connected. Vehicle ID: {self.vehicle_id}, Session ID: {self.session_id}"
            )
        except Exception as e:
            self._connected = False
            print(f"Supabase unavailable ({e.__class__.__name__}), running offline")
            self._fetch_feature_settings()  # still loads .env defaults

    def _generate_invite_code(self):
        """Generate a random 6-character alphanumeric invite code"""
        chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return "".join(random.choice(chars) for _ in range(6))

    def _register_vehicle(self):
        """Register or update vehicle in database on startup"""
        try:
            # Check if vehicle exists
            existing = (
                self.client.table("vehicles")
                .select("id, invite_code")
                .eq("id", self.vehicle_id)
                .execute()
            )

            if existing.data:
                # Vehicle exists, update name if changed
                self.client.table("vehicles").update(
                    {
                        "name": self.vehicle_name,
                        "updated_at": datetime.now(PST).isoformat(),
                    }
                ).eq("id", self.vehicle_id).execute()
                invite_code = existing.data[0]["invite_code"]
                print(f"Vehicle registered. Invite code: {invite_code}")
            else:
                # Create new vehicle with invite code
                invite_code = self._generate_invite_code()
                self.client.table("vehicles").insert(
                    {
                        "id": self.vehicle_id,
                        "name": self.vehicle_name,
                        "invite_code": invite_code,
                    }
                ).execute()
                print(f"New vehicle created. Invite code: {invite_code}")

            # Initialize realtime record
            self.client.table("vehicle_realtime").upsert(
                {
                    "vehicle_id": self.vehicle_id,
                    "updated_at": datetime.now(PST).isoformat(),
                }
            ).execute()

        except Exception as e:
            print(f"Error registering vehicle: {e}")
            raise

    def _fetch_feature_settings(self):
        """Fetch feature toggle settings from the Supabase vehicles table.

        Priority: .env explicit override > Supabase > default.
        If a key is explicitly set in .env, it always wins.
        """
        supabase_settings = {}
        try:
            response = (
                self.client.table("vehicles")
                .select(
                    "enable_yolo, enable_stream, enable_shazam, "
                    "enable_microphone, enable_camera, enable_dashcam"
                )
                .eq("id", self.vehicle_id)
                .execute()
            )
            if response.data:
                supabase_settings = response.data[0]
        except Exception as e:
            print(f"Warning: Could not fetch feature settings from Supabase: {e}")

        # Merge: .env override > Supabase > default
        # Each tuple: (env_value, env_was_set, supabase_key, default)
        _toggles = {
            "enable_stream": (
                _ENV_ENABLE_STREAM,
                _ENV_STREAM_SET,
                "enable_stream",
                True,
            ),
            "enable_shazam": (
                _ENV_ENABLE_SHAZAM,
                _ENV_SHAZAM_SET,
                "enable_shazam",
                True,
            ),
            "enable_microphone": (
                _ENV_ENABLE_MICROPHONE,
                _ENV_MIC_SET,
                "enable_microphone",
                True,
            ),
            "enable_dashcam": (
                _ENV_ENABLE_DASHCAM,
                _ENV_DASHCAM_SET,
                "enable_dashcam",
                True,
            ),
        }

        self.feature_settings = {}
        print("Feature settings:")
        for key, (env_val, env_set, sb_key, default) in _toggles.items():
            if env_set:
                val = env_val
                source = ".env override"
            elif sb_key in supabase_settings:
                val = supabase_settings[sb_key]
                source = "Supabase"
            else:
                val = default
                source = "default"

            self.feature_settings[key] = val
            print(f"  {key}: {val}  ({source})", flush=True)

        # Camera and YOLO are always enabled
        self.feature_settings["enable_yolo"] = True
        self.feature_settings["enable_camera"] = True
        print(
            f"  enable_yolo: {self.feature_settings['enable_yolo']}  (always on)",
            flush=True,
        )
        print(
            f"  enable_camera: {self.feature_settings['enable_camera']}  (always on)",
            flush=True,
        )

    def generate_face_embedding(self, face_image: np.ndarray) -> list | None:
        """Generate a 128-dimensional face embedding from a face image.

        Args:
            face_image: BGR image containing a face (from OpenCV)

        Returns:
            List of 128 floats representing the face embedding, or None if no face found
        """
        # Temporarily disabled due to dlib compilation issues
        return None

        # try:
        #     # Convert BGR to RGB (face_recognition expects RGB)
        #     rgb_image = cv2.cvtColor(face_image, cv2.COLOR_BGR2RGB)

        #     # Get face encodings (128-dimensional embedding)
        #     # We use the 'large' model for better accuracy
        #     encodings = face_recognition.face_encodings(
        #         rgb_image,
        #         known_face_locations=None,  # Let it detect the face
        #         num_jitters=1,  # Slightly re-sample face for better accuracy
        #         model="large",
        #     )

        #     if encodings:
        #         # Return the first face encoding as a list
        #         return encodings[0].tolist()
        #     else:
        #         # No face detected by face_recognition
        #         # Try with the full image assuming it's already cropped to a face
        #         # Use a face location covering the whole image
        #         h, w = rgb_image.shape[:2]
        #         face_location = [(0, w, h, 0)]  # top, right, bottom, left
        #         encodings = face_recognition.face_encodings(
        #             rgb_image,
        #             known_face_locations=face_location,
        #             num_jitters=1,
        #             model="large",
        #         )
        #         if encodings:
        #             return encodings[0].tolist()

        #     return None
        # except Exception as e:
        #     print(f"Error generating face embedding: {e}")
        #     return None

    def find_or_create_cluster(self, embedding: list) -> str | None:
        """Find a matching face cluster or create a new one.

        Uses the Supabase function to find similar faces and return a cluster_id.

        Args:
            embedding: 128-dimensional face embedding

        Returns:
            UUID string of the cluster, or None on error
        """
        try:
            # Format embedding as PostgreSQL vector string
            embedding_str = "[" + ",".join(str(x) for x in embedding) + "]"

            # Call the Supabase function to find or create cluster
            response = self.client.rpc(
                "find_or_create_face_cluster",
                {
                    "p_vehicle_id": self.vehicle_id,
                    "p_embedding": embedding_str,
                    "p_similarity_threshold": 0.6,  # Faces with >60% similarity are clustered
                },
            ).execute()

            if response.data:
                return response.data
            return None
        except Exception as e:
            print(f"Error finding/creating cluster: {e}")
            return None

    def _create_trip(self):
        """Create a new trip record for this session"""
        try:
            record = {
                "vehicle_id": self.vehicle_id,
                "session_id": self.session_id,
                "started_at": datetime.now(PST).isoformat(),
                "status": "ok",
            }

            response = self.client.table("vehicle_trips").insert(record).execute()

            if response.data and len(response.data) > 0:
                self.trip_id = response.data[0]["id"]
                print(f"Trip created: {self.trip_id}")
            else:
                print("Warning: Trip created but no ID returned")

        except Exception as e:
            print(f"Error creating trip: {e}")

    def _calculate_trip_status(self):
        """Calculate trip status based on max intoxication score"""
        if self.trip_max_intox_score >= 4:
            return "danger"
        elif self.trip_max_intox_score >= 2:
            return "warning"
        return "ok"

    def record_crash(self, crash_event):
        """Record a crash detection event on the current trip."""
        self.trip_crash_detected = True
        self.trip_crash_severity = crash_event.get("severity", "moderate")
        # Force an immediate sync to persist crash data
        self._sync_trip_to_db()

    def update_trip_stats(
        self,
        speed: int,
        intox_score: int,
        is_speeding: bool,
        is_drowsy: bool,
        is_excessive_blinking: bool,
        is_unstable_eyes: bool,
        latitude: float = 0.0,
        longitude: float = 0.0,
        is_real_gps: bool = False,
    ):
        """Update trip statistics (called frequently during session)"""
        # Track max values
        self.trip_max_speed = max(self.trip_max_speed, speed)
        self.trip_max_intox_score = max(self.trip_max_intox_score, intox_score)

        # Track speed samples for average
        self.trip_speed_samples.append(speed)

        # Count speeding events (only when transitioning to speeding)
        if is_speeding and not self.was_speeding:
            self.trip_speeding_events += 1
        self.was_speeding = is_speeding

        # Count drowsy events (only when transitioning to drowsy)
        if is_drowsy and not self.was_drowsy:
            self.trip_drowsy_events += 1
        self.was_drowsy = is_drowsy

        # Count excessive blinking events (only when transitioning)
        if is_excessive_blinking and not self.was_excessive_blinking:
            self.trip_excessive_blinking_events += 1
        self.was_excessive_blinking = is_excessive_blinking

        # Count unstable eyes events (only when transitioning)
        if is_unstable_eyes and not self.was_unstable_eyes:
            self.trip_unstable_eyes_events += 1
        self.was_unstable_eyes = is_unstable_eyes

        # Record GPS waypoint (only with real satellite fix)
        if is_real_gps and latitude != 0.0 and longitude != 0.0:
            self.trip_waypoints.append(
                {
                    "lat": round(latitude, 6),
                    "lng": round(longitude, 6),
                    "spd": int(speed),
                    "ts": int(time.time()),
                }
            )

        # Periodically update trip in database
        current_time = time.time()
        if current_time - self.last_trip_update >= self.trip_update_cooldown:
            self._sync_trip_to_db()
            self.last_trip_update = current_time

    def _sync_trip_to_db(self):
        """Sync current trip stats to database (non-blocking)"""
        if not self.trip_id:
            return
        if self._trip_sync_busy:
            return

        self._trip_sync_busy = True

        # Snapshot values to avoid races with main thread
        avg_speed = (
            sum(self.trip_speed_samples) / len(self.trip_speed_samples)
            if self.trip_speed_samples
            else 0
        )
        record = {
            "max_speed_mph": int(self.trip_max_speed),
            "avg_speed_mph": float(round(avg_speed, 2)),
            "max_intoxication_score": int(self.trip_max_intox_score),
            "speeding_event_count": int(self.trip_speeding_events),
            "drowsy_event_count": int(self.trip_drowsy_events),
            "excessive_blinking_event_count": int(self.trip_excessive_blinking_events),
            "unstable_eyes_event_count": int(self.trip_unstable_eyes_events),
            "face_detection_count": int(self.trip_face_detections),
            "speed_sample_count": len(self.trip_speed_samples),
            "speed_sample_sum": int(sum(self.trip_speed_samples)),
            "status": self._calculate_trip_status(),
            "route_waypoints": self.trip_waypoints,
            "crash_detected": self.trip_crash_detected,
            "crash_severity": self.trip_crash_severity,
        }
        trip_id = self.trip_id

        # Store for BLE relay (iOS can upload on Pi's behalf when offline)
        # Exclude route_waypoints — too large for BLE MTU
        relay_record = {k: v for k, v in record.items() if k != "route_waypoints"}
        relay_record["id"] = trip_id
        self.latest_trip_record = relay_record

        def _do_sync():
            try:
                self.client.table("vehicle_trips").update(record).eq(
                    "id", trip_id
                ).execute()
            except Exception as e:
                print(f"Error syncing trip stats: {e}")
            finally:
                self._trip_sync_busy = False

        self._executor.submit(_do_sync)

    def end_trip(self):
        """End the current trip (called on session end)"""
        if not self.trip_id:
            return

        try:
            avg_speed = (
                sum(self.trip_speed_samples) / len(self.trip_speed_samples)
                if self.trip_speed_samples
                else 0
            )

            record = {
                "ended_at": datetime.now(PST).isoformat(),
                "max_speed_mph": int(self.trip_max_speed),
                "avg_speed_mph": float(round(avg_speed, 2)),
                "max_intoxication_score": int(self.trip_max_intox_score),
                "speeding_event_count": int(self.trip_speeding_events),
                "drowsy_event_count": int(self.trip_drowsy_events),
                "excessive_blinking_event_count": int(
                    self.trip_excessive_blinking_events
                ),
                "unstable_eyes_event_count": int(self.trip_unstable_eyes_events),
                "face_detection_count": int(self.trip_face_detections),
                "speed_sample_count": len(self.trip_speed_samples),
                "speed_sample_sum": int(sum(self.trip_speed_samples)),
                "status": self._calculate_trip_status(),
                "route_waypoints": self.trip_waypoints,
                "crash_detected": self.trip_crash_detected,
                "crash_severity": self.trip_crash_severity,
            }

            self.client.table("vehicle_trips").update(record).eq(
                "id", self.trip_id
            ).execute()
            print(
                f"Trip ended: {self.trip_id} (Status: {self._calculate_trip_status()})"
            )

        except Exception as e:
            print(f"Error ending trip: {e}")

    def reset_vehicle_realtime(self):
        """Reset vehicle_realtime to parked/idle state (called on session end)"""
        try:
            record = {
                "vehicle_id": self.vehicle_id,
                "updated_at": datetime.now(PST).isoformat(),
                "speed_mph": 0,
                "heading_degrees": 0,
                "compass_direction": "N",
                "is_speeding": False,
                "is_moving": False,
                "driver_status": "unknown",
                "intoxication_score": 0,
                "satellites": 0,
                "is_phone_detected": False,
                "is_drinking_detected": False,
                "current_song_title": None,
                "current_song_artist": None,
                "current_song_detected_at": None,
                "buzzer_active": False,
            }
            self.client.table("vehicle_realtime").upsert(record).execute()
            print(f"Vehicle realtime reset to parked state for {self.vehicle_id}")
        except Exception as e:
            print(f"Error resetting vehicle realtime: {e}")

    def increment_face_detection_count(self):
        """Increment face detection count for current trip"""
        self.trip_face_detections += 1

    def _subscribe_to_buzzer_commands(self):
        """Subscribe to realtime changes in vehicle_realtime for buzzer control

        Note: This uses polling instead of realtime subscriptions due to
        Python Supabase client limitations. Checks for buzzer state every 2 seconds.
        """
        if not self.buzzer:
            print("No buzzer controller available, skipping buzzer polling")
            return

        self.last_buzzer_check = 0
        self.buzzer_check_interval = 2.0  # Check every 2 seconds
        self.last_buzzer_state = False

        print("Remote buzzer control enabled (polling mode)")

    def check_buzzer_commands(self):
        """Poll for buzzer command changes (non-blocking)"""
        if not self.buzzer:
            return

        current_time = time.time()
        if current_time - self.last_buzzer_check < self.buzzer_check_interval:
            return
        if self._buzzer_check_busy:
            return

        self._buzzer_check_busy = True
        self.last_buzzer_check = current_time

        def _do_check():
            try:
                response = (
                    self.client.table("vehicle_realtime")
                    .select("buzzer_active, buzzer_type")
                    .eq("vehicle_id", self.vehicle_id)
                    .execute()
                )

                if response.data and len(response.data) > 0:
                    buzzer_active = response.data[0].get("buzzer_active", False)
                    buzzer_type = response.data[0].get("buzzer_type", "alert")

                    if buzzer_active != self.last_buzzer_state:
                        if buzzer_active:
                            print(
                                f"\n>>> REMOTE BUZZER ACTIVATED ({buzzer_type}) <<<\n"
                            )
                            self.buzzer.start_continuous(buzzer_type)
                        else:
                            print("\n>>> REMOTE BUZZER DEACTIVATED <<<\n")
                            self.buzzer.stop_continuous()

                        self.last_buzzer_state = buzzer_active

            except Exception as e:
                print(f"Error checking buzzer commands: {e}")
            finally:
                self._buzzer_check_busy = False

        self._executor.submit(_do_check)

    def upload_music_detection(self, song_info: dict):
        """Upload detected music to Supabase (non-blocking)

        Args:
            song_info: Dictionary with song information from Shazam
                {title, artist, album, release_year, genres, shazam_url, etc.}
        """
        if not song_info:
            return
        if self._music_upload_busy:
            return

        self._music_upload_busy = True

        # Snapshot data to avoid races
        record = {
            "vehicle_id": self.vehicle_id,
            "session_id": self.session_id,
            "title": song_info.get("title", "Unknown"),
            "artist": song_info.get("artist", "Unknown Artist"),
            "detected_at": datetime.now(PST).isoformat(),
        }

        # Optional fields
        if "album" in song_info:
            record["album"] = song_info["album"]
        if "release_year" in song_info:
            record["release_year"] = song_info["release_year"]
        if "genres" in song_info:
            record["genres"] = song_info["genres"]
        if "label" in song_info:
            record["label"] = song_info["label"]
        if "shazam_url" in song_info:
            record["shazam_url"] = song_info["shazam_url"]
        if "apple_music_url" in song_info:
            record["apple_music_url"] = song_info["apple_music_url"]
        if "spotify_url" in song_info:
            record["spotify_url"] = song_info["spotify_url"]

        def _do_upload():
            try:
                # Insert music detection
                self.client.table("music_detections").insert(record).execute()

                # Update vehicle_realtime with current song
                self.client.table("vehicle_realtime").upsert(
                    {
                        "vehicle_id": self.vehicle_id,
                        "current_song_title": record["title"],
                        "current_song_artist": record["artist"],
                        "current_song_detected_at": record["detected_at"],
                        "updated_at": datetime.now(PST).isoformat(),
                    }
                ).execute()

                print(f"\n🎵 Detected: {record['title']} by {record['artist']}")

            except Exception as e:
                print(f"Error uploading music detection: {e}")
            finally:
                self._music_upload_busy = False

        self._executor.submit(_do_upload)

    def update_vehicle_realtime(
        self,
        speed_mph: int,
        heading_degrees: int,
        compass_direction: str,
        is_speeding: bool,
        driver_status: str = "unknown",
        intoxication_score: int = 0,
        latitude: float = None,
        longitude: float = None,
        satellites: int = 0,
        is_phone_detected: bool = False,
        is_drinking_detected: bool = False,
    ):
        """Update vehicle real-time location/status (non-blocking)"""
        current_time = time.time()
        if current_time - self.last_realtime_update < self.realtime_cooldown:
            return None
        if self._realtime_busy:
            return None

        self._realtime_busy = True
        self.last_realtime_update = current_time

        # Convert to native Python types to ensure JSON serialization
        record = {
            "vehicle_id": self.vehicle_id,
            "updated_at": datetime.now(PST).isoformat(),
            "speed_mph": int(speed_mph),
            "heading_degrees": int(heading_degrees),
            "compass_direction": str(compass_direction),
            "is_speeding": bool(is_speeding),
            "is_moving": bool(speed_mph > 0),
            "driver_status": str(driver_status),
            "intoxication_score": int(intoxication_score),
            "is_phone_detected": bool(is_phone_detected),
            "is_drinking_detected": bool(is_drinking_detected),
        }

        # Add GPS coordinates if available
        if latitude is not None and longitude is not None:
            record["latitude"] = float(latitude)
            record["longitude"] = float(longitude)
            record["satellites"] = int(satellites)

        # Store for BLE relay (iOS can upload on Pi's behalf when offline)
        self.latest_realtime_record = record

        def _do_update():
            try:
                self.client.table("vehicle_realtime").upsert(record).execute()
            except Exception as e:
                print(f"Error updating vehicle realtime: {e}")
            finally:
                self._realtime_busy = False

        self._executor.submit(_do_update)

    def should_upload(self):
        """Check if enough time has passed since last upload"""
        current_time = time.time()
        return current_time - self.last_upload_time >= self.upload_cooldown

    def upload_face_detection(
        self,
        face_image: np.ndarray,
        face_bbox: dict,
        left_eye_state: str,
        left_eye_ear: float,
        right_eye_state: str,
        right_eye_ear: float,
        intox_data: dict,
        driving_data: dict = None,
        distraction_data: dict = None,
    ):
        """Upload face snapshot and metadata to Supabase (non-blocking)"""
        if not self.should_upload():
            return None
        if self._upload_busy:
            return None

        self._upload_busy = True
        self.last_upload_time = time.time()

        # Encode image to JPEG bytes on the main thread (needs numpy array)
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
        filename = f"{self.vehicle_id}/{self.session_id}/{timestamp}.jpg"
        _, buffer = cv2.imencode(".jpg", face_image, [cv2.IMWRITE_JPEG_QUALITY, 85])
        image_bytes = buffer.tobytes()

        # Snapshot all data needed for the upload (avoid referencing mutable state later)

        def _do_upload():
            try:
                # Upload image to storage
                self.client.storage.from_("face-snapshots").upload(
                    path=filename,
                    file=image_bytes,
                    file_options={"content-type": "image/jpeg"},
                )

                # Generate face embedding for clustering similar faces
                face_embedding = self.generate_face_embedding(face_image)
                face_cluster_id = None

                if face_embedding:
                    face_cluster_id = self.find_or_create_cluster(face_embedding)

                # Prepare metadata record
                avg_ear = float((left_eye_ear + right_eye_ear) / 2)
                record = {
                    "vehicle_id": self.vehicle_id,
                    "face_bbox": face_bbox,
                    "left_eye_state": left_eye_state,
                    "left_eye_ear": float(round(left_eye_ear, 4)),
                    "right_eye_state": right_eye_state,
                    "right_eye_ear": float(round(right_eye_ear, 4)),
                    "avg_ear": float(round(avg_ear, 4)),
                    "is_drowsy": bool(intox_data.get("drowsy", False)),
                    "is_excessive_blinking": bool(
                        intox_data.get("excessive_blinking", False)
                    ),
                    "is_unstable_eyes": bool(intox_data.get("unstable_eyes", False)),
                    "intoxication_score": int(intox_data.get("score", 0)),
                    "image_path": filename,
                    "session_id": self.session_id,
                }

                if face_embedding:
                    record["face_embedding"] = (
                        "[" + ",".join(str(x) for x in face_embedding) + "]"
                    )
                if face_cluster_id:
                    record["face_cluster_id"] = face_cluster_id

                if driving_data:
                    record["speed_mph"] = int(driving_data.get("speed", 0))
                    record["heading_degrees"] = int(driving_data.get("heading", 0))
                    record["compass_direction"] = str(
                        driving_data.get("direction", "N")
                    )
                    record["is_speeding"] = bool(driving_data.get("is_speeding", False))

                if distraction_data:
                    record["is_phone_detected"] = bool(
                        distraction_data.get("phone_detected", False)
                    )
                    record["is_drinking_detected"] = bool(
                        distraction_data.get("drinking_detected", False)
                    )

                self.client.table("face_detections").insert(record).execute()

            except Exception as e:
                print(f"Error uploading to Supabase: {e}")
            finally:
                self._upload_busy = False

        self._executor.submit(_do_upload)


class DistractionDetector:
    """YOLO-based detector for phone usage and drinking detection.

    Combines YOLO object detection (visible phones) with MediaPipe Hands
    (hand-at-ear gesture) to detect phone usage even when the phone is
    occluded against the ear during a call.

    Supports two backends:
      - **ultralytics** (dev machines with PyTorch): loads .pt models directly
      - **onnxruntime** (RPi / edge): loads .onnx models without PyTorch

    On RPi where PyTorch/ultralytics aren't available, the detector
    automatically falls back to ONNX runtime with the exported nano model.
    """

    # COCO class IDs for driver monitoring
    CELL_PHONE = 67
    BOTTLE = 39
    CUP = 41
    PHONE_CLASSES = {63, 65, 67, 73}  # laptop, remote, cell phone, book
    DRINK_CLASSES = {39, 40, 41}  # bottle, wine glass, cup

    # COCO class names (subset used for logging when running ONNX backend)
    COCO_NAMES = {
        0: "person",
        39: "bottle",
        40: "wine glass",
        41: "cup",
        63: "laptop",
        65: "remote",
        67: "cell phone",
        73: "book",
    }

    # ONNX model candidates: tried in order when ultralytics is unavailable
    _ONNX_CANDIDATES = [
        "yolo-models/yolo26n.onnx",
        "yolo-models/yolo26s.onnx",
        "yolo-models/yolo26m.onnx",
    ]

    def __init__(self, model_path=None, enabled=True):
        """Initialize YOLO model for object detection.

        On macOS (Apple Silicon), prefers ONNX+CoreML for ~3-5x faster inference
        than PyTorch CPU.  Auto-exports .pt → .onnx if needed (one-time).
        On RPi, uses ONNX runtime with CPU provider.
        Falls back to ultralytics PyTorch if ONNX is unavailable.

        Args:
            model_path: Path to YOLO model weights (.pt or .onnx).
                        If None, uses YOLO_MODEL_PATH env var or auto-detects.
            enabled: Whether detection is enabled at all.
        """
        self.enabled = enabled

        # Get model path from env var if not provided.
        # Always use yolo26n (nano) model for optimal performance
        if model_path is None:
            model_path = os.environ.get("YOLO_MODEL_PATH")
        if model_path is None:
            model_path = "yolo-models/yolo26n.pt"

        # Classes relevant to driver monitoring (subset of COCO 80)
        self.TARGET_CLASSES = [0, 39, 40, 41, 63, 65, 67, 73]
        #  0=person, 39=bottle, 40=wine glass, 41=cup,
        # 63=laptop, 65=remote, 67=cell phone, 73=book

        # Pre-computed numpy arrays for vectorized ONNX post-processing
        self._target_set_arr = np.array(self.TARGET_CLASSES, dtype=np.intp)
        self._phone_set_arr = np.array(list(self.PHONE_CLASSES), dtype=np.intp)
        self._drink_set_arr = np.array(list(self.DRINK_CLASSES), dtype=np.intp)

        # Backend state: exactly one of these will be set
        self.model = None  # ultralytics YOLO model (if available)
        self._onnx_session = None  # onnxruntime session (RPi fallback)
        self._onnx_input_name = None
        self._onnx_img_size = 640  # overridden from model metadata
        self._onnx_padded = None  # pre-allocated letterbox buffer
        self._backend = None  # "ultralytics" or "onnx"

        if self.enabled:
            self.confidence_threshold = 0.45

            # --- On macOS, prefer ONNX+CoreML (much faster than PyTorch CPU) ---
            # Try even if no ONNX file exists yet — auto-export will create one.
            if _IS_MACOS:
                try:
                    import onnxruntime  # noqa: F401

                    onnx_path = self._find_or_export_onnx(model_path)
                    if onnx_path and self._try_load_onnx(onnx_path):
                        print("YOLO model loaded (onnx+CoreML, fastest path)")
                except ImportError:
                    pass  # onnxruntime not installed, skip to ultralytics

            # --- Fallback: ultralytics PyTorch (dev machines without ONNX) ---
            if self._backend is None and YOLO_AVAILABLE:
                try:
                    print(f"Loading YOLO model (ultralytics): {model_path}")
                    self.model = YOLO(model_path)
                    self._backend = "ultralytics"
                    print("YOLO model loaded successfully (ultralytics backend)")
                except Exception as e:
                    print(f"  ultralytics YOLO failed: {e}")

            # --- Fallback: ONNX runtime (RPi / edge) ---
            if self._backend is None:
                onnx_path = self._find_onnx_model(model_path)
                if onnx_path:
                    self._try_load_onnx(onnx_path)

            if self._backend is None:
                print("YOLO detection disabled - no backend available")
                self.enabled = False
        else:
            print("YOLO detection disabled - distraction detection unavailable")

        # Detection state
        self.phone_detected = False
        self.drinking_detected = False
        self.phone_bbox = None
        self.bottle_bbox = None
        self.hand_at_ear = False  # True when phone detected via hand-at-ear

        # Two-tier confidence: high confidence anywhere, low confidence near face/hands
        self._phone_conf_high = 0.25  # Phone-class objects anywhere (lowered)
        self._phone_conf_near = 0.15  # Phone-class objects near face/hands (lowered)
        self._drink_conf = 0.30  # Drink-class objects (bottle/cup/wine glass)

        # Sliding window smoothing — phone detected in N of last W frames
        self._PHONE_WINDOW = 4  # Shorter window for faster response
        self._PHONE_MIN_HITS = 1  # Only need 1 detection in window
        self._phone_window = deque(
            maxlen=self._PHONE_WINDOW
        )  # True/False per YOLO frame
        self._drink_window = deque(maxlen=self._PHONE_WINDOW)
        self.phone_frames = 0
        self.drinking_frames = 0

        # Cooldown: once phone_detected goes True, hold it for at least this
        # many seconds before allowing it to drop back to False.
        self._PHONE_COOLDOWN_SECS = 1.5  # Shorter cooldown for faster response
        self._phone_last_seen = 0.0

        # Async YOLO processing — runs inference in a background thread
        # so the main loop is never blocked by model forward pass
        if self.enabled:
            self._yolo_executor = ThreadPoolExecutor(max_workers=1)
        else:
            self._yolo_executor = None
        self._yolo_future = None
        self._yolo_upscale = 1.0  # Scale factor for pre-downscaled frames

        # YOLO performance tracking
        self._yolo_times = deque(maxlen=50)
        self._yolo_completions = 0

        # Hand detection throttling: run every Nth YOLO cycle to save overhead.
        # At ~25 YOLO FPS, interval=8 means hand check ~3x/sec (sufficient for phone detection).
        self._hand_detect_interval = 4  # Run hand detection more frequently
        self._hand_detect_counter = 0

        # MediaPipe Hands for hand-at-ear (phone call) detection.
        # When a phone is held against the ear, YOLO can't see it — but
        # we CAN detect the hand raised to the ear and infer phone usage.
        # Uses Tasks API (same pattern as FaceLandmarker in FaceAnalyzer).
        self.hand_landmarker = None
        self._mp = None  # mediapipe module reference for Image creation
        self._last_face_bbox = None  # Cached face bbox from previous frame
        if self.enabled:
            try:
                import mediapipe as _mp
                from mediapipe.tasks import python as _mp_python
                from mediapipe.tasks.python import vision as _mp_vision

                self._mp = _mp

                base_options = _mp_python.BaseOptions(
                    model_asset_path="hand_landmarker.task"
                )
                options = _mp_vision.HandLandmarkerOptions(
                    base_options=base_options,
                    running_mode=_mp_vision.RunningMode.IMAGE,
                    num_hands=2,
                    min_hand_detection_confidence=0.3,
                    min_hand_presence_confidence=0.3,
                    min_tracking_confidence=0.3,
                )
                self.hand_landmarker = _mp_vision.HandLandmarker.create_from_options(
                    options
                )
                print("MediaPipe HandLandmarker loaded for phone-at-ear detection")
            except Exception as e:
                print(
                    f"MediaPipe Hands not available ({e}) — phone-at-ear detection disabled"
                )

    def _find_onnx_model(self, model_path):
        """Find an ONNX model file, checking the given path and fallback candidates."""
        # If the given path is already .onnx and exists, use it
        if model_path.endswith(".onnx") and os.path.isfile(model_path):
            return model_path
        # Try replacing .pt extension with .onnx
        onnx_variant = model_path.replace(".pt", ".onnx")
        if os.path.isfile(onnx_variant):
            return onnx_variant
        # Try candidates in order (nano first — smallest/fastest for RPi)
        for candidate in self._ONNX_CANDIDATES:
            if os.path.isfile(candidate):
                return candidate
        return None

    def _find_or_export_onnx(self, model_path):
        """Find the matching ONNX model or auto-export from .pt (one-time on macOS).

        Prioritizes the exact matching model (e.g. yolo26m.onnx for yolo26m.pt)
        to preserve accuracy.  Falls back to any available ONNX only if export fails.

        Returns the ONNX path if found or exported, None otherwise.
        """
        # Check if the matching ONNX already exists (e.g. yolo26m.onnx for yolo26m.pt)
        if model_path.endswith(".pt"):
            onnx_variant = model_path.replace(".pt", ".onnx")
            if os.path.isfile(onnx_variant):
                return onnx_variant

        # If model_path is already .onnx, use it directly
        if model_path.endswith(".onnx") and os.path.isfile(model_path):
            return model_path

        # Auto-export .pt → .onnx if ultralytics is available (one-time operation)
        if YOLO_AVAILABLE and model_path.endswith(".pt") and os.path.isfile(model_path):
            try:
                print(
                    f"  Auto-exporting {model_path} → ONNX (one-time, for CoreML acceleration)..."
                )
                exported = YOLO(model_path).export(
                    format="onnx", half=True, simplify=True
                )
                print(f"  Exported: {exported}")
                return str(exported)
            except Exception as e:
                print(f"  Auto-export failed ({e}), will try fallback")

        # Fall back to any available ONNX model
        return self._find_onnx_model(model_path)

    def _try_load_onnx(self, onnx_path):
        """Load an ONNX model with the best available execution provider.

        Returns True if loaded successfully, False otherwise.
        """
        try:
            import onnxruntime as ort

            providers = _get_ort_providers()
            print(f"Loading YOLO model (onnxruntime): {onnx_path}")
            print(f"  Execution providers: {providers}")
            opts = ort.SessionOptions()
            opts.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
            opts.intra_op_num_threads = 4
            opts.inter_op_num_threads = 1
            self._onnx_session = ort.InferenceSession(
                onnx_path,
                sess_options=opts,
                providers=providers,
            )
            inp = self._onnx_session.get_inputs()[0]
            self._onnx_input_name = inp.name
            self._onnx_img_size = inp.shape[2]  # H from [1,3,H,W]
            # Pre-allocate letterbox buffer (reused every inference)
            self._onnx_padded = np.full(
                (self._onnx_img_size, self._onnx_img_size, 3), 114, dtype=np.uint8
            )
            # Pre-allocate float32 blob buffer (avoids allocation each frame)
            self._onnx_blob = np.empty(
                (1, 3, self._onnx_img_size, self._onnx_img_size), dtype=np.float32
            )
            self._backend = "onnx"
            print(f"YOLO model loaded successfully (onnx backend, input {inp.shape})")
            return True
        except Exception as e:
            print(f"  ONNX YOLO failed: {e}")
            return False

    def _run_onnx_inference(self, frame):
        """Run YOLO inference using onnxruntime (no ultralytics/PyTorch needed).

        Handles preprocessing (resize, normalize, NCHW), inference, and
        post-processing (decode boxes, NMS, class filtering).

        Returns:
            list of (class_id, confidence, x1, y1, x2, y2) detections
        """
        orig_h, orig_w = frame.shape[:2]
        img_size = self._onnx_img_size

        # --- Preprocess: resize with letterbox padding ---
        scale = min(img_size / orig_h, img_size / orig_w)
        new_w, new_h = int(orig_w * scale), int(orig_h * scale)
        resized = cv2.resize(frame, (new_w, new_h), interpolation=cv2.INTER_LINEAR)

        # Pad to square (reuse pre-allocated buffer, skip full fill if padding unchanged)
        pad_w = (img_size - new_w) // 2
        pad_h = (img_size - new_h) // 2
        padded = self._onnx_padded
        # Only fill padding strips (not the center) — saves ~1ms for 640x640 buffer
        if pad_h > 0:
            padded[:pad_h, :] = 114
            padded[pad_h + new_h :, :] = 114
        if pad_w > 0:
            padded[pad_h : pad_h + new_h, :pad_w] = 114
            padded[pad_h : pad_h + new_h, pad_w + new_w :] = 114
        padded[pad_h : pad_h + new_h, pad_w : pad_w + new_w] = resized

        # BGR → RGB, HWC → CHW, normalize to 0-1 into pre-allocated blob
        blob = self._onnx_blob
        # In-place copy + convert: BGR→RGB via ::-1, then transpose into [1,3,H,W]
        np.copyto(blob[0], padded[:, :, ::-1].transpose(2, 0, 1), casting="unsafe")
        blob *= 1.0 / 255.0

        # --- Inference ---
        outputs = self._onnx_session.run(None, {self._onnx_input_name: blob})
        preds = outputs[0]  # [1, 84, N] — 4 box + 80 class scores

        # Transpose to [N, 84]
        preds = preds[0].T  # [N, 84]

        # --- Post-process (vectorized numpy — no Python loops) ---
        # Split box coords and class scores
        cx, cy, bw, bh = preds[:, 0], preds[:, 1], preds[:, 2], preds[:, 3]
        class_scores = preds[:, 4:]  # [N, 80]

        # Best class per prediction
        class_ids = np.argmax(class_scores, axis=1)
        confidences = class_scores[np.arange(len(class_ids)), class_ids]

        # Vectorized filter: target classes + per-class confidence thresholds
        target_mask = np.isin(class_ids, self._target_set_arr)
        phone_mask = np.isin(class_ids, self._phone_set_arr)
        drink_mask = np.isin(class_ids, self._drink_set_arr)
        # Phone classes: lowest threshold (0.18) to catch partial/angled phones
        # Drink classes: moderate threshold (0.30) for bottles/cups
        # Other target classes: standard threshold (0.45)
        conf_thresholds = np.full(len(confidences), self.confidence_threshold)
        conf_thresholds[phone_mask] = self._phone_conf_near
        conf_thresholds[drink_mask] = self._drink_conf
        mask = target_mask & (confidences >= conf_thresholds)

        if not np.any(mask):
            return []

        cx, cy, bw, bh = cx[mask], cy[mask], bw[mask], bh[mask]
        class_ids = class_ids[mask]
        confidences = confidences[mask]

        # Convert cx,cy,w,h → x1,y1,x2,y2 (in padded image coords)
        x1 = cx - bw / 2
        y1 = cy - bh / 2
        x2 = cx + bw / 2
        y2 = cy + bh / 2

        # Remove padding and rescale to original frame coords
        x1 = ((x1 - pad_w) / scale).clip(0, orig_w)
        y1 = ((y1 - pad_h) / scale).clip(0, orig_h)
        x2 = ((x2 - pad_w) / scale).clip(0, orig_w)
        y2 = ((y2 - pad_h) / scale).clip(0, orig_h)

        # NMS — use the lowest admitted threshold so low-conf phone detections
        # survive (class-specific filtering was already applied above).
        boxes_list = np.stack([x1, y1, x2 - x1, y2 - y1], axis=1).tolist()
        conf_list = confidences.tolist()
        indices = cv2.dnn.NMSBoxes(boxes_list, conf_list, self._phone_conf_near, 0.45)

        detections = []
        if len(indices) > 0:
            for i in indices.flatten():
                detections.append(
                    (
                        int(class_ids[i]),
                        float(confidences[i]),
                        int(x1[i]),
                        int(y1[i]),
                        int(x2[i]),
                        int(y2[i]),
                    )
                )
        return detections

    def _boxes_overlap(self, box1, box2, overlap_threshold=0.1):
        """Check if two bounding boxes overlap significantly"""
        if box1 is None or box2 is None:
            return False

        x1_1, y1_1, x2_1, y2_1 = box1
        x1_2, y1_2, x2_2, y2_2 = box2

        # Calculate intersection
        x1_i = max(x1_1, x1_2)
        y1_i = max(y1_1, y1_2)
        x2_i = min(x2_1, x2_2)
        y2_i = min(y2_1, y2_2)

        if x2_i <= x1_i or y2_i <= y1_i:
            return False

        intersection = (x2_i - x1_i) * (y2_i - y1_i)
        area1 = (x2_1 - x1_1) * (y2_1 - y1_1)
        area2 = (x2_2 - x1_2) * (y2_2 - y1_2)
        min_area = min(area1, area2)

        return (intersection / min_area) > overlap_threshold if min_area > 0 else False

    def _is_gripping_hand(self, hand_lms):
        """Check if hand is in a gripping shape (thumb close to fingers).

        This helps detect phones when held with an open palm but gripped.
        """
        # Check thumb tip (4) to index finger tip (8), middle finger tip (12), ring finger tip (16)
        thumb_tip = hand_lms[4]
        index_tip = hand_lms[8]
        middle_tip = hand_lms[12]
        ring_tip = hand_lms[16]

        # Calculate distances
        thumb_index_dist = (
            (thumb_tip.x - index_tip.x) ** 2 + (thumb_tip.y - index_tip.y) ** 2
        ) ** 0.5
        thumb_middle_dist = (
            (thumb_tip.x - middle_tip.x) ** 2 + (thumb_tip.y - middle_tip.y) ** 2
        ) ** 0.5
        thumb_ring_dist = (
            (thumb_tip.x - ring_tip.x) ** 2 + (thumb_tip.y - ring_tip.y) ** 2
        ) ** 0.5

        # If thumb is close to any finger, consider it gripping
        return (
            thumb_index_dist < 0.15
            or thumb_middle_dist < 0.15
            or thumb_ring_dist < 0.15
        )

    def _is_near_face(self, object_bbox, face_bbox, proximity_ratio=0.5):
        """Check if object is near the face region (likely being held/used)"""
        if object_bbox is None or face_bbox is None:
            return False

        # Get face center and dimensions
        face_x1 = face_bbox.get("x_min", 0)
        face_y1 = face_bbox.get("y_min", 0)
        face_x2 = face_bbox.get("x_max", 0)
        face_y2 = face_bbox.get("y_max", 0)

        face_center_x = (face_x1 + face_x2) / 2
        face_center_y = (face_y1 + face_y2) / 2
        face_width = face_x2 - face_x1
        face_height = face_y2 - face_y1

        # Get object center
        obj_x1, obj_y1, obj_x2, obj_y2 = object_bbox
        obj_center_x = (obj_x1 + obj_x2) / 2
        obj_center_y = (obj_y1 + obj_y2) / 2

        # Check if object center is within extended face region
        extended_width = face_width * (1 + proximity_ratio)
        extended_height = face_height * (1 + proximity_ratio)

        dx = abs(obj_center_x - face_center_x)
        dy = abs(obj_center_y - face_center_y)

        return dx < extended_width * 1.5 and dy < extended_height * 1.5

    def _detect_hands(self, frame):
        """Run MediaPipe hand detection once and return results.

        Downscales input to 480px max dimension before inference (hand landmarks
        are normalized 0-1 so resolution doesn't matter for downstream logic).

        Returns:
            list|None: list of hand landmark sets, or None if unavailable
        """
        if self.hand_landmarker is None or self._mp is None:
            return None

        h, w = frame.shape[:2]
        # Downscale for faster hand detection (saves ~30% compute on 720p+)
        _max = 480
        if max(h, w) > _max:
            _s = _max / max(h, w)
            hand_input = cv2.resize(
                frame, (int(w * _s), int(h * _s)), interpolation=cv2.INTER_LINEAR
            )
        else:
            hand_input = frame

        rgb = cv2.cvtColor(hand_input, cv2.COLOR_BGR2RGB)
        mp_image = self._mp.Image(image_format=self._mp.ImageFormat.SRGB, data=rgb)
        results = self.hand_landmarker.detect(mp_image)

        if not results.hand_landmarks:
            return None
        return results.hand_landmarks

    @staticmethod
    def _fingers_curled(hand_lms):
        """Check if fingers are curled (gripping a phone-shaped object).

        A finger is "not extended" if its tip is closer to the wrist than
        the finger's MCP (knuckle) joint.  When gripping a phone the fingers
        wrap around it — tips come back toward the palm even though they're
        not in a tight fist.  A generous 1.5× multiplier accounts for this.

        Returns:
            int: number of curled fingers (0-4, excluding thumb)
        """
        wrist = hand_lms[0]
        # (MCP index, TIP index) for index, middle, ring, pinky
        finger_joints = [(5, 8), (9, 12), (13, 16), (17, 20)]
        curled = 0
        for mcp_idx, tip_idx in finger_joints:
            mcp = hand_lms[mcp_idx]
            tip = hand_lms[tip_idx]
            d_tip = ((tip.x - wrist.x) ** 2 + (tip.y - wrist.y) ** 2) ** 0.5
            d_mcp = ((mcp.x - wrist.x) ** 2 + (mcp.y - wrist.y) ** 2) ** 0.5
            if d_tip < d_mcp * 1.8:  # More permissive (was 1.5)
                curled += 1
        return curled

    def _detect_hand_near_face(self, frame, hand_landmarks=None):
        """Detect a hand raised near the face → phone at ear.

        Gates:
          G1 – hand in upper 70% of frame (head level)
          G2 – wrist near the face (within 2× face width, 1.5× face height)
        Plus finger-curl check (>= 1 of 4 fingers curled — relaxed for
        various phone-holding grips including palm-flat and speakerphone).

        No orientation gate — phone can be held portrait OR landscape.

        Returns:
            tuple: (is_near_face: bool, hand_bbox: tuple|None)
        """
        if hand_landmarks is None:
            hand_landmarks = self._detect_hands(frame)
        if hand_landmarks is None:
            return False, None

        h, w = frame.shape[:2]
        face = self._last_face_bbox

        for hand_lms in hand_landmarks:
            wrist_x = hand_lms[0].x * w
            wrist_y = hand_lms[0].y * h

            # G1: hand must be in upper 70% of frame
            if wrist_y > h * 0.70:
                continue

            # Finger curl check — relaxed: even 1 curled finger suggests
            # gripping something (some people hold phone with open palm)
            curled = self._fingers_curled(hand_lms)
            if curled < 1:
                # Also check if hand is in a gripping shape (thumb close to fingers)
                if self._is_gripping_hand(hand_lms):
                    curled = 1  # Treat as gripping
                else:
                    continue

            if face is not None:
                face_cx = (face["x_min"] + face["x_max"]) / 2
                face_cy = (face["y_min"] + face["y_max"]) / 2
                face_w = face["x_max"] - face["x_min"]
                face_h = face["y_max"] - face["y_min"]

                # G2: wrist near the face (widened for side-of-head phone holding)
                dx = abs(wrist_x - face_cx)
                dy = abs(wrist_y - face_cy)
                if dx > face_w * 2.0 or dy > face_h * 1.5:
                    continue
            else:
                if wrist_y > h * 0.55:
                    continue
                if wrist_x < w * 0.1 or wrist_x > w * 0.9:
                    continue

            xs = [lm.x * w for lm in hand_lms]
            ys = [lm.y * h for lm in hand_lms]
            bbox = (int(min(xs)), int(min(ys)), int(max(xs)), int(max(ys)))
            print(f"  HANDS: phone-at-ear (curled={curled}/4)")
            return True, bbox

        return False, None

    def _is_in_hand_region(self, object_bbox, frame_shape):
        """Check if object is within hand region (wrist to fingertips area).

        This helps detect phones when held sideways or in front of the face
        that might not be classified as "near face" by the strict distance check.
        """
        if object_bbox is None:
            return False

        h, w = frame_shape
        obj_x1, obj_y1, obj_x2, obj_y2 = object_bbox

        # Get hand regions if available
        hand_landmarks = self._detect_hands(frame_shape)
        if hand_landmarks is None:
            # Fallback: use general driver area (lower middle portion of frame)
            driver_area_top = int(h * 0.3)
            driver_area_bottom = int(h * 0.8)
            driver_area_left = int(w * 0.2)
            driver_area_right = int(w * 0.8)

            # Check if phone bbox overlaps with driver area
            return not (
                obj_x2 < driver_area_left
                or obj_x1 > driver_area_right
                or obj_y2 < driver_area_top
                or obj_y1 > driver_area_bottom
            )

        # Check if object is near any hand
        for hand_lms in hand_landmarks:
            # Get hand bounding box
            xs = [lm.x * w for lm in hand_lms]
            ys = [lm.y * h for lm in hand_lms]
            hand_bbox = (int(min(xs)), int(min(ys)), int(max(xs)), int(max(ys)))

            # Check if object overlaps with hand region (more permissive)
            if self._boxes_overlap(object_bbox, hand_bbox, overlap_threshold=0.1):
                return True

            # Also check if object is close to hand (extended region)
            hand_center_x = (hand_bbox[0] + hand_bbox[2]) / 2
            hand_center_y = (hand_bbox[1] + hand_bbox[3]) / 2
            hand_width = hand_bbox[2] - hand_bbox[0]
            hand_height = hand_bbox[3] - hand_bbox[1]

            # Object center
            obj_center_x = (obj_x1 + obj_x2) / 2
            obj_center_y = (obj_y1 + obj_y2) / 2

            # Check distance (allow more space for phone)
            max_distance = max(hand_width, hand_height) * 3  # Increased from 2
            dx = abs(obj_center_x - hand_center_x)
            dy = abs(obj_center_y - hand_center_y)

            if dx < max_distance and dy < max_distance:
                return True

        return False

    def _detect_hand_holding(self, frame, hand_landmarks=None):
        """Detect a hand holding a phone-sized object (texting posture).

        Unlike hand-at-ear, this catches the phone held in front or below
        the face — common when texting, scrolling, or checking maps.

        Gates:
          G1 — hand in upper 75% of frame
          G2 — at least 3 of 4 fingers curled (tight grip on phone)
          G3 — hand is roughly in the driver's area (not at frame edges)

        Returns:
            tuple: (is_holding: bool, hand_bbox: tuple|None)
        """
        if hand_landmarks is None:
            hand_landmarks = self._detect_hands(frame)
        if hand_landmarks is None:
            return False, None

        h, w = frame.shape[:2]

        for hand_lms in hand_landmarks:
            wrist_y = hand_lms[0].y * h
            wrist_x = hand_lms[0].x * w

            # G1: hand in upper 75% of frame
            if wrist_y > h * 0.75:
                continue

            # G2: tight grip (3+ fingers curled)
            curled = self._fingers_curled(hand_lms)
            if curled < 3:
                continue

            # G3: not at extreme edges of frame
            if wrist_x < w * 0.05 or wrist_x > w * 0.95:
                continue

            xs = [lm.x * w for lm in hand_lms]
            ys = [lm.y * h for lm in hand_lms]
            bbox = (int(min(xs)), int(min(ys)), int(max(xs)), int(max(ys)))
            print(f"  HANDS: phone-holding (curled={curled}/4)")
            return True, bbox

        return False, None

    def detect(self, frame, face_bbox=None):
        """Run YOLO detection on frame (non-blocking async).

        Submits inference to a background thread and returns cached results
        instantly so the main loop is never blocked by the YOLO model.
        Smoothing state is updated only when new YOLO results arrive.

        Also runs MediaPipe Hands in the same background thread to detect
        hand-at-ear gestures (phone calls where the phone is occluded).

        Args:
            frame: BGR image from OpenCV
            face_bbox: Optional face bounding box dict with x_min/y_min/x_max/y_max.
                       Used by hand-at-ear detection to locate ear regions.

        Returns:
            dict with detection results
        """
        # Cache face bbox for the background thread's hand-at-ear check
        if face_bbox is not None:
            self._last_face_bbox = face_bbox
        # Return empty results if YOLO is disabled
        if not self.enabled or self._backend is None:
            return {
                "phone_detected": False,
                "drinking_detected": False,
                "phone_bbox": None,
                "bottle_bbox": None,
                "phone_frames": 0,
                "drinking_frames": 0,
                "hand_at_ear": False,
            }

        # Check for completed async YOLO result
        new_phone = None
        new_bottle = None
        is_hand_at_ear = False
        has_result = False

        if self._yolo_future is not None:
            if self._yolo_future.done():
                try:
                    new_phone, new_bottle, is_hand_at_ear = self._yolo_future.result()
                except Exception:
                    pass
                self._yolo_future = None
                has_result = True

        # Submit new YOLO inference if not busy.
        # Pre-downscale large frames → cv2.resize creates a new array (thread-safe)
        # and the smaller frame is faster to process in the ONNX pipeline.
        if self._yolo_future is None:
            h, w = frame.shape[:2]
            max_dim = max(h, w)
            if max_dim > self._onnx_img_size and self._backend == "onnx":
                self._yolo_upscale = max_dim / self._onnx_img_size
                yolo_frame = cv2.resize(
                    frame,
                    (int(w / self._yolo_upscale), int(h / self._yolo_upscale)),
                    interpolation=cv2.INTER_LINEAR,
                )
            else:
                self._yolo_upscale = 1.0
                yolo_frame = frame.copy()
            self._yolo_future = self._yolo_executor.submit(
                self._run_yolo_inference, yolo_frame
            )

        # Update smoothing only when we have new YOLO results
        if has_result:
            # Rescale bboxes if frame was pre-downscaled for YOLO
            s = self._yolo_upscale
            if s != 1.0:
                if new_phone is not None:
                    new_phone = tuple(int(v * s) for v in new_phone)
                if new_bottle is not None:
                    new_bottle = tuple(int(v * s) for v in new_bottle)
            now = time.time()

            # Sliding window: record hit/miss for this YOLO frame
            self._phone_window.append(new_phone is not None)
            self._drink_window.append(new_bottle is not None)

            # Phone: update bbox and hand_at_ear state
            if new_phone is not None:
                self.phone_bbox = new_phone
                self.hand_at_ear = is_hand_at_ear
                self._phone_last_seen = now
            elif not any(self._phone_window):
                # Only clear bbox when no hits in the entire window
                self.phone_bbox = None
                self.hand_at_ear = False

            if new_bottle is not None:
                self.bottle_bbox = new_bottle
            elif not any(self._drink_window):
                self.bottle_bbox = None

            # Sliding window counts
            self.phone_frames = sum(self._phone_window)
            self.drinking_frames = sum(self._drink_window)

            # Phone detection: N hits in last W frames OR within cooldown
            raw_phone = self.phone_frames >= self._PHONE_MIN_HITS
            if raw_phone:
                self.phone_detected = True
                self._phone_last_seen = now
            elif now - self._phone_last_seen < self._PHONE_COOLDOWN_SECS:
                self.phone_detected = True
            else:
                self.phone_detected = False

            self.drinking_detected = self.drinking_frames >= self._PHONE_MIN_HITS

        return {
            "phone_detected": self.phone_detected,
            "drinking_detected": self.drinking_detected,
            "phone_bbox": self.phone_bbox,
            "bottle_bbox": self.bottle_bbox,
            "phone_frames": self.phone_frames,
            "drinking_frames": self.drinking_frames,
            "hand_at_ear": self.hand_at_ear,
        }

    def _run_yolo_inference(self, frame):
        """Run YOLO model inference + hand-at-ear detection in background thread.

        Uses ultralytics backend on dev machines, onnxruntime on RPi/edge.
        Two-tier phone detection:
          - High confidence (0.30+) = phone detected anywhere
          - Low confidence (0.18+) near face/hands = phone detected
          - Hand-at-ear fallback when YOLO misses entirely

        Returns:
            tuple: (phone_bbox, bottle_bbox, hand_at_ear)
                   phone_bbox/bottle_bbox are (x1,y1,x2,y2) or None
                   hand_at_ear is True if phone was detected via hand-near-face
        """
        t0 = time.time()
        current_phone = None
        current_bottle = None
        hand_at_ear = False
        # Collect all phone candidates for two-tier filtering
        phone_candidates = []  # (bbox, conf, class_name)

        if self._backend == "ultralytics":
            # --- Ultralytics backend (dev machines with PyTorch) ---
            # Use low confidence to catch partial phones; filter afterwards
            results = self.model(
                frame,
                verbose=False,
                conf=self._phone_conf_near,
                classes=self.TARGET_CLASSES,
            )

            for result in results:
                boxes = result.boxes
                if boxes is None:
                    continue

                for box in boxes:
                    cls = int(box.cls[0])
                    conf = float(box.conf[0])
                    xyxy = box.xyxy[0].cpu().numpy()
                    bbox = (int(xyxy[0]), int(xyxy[1]), int(xyxy[2]), int(xyxy[3]))
                    class_name = self.model.names[cls]

                    if cls in self.PHONE_CLASSES:
                        phone_candidates.append((bbox, conf, class_name))
                    elif (
                        cls in self.DRINK_CLASSES and conf >= self.confidence_threshold
                    ):
                        current_bottle = bbox
                        print(
                            f"YOLO: DRINK (class {cls}: {class_name}) conf={conf:.2f}"
                        )

        elif self._backend == "onnx":
            # --- ONNX runtime backend (RPi / edge without PyTorch) ---
            detections = self._run_onnx_inference(frame)

            for cls, conf, x1, y1, x2, y2 in detections:
                bbox = (x1, y1, x2, y2)
                class_name = self.COCO_NAMES.get(cls, f"class_{cls}")

                if cls in self.PHONE_CLASSES:
                    phone_candidates.append((bbox, conf, class_name))
                elif cls in self.DRINK_CLASSES and conf >= self._drink_conf:
                    current_bottle = bbox
                    print(f"YOLO: DRINK (class {cls}: {class_name}) conf={conf:.2f}")

        # Two-tier phone filtering:
        # Tier 1 — high confidence (0.25+): accept anywhere
        # Tier 2 — low confidence (0.15+): accept only near face or hands
        # Also check if phone is in hand regions (wrist to fingertips)
        face = self._last_face_bbox
        phone_candidates.sort(key=lambda x: x[1], reverse=True)  # highest conf first
        for bbox, conf, class_name in phone_candidates:
            if conf >= self._phone_conf_high:
                # Tier 1: high confidence — phone anywhere
                current_phone = bbox
                print(f"YOLO: PHONE ({class_name}) conf={conf:.2f}")
                break
            elif face is not None and self._is_near_face(
                bbox,
                face,
                proximity_ratio=1.5,  # Increased from 1.0
            ):
                # Tier 2: low confidence but near the driver's face
                current_phone = bbox
                print(f"YOLO: PHONE-NEAR ({class_name}) conf={conf:.2f} [near face]")
                break
            elif face is not None and self._is_in_hand_region(bbox, frame.shape):
                # Tier 3: Check if phone is in hand region (wrist to fingertips)
                current_phone = bbox
                print(
                    f"YOLO: PHONE-IN-HAND ({class_name}) conf={conf:.2f} [in hand region]"
                )
                break

        # Hand-at-ear / hand-holding-phone fallback:
        # When YOLO didn't see a phone, check for hand gestures.
        # Throttled to every Nth YOLO cycle to reduce per-cycle overhead.
        self._hand_detect_counter += 1
        run_hands = (
            current_phone is None
            and self.hand_landmarker is not None
            and self._hand_detect_counter >= self._hand_detect_interval
        )
        if run_hands:
            self._hand_detect_counter = 0
            hand_landmarks = self._detect_hands(frame)
            if hand_landmarks is not None:
                # Check 1: hand near face (phone at ear)
                is_near, hand_bbox = self._detect_hand_near_face(frame, hand_landmarks)
                if is_near and hand_bbox is not None:
                    current_phone = hand_bbox
                    hand_at_ear = True
                else:
                    # Check 2: hand holding object in upper frame (texting posture)
                    holding, hold_bbox = self._detect_hand_holding(
                        frame, hand_landmarks
                    )
                    if holding and hold_bbox is not None:
                        current_phone = hold_bbox
                        hand_at_ear = False

        self._yolo_times.append(time.time() - t0)
        self._yolo_completions += 1
        return current_phone, current_bottle, hand_at_ear

    def get_yolo_stats(self):
        """Return (avg_ms, fps, completions) for recent YOLO inferences."""
        if not self._yolo_times:
            return 0.0, 0.0, self._yolo_completions
        avg = sum(self._yolo_times) / len(self._yolo_times)
        fps = 1.0 / avg if avg > 0 else 0.0

        return avg * 1000, fps, self._yolo_completions

    def reset_yolo_stats(self):
        """Reset the completion counter (called after each stats print)."""
        self._yolo_completions = 0

    def shutdown(self):
        """Shutdown the YOLO executor and release MediaPipe HandLandmarker."""
        if self._yolo_executor is not None:
            self._yolo_executor.shutdown(wait=False)
        if self.hand_landmarker is not None:
            self.hand_landmarker.close()

    def draw_detections(self, frame):
        """Draw detection boxes on frame (optimized)"""
        if self.phone_bbox:
            x1, y1, x2, y2 = self.phone_bbox
            color = COLOR_RED if self.phone_detected else COLOR_ORANGE
            cv2.rectangle(frame, (x1, y1), (x2, y2), color, 2)
            hits = f"{self.phone_frames}/{self._PHONE_WINDOW}"
            if self.hand_at_ear:
                label = (
                    f"PHONE (HAND {hits})!"
                    if self.phone_detected
                    else f"Hand near face ({hits})"
                )
            else:
                label = (
                    f"PHONE ({hits}) - DISTRACTED!"
                    if self.phone_detected
                    else f"Phone ({hits})"
                )
            cv2.putText(frame, label, (x1, y1 - 10), FONT_FAST, 1.0, color, 1)

        if self.bottle_bbox:
            x1, y1, x2, y2 = self.bottle_bbox
            color = COLOR_ORANGE if self.drinking_detected else (255, 165, 0)
            cv2.rectangle(frame, (x1, y1), (x2, y2), color, 2)
            label = "DRINKING!" if self.drinking_detected else "Bottle/Cup"
            cv2.putText(frame, label, (x1, y1 - 10), FONT_FAST, 1.0, color, 1)

        return frame


class DrivingSimulator:
    def __init__(
        self,
        gps_reader: GPSReader = None,
        speed_limit_checker: SpeedLimitChecker = None,
    ):
        self.gps = gps_reader
        self.speed_limit_checker = speed_limit_checker
        self.speed = 45.0  # Start at 45 MPH (used for simulation mode)
        self.speed_limit = 65  # Default speed limit (will be updated from GPS)
        self.min_speed = 0
        self.max_speed = 100
        self.direction = "forward"
        self.update_counter = 0
        self.update_frequency = 5  # Update every 5 frames for smoother changes

        # Compass direction (0-360 degrees, 0=North, 90=East, 180=South, 270=West)
        self.heading = 45.0  # Start heading Northeast (used for simulation mode)
        self.compass_directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

        # GPS data cache
        self._last_speed = 0.0
        self._satellites = 0
        self._latitude = GPSReader.APPLE_PARK_LAT if gps_reader else 37.3349
        self._longitude = GPSReader.APPLE_PARK_LON if gps_reader else -122.0090

        # Speed limit update tracking
        self.last_speed_limit_update = 0
        self.speed_limit_update_interval = 30.0  # Update every 30 seconds
        self.speed_limit_fetching = False

    def update_speed_limit(self):
        """Update speed limit from GPS coordinates (non-blocking)"""
        if not self.speed_limit_checker:
            return

        current_time = time.time()
        if (
            current_time - self.last_speed_limit_update
            < self.speed_limit_update_interval
        ):
            return

        if self.speed_limit_fetching:
            return  # Already fetching

        self.speed_limit_fetching = True
        self.last_speed_limit_update = current_time

        lat = self.get_latitude()
        lon = self.get_longitude()

        def _do_fetch():
            try:
                fetched_limit = self.speed_limit_checker.get_speed_limit(lat, lon)
                if fetched_limit is not None:
                    self.speed_limit = fetched_limit
                    print(
                        f"Speed limit updated: {self.speed_limit} MPH (from GPS location)"
                    )
                else:
                    print(
                        "Speed limit not available for current location, using default"
                    )
            except Exception as e:
                print(f"Error fetching speed limit: {e}")
            finally:
                self.speed_limit_fetching = False

        threading.Thread(target=_do_fetch, daemon=True).start()

    def update_speed(self):
        """Update speed - from GPS if available, otherwise simulate"""
        self.update_counter += 1

        # Update speed limit periodically
        self.update_speed_limit()

        if self.gps and not self.gps.is_fake:
            # Use real GPS data
            new_speed = self.gps.speed_mph
            self.heading = self.gps.heading
            self._satellites = self.gps.satellites
            self._latitude = self.gps.latitude
            self._longitude = self.gps.longitude

            # Determine direction based on speed change
            if new_speed > self._last_speed + 0.5:
                self.direction = "accelerating"
            elif new_speed < self._last_speed - 0.5:
                self.direction = "decelerating"
            else:
                self.direction = "steady"

            self._last_speed = new_speed
            self.speed = new_speed
        else:
            # Simulation mode (fallback or no GPS)
            if self.update_counter >= self.update_frequency:
                self.update_counter = 0

                # Random speed change between -3 and +3 MPH
                change = random.uniform(-3.0, 3.0)
                new_speed = self.speed + change

                # Keep within bounds
                self.speed = max(self.min_speed, min(self.max_speed, new_speed))

                # Determine direction based on speed change
                if change > 0.5:
                    self.direction = "accelerating"
                elif change < -0.5:
                    self.direction = "decelerating"
                else:
                    self.direction = "steady"

                # Update heading with slight random drift (realistic driving)
                heading_change = random.uniform(-5.0, 5.0)
                self.heading = (self.heading + heading_change) % 360

    def manual_speed_increase(self, amount=10):
        """Manually increase speed (for testing - only works in simulation mode)"""
        if not self.gps or self.gps.is_fake:
            self.speed = min(self.max_speed, self.speed + amount)
            self.direction = "accelerating"

    def manual_speed_decrease(self, amount=10):
        """Manually decrease speed (for testing - only works in simulation mode)"""
        if not self.gps or self.gps.is_fake:
            self.speed = max(self.min_speed, self.speed - amount)
            self.direction = "decelerating"

    def set_speeding_mode(self):
        """Set speed to 75 MPH for testing speeding alerts (simulation only)"""
        if not self.gps or self.gps.is_fake:
            self.speed = 75.0
            self.direction = "speeding"

    def reset_speed(self):
        """Reset speed to safe default (simulation only)"""
        if not self.gps or self.gps.is_fake:
            self.speed = 45.0
            self.direction = "steady"

    def get_speed(self):
        """Get current speed as integer"""
        return int(round(self.speed))

    def is_speeding(self):
        """Check if currently speeding"""
        return self.speed > self.speed_limit

    def get_speed_status(self):
        """Get speed status color"""
        if self.speed > self.speed_limit + 10:
            return (0, 0, 255)  # Red - excessive speeding
        elif self.speed > self.speed_limit:
            return (0, 165, 255)  # Orange - speeding
        else:
            return (0, 255, 0)  # Green - within limit

    def get_compass_direction(self):
        """Get compass direction (N, NE, E, SE, S, SW, W, NW)"""
        index = int((self.heading + 22.5) / 45.0) % 8
        return self.compass_directions[index]

    def get_direction_string(self):
        """Get direction string with degrees (e.g., '342NW')"""
        return f"{int(self.heading)}{self.get_compass_direction()}"

    def get_heading(self):
        """Get current heading in degrees"""
        return int(self.heading)

    def get_satellites(self):
        """Get number of GPS satellites"""
        if self.gps:
            return self.gps.satellites
        return self._satellites

    def get_latitude(self):
        """Get current latitude"""
        if self.gps:
            return self.gps.latitude
        return self._latitude

    def get_longitude(self):
        """Get current longitude"""
        if self.gps:
            return self.gps.longitude
        return self._longitude

    def has_gps_fix(self):
        """Check if GPS has a valid fix"""
        if self.gps:
            return self.gps.has_fix
        return False

    def is_using_gps(self):
        """Check if using real GPS data"""
        return self.gps is not None and not self.gps.is_fake

    def get_speed_limit(self):
        """Get current speed limit"""
        return self.speed_limit


class FallbackFaceDetector:
    """Lightweight face detector using OpenCV's Haar cascade.

    Used when MediaPipe is unavailable (protobuf conflicts, etc.).
    Only provides face bounding boxes and crops -- no EAR or intoxication
    analysis (handled by custom ONNX models via DriverAwarenessSystem).
    """

    def __init__(self):
        cascade_path = cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
        self.detector = cv2.CascadeClassifier(cascade_path)
        print("FallbackFaceDetector: using OpenCV Haar cascade (MediaPipe unavailable)")

    def process_frame(self, frame, timestamp_ms):
        h, w, _ = frame.shape
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        faces = self.detector.detectMultiScale(
            gray, scaleFactor=1.1, minNeighbors=5, minSize=(60, 60)
        )

        detection_data = None

        if len(faces) > 0:
            # Use the largest face
            fx, fy, fw, fh = max(faces, key=lambda f: f[2] * f[3])
            x_min, y_min, x_max, y_max = fx, fy, fx + fw, fy + fh

            cv2.rectangle(frame, (x_min, y_min), (x_max, y_max), COLOR_GREEN, 2)

            # Extract face crop with padding
            padding = 20
            crop_x_min = max(0, x_min - padding)
            crop_y_min = max(0, y_min - padding)
            crop_x_max = min(w, x_max + padding)
            crop_y_max = min(h, y_max + padding)
            face_crop = frame[crop_y_min:crop_y_max, crop_x_min:crop_x_max].copy()

            detection_data = {
                "intox_data": {
                    "drowsy": False,
                    "excessive_blinking": False,
                    "unstable_eyes": False,
                    "score": 0,
                    "ear": 0.3,
                },
                "face_crop": face_crop,
                "face_bbox": {
                    "x_min": x_min,
                    "y_min": y_min,
                    "x_max": x_max,
                    "y_max": y_max,
                },
                "left_eye_state": "OPEN",
                "left_eye_ear": 0.3,
                "right_eye_state": "OPEN",
                "right_eye_ear": 0.3,
            }

        return frame, detection_data

    # Alias so multiprocessing face worker can call the same method name
    _analyze_frame_sync = process_frame


class FaceAnalyzer:
    def __init__(self):
        # Lazy import — keeps mediapipe out of module scope to avoid segfaults
        import mediapipe as _mp
        from mediapipe.tasks import python as _mp_python
        from mediapipe.tasks.python import vision as _mp_vision

        self._mp = _mp

        # Initialize MediaPipe Face Landmarker (with blendshapes for gaze)
        base_options = _mp_python.BaseOptions(model_asset_path="face_landmarker.task")
        options = _mp_vision.FaceLandmarkerOptions(
            base_options=base_options,
            running_mode=_mp_vision.RunningMode.VIDEO,
            num_faces=5,
            min_face_detection_confidence=0.5,
            min_face_presence_confidence=0.5,
            min_tracking_confidence=0.5,
            output_face_blendshapes=True,
        )
        self.landmarker = _mp_vision.FaceLandmarker.create_from_options(options)

        # Async face analysis — runs MediaPipe in a background thread
        # so the main loop is never blocked by face detection inference.
        self._executor = ThreadPoolExecutor(max_workers=1)
        self._future = None
        self._cached_detection = None  # last detection_data
        self._cached_frame = None  # last annotated frame
        self._last_ts = -1  # last submitted timestamp (must be monotonic)

        # MediaPipe input cap: downscale large frames before inference.
        # Face detection works well at 480p; full 1080p wastes ~60% compute.
        self._mp_max_dim = 640

        # Eye landmarks indices for MediaPipe Face Mesh
        self.LEFT_EYE = [362, 385, 387, 263, 373, 380]
        self.RIGHT_EYE = [33, 160, 158, 133, 153, 144]

        # Head pose estimation: 6-point 3D face model (generic proportions)
        # Indices: nose tip=1, chin=152, left eye outer=263, right eye outer=33,
        #          left mouth corner=287, right mouth corner=57
        self.POSE_LANDMARKS = [1, 152, 263, 33, 287, 57]
        self.POSE_MODEL_3D = np.array(
            [
                [0.0, 0.0, 0.0],  # Nose tip
                [0.0, -63.6, -12.5],  # Chin
                [-43.3, 32.7, -26.0],  # Left eye outer
                [43.3, 32.7, -26.0],  # Right eye outer
                [-28.9, -28.9, -24.1],  # Left mouth corner
                [28.9, -28.9, -24.1],  # Right mouth corner
            ],
            dtype=np.float64,
        )
        # Pre-allocated arrays for solvePnP (avoids per-frame allocation)
        self._pose_image_pts = np.empty((6, 2), dtype=np.float64)
        self._pose_nose_3d = np.array([[0.0, 0.0, 500.0]], dtype=np.float64)
        # Camera matrix cached per resolution (set on first call)
        self._cam_matrix = None
        self._cam_matrix_wh = (0, 0)
        self._focal_length = 0.0

        # Blendshape names used in analyze_gaze (for fast set-membership test)
        self._GAZE_BLENDSHAPE_NAMES = frozenset(
            {
                "eyeLookOutLeft",
                "eyeLookInRight",
                "eyeLookInLeft",
                "eyeLookOutRight",
                "eyeLookDownLeft",
                "eyeLookDownRight",
                "eyeLookUpLeft",
                "eyeLookUpRight",
                "eyeBlinkLeft",
                "eyeBlinkRight",
            }
        )

        # Thresholds
        self.EAR_THRESHOLD = 0.21
        self.DROWSINESS_FRAMES = 20
        self.BLINK_THRESHOLD = 30

        # Gaze distraction thresholds
        # Blendshape scores are 0.0-1.0; above this = looking in that direction
        self.GAZE_THRESHOLD = 0.25  # Default threshold
        self.GAZE_THRESHOLD_DOWN = (
            0.15  # Lower threshold for downward gaze (more common)
        )
        # Both eyeBlink blendshapes above this = eyes closed
        self.BLINK_CLOSED_THRESHOLD = 0.55
        # Head pose thresholds (degrees) for distraction
        self.HEAD_YAW_THRESHOLD = 30  # Looking left/right
        self.HEAD_PITCH_THRESHOLD = (
            35  # Increased from 20 to avoid false positives from natural chin positions
        )
        # Confidence threshold for eye gaze - if eye direction is confident, ignore head pose
        self.GAZE_CONFIDENCE_THRESHOLD = 0.15  # If max eye gaze score < this, use head pose
        # Seconds of sustained gaze-away before flagging as distracted
        self.GAZE_DISTRACTION_SECONDS = 2.0
        # Seconds of sustained eyes-closed before flagging as impaired
        self.EYES_CLOSED_IMPAIRED_SECONDS = 1.0

        # Tracking variables
        self.eye_closed_counter = 0
        self.blink_counter = 0
        self.blink_history = deque(maxlen=100)
        self.ear_history = deque(maxlen=50)

        # Gaze / eyes-closed temporal tracking (wall-clock based)
        self._gaze_away_start = None  # time.time() when gaze left center
        self._eyes_closed_start = None  # time.time() when both eyes closed
        self._last_gaze_direction = "straight"

        # Face-loss tracking: when face disappears (full head turn / side profile),
        # continue counting as "looking away" since the driver left the camera view.
        self._face_last_seen = None  # time.time() of last face detection
        self._face_was_present = False  # True once we've seen a face this session
        self._gaze_debug_enabled = (
            False  # Enable with --debug-gaze flag later if needed
        )

    @staticmethod
    def _euclidean(p1, p2):
        """Fast euclidean distance (replaces scipy.spatial.distance.euclidean)."""
        dx = p1[0] - p2[0]
        dy = p1[1] - p2[1]
        return (dx * dx + dy * dy) ** 0.5

    def calculate_ear(self, eye_landmarks):
        """Calculate Eye Aspect Ratio"""
        _dist = self._euclidean
        A = _dist(eye_landmarks[1], eye_landmarks[5])
        B = _dist(eye_landmarks[2], eye_landmarks[4])
        C = _dist(eye_landmarks[0], eye_landmarks[3])
        return (A + B) / (2.0 * C)

    def get_eye_landmarks(self, face_landmarks, eye_indices, w, h):
        """Extract eye landmark coordinates"""
        return [
            (int(face_landmarks[idx].x * w), int(face_landmarks[idx].y * h))
            for idx in eye_indices
        ]

    def estimate_head_pose(self, face_landmarks, w, h):
        """Estimate head yaw/pitch from face landmarks using solvePnP.

        Uses the rotation vector directly (via Rodrigues) to extract yaw/pitch,
        avoiding the expensive projectPoints call.

        Returns:
            dict with yaw, pitch (degrees), or None if estimation fails.
            Positive yaw = looking right, negative = looking left.
            Positive pitch = looking down, negative = looking up.
        """
        # Fill pre-allocated image_points array (avoids per-frame allocation)
        pts = self._pose_image_pts
        for i, idx in enumerate(self.POSE_LANDMARKS):
            lm = face_landmarks[idx]
            pts[i, 0] = lm.x * w
            pts[i, 1] = lm.y * h

        # Cache camera matrix per resolution (only rebuild when frame size changes)
        if self._cam_matrix_wh != (w, h):
            focal_length = float(w)
            self._cam_matrix = np.array(
                [
                    [focal_length, 0.0, w * 0.5],
                    [0.0, focal_length, h * 0.5],
                    [0.0, 0.0, 1.0],
                ],
                dtype=np.float64,
            )
            self._cam_matrix_wh = (w, h)
            self._focal_length = focal_length

        success, rvec, tvec = cv2.solvePnP(
            self.POSE_MODEL_3D,
            pts,
            self._cam_matrix,
            None,
            flags=cv2.SOLVEPNP_ITERATIVE,
        )
        if not success:
            return None

        # Extract yaw/pitch directly from rotation matrix (avoids projectPoints)
        rmat, _ = cv2.Rodrigues(rvec)
        # Decompose rotation matrix to Euler angles
        yaw = math.degrees(math.atan2(rmat[2, 0], rmat[2, 2]))
        pitch = math.degrees(math.asin(max(-1.0, min(1.0, -rmat[2, 1]))))

        return {"yaw": round(yaw, 1), "pitch": round(pitch, 1)}

    def analyze_gaze(self, blendshapes, head_pose=None):
        """Analyze gaze direction from blendshapes + head pose.

        Combines two signals:
        1. Eye blendshapes — iris/pupil direction within the eye socket
        2. Head pose (yaw/pitch) — physical head rotation

        Either signal alone can trigger a "looking away" detection:
        - Eyes looking left while head faces forward = distracted
        - Head turned 30+ degrees while eyes face forward = distracted
        - Both = definitely distracted

        Args:
            blendshapes: list of mediapipe blendshape categories for one face
            head_pose: dict with 'yaw' and 'pitch' in degrees, or None

        Returns:
            dict with gaze_direction, gaze_distracted, eyes_both_closed,
                 gaze_away_seconds, eyes_closed_seconds, head_yaw, head_pitch
        """
        now = time.time()

        # Single-pass blendshape extraction: only grab the ~10 values we need
        # instead of building a full dict over all ~52 blendshapes.
        _eOL = _eIR = _eIL = _eOR = _eDL = _eDR = _eUL = _eUR = _bL = _bR = 0.0
        _GAZE_NAMES = self._GAZE_BLENDSHAPE_NAMES
        if not blendshapes and self._gaze_debug_enabled:
            print("DEBUG: No blendshapes detected!")

        for b in blendshapes:
            _n = b.category_name
            if _n not in _GAZE_NAMES:
                continue
            _s = b.score
            if _n == "eyeLookOutLeft":
                _eOL = _s
            elif _n == "eyeLookInRight":
                _eIR = _s
            elif _n == "eyeLookInLeft":
                _eIL = _s
            elif _n == "eyeLookOutRight":
                _eOR = _s
            elif _n == "eyeLookDownLeft":
                _eDL = _s
            elif _n == "eyeLookDownRight":
                _eDR = _s
            elif _n == "eyeLookUpLeft":
                _eUL = _s
            elif _n == "eyeLookUpRight":
                _eUR = _s
            elif _n == "eyeBlinkLeft":
                _bL = _s
            elif _n == "eyeBlinkRight":
                _bR = _s

        # --- Eye-based gaze direction ---
        look_left = (_eOL + _eIR) * 0.5
        look_right = (_eIL + _eOR) * 0.5
        look_down = (_eDL + _eDR) * 0.5
        look_up = (_eUL + _eUR) * 0.5

        # Debug logging for gaze detection (only print when significant values detected)
        # if max(look_left, look_right, look_down, look_up) > 0.1:
        # print(
        #     f"  GAZE_DEBUG: L={look_left:.3f} R={look_right:.3f} D={look_down:.3f} U={look_up:.3f} (threshold={self.GAZE_THRESHOLD:.3f})"
        # )

        eye_direction = "straight"
        # More sensitive detection for down gaze - common when looking at phone
        if look_down > self.GAZE_THRESHOLD_DOWN:
            eye_direction = "down"
        elif look_up > self.GAZE_THRESHOLD:
            eye_direction = "up"
        elif look_left > self.GAZE_THRESHOLD:
            eye_direction = "left"
        elif look_right > self.GAZE_THRESHOLD:
            eye_direction = "right"

        # --- Head pose direction ---
        head_direction = "straight"
        head_yaw = 0.0
        head_pitch = 0.0
        if head_pose:
            head_yaw = head_pose["yaw"]
            head_pitch = head_pose["pitch"]
            if abs(head_yaw) > self.HEAD_YAW_THRESHOLD:
                head_direction = "left" if head_yaw < 0 else "right"
            elif abs(head_pitch) > self.HEAD_PITCH_THRESHOLD:
                head_direction = "up" if head_pitch > 0 else "down"

        # --- Combined gaze direction: prioritize confident eye gaze ---
        # Calculate eye gaze confidence (how strong the eye direction signal is)
        max_eye_gaze = max(look_left, look_right, look_down, look_up)
        eye_gaze_confident = max_eye_gaze >= self.GAZE_CONFIDENCE_THRESHOLD

        # Decision logic:
        # 1. If eye direction is detected AND confident, use it (ignore head pose)
        # 2. If eye direction is "straight" with low confidence, fall back to head pose
        # 3. This prevents false positives when chin is tilted but eyes are forward
        if eye_direction != "straight" and eye_gaze_confident:
            # Eyes are clearly looking somewhere - use eye direction
            gaze_direction = eye_direction
        elif eye_direction == "straight" and eye_gaze_confident:
            # Eyes are confidently looking straight - trust eyes, ignore head pose
            gaze_direction = "straight"
        elif head_direction != "straight":
            # Eye gaze not confident - use head pose as fallback
            gaze_direction = head_direction
        else:
            gaze_direction = "straight"

        # --- Eyes closed (both eyes) ---
        blink_left = _bL
        blink_right = _bR
        eyes_both_closed = (
            blink_left > self.BLINK_CLOSED_THRESHOLD
            and blink_right > self.BLINK_CLOSED_THRESHOLD
        )

        # --- Temporal tracking: gaze away ---
        # Only start timer for sustained gaze away (left/right/up/down)
        if gaze_direction in ["left", "right", "up", "down"]:
            if self._gaze_away_start is None:
                self._gaze_away_start = now
            gaze_away_seconds = now - self._gaze_away_start
        else:
            self._gaze_away_start = None
            gaze_away_seconds = 0.0

        gaze_distracted = gaze_away_seconds >= self.GAZE_DISTRACTION_SECONDS

        # --- Temporal tracking: eyes closed ---
        if eyes_both_closed:
            if self._eyes_closed_start is None:
                self._eyes_closed_start = now
            eyes_closed_seconds = now - self._eyes_closed_start
        else:
            self._eyes_closed_start = None
            eyes_closed_seconds = 0.0

        eyes_closed_impaired = eyes_closed_seconds >= self.EYES_CLOSED_IMPAIRED_SECONDS

        self._last_gaze_direction = gaze_direction

        return {
            "gaze_direction": gaze_direction,
            "gaze_distracted": gaze_distracted,
            "gaze_away_seconds": round(gaze_away_seconds, 2),
            "eyes_both_closed": eyes_both_closed,
            "eyes_closed_impaired": eyes_closed_impaired,
            "eyes_closed_seconds": round(eyes_closed_seconds, 2),
            "look_left": round(look_left, 3),
            "look_right": round(look_right, 3),
            "look_down": round(look_down, 3),
            "look_up": round(look_up, 3),
            "blink_left": round(blink_left, 3),
            "blink_right": round(blink_right, 3),
            "head_yaw": head_yaw,
            "head_pitch": head_pitch,
        }

    def analyze_gaze_from_head_pose(self, head_pose):
        """Fallback gaze analysis using only head pose (no blendshapes available).

        Used when the face is turned far enough that MediaPipe can still detect
        landmarks but blendshapes are unreliable (e.g. side profile).
        """
        now = time.time()
        yaw = head_pose["yaw"]
        pitch = head_pose["pitch"]

        gaze_direction = "straight"
        if abs(yaw) > self.HEAD_YAW_THRESHOLD:
            gaze_direction = "left" if yaw < 0 else "right"
        elif abs(pitch) > self.HEAD_PITCH_THRESHOLD:
            gaze_direction = "up" if pitch > 0 else "down"

        # Temporal tracking
        if gaze_direction != "straight":
            if self._gaze_away_start is None:
                self._gaze_away_start = now
            gaze_away_seconds = now - self._gaze_away_start
        else:
            self._gaze_away_start = None
            gaze_away_seconds = 0.0

        gaze_distracted = gaze_away_seconds >= self.GAZE_DISTRACTION_SECONDS
        self._last_gaze_direction = gaze_direction

        return {
            "gaze_direction": gaze_direction,
            "gaze_distracted": gaze_distracted,
            "gaze_away_seconds": round(gaze_away_seconds, 2),
            "eyes_both_closed": False,
            "eyes_closed_impaired": False,
            "eyes_closed_seconds": 0.0,
            "look_left": 0,
            "look_right": 0,
            "look_down": 0,
            "look_up": 0,
            "blink_left": 0,
            "blink_right": 0,
            "head_yaw": yaw,
            "head_pitch": pitch,
        }

    def detect_intoxication(self, left_ear, right_ear):
        """Detect potential intoxication indicators"""
        avg_ear = (left_ear + right_ear) / 2
        self.ear_history.append(avg_ear)

        # Track eye closure
        if avg_ear < self.EAR_THRESHOLD:
            self.eye_closed_counter += 1
        else:
            if self.eye_closed_counter > 2:
                self.blink_counter += 1
                self.blink_history.append(1)
            self.eye_closed_counter = 0

        # Intoxication indicators
        is_drowsy = self.eye_closed_counter >= self.DROWSINESS_FRAMES

        # Calculate blink rate (blinks per frame over last 100 frames)
        recent_blinks = sum(self.blink_history) if len(self.blink_history) > 0 else 0
        excessive_blinking = recent_blinks > self.BLINK_THRESHOLD

        # EAR variance (high variance suggests instability)
        # Threshold increased - 0.005 was way too sensitive, normal blinking causes that
        if len(self.ear_history) > 10:
            _hist = self.ear_history
            _mean = sum(_hist) / len(_hist)
            ear_variance = sum((x - _mean) ** 2 for x in _hist) / len(_hist)
        else:
            ear_variance = 0
        unstable_eyes = ear_variance > 0.02  # Much higher threshold

        # Overall intoxication score
        intoxication_score = 0
        if is_drowsy:
            intoxication_score += 3
        if excessive_blinking:
            intoxication_score += 2
        if unstable_eyes:
            intoxication_score += 1

        return {
            "drowsy": is_drowsy,
            "excessive_blinking": excessive_blinking,
            "unstable_eyes": unstable_eyes,
            "score": intoxication_score,
            "ear": avg_ear,
        }

    def _analyze_frame_sync(self, frame, timestamp_ms):
        """Run MediaPipe face detection + analysis on a single frame.

        This is the heavy-compute method that runs in the background thread.
        Returns (annotated_frame, detection_data).
        """
        h, w, _ = frame.shape

        # Downscale large frames before MediaPipe (saves ~40% compute on 1080p).
        # Landmark coordinates are normalized 0-1, so they map back to any resolution.
        _max = self._mp_max_dim
        if max(h, w) > _max:
            _scale = _max / max(h, w)
            _sw, _sh = int(w * _scale), int(h * _scale)
            mp_input = cv2.resize(frame, (_sw, _sh), interpolation=cv2.INTER_LINEAR)
        else:
            mp_input = frame

        rgb_frame = cv2.cvtColor(mp_input, cv2.COLOR_BGR2RGB)

        # Convert to MediaPipe Image
        mp_image = self._mp.Image(
            image_format=self._mp.ImageFormat.SRGB, data=rgb_frame
        )

        # Detect face landmarks
        results = self.landmarker.detect_for_video(mp_image, timestamp_ms)

        # Detection data to return
        detection_data = None
        now = time.time()

        if results.face_landmarks:
            # Face detected — update face-loss tracker
            self._face_last_seen = now
            self._face_was_present = True

            for face_idx, face_landmarks in enumerate(results.face_landmarks):
                # Get face bounding box (single pass over landmarks)
                lm0 = face_landmarks[0]
                xn, xx, yn, yx = lm0.x, lm0.x, lm0.y, lm0.y
                for lm in face_landmarks:
                    _lx, _ly = lm.x, lm.y
                    if _lx < xn:
                        xn = _lx
                    elif _lx > xx:
                        xx = _lx
                    if _ly < yn:
                        yn = _ly
                    elif _ly > yx:
                        yx = _ly
                x_min, x_max = int(xn * w), int(xx * w)
                y_min, y_max = int(yn * h), int(yx * h)

                # Draw face rectangle
                cv2.rectangle(frame, (x_min, y_min), (x_max, y_max), COLOR_GREEN, 2)

                # Get eye landmarks
                left_eye = self.get_eye_landmarks(face_landmarks, self.LEFT_EYE, w, h)
                right_eye = self.get_eye_landmarks(face_landmarks, self.RIGHT_EYE, w, h)

                # Calculate EAR for both eyes
                left_ear = self.calculate_ear(left_eye)
                right_ear = self.calculate_ear(right_eye)

                # Determine eye state
                left_eye_state = "CLOSED" if left_ear < self.EAR_THRESHOLD else "OPEN"
                right_eye_state = "CLOSED" if right_ear < self.EAR_THRESHOLD else "OPEN"

                # Note: Eye landmark circles removed for performance

                # Detect intoxication
                intox_data = self.detect_intoxication(left_ear, right_ear)

                # Head pose estimation (yaw/pitch from solvePnP)
                head_pose = self.estimate_head_pose(face_landmarks, w, h)

                # Gaze direction + eyes-closed analysis from blendshapes + head pose
                gaze_data = None
                if results.face_blendshapes and face_idx < len(
                    results.face_blendshapes
                ):
                    gaze_data = self.analyze_gaze(
                        results.face_blendshapes[face_idx], head_pose=head_pose
                    )
                elif head_pose:
                    # No blendshapes (e.g. side profile) — use head pose only
                    gaze_data = self.analyze_gaze_from_head_pose(head_pose)

                # Extract face crop for upload (with padding)
                padding = 20
                crop_x_min = max(0, x_min - padding)
                crop_y_min = max(0, y_min - padding)
                crop_x_max = min(w, x_max + padding)
                crop_y_max = min(h, y_max + padding)
                face_crop = frame[crop_y_min:crop_y_max, crop_x_min:crop_x_max].copy()

                # Build detection data for upload
                detection_data = {
                    "intox_data": intox_data,
                    "face_crop": face_crop,
                    "face_bbox": {
                        "x_min": x_min,
                        "y_min": y_min,
                        "x_max": x_max,
                        "y_max": y_max,
                    },
                    "left_eye_state": left_eye_state,
                    "left_eye_ear": left_ear,
                    "right_eye_state": right_eye_state,
                    "right_eye_ear": right_ear,
                    "gaze_data": gaze_data,
                }

                # Optimized text rendering - combine multiple labels into fewer calls
                # Use FONT_HERSHEY_PLAIN (faster) and thickness=1 (50% faster than thickness=2)
                y_offset = y_min - 30
                # Combined eye status in one line
                eye_info = f"L:{left_eye_state}({left_ear:.2f}) R:{right_eye_state}({right_ear:.2f})"
                cv2.putText(
                    frame,
                    eye_info,
                    (x_min, y_offset),
                    FONT_FAST,
                    0.9,
                    COLOR_GREEN,
                    1,
                )

                # Show gaze direction above the eye info
                if gaze_data:
                    gaze_dir = gaze_data["gaze_direction"].upper()
                    head_info = ""
                    if gaze_data.get("head_yaw") or gaze_data.get("head_pitch"):
                        head_info = f" [Y:{gaze_data['head_yaw']:.0f} P:{gaze_data['head_pitch']:.0f}]"

                    # Debug output for downward gaze
                    if gaze_dir == "DOWN" and self._gaze_debug_enabled:
                        print("DEBUG: Downward gaze detected!")

                    if gaze_data["eyes_closed_impaired"]:
                        gaze_label = f"EYES CLOSED ({gaze_data['eyes_closed_seconds']:.1f}s) - IMPAIRED"
                        gaze_color = COLOR_RED
                    elif gaze_data["gaze_distracted"]:
                        gaze_label = f"LOOKING {gaze_dir} ({gaze_data['gaze_away_seconds']:.1f}s) - DISTRACTED{head_info}"
                        gaze_color = COLOR_RED
                    elif gaze_data["eyes_both_closed"]:
                        gaze_label = (
                            f"EYES CLOSED ({gaze_data['eyes_closed_seconds']:.1f}s)"
                        )
                        gaze_color = COLOR_ORANGE
                    elif gaze_dir != "STRAIGHT":
                        gaze_label = f"Gaze: {gaze_dir} ({gaze_data['gaze_away_seconds']:.1f}s){head_info}"
                        gaze_color = COLOR_ORANGE
                    else:
                        gaze_label = f"Gaze: {gaze_dir}{head_info}"
                        gaze_color = COLOR_GREEN

                    cv2.putText(
                        frame,
                        gaze_label,
                        (x_min, y_offset - 16),
                        FONT_FAST,
                        0.9,
                        gaze_color,
                        1,
                    )

                # Determine status and build warning message efficiently
                y_offset = y_max + 20
                if gaze_data and gaze_data["eyes_closed_impaired"]:
                    status = "IMPAIRED - EYES CLOSED"
                    color = COLOR_RED
                elif gaze_data and gaze_data["gaze_distracted"]:
                    status = "DISTRACTED - LOOKING AWAY"
                    color = COLOR_RED
                elif intox_data["score"] >= 4:
                    status = "HIGH RISK - INTOXICATED"
                    color = COLOR_RED
                elif intox_data["score"] >= 2:
                    status = "MODERATE RISK - IMPAIRED"
                    color = COLOR_ORANGE
                else:
                    status = "NORMAL - ALERT"
                    color = COLOR_GREEN

                cv2.putText(
                    frame,
                    status,
                    (x_min, y_offset),
                    FONT_FAST,
                    1.0,
                    color,
                    1,
                )
                y_offset += 18

                # Combine all warnings into a single string for one draw call
                warnings = []
                if intox_data["drowsy"]:
                    warnings.append("Drowsy")
                if intox_data["excessive_blinking"]:
                    warnings.append("Excess Blink")
                if intox_data["unstable_eyes"]:
                    warnings.append("Eye Instability")

                if warnings:
                    warning_text = "WARN: " + ", ".join(warnings)
                    cv2.putText(
                        frame,
                        warning_text,
                        (x_min, y_offset),
                        FONT_FAST,
                        0.9,
                        COLOR_RED if intox_data["drowsy"] else COLOR_ORANGE,
                        1,
                    )

        # --- Face-lost detection: full head turn / side profile ---
        # When the face was visible but now gone, the driver has turned away.
        # Synthesize gaze data so the distraction timer keeps running.
        if (
            detection_data is None
            and self._face_was_present
            and self._face_last_seen is not None
        ):
            face_gone_secs = now - self._face_last_seen

            # Only flag after a brief grace period (0.3s) to avoid flicker
            if face_gone_secs > 0.3:
                # Continue the gaze-away timer from when the face was last seen
                if self._gaze_away_start is None:
                    self._gaze_away_start = self._face_last_seen
                gaze_away_seconds = now - self._gaze_away_start
                gaze_distracted = gaze_away_seconds >= self.GAZE_DISTRACTION_SECONDS

                gaze_data = {
                    "gaze_direction": "away",
                    "gaze_distracted": gaze_distracted,
                    "gaze_away_seconds": round(gaze_away_seconds, 2),
                    "eyes_both_closed": False,
                    "eyes_closed_impaired": False,
                    "eyes_closed_seconds": 0.0,
                    "look_left": 0,
                    "look_right": 0,
                    "look_down": 0,
                    "look_up": 0,
                    "blink_left": 0,
                    "blink_right": 0,
                    "head_yaw": 0.0,
                    "head_pitch": 0.0,
                }

                # Build minimal detection_data with face-lost gaze
                detection_data = {
                    "intox_data": {
                        "drowsy": False,
                        "excessive_blinking": False,
                        "unstable_eyes": False,
                        "score": 0,
                        "ear": 0.0,
                    },
                    "face_crop": None,
                    "face_bbox": None,
                    "left_eye_state": "UNKNOWN",
                    "left_eye_ear": 0.0,
                    "right_eye_state": "UNKNOWN",
                    "right_eye_ear": 0.0,
                    "gaze_data": gaze_data,
                }

                # Draw "FACE LOST" warning on frame
                label = f"FACE LOST ({face_gone_secs:.1f}s)"
                color = COLOR_RED if gaze_distracted else COLOR_ORANGE
                cv2.putText(frame, label, (10, 30), FONT_FAST, 1.2, color, 1)
                if gaze_distracted:
                    cv2.putText(
                        frame,
                        "DISTRACTED - LOOKING AWAY",
                        (10, 52),
                        FONT_FAST,
                        1.0,
                        COLOR_RED,
                        1,
                    )

        return frame, detection_data

    def process_frame(self, frame, timestamp_ms):
        """Async face detection — submits to background thread, returns cached results.

        Works like DistractionDetector.detect(): the heavy MediaPipe inference
        runs in a background thread so the main loop never blocks.  Returns
        the most recent annotated frame + detection_data instantly.

        Returns:
            tuple: (processed_frame, detection_data) — from the latest completed analysis
        """
        # Check for completed background result
        if self._future is not None and self._future.done():
            try:
                annotated_frame, det_data = self._future.result()
                self._cached_frame = annotated_frame
                self._cached_detection = det_data
            except Exception:
                pass
            self._future = None

        # Submit new analysis if background thread is free
        if self._future is None and timestamp_ms > self._last_ts:
            self._last_ts = timestamp_ms
            # frame.copy() gives the background thread its own memory
            self._future = self._executor.submit(
                self._analyze_frame_sync, frame.copy(), timestamp_ms
            )

        # Return latest annotated frame + detection data.
        # The frame has face annotations baked in from the background thread.
        # YOLO boxes drawn later may be on a 1-frame-old base — imperceptible.
        if self._cached_frame is not None:
            return self._cached_frame, self._cached_detection

        # No result yet (first few frames) — return raw frame
        return frame, None

    def shutdown(self):
        """Shutdown the background analysis thread."""
        if self._executor is not None:
            self._executor.shutdown(wait=False)


class MusicRecognizer:
    """Manages microphone and Shazam integration for ambient music detection"""

    def __init__(self, recognition_interval=20, debug_save_audio=False):
        """Initialize music recognizer

        Args:
            recognition_interval: Seconds between recognition attempts (default: 20)
            debug_save_audio: If True, saves audio samples to audio_samples/ directory
        """
        self.microphone = None
        self.shazam = None
        self.recognition_interval = recognition_interval
        self.debug_save_audio = debug_save_audio
        self.last_recognition = 0
        self.enabled = False
        self._recognizing = False

    def start(self):
        """Start microphone and Shazam services"""
        try:
            # Initialize microphone
            self.microphone = MicrophoneController(sample_rate=44100, channels=1)
            self.microphone.start()

            # Initialize Shazam
            self.shazam = ShazamRecognizer(debug_save_audio=self.debug_save_audio)
            self.shazam.start()

            self.enabled = True

            # Determine mode
            if self.microphone.is_fake and self.shazam.is_fake:
                mode = "SIMULATED (no microphone or Shazam API)"
            elif self.microphone.is_fake:
                mode = "REAL SHAZAM / SIMULATED MICROPHONE (no audio input device)"
            elif self.shazam.is_fake:
                mode = "REAL MICROPHONE / SIMULATED SHAZAM (no shazamio library)"
            else:
                mode = "REAL (hardware microphone + Shazam API)"

            print(f"\nMusic recognition enabled:")
            print(f"  Mode: {mode}")
            print(f"  Interval: {self.recognition_interval}s between attempts")
            print(f"  Microphone: {'SIMULATED' if self.microphone.is_fake else 'REAL'}")
            print(f"  Shazam API: {'SIMULATED' if self.shazam.is_fake else 'REAL'}")

        except Exception as e:
            print(f"Music recognition unavailable: {e}")
            self.enabled = False

    def stop(self):
        """Stop microphone and cleanup resources"""
        if self.microphone:
            self.microphone.stop()
        print("Music recognition stopped")

    def should_recognize(self):
        """Check if enough time has passed for another recognition"""
        current_time = time.time()
        return (
            self.enabled
            and not self._recognizing
            and (current_time - self.last_recognition) >= self.recognition_interval
        )

    def recognize_song(self, callback=None):
        """Attempt to recognize currently playing song (non-blocking)

        Args:
            callback: Optional function to call with song_info when recognition completes
        """
        if not self.should_recognize():
            return

        self._recognizing = True
        self.last_recognition = time.time()

        def _do_recognition():
            try:
                # Get recent audio (last 5 seconds for recognition)
                wav_data = self.microphone.get_audio_wav(duration=5)
                audio_bytes = wav_data.getvalue()

                # Check audio level
                audio_level = self.microphone.get_audio_level()
                level_status = (
                    "SILENT"
                    if audio_level < 0.01
                    else "QUIET"
                    if audio_level < 0.1
                    else "GOOD"
                    if audio_level < 0.5
                    else "LOUD"
                )

                print(
                    f"SHAZAM: Captured {len(audio_bytes)} bytes of audio (level: {audio_level * 100:.1f}% - {level_status})"
                )

                # Check if we actually got audio data
                if len(audio_bytes) < 1000:
                    print(
                        f"SHAZAM: ✗ Warning - very little audio captured ({len(audio_bytes)} bytes)"
                    )
                    print(
                        "SHAZAM:   Check if microphone is working and music is playing"
                    )
                    return

                # Warn if audio is silent or very quiet
                if audio_level < 0.01:
                    print(
                        f"SHAZAM: ⚠️  Warning - microphone is SILENT (level: {audio_level * 100:.1f}%)"
                    )
                elif audio_level < 0.05:
                    print(
                        f"SHAZAM: ⚠️  Warning - audio is very QUIET (level: {audio_level * 100:.1f}%)"
                    )

                # Recognize song
                song_info = self.shazam.recognize_from_bytes(audio_bytes)

                # Call callback if provided
                if callback and song_info:
                    callback(song_info)
                elif not song_info:
                    print("SHAZAM: No song identified from audio")
                    if self.microphone.is_fake:
                        print("SHAZAM:   (Using simulated microphone - no real audio)")

            except Exception as e:
                print(f"SHAZAM: ✗ Error during music recognition: {e}")
                import traceback

                traceback.print_exc()
            finally:
                self._recognizing = False

        threading.Thread(target=_do_recognition, daemon=True).start()

    @property
    def is_recognizing(self):
        """Check if currently performing recognition"""
        return self._recognizing

    @property
    def is_enabled(self):
        """Check if music recognition is enabled and working"""
        return self.enabled


def draw_dashcam_hud(frame, speed, heading, direction):
    """Draw speed/heading/time HUD bar at the top of the frame."""
    h, w = frame.shape[:2]
    # Semi-transparent dark bar at top
    overlay = frame[0:36, 0:w].copy()
    frame[0:36, 0:w] = (overlay * 0.4).astype(frame.dtype)
    timestamp = datetime.now(PST).strftime("%Y-%m-%d %H:%M:%S")
    hud_text = f"{speed} MPH  {direction}  {heading}\xb0  {timestamp}"
    cv2.putText(frame, hud_text, (10, 25), FONT_FAST, 1.2, COLOR_WHITE, 1)
    return frame


def draw_distraction_warning(frame, distraction_data, gaze_data=None):
    """Draw stacked distraction warning banners on frame.

    Shows ALL active warnings simultaneously, stacked from the bottom.
    Each banner is 30px tall with its own color and label.
    """
    if not distraction_data:
        return frame

    h, w = frame.shape[:2]
    banner_h = 30

    # Collect all active warnings: (label, color)
    warnings = []

    if gaze_data and gaze_data.get("eyes_closed_impaired"):
        secs = gaze_data["eyes_closed_seconds"]
        warnings.append((f"IMPAIRED: EYES CLOSED ({secs:.1f}s)", COLOR_DARK_RED))

    if gaze_data and gaze_data.get("gaze_distracted"):
        direction = gaze_data["gaze_direction"].upper()
        secs = gaze_data["gaze_away_seconds"]
        warnings.append(
            (f"DISTRACTED: LOOKING {direction} ({secs:.1f}s)", COLOR_DARK_RED)
        )

    if distraction_data.get("phone_detected"):
        warnings.append(("WARNING: PHONE DETECTED", COLOR_DARK_RED))

    if distraction_data.get("drinking_detected"):
        warnings.append(("WARNING: DRINKING DETECTED", COLOR_DARK_ORANGE))

    if not warnings:
        return frame

    # Draw banners stacked from bottom
    for i, (label, color) in enumerate(warnings):
        y_top = h - banner_h * (i + 1)
        y_bot = h - banner_h * i
        frame[y_top:y_bot, 0:w] = color
        cv2.putText(
            frame,
            label,
            (10, y_bot - 8),
            FONT_FAST,
            1.4,
            COLOR_WHITE,
            1,
        )

    return frame


def main():
    print("Imports complete. Starting main()...", flush=True)
    parser = argparse.ArgumentParser(description="Driver monitoring system")
    parser.add_argument(
        "--headless",
        action="store_true",
        default=os.environ.get("HEADLESS", "").lower() in ("true", "1", "yes"),
        help="Run without GUI display (env: HEADLESS=true)",
    )
    parser.add_argument(
        "--camera",
        type=int,
        default=int(os.environ.get("CAMERA_INDEX", "0")),
        help="Camera device index (env: CAMERA_INDEX, default: 0)",
    )
    args = parser.parse_args()
    headless = args.headless

    # Graceful shutdown via SIGINT/SIGTERM in headless mode
    shutdown_requested = False

    def _signal_handler(signum, frame):
        nonlocal shutdown_requested
        print("\nShutdown signal received, stopping...")
        shutdown_requested = True

    signal.signal(signal.SIGINT, _signal_handler)
    signal.signal(signal.SIGTERM, _signal_handler)

    # --- Parallel startup: run availability checks, Supabase network init,
    # GPS, and camera probe all at the same time.  This overlaps ~5s of
    # MediaPipe/YOLO import checks with ~2-3s of Supabase HTTP round-trips.
    gps_reader = GPSReader()
    gps_reader.start()

    speed_limit_checker = SpeedLimitChecker(search_radius=50)
    driving_sim = DrivingSimulator(
        gps_reader=gps_reader, speed_limit_checker=speed_limit_checker
    )
    buzzer = BuzzerController()
    buzzer.start()

    # Launch availability checks + Supabase init in parallel
    with ThreadPoolExecutor(max_workers=3) as _boot_pool:
        _mp_fut = _boot_pool.submit(_check_mediapipe)
        _yolo_fut = _boot_pool.submit(_check_yolo)
        _supa_fut = _boot_pool.submit(SupabaseUploader, buzzer)
        _mp_fut.result()  # sets _MEDIAPIPE_AVAILABLE
        _yolo_fut.result()  # sets YOLO_AVAILABLE, YOLO_ONNX_AVAILABLE
        supabase_uploader = _supa_fut.result()

    # Feature settings from Supabase (falls back to .env)
    settings = supabase_uploader.feature_settings
    enable_yolo = settings["enable_yolo"]  # Always True (or True if YOLO available)
    enable_stream = settings["enable_stream"]
    enable_shazam = settings["enable_shazam"] and settings["enable_microphone"]
    enable_camera = settings["enable_camera"]  # Always True
    enable_dashcam = settings["enable_dashcam"]

    # Initialize BLE GATT server (direct iOS communication)
    ble_server = None
    if BLE_AVAILABLE:

        def _ble_settings_write(data):
            """Handle settings written from iOS via BLE."""
            # Note: Camera and YOLO are always enabled and cannot be toggled
            key_map = {
                "stream": "enable_stream",
                "shazam": "enable_shazam",
                "mic": "enable_microphone",
                "dash": "enable_dashcam",
            }
            for short, full in key_map.items():
                if short in data:
                    supabase_uploader.feature_settings[full] = bool(data[short])
            print(
                f"[BLE] Feature settings updated: {supabase_uploader.feature_settings}"
            )

        def _ble_buzzer_write(data):
            """Handle buzzer commands from iOS via BLE."""
            if data.get("active"):
                custom_params = None
                if data.get("type") == "custom":
                    custom_params = {
                        "freq": data.get("freq", 800),
                        "on": data.get("on", 0.5),
                        "off": data.get("off", 0.5),
                        "duty": data.get("duty", 50),
                    }
                buzzer.start_continuous(
                    data.get("type", "alert"), custom_params=custom_params
                )
            else:
                buzzer.stop_continuous()

        def _ble_recording_write(data):
            """Handle recording commands from iOS via BLE."""
            nonlocal dashcam
            command = data.get("command", "")
            if command == "stop":
                if dashcam:
                    print("[BLE] Stopping dashcam recording...")
                    dashcam.stop()
                    dashcam = None
                    print("[BLE] Dashcam recording stopped successfully")
            elif command == "start":
                if not dashcam and cap:
                    print("[BLE] Starting dashcam recording...")
                    dashcam = DashcamRecorder()
                    dashcam.start(supabase_uploader.trip_id, width, height)
                    print("[BLE] Dashcam recording started successfully")

        ble_server = BluetoothServer(
            on_settings_write=_ble_settings_write,
            on_buzzer_write=_ble_buzzer_write,
            on_recording_write=_ble_recording_write,
        )
        ble_server.start()
        ble_server.update_settings(settings)

    # --- Hardware retry loop ---
    # If camera or microphone is enabled but fails to open, blast the error
    # buzzer and retry every second until the hardware is available.
    # If camera disconnects mid-session, clean up and loop back here.

    def _try_open_camera(camera_index):
        """Attempt to open camera. Returns True if openable."""
        test = cv2.VideoCapture(camera_index)
        opened = test.isOpened()
        test.release()
        return opened

    def _try_open_microphone():
        """Attempt to open microphone. Returns True if real mic available."""
        try:
            mic = MicrophoneController(sample_rate=44100, channels=1)
            mic.start()
            is_real = not mic.is_fake
            mic.stop()
            return is_real
        except Exception:
            return False

    camera_needed = enable_camera
    mic_needed = enable_shazam

    while not shutdown_requested:
        # --- Phase 1: Wait for hardware ---
        while not shutdown_requested:
            camera_ok = not camera_needed or _try_open_camera(args.camera)
            mic_ok = not mic_needed or _try_open_microphone()

            if camera_ok:
                # Camera is available, proceed even if microphone is missing
                if mic_needed and not mic_ok:
                    print(
                        "Camera detected but microphone not available. Proceeding without microphone and Shazam."
                    )
                break

            missing = []
            if not camera_ok:
                missing.append("camera")
            if not mic_ok and mic_needed:
                missing.append("microphone")
            print(f"Waiting for hardware: {', '.join(missing)}...")
            buzzer.play_error_alert()
            time.sleep(1)

        if shutdown_requested:
            break

        # Hardware available — play startup sound and begin session
        buzzer.play_startup_alert()
        print("\n=== Starting new session ===\n")

        # --- Phase 2: Initialize session resources ---
        cap = None
        analyzer = None
        distraction_detector = None
        music_recognizer = None
        streamer = None
        dashcam = None
        gyro_reader = None
        crash_detector = None
        width, height = 0, 0

        # Custom ONNX model inference (replaces MediaPipe EAR + YOLO)
        # Disabled by default — set ENABLE_CUSTOM_MODELS=true in .env to use
        driver_system = None
        if _ENV_ENABLE_CUSTOM_MODELS:
            print("Loading custom ONNX models...", flush=True)
            try:
                print("  Importing DriverAwarenessSystem...", end=" ", flush=True)
                from models.inference import DriverAwarenessSystem

                print("ok")

                eye_path = _find_model(_EYE_CANDIDATES)
                activity_path = _find_model(_ACTIVITY_CANDIDATES)
                if eye_path or activity_path:
                    print(f"  Loading eye model: {eye_path}", flush=True)
                    print(f"  Loading activity model: {activity_path}", flush=True)
                    driver_system = DriverAwarenessSystem(
                        eye_model_path=eye_path,
                        activity_model_path=activity_path,
                    )
                    health = driver_system.get_health()
                    print(
                        f"  Custom ONNX models loaded: eye={health['eye_model_loaded']}, activity={health['activity_model_loaded']}"
                    )
                else:
                    print("  No ONNX model files found in models/checkpoints/")
            except ImportError as e:
                print(f"FAILED ({e})")
                print("  Custom models not available (models package not found)")
            except Exception as e:
                print(f"FAILED ({e})")
                print("  Falling back to MediaPipe + YOLO")
                driver_system = None
        else:
            print(
                "Custom ONNX models disabled (set ENABLE_CUSTOM_MODELS=true in .env to enable)"
            )

        if enable_camera:
            # Load camera, FaceAnalyzer, and YOLO all in parallel — camera
            # open (~0.5s) overlaps with model loading (~2-3s each).
            def _open_camera():
                _cap = ThreadedCamera(args.camera)
                if not _cap.isOpened():
                    print("Error: Could not open camera — continuing without it")
                    return None
                _cap.start()
                return _cap

            if _IS_ARM_LINUX:
                # --- RPi4: use multiprocessing (separate CPU cores) ---
                # Each inference model gets its own process, bypassing the GIL.
                # Core 1: main loop + camera   Core 2: FaceAnalyzer
                # Core 3: YOLO/ONNX            Core 4: OS + I/O threads
                print("Using MULTIPROCESSING mode (ARM Linux — 4 cores)")
                cap = _open_camera()
                analyzer = FaceAnalyzerProxy(mp_max_dim=640)
                distraction_detector = DistractionDetectorProxy(enabled=enable_yolo)
            else:
                # --- macOS / other: use threads (fast enough with CoreML) ---
                def _load_face_analyzer():
                    if _check_mediapipe():
                        try:
                            fa = FaceAnalyzer()
                            print("  FaceAnalyzer loaded")
                            return fa
                        except Exception as e:
                            print(f"  FaceAnalyzer failed ({e}), using fallback")
                            return FallbackFaceDetector()
                    return FallbackFaceDetector()

                def _load_distraction_detector():
                    dd = DistractionDetector(enabled=enable_yolo)
                    print("  DistractionDetector loaded")
                    return dd

                with ThreadPoolExecutor(max_workers=3) as _model_pool:
                    _cam_future = _model_pool.submit(_open_camera)
                    _fa_future = _model_pool.submit(_load_face_analyzer)
                    _dd_future = _model_pool.submit(_load_distraction_detector)
                    cap = _cam_future.result()
                    analyzer = _fa_future.result()
                    distraction_detector = _dd_future.result()

            if cap is not None:
                width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
                height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
                print(f"Camera opened: {width}x{height} (threaded capture)")
        else:
            print("Camera disabled via Supabase settings")

        mode_label = "HEADLESS" if headless else "GUI"
        print(f"Mode: {mode_label}")

        # Print hardware status summary
        print("\nHardware Status:")
        print(f"  Camera: {'✓ Available' if cap else '✗ Not available'}")
        print(
            f"  Microphone: {'✓ Available' if music_recognizer else '✗ Not available'}"
        )
        if enable_shazam:
            print(
                f"  Shazam: {'✓ Enabled' if music_recognizer else '✗ Disabled (microphone not available)'}"
            )
        else:
            print("  Shazam: ✗ Disabled (feature off)")

        if cap:
            if enable_yolo:
                print("- YOLO ENABLED")
            else:
                print("- YOLO DISABLED")
        else:
            print("- Camera OFF (face detection, YOLO, streaming unavailable)")
        if enable_stream and cap:
            print(f"- Video stream via Supabase Storage (~{STREAM_FPS} fps)")
        if enable_shazam:
            # Check if microphone is available
            mic_available = not mic_needed or _try_open_microphone()
            if mic_available:
                print(f"- Shazam music recognition (~every {SHAZAM_INTERVAL}s)")
            else:
                print("- Shazam music recognition DISABLED (microphone not available)")
        if enable_dashcam and cap:
            print("- Dashcam recording (local MP4)")
        if not headless and cap:
            print("- Press 'X' to simulate speeding (75 MPH)")
            print("- Press 'C' to reset speed to normal (45 MPH)")
            print("- Press UP/DOWN arrows to adjust speed by 10 MPH")

        # Video streaming (requires camera)
        if enable_stream and cap:
            streamer = VideoStreamer(
                supabase_client=supabase_uploader.client,
                vehicle_id=supabase_uploader.vehicle_id,
                quality=STREAM_QUALITY,
                fps=STREAM_FPS,
                width=STREAM_WIDTH,
            )
            streamer.start()

        # Dashcam recording (requires camera)
        if enable_dashcam and cap:
            dashcam = DashcamRecorder()
            dashcam.start(supabase_uploader.trip_id, width, height)

        # Music recognition (requires microphone)
        if enable_shazam:
            # Only start music recognizer if microphone is available
            mic_ok = not mic_needed or _try_open_microphone()
            if mic_ok:
                music_recognizer = MusicRecognizer(
                    recognition_interval=SHAZAM_INTERVAL, debug_save_audio=SHAZAM_DEBUG
                )
                music_recognizer.start()
                print("Shazam music recognition started")
            else:
                print("Shazam disabled: microphone not available")

        # Optional gyro reader (serial acc/gyro)
        last_effective_risk = None
        GYRO_HARSH_THRESHOLD_DEG_S = 50.0
        GYRO_BUMP = 1
        if GYRO_AVAILABLE:
            try:
                _gr = GyroReader()
                _gr.start(print_from_loop=False)
                gyro_reader = _gr
                crash_detector = CrashDetector()
                print("Gyro reader started (serial, crash detection enabled)")
            except Exception as e:
                print(f"Gyro reader unavailable: {e}")

        frame_count = 0

        # FPS tracking
        fps_frame_count = 0  # loop iterations (for loop FPS)
        fps_cam_start_seq = cap.frame_count if cap else 0  # camera HW frames
        fps_start_time = time.time()
        last_fps_print = time.time()

        process_times = deque(maxlen=100)  # Track last 100 total frame times
        draw_times = deque(maxlen=100)

        # Pre-allocated default dict — reused every frame when no detections
        _DEFAULT_DISTRACTION = {
            "phone_detected": False,
            "drinking_detected": False,
            "phone_bbox": None,
            "bottle_bbox": None,
            "phone_frames": 0,
            "drinking_frames": 0,
            "hand_at_ear": False,
        }

        # --- Phase 3: Main processing loop ---
        print(f"Startup complete in {time.time() - _startup_t0:.1f}s")
        while not shutdown_requested:
            frame_start_time = time.time()

            # Update driving simulation (GPS / speed)
            driving_sim.update_speed()

            # Defaults when camera is off
            processed_frame = None
            detection_data = None
            intox_data = None
            awareness = None
            distraction_data = _DEFAULT_DISTRACTION

            # --- Camera-dependent processing ---
            if cap is not None:
                ret, frame = cap.read()
                if not ret:
                    print("Error: Could not read frame — camera disconnected")
                    break

                if _ENV_MIRROR_CAMERA:
                    frame = cv2.flip(frame, 1)

                timestamp_ms = int(frame_count * 33.33)
                frame_count += 1
                fps_frame_count += 1

                # Face detection (async — submits to background thread, returns cached)
                processed_frame, detection_data = analyzer.process_frame(
                    frame, timestamp_ms
                )

                # YOLO distraction detection (async — no-op when custom models loaded)
                # Pass face_bbox so hand-at-ear can locate ear regions
                face_bbox = detection_data.get("face_bbox") if detection_data else None
                distraction_data = distraction_detector.detect(
                    frame, face_bbox=face_bbox
                )

                # Custom model inference: override distraction_data and intox_data
                if driver_system:
                    face_crop = detection_data["face_crop"] if detection_data else None
                    awareness = driver_system.process_frame(
                        face_crop=face_crop,
                        upper_body_crop=frame,
                    )
                    # Override YOLO results with activity model output
                    distraction_data = {
                        "phone_detected": awareness["is_phone_detected"],
                        "drinking_detected": awareness["is_drinking_detected"],
                        "phone_bbox": None,
                        "bottle_bbox": None,
                        "phone_frames": 0,
                        "drinking_frames": 0,
                    }
                    # Override MediaPipe EAR intoxication with eye model output
                    intox_data = {
                        "drowsy": awareness["is_drowsy"],
                        "excessive_blinking": awareness["is_excessive_blinking"],
                        "unstable_eyes": awareness["is_unstable_eyes"],
                        "score": awareness["intoxication_score"],
                        "ear": awareness["ear_score"],
                    }
                    # Override detection_data fields for Supabase upload
                    if detection_data:
                        detection_data["intox_data"] = intox_data
                        detection_data["left_eye_state"] = awareness["left_eye_state"]
                        detection_data["right_eye_state"] = awareness["right_eye_state"]
                        detection_data["left_eye_ear"] = awareness["ear_score"]
                        detection_data["right_eye_ear"] = awareness["ear_score"]
                else:
                    intox_data = (
                        detection_data["intox_data"] if detection_data else None
                    )

                # Extract gaze data from this frame (if available)
                gaze_data = detection_data.get("gaze_data") if detection_data else None

                # Buzzer alerts — continuous for phone/gaze, one-shot for others
                _buzzer_continuous_needed = False
                if distraction_data["phone_detected"]:
                    _buzzer_continuous_needed = True
                if gaze_data and gaze_data["gaze_distracted"]:
                    _buzzer_continuous_needed = True

                if _buzzer_continuous_needed:
                    if not buzzer.continuous_active:
                        buzzer.start_continuous("alert")
                else:
                    if buzzer.continuous_active:
                        buzzer.stop_continuous()
                    # One-shot alert for prolonged eyes closed
                    if gaze_data and gaze_data["eyes_closed_impaired"]:
                        buzzer.play_drowsy_alert()
            else:
                gaze_data = None
                # Camera off — throttle loop to ~10 Hz
                time.sleep(0.1)

            # --- Always: driver status + composite risk score ---
            if awareness:
                driver_status = awareness["driver_state"]
            elif gaze_data and gaze_data["eyes_closed_impaired"]:
                driver_status = "impaired"
            elif gaze_data and gaze_data["gaze_distracted"]:
                driver_status = "distracted_gaze"
            elif distraction_data["phone_detected"]:
                driver_status = "distracted_phone"
            elif distraction_data["drinking_detected"]:
                driver_status = "distracted_drinking"
            else:
                driver_status = "alert"

            # --- Composite risk score (0-6) ---
            effective_risk = 0

            # Phone detected → max risk immediately
            if distraction_data["phone_detected"]:
                effective_risk = 6

            # Gaze distraction → risk increases with duration
            if gaze_data:
                # Looking down is immediately 6/6 risk (phone usage)
                if gaze_data["gaze_direction"] == "down":
                    effective_risk = 6
                elif gaze_data["gaze_away_seconds"] > 0:
                    away_secs = gaze_data["gaze_away_seconds"]
                    if away_secs >= 4.0:
                        gaze_risk = 4  # 4+ seconds looking away
                    elif away_secs >= 3.0:
                        gaze_risk = 3
                    elif away_secs >= 2.0:
                        gaze_risk = 2  # crosses distraction threshold
                    elif away_secs >= 1.0:
                        gaze_risk = 1  # starting to look away
                    else:
                        gaze_risk = 0
                    effective_risk = max(effective_risk, gaze_risk)

            # Eyes closed → high risk
            if gaze_data and gaze_data["eyes_closed_impaired"]:
                effective_risk = max(effective_risk, 5)

            # Speeding → adds +1 or +2 to risk
            if driving_sim.is_speeding():
                speed_over = driving_sim.get_speed() - driving_sim.speed_limit
                if speed_over > 15:
                    effective_risk = min(6, effective_risk + 2)
                else:
                    effective_risk = min(6, effective_risk + 1)

            # Gyro — graduated scale based on harshness of motion
            if gyro_reader is not None:
                latest = gyro_reader.get_latest()
                if latest is not None:
                    gyro_mag = latest["gyro_mag"]
                    if gyro_mag >= 150.0:
                        gyro_bump = 3  # extreme swerving
                    elif gyro_mag >= 100.0:
                        gyro_bump = 2  # harsh maneuver
                    elif gyro_mag >= GYRO_HARSH_THRESHOLD_DEG_S:
                        gyro_bump = 1  # notable motion
                    else:
                        gyro_bump = 0
                    effective_risk = min(6, effective_risk + gyro_bump)
                    last_effective_risk = effective_risk

                    # Crash detection
                    if crash_detector is not None:
                        crash_detector.feed(
                            latest["acc_mag"],
                            latest["acc_delta"],
                            gyro_mag,
                            latest["timestamp"],
                        )
                        crash_event = crash_detector.get_crash_event()
                        if crash_event:
                            print(
                                f"\n>>> CRASH DETECTED: {crash_event['severity'].upper()} <<<"
                            )
                            print(
                                f"    Peak: {crash_event['peak_g']}g, Gyro: {crash_event['peak_gyro']} deg/s\n"
                            )
                            buzzer.start_continuous("emergency")
                            supabase_uploader.record_crash(crash_event)

            effective_risk = min(6, effective_risk)

            # --- Always: realtime + trip + buzzer ---
            supabase_uploader.update_vehicle_realtime(
                speed_mph=driving_sim.get_speed(),
                heading_degrees=driving_sim.get_heading(),
                compass_direction=driving_sim.get_compass_direction(),
                is_speeding=driving_sim.is_speeding(),
                driver_status=driver_status,
                intoxication_score=effective_risk,
                latitude=driving_sim.get_latitude(),
                longitude=driving_sim.get_longitude(),
                satellites=driving_sim.get_satellites(),
                is_phone_detected=distraction_data["phone_detected"],
                is_drinking_detected=distraction_data["drinking_detected"],
            )

            supabase_uploader.update_trip_stats(
                speed=driving_sim.get_speed(),
                intox_score=effective_risk,
                is_speeding=driving_sim.is_speeding(),
                is_drowsy=False,
                is_excessive_blinking=False,
                is_unstable_eyes=False,
                latitude=driving_sim.get_latitude(),
                longitude=driving_sim.get_longitude(),
                is_real_gps=driving_sim.is_using_gps() and driving_sim.has_gps_fix(),
            )

            supabase_uploader.check_buzzer_commands()

            # --- BLE direct updates (alongside Supabase) ---
            if ble_server and not ble_server.is_fake:
                ble_server.update_realtime(
                    {
                        "speed_mph": driving_sim.get_speed(),
                        "heading_degrees": driving_sim.get_heading(),
                        "compass_direction": driving_sim.get_compass_direction(),
                        "is_speeding": driving_sim.is_speeding(),
                        "driver_status": driver_status,
                        "intoxication_score": effective_risk,
                        "latitude": driving_sim.get_latitude(),
                        "longitude": driving_sim.get_longitude(),
                        "satellites": driving_sim.get_satellites(),
                        "is_phone_detected": distraction_data["phone_detected"],
                        "is_drinking_detected": distraction_data["drinking_detected"],
                        "camera_url": None,
                    }
                )
                ble_server.update_trip(
                    {
                        "trip_id": supabase_uploader.trip_id or "",
                        "duration": int(time.time() - fps_start_time),
                        "max_speed": supabase_uploader.trip_max_speed,
                        "avg_speed": sum(supabase_uploader.trip_speed_samples)
                        / max(len(supabase_uploader.trip_speed_samples), 1),
                        "speeding_events": supabase_uploader.trip_speeding_events,
                        "drowsy_events": supabase_uploader.trip_drowsy_events,
                        "phone_events": getattr(
                            supabase_uploader, "trip_phone_events", 0
                        ),
                        "max_intox_score": supabase_uploader.trip_max_intox_score,
                    }
                )

                # Relay: send full Supabase-format records for iOS to upload
                # when the Pi has no internet. iOS reads this and upserts to Supabase.
                relay_data = {}
                if supabase_uploader.latest_realtime_record:
                    relay_data["rt"] = supabase_uploader.latest_realtime_record
                if supabase_uploader.latest_trip_record:
                    relay_data["trip"] = supabase_uploader.latest_trip_record
                if relay_data:
                    ble_server.update_relay(relay_data)

            # --- Camera-dependent uploads ---
            if cap is not None:
                if (
                    detection_data
                    and detection_data.get("face_crop") is not None
                    and supabase_uploader.should_upload()
                ):
                    driving_data = {
                        "speed": driving_sim.get_speed(),
                        "heading": driving_sim.get_heading(),
                        "direction": driving_sim.get_compass_direction(),
                        "is_speeding": driving_sim.is_speeding(),
                    }
                    supabase_uploader.upload_face_detection(
                        face_image=detection_data["face_crop"],
                        face_bbox=detection_data["face_bbox"],
                        left_eye_state=detection_data["left_eye_state"],
                        left_eye_ear=detection_data["left_eye_ear"],
                        right_eye_state=detection_data["right_eye_state"],
                        right_eye_ear=detection_data["right_eye_ear"],
                        intox_data=detection_data["intox_data"],
                        driving_data=driving_data,
                        distraction_data=distraction_data,
                    )
                    supabase_uploader.increment_face_detection_count()

                if detection_data:
                    supabase_uploader.increment_face_detection_count()

            # Music recognition (independent of camera)
            if music_recognizer:
                music_recognizer.recognize_song(
                    callback=supabase_uploader.upload_music_detection
                )

            # --- Drawing / streaming / GUI (camera only) ---
            if cap is not None and processed_frame is not None:
                # Only draw overlays when someone will see them (GUI or streaming)
                _need_draw = not headless or streamer or dashcam
                if _need_draw:
                    t_draw = time.time()
                    processed_frame = distraction_detector.draw_detections(
                        processed_frame
                    )
                    processed_frame = draw_distraction_warning(
                        processed_frame, distraction_data, gaze_data=gaze_data
                    )
                    draw_times.append(time.time() - t_draw)

                # Track total frame processing time
                frame_end_time = time.time()
                process_times.append(frame_end_time - frame_start_time)

                # Print FPS stats every 5 seconds
                current_time = time.time()
                if current_time - last_fps_print >= 5.0:
                    elapsed = current_time - fps_start_time
                    # Actual camera hardware FPS (unique frames from sensor)
                    cam_frames = cap.frame_count - fps_cam_start_seq
                    capture_fps = cam_frames / elapsed if elapsed > 0 else 0
                    avg_total = (
                        sum(process_times) / len(process_times) if process_times else 0
                    )
                    loop_fps = 1.0 / avg_total if avg_total > 0 else 0
                    avg_draw = sum(draw_times) / len(draw_times) if draw_times else 0

                    # YOLO stats from the async executor
                    yolo_ms, yolo_fps, yolo_runs = (
                        distraction_detector.get_yolo_stats()
                        if distraction_detector
                        else (0, 0, 0)
                    )
                    yolo_label = (
                        f"YOLO: {yolo_fps:.1f} FPS ({yolo_ms:.1f}ms, {yolo_runs} runs)"
                        if distraction_detector and distraction_detector.enabled
                        else "YOLO: OFF"
                    )

                    stats_lines = (
                        f"\n[STATS] Loop: {loop_fps:.1f} FPS "
                        f"({avg_total * 1000:.1f}ms/frame) | "
                        f"Camera: {capture_fps:.1f} FPS | "
                        f"{yolo_label}\n"
                        f"        Draw: {avg_draw * 1000:.1f}ms | "
                        f"Resolution: {width}x{height}\n"
                    )
                    if gyro_reader is not None:
                        gyro_latest = gyro_reader.get_latest()
                        if gyro_latest is not None:
                            gyro_part = (
                                f"        Gyro: {gyro_latest['gyro_mag']:.2f} deg/s"
                            )
                            if last_effective_risk is not None:
                                gyro_part += f" | risk+gyro: {last_effective_risk}"
                            stats_lines += gyro_part + "\n"
                    print(stats_lines)

                    if distraction_detector:
                        distraction_detector.reset_yolo_stats()
                    fps_frame_count = 0
                    fps_cam_start_seq = cap.frame_count
                    fps_start_time = current_time
                    last_fps_print = current_time

                if streamer:
                    streamer.update_frame(processed_frame)

                # HTTP camera server: always update with latest frame
                if dashcam:
                    dashcam.write_frame(
                        processed_frame,
                        hud_data={
                            "speed": driving_sim.get_speed(),
                            "heading": driving_sim.get_heading(),
                            "direction": driving_sim.get_compass_direction(),
                        },
                    )

                if not headless:
                    cv2.imshow("Infineon Project - Winter 2026", processed_frame)
                    key = cv2.waitKey(1) & 0xFF

                    if key == ord("q"):
                        shutdown_requested = True
                        break
                    elif key == 82 or key == 0:
                        driving_sim.manual_speed_increase(10)
                        print(f"Speed increased to: {driving_sim.get_speed()} MPH")
                    elif key == 84 or key == 1:
                        driving_sim.manual_speed_decrease(10)
                        print(f"Speed decreased to: {driving_sim.get_speed()} MPH")
                    elif key == ord("x"):
                        driving_sim.set_speeding_mode()
                        print(
                            f"SPEEDING MODE: Speed set to {driving_sim.get_speed()} MPH"
                        )
                    elif key == ord("c"):
                        driving_sim.reset_speed()
                        print(f"Speed reset to: {driving_sim.get_speed()} MPH")

        # --- Per-session cleanup ---
        print("\n=== Session ended, cleaning up ===\n")
        if dashcam:
            dashcam.stop()
        if streamer:
            streamer.stop()
        if gyro_reader is not None:
            gyro_reader.stop()
        if music_recognizer:
            music_recognizer.stop()
        if distraction_detector:
            distraction_detector.shutdown()
        if analyzer and hasattr(analyzer, "shutdown"):
            analyzer.shutdown()
        if cap is not None:
            cap.release()
        if not headless and cap is not None:
            cv2.destroyAllWindows()

        # If shutdown was requested (Ctrl+C / 'q'), exit the outer loop
        if shutdown_requested:
            break

        # Otherwise camera/mic disconnected — loop back to hardware retry
        print("Hardware lost — will retry...\n")

    # --- Final cleanup (runs once on exit) ---
    supabase_uploader.end_trip()
    supabase_uploader.reset_vehicle_realtime()
    if ble_server:
        ble_server.stop()
    buzzer.stop()
    gps_reader.stop()


if __name__ == "__main__":
    main()
