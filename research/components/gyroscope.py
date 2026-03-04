import math
import os
import struct
import threading
import time
from collections import deque

DEFAULT_PORT = "/dev/ttyACM0"
BAUD = 115200
PRINT_INTERVAL = 0.2


class GyroReader:
    """Reads acc/gyro from serial; exposes thread-safe get_latest()."""

    def __init__(self, port=None, baud=BAUD, print_interval=PRINT_INTERVAL):
        self.port = port or os.environ.get("GYRO_SERIAL_PORT", DEFAULT_PORT)
        self.baud = baud
        self.print_interval = print_interval
        self._lock = threading.Lock()
        self._ser = None
        self._thread = None
        self._running = False
        # Latest values (None until first packet)
        self._last_acc_mag = None
        self._last_acc_delta = None
        self._last_gyro_mag = None
        self._last_gyrox = None
        self._last_gyroy = None
        self._last_gyroz = None
        self._last_ts = None
        self._measurement_count = 0
        self._prev_acc_mag = None
        self._last_print = time.time()
        self._print_from_loop = False

    def start(self, print_from_loop=False):
        """Open serial and start the read loop in a daemon thread."""
        import serial

        self._ser = serial.Serial(self.port, self.baud, timeout=0)
        self._running = True
        self._print_from_loop = print_from_loop
        self._thread = threading.Thread(target=self._read_loop, daemon=True)
        self._thread.start()

    def stop(self):
        """Stop the read loop and close serial."""
        self._running = False
        if self._thread:
            self._thread.join(timeout=2.0)
            self._thread = None
        if self._ser:
            try:
                self._ser.close()
            except Exception:
                pass
            self._ser = None

    def get_latest(self):
        """
        Return latest reading or None if no data yet.
        Returns a dict: acc_mag, acc_delta, gyro_mag, gyrox, gyroy, gyroz, timestamp.
        """
        with self._lock:
            if self._last_ts is None:
                return None
            return {
                "acc_mag": self._last_acc_mag,
                "acc_delta": self._last_acc_delta,
                "gyro_mag": self._last_gyro_mag,
                "gyrox": self._last_gyrox,
                "gyroy": self._last_gyroy,
                "gyroz": self._last_gyroz,
                "timestamp": self._last_ts,
            }

    def _read_loop(self):
        buffer = bytearray()
        while self._running and self._ser and self._ser.is_open:
            try:
                buffer += self._ser.read(self._ser.in_waiting or 1)
            except Exception:
                break
            while len(buffer) >= 15 and self._running:
                if buffer[0] != 0xAA or buffer[1] != 0x55:
                    buffer.pop(0)
                    continue
                payload = buffer[2:14]
                checksum = buffer[14]
                calc_checksum = 0
                for b in payload:
                    calc_checksum ^= b
                if calc_checksum != checksum:
                    buffer.pop(0)
                    continue
                accx_i, accy_i, accz_i, gyrox_i, gyroy_i, gyroz_i = struct.unpack(
                    "<hhhhhh", payload
                )
                accx = accx_i / 1000
                accy = accy_i / 1000
                accz = accz_i / 1000
                gyrox = gyrox_i / 100
                gyroy = gyroy_i / 100
                gyroz = gyroz_i / 100
                acc_mag = math.sqrt(accx**2 + accy**2 + accz**2)
                if self._prev_acc_mag is None:
                    acc_delta = 0.0
                else:
                    acc_delta = acc_mag - self._prev_acc_mag
                self._prev_acc_mag = acc_mag
                gyro_mag = math.sqrt(gyrox**2 + gyroy**2 + gyroz**2)
                self._measurement_count += 1
                buffer = buffer[15:]

                with self._lock:
                    self._last_acc_mag = acc_mag
                    self._last_acc_delta = acc_delta
                    self._last_gyro_mag = gyro_mag
                    self._last_gyrox = gyrox
                    self._last_gyroy = gyroy
                    self._last_gyroz = gyroz
                    self._last_ts = time.time()

                now = time.time()
                if (
                    self._print_from_loop
                    and now - self._last_print >= self.print_interval
                ):
                    if self._measurement_count > 0:
                        print(
                            f"{now:.3f}, {acc_mag:.3f}, {acc_delta:.3f}, "
                            f"{self._measurement_count}"
                        )
                    self._measurement_count = 0
                    self._last_print = now
            time.sleep(0.001)


