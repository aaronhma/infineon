"""Simple HTTP server that serves the latest camera frame as JPEG.

Runs in a background thread. The main loop calls `update_frame()` with
each new OpenCV frame; the server holds the latest JPEG in memory and
serves it at GET /frame.

Usage from main.py:
    server = CameraServer(port=8554)
    server.start()
    ...
    server.update_frame(cv2_frame)   # called every loop iteration
    ...
    server.stop()
"""

import socket
import threading
import time
from http.server import HTTPServer, BaseHTTPRequestHandler

import cv2


def _get_local_ip() -> str:
    """Get the Pi's local IP address."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"


class CameraServer:
    """Threaded HTTP server that serves camera frames."""

    def __init__(self, port: int = 8554, quality: int = 50, width: int = 480):
        self.port = port
        self.quality = quality
        self.width = width
        self._lock = threading.Lock()
        self._jpeg_bytes: bytes = b""
        self._server: HTTPServer | None = None
        self._thread: threading.Thread | None = None
        self.local_ip = _get_local_ip()

    def start(self):
        """Start the HTTP server in a background thread."""
        parent = self

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                if self.path == "/frame":
                    with parent._lock:
                        data = parent._jpeg_bytes
                    if not data:
                        self.send_response(204)
                        self.end_headers()
                        return
                    self.send_response(200)
                    self.send_header("Content-Type", "image/jpeg")
                    self.send_header("Content-Length", str(len(data)))
                    self.send_header("Cache-Control", "no-cache")
                    self.end_headers()
                    self.wfile.write(data)
                else:
                    self.send_response(404)
                    self.end_headers()

            def log_message(self, format, *args):
                pass  # Suppress request logging

        self._server = HTTPServer(("0.0.0.0", self.port), Handler)
        self._thread = threading.Thread(target=self._server.serve_forever, daemon=True)
        self._thread.start()
        print(f"[Camera HTTP] Serving at http://{self.local_ip}:{self.port}/frame")

    def stop(self):
        """Shut down the server."""
        if self._server:
            self._server.shutdown()
            self._server = None
        if self._thread:
            self._thread.join(timeout=3)
            self._thread = None
        print("[Camera HTTP] Server stopped")

    def update_frame(self, frame):
        """Compress and store the latest frame (called from main loop)."""
        h, w = frame.shape[:2]
        if w > self.width:
            scale = self.width / w
            frame = cv2.resize(
                frame, (self.width, int(h * scale)),
                interpolation=cv2.INTER_AREA,
            )
        _, buf = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, self.quality])
        with self._lock:
            self._jpeg_bytes = buf.tobytes()
