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


class ImpairmentDetector:
    """Detects impairment from shaking patterns using G-force deviation from baseline.
    
    Tracks multiple shakes over a time window and calculates a risk score (0-100)
    based on the severity and frequency of shaking motions.
    
    Shake detection: G-force deviates by more than ±0.7g from 1g baseline (gravity).
    Since our gyro doesn't account for gravity, we use 1g as the resting baseline.
    """
    
    # Baseline for shake detection (1g = gravity, since gyro doesn't account for it)
    BASELINE_G = 1.0
    DEVIATION_THRESHOLD = 0.7        # ±0.7g from baseline triggers shake
    
    # Severity thresholds (based on deviation magnitude)
    HIGH_DEVIATION = 1.0             # 1g+ deviation from baseline
    SEVERE_DEVIATION = 1.5           # 1.5g+ deviation from baseline
    
    # Time windows for shake tracking
    SHAKE_WINDOW = 5.0               # Window to track shakes (seconds)
    SHAKE_COOLDOWN = 0.2             # Minimum time between distinct shakes
    
    # Risk score parameters
    RISK_DECAY_RATE = 5.0            # Risk points decayed per second
    RISK_PER_SHAKE_BASE = 15.0       # Base risk points per shake
    RISK_PER_HIGH_SHAKE = 25.0       # Risk points for high deviation
    RISK_PER_SEVERE_SHAKE = 40.0     # Risk points for severe deviation
    MAX_RISK = 100.0                 # Maximum risk score
    ALARM_THRESHOLD = 70.0           # Risk score that triggers alarm
    
    def __init__(self):
        # Current G-force and deviation
        self._current_g = 0.0
        self._current_deviation = 0.0
        
        # Shake history (timestamp, severity)
        self._shake_history = deque(maxlen=50)
        self._last_shake_time = 0.0
        
        # Risk score (0-100)
        self._risk_score = 0.0
        self._last_update = time.time()
        
        # Alarm state
        self._alarm_active = False
        self._alarm_event = None
        
    def feed(self, acc_mag, acc_delta, gyro_mag, timestamp):
        """Feed a new sensor reading into the impairment detector.
        
        Args:
            acc_mag: Accelerometer magnitude in G
            acc_delta: Change in accelerometer magnitude
            gyro_mag: Gyroscope magnitude in deg/s
            timestamp: Current timestamp
        """
        # Calculate deviation from baseline (1g)
        self._current_g = acc_mag
        self._current_deviation = abs(acc_mag - self.BASELINE_G)
        
        # Decay risk score over time
        self._decay_risk(timestamp)
        
        # Check for shake event (deviation > threshold)
        if (self._current_deviation >= self.DEVIATION_THRESHOLD and 
            timestamp - self._last_shake_time >= self.SHAKE_COOLDOWN):
            self._detect_shake(acc_mag, gyro_mag, timestamp)
        
        # Check alarm threshold
        self._check_alarm()
        
    def _detect_shake(self, acc_mag, gyro_mag, timestamp):
        """Detect and record a shake event."""
        # Determine severity based on deviation from baseline
        deviation = self._current_deviation
        if deviation >= self.SEVERE_DEVIATION:
            severity = "severe"
            risk_add = self.RISK_PER_SEVERE_SHAKE
        elif deviation >= self.HIGH_DEVIATION:
            severity = "high"
            risk_add = self.RISK_PER_HIGH_SHAKE
        else:
            severity = "moderate"
            risk_add = self.RISK_PER_SHAKE_BASE
            
        # Add bonus for high gyro rotation (indicates erratic movement)
        if gyro_mag >= 100.0:
            risk_add *= 1.2
        elif gyro_mag >= 70.0:
            risk_add *= 1.1
            
        # Record shake
        self._shake_history.append({
            "timestamp": timestamp,
            "severity": severity,
            "acc_mag": acc_mag,
            "deviation": deviation,
            "gyro_mag": gyro_mag,
            "risk_added": risk_add,
        })
        
        # Update risk score
        self._risk_score = min(self.MAX_RISK, self._risk_score + risk_add)
        self._last_shake_time = timestamp
        
        # Immediately activate alarm on shake detection
        self._alarm_active = True
        self._alarm_event = {
            "type": "impairment_alarm",
            "risk_score": round(self._risk_score, 1),
            "shake_count": len(self._shake_history) + 1,
            "timestamp": time.time(),
        }
        
        # Clean old shakes from window
        self._prune_shake_history(timestamp)
        
        print(f"[IMPAIRMENT] Shake detected: {severity} (deviation={deviation:.2f}g, gyro={gyro_mag:.1f}°/s) → risk={self._risk_score:.0f} [ALARM]")
        
    def _prune_shake_history(self, current_time):
        """Remove shakes outside the tracking window."""
        while self._shake_history and current_time - self._shake_history[0]["timestamp"] > self.SHAKE_WINDOW:
            self._shake_history.popleft()
            
    def _decay_risk(self, timestamp):
        """Decay risk score over time when no shaking occurs."""
        if self._last_update is None:
            self._last_update = timestamp
            return
            
        elapsed = timestamp - self._last_update
        if elapsed > 0:
            decay = self.RISK_DECAY_RATE * elapsed
            self._risk_score = max(0.0, self._risk_score - decay)
        self._last_update = timestamp
        
    def _check_alarm(self):
        """Check if alarm should be turned off (risk dropped below threshold)."""
        # Alarm is activated immediately on shake detection in _detect_shake()
        # Only turn off when risk drops below threshold
        if self._alarm_active and self._risk_score < self.ALARM_THRESHOLD:
            self._alarm_active = False
            print(f"[IMPAIRMENT] Alarm cleared - risk dropped to {self._risk_score:.0f}")
            
    def get_risk_score(self):
        """Get current risk score (0-100)."""
        return round(self._risk_score, 1)
        
    def get_shake_count(self):
        """Get number of shakes in current window."""
        return len(self._shake_history)
        
    def is_alarm_active(self):
        """Check if impairment alarm is currently active."""
        return self._alarm_active
        
    def get_alarm_event(self):
        """Return and clear the pending alarm event, or None."""
        event = self._alarm_event
        self._alarm_event = None
        return event
        
    def get_status(self):
        """Get full status dict for BLE/Supabase updates."""
        return {
            "risk_score": round(self._risk_score, 1),
            "shake_count": len(self._shake_history),
            "alarm_active": self._alarm_active,
            "current_g": round(self._current_g, 2),
            "deviation": round(self._current_deviation, 2),
        }
        
    def reset(self):
        """Reset all state."""
        self._current_g = 0.0
        self._current_deviation = 0.0
        self._shake_history.clear()
        self._last_shake_time = 0.0
        self._risk_score = 0.0
        self._last_update = time.time()
        self._alarm_active = False
        self._alarm_event = None


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