class CrashDetector:
    """iPhone-style crash detection using accelerometer + gyroscope data.

    Multi-phase state machine:
      MONITORING → IMPACT_DETECTED → CONFIRMING → CRASH_CONFIRMED → COOLDOWN

    Requires all three phases to confirm a crash:
      1. IMPACT:    acc_mag > 3.0g  OR  |acc_delta| > 2.0g
      2. ROTATION:  gyro_mag > 150 deg/s within 2s of impact
      3. STILLNESS: acc_mag ≈ 1.0g (±0.3) AND gyro < 20 deg/s within 5s
    """

    # States
    MONITORING = "monitoring"
    IMPACT_DETECTED = "impact_detected"
    CONFIRMING = "confirming"
    CRASH_CONFIRMED = "crash_confirmed"
    COOLDOWN = "cooldown"

    # Thresholds
    IMPACT_G = 3.0            # g-force for impact detection
    IMPACT_DELTA_G = 2.0      # sudden change threshold
    ROTATION_DEG_S = 150.0    # gyro magnitude for rotation phase
    STILLNESS_G_LOW = 0.7     # acc_mag range for stillness
    STILLNESS_G_HIGH = 1.3
    STILLNESS_GYRO = 20.0     # gyro must be below this

    # Severity thresholds
    SEVERE_G = 4.0
    SEVERE_GYRO = 250.0

    # Timing
    ROTATION_WINDOW = 2.0     # seconds after impact to detect rotation
    STILLNESS_WINDOW = 5.0    # seconds after impact to detect stillness
    COOLDOWN_DURATION = 60.0  # seconds before allowing re-trigger

    def __init__(self):
        self._state = self.MONITORING
        self._impact_time = 0.0
        self._peak_g = 0.0
        self._peak_gyro = 0.0
        self._rotation_confirmed = False
        self._crash_event = None
        self._cooldown_until = 0.0
        self._history = deque(maxlen=30)  # ~3s at 10Hz

    def feed(self, acc_mag, acc_delta, gyro_mag, timestamp):
        """Feed a new sensor reading into the detector."""
        self._history.append({
            "acc_mag": acc_mag,
            "acc_delta": acc_delta,
            "gyro_mag": gyro_mag,
            "ts": timestamp,
        })

        if self._state == self.MONITORING:
            self._check_impact(acc_mag, acc_delta, gyro_mag, timestamp)

        elif self._state == self.IMPACT_DETECTED:
            self._peak_g = max(self._peak_g, acc_mag)
            self._peak_gyro = max(self._peak_gyro, gyro_mag)
            elapsed = timestamp - self._impact_time

            # Check rotation within window
            if gyro_mag >= self.ROTATION_DEG_S:
                self._rotation_confirmed = True

            if elapsed > self.ROTATION_WINDOW:
                if self._rotation_confirmed:
                    self._state = self.CONFIRMING
                else:
                    # No rotation — likely a bump, not a crash
                    self._reset()

        elif self._state == self.CONFIRMING:
            self._peak_g = max(self._peak_g, acc_mag)
            self._peak_gyro = max(self._peak_gyro, gyro_mag)
            elapsed = timestamp - self._impact_time

            # Check for post-impact stillness
            if (self.STILLNESS_G_LOW <= acc_mag <= self.STILLNESS_G_HIGH
                    and gyro_mag < self.STILLNESS_GYRO):
                self._confirm_crash(timestamp)
            elif elapsed > self.STILLNESS_WINDOW:
                # Timeout — no stillness detected, reset
                self._reset()

        elif self._state == self.COOLDOWN:
            if timestamp >= self._cooldown_until:
                self._state = self.MONITORING

    def get_crash_event(self):
        """Return and clear the pending crash event, or None."""
        event = self._crash_event
        self._crash_event = None
        return event

    def _check_impact(self, acc_mag, acc_delta, gyro_mag, timestamp):
        if timestamp < self._cooldown_until:
            return
        if acc_mag >= self.IMPACT_G or abs(acc_delta) >= self.IMPACT_DELTA_G:
            self._state = self.IMPACT_DETECTED
            self._impact_time = timestamp
            self._peak_g = acc_mag
            self._peak_gyro = gyro_mag
            self._rotation_confirmed = gyro_mag >= self.ROTATION_DEG_S
            print(f"[CRASH] Impact detected: {acc_mag:.2f}g, Δ{acc_delta:.2f}g")

    def _confirm_crash(self, timestamp):
        severity = "severe" if (
            self._peak_g >= self.SEVERE_G and self._peak_gyro >= self.SEVERE_GYRO
        ) else "moderate"

        self._crash_event = {
            "severity": severity,
            "peak_g": round(self._peak_g, 2),
            "peak_gyro": round(self._peak_gyro, 2),
            "impact_time": self._impact_time,
            "confirmed_time": timestamp,
        }

        print(
            f"[CRASH] CONFIRMED ({severity}): peak {self._peak_g:.1f}g, "
            f"gyro {self._peak_gyro:.1f} deg/s"
        )

        self._state = self.COOLDOWN
        self._cooldown_until = timestamp + self.COOLDOWN_DURATION
        self._rotation_confirmed = False

    def _reset(self):
        self._state = self.MONITORING
        self._impact_time = 0.0
        self._peak_g = 0.0
        self._peak_gyro = 0.0
        self._rotation_confirmed = False


if __name__ == "__main__":
    import serial  # noqa: F401 - used by GyroReader.start()

    reader = GyroReader()
    reader.start(print_from_loop=True)
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        pass
    finally:
        reader.stop()
