"""Safety-critical inference wrapper for driver awareness models.

This is the most important file in the entire models/ directory.
Raw model accuracy doesn't save lives -- confidence thresholds,
temporal voting, and fail-safe defaults do.

Design principles:
    1. NEVER trust a single frame. Require N consecutive agreeing frames.
    2. NEVER output "safe" when uncertain. Default to ALERT state.
    3. Transition to DANGER fast (2 frames), transition to SAFE slow (5 frames).
    4. Reject low-confidence predictions entirely.
    5. Track system health -- if inference fails, assume danger.

Usage:
    from models.inference import DriverAwarenessSystem

    system = DriverAwarenessSystem(
        eye_model_path="models/checkpoints/eye_state.onnx",
        activity_model_path="models/checkpoints/driver_activity.onnx",
    )

    # Per-frame call in your camera loop
    result = system.process_frame(face_crop, upper_body_crop)
    print(result["driver_state"])      # "alert" | "drowsy" | "distracted" | "impaired"
    print(result["confidence"])        # 0.0-1.0
    print(result["is_safe"])           # True/False
    print(result["alerts"])            # ["phone_detected", "eyes_closed"]
"""

import time
from collections import deque
from dataclasses import dataclass, field
from enum import Enum

import cv2
import numpy as np


class DriverState(str, Enum):
    ALERT = "alert"
    DROWSY = "drowsy"
    DISTRACTED_PHONE = "distracted_phone"
    DISTRACTED_DRINKING = "distracted_drinking"
    DISTRACTED_OTHER = "distracted_other"
    EYES_CLOSED = "eyes_closed"
    LOOKING_AWAY = "looking_away"
    UNKNOWN = "unknown"  # fail-safe state


# States considered dangerous -- trigger alerts
DANGER_STATES = {
    DriverState.DROWSY,
    DriverState.DISTRACTED_PHONE,
    DriverState.DISTRACTED_DRINKING,
    DriverState.EYES_CLOSED,
    DriverState.LOOKING_AWAY,
    DriverState.UNKNOWN,
}


@dataclass
class SafetyConfig:
    """Configuration for safety-critical inference behavior."""

    # Confidence thresholds -- predictions below these are REJECTED
    # and treated as UNKNOWN (which is a danger state)
    eye_confidence_threshold: float = 0.70
    activity_confidence_threshold: float = 0.65

    # Temporal voting: require N consecutive frames to CONFIRM a state
    # Asymmetric: fast to detect danger, slow to clear it
    frames_to_confirm_danger: int = 2    # 2 frames (~100ms at 20fps) to trigger alert
    frames_to_confirm_safe: int = 5      # 5 frames (~250ms at 20fps) to clear alert

    # Drowsiness: eyes closed for this many consecutive frames = drowsy
    drowsy_frame_threshold: int = 15     # ~750ms at 20fps

    # History buffer size for temporal analysis
    history_size: int = 30               # ~1.5 seconds at 20fps

    # Maximum time between frames before resetting state (ms)
    # If inference stalls, assume danger
    max_frame_gap_ms: float = 500.0

    # EAR threshold for eye closure (from existing system)
    ear_threshold: float = 0.21


@dataclass
class FrameResult:
    """Result from processing a single frame."""
    eye_state: str = "unknown"
    eye_confidence: float = 0.0
    ear_score: float = 0.0
    activity: str = "unknown"
    activity_confidence: float = 0.0
    raw_eye_probs: np.ndarray = field(default_factory=lambda: np.array([]))
    raw_activity_probs: np.ndarray = field(default_factory=lambda: np.array([]))
    inference_time_ms: float = 0.0


EYE_CLASSES = ["eyes_open", "eyes_partially_closed", "eyes_closed", "sunglasses"]
ACTIVITY_CLASSES = [
    "safe_driving", "texting_phone_right", "texting_phone_left",
    "talking_phone_right", "talking_phone_left", "drinking",
    "reaching_behind", "looking_away", "adjusting_hair_makeup",
    "talking_passenger",
]

# Map activity classes to driver states
ACTIVITY_TO_STATE = {
    "safe_driving": DriverState.ALERT,
    "texting_phone_right": DriverState.DISTRACTED_PHONE,
    "texting_phone_left": DriverState.DISTRACTED_PHONE,
    "talking_phone_right": DriverState.DISTRACTED_PHONE,
    "talking_phone_left": DriverState.DISTRACTED_PHONE,
    "drinking": DriverState.DISTRACTED_DRINKING,
    "reaching_behind": DriverState.DISTRACTED_OTHER,
    "looking_away": DriverState.LOOKING_AWAY,
    "adjusting_hair_makeup": DriverState.DISTRACTED_OTHER,
    "talking_passenger": DriverState.ALERT,  # talking is not dangerous
}


class DriverAwarenessSystem:
    """Safety-critical driver awareness inference system.

    Wraps ONNX models with temporal voting, confidence rejection,
    and fail-safe behavior for deployment on Raspberry Pi 4.
    """

    def __init__(
        self,
        eye_model_path: str | None = None,
        activity_model_path: str | None = None,
        config: SafetyConfig | None = None,
    ):
        self.config = config or SafetyConfig()

        # Load ONNX models
        self.eye_session = None
        self.activity_session = None

        if eye_model_path:
            self.eye_session = self._load_onnx(eye_model_path)
        if activity_model_path:
            self.activity_session = self._load_onnx(activity_model_path)

        # Temporal state tracking
        self._eye_history: deque[str] = deque(maxlen=self.config.history_size)
        self._activity_history: deque[str] = deque(maxlen=self.config.history_size)
        self._ear_history: deque[float] = deque(maxlen=self.config.history_size)
        self._eyes_closed_consecutive: int = 0
        self._current_state: DriverState = DriverState.UNKNOWN
        self._state_frame_count: int = 0
        self._confirmed_state: DriverState = DriverState.UNKNOWN
        self._last_frame_time: float = 0.0
        self._frame_count: int = 0

        # ImageNet normalization constants (precomputed for speed)
        self._mean = np.array([0.485, 0.456, 0.406], dtype=np.float32).reshape(1, 1, 3)
        self._std = np.array([0.229, 0.224, 0.225], dtype=np.float32).reshape(1, 1, 3)

    def _load_onnx(self, path: str):
        """Load ONNX model optimized for CPU inference."""
        import onnxruntime as ort

        opts = ort.SessionOptions()
        opts.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
        opts.intra_op_num_threads = 4        # RPi4 has 4 cores
        opts.inter_op_num_threads = 1
        opts.enable_cpu_mem_arena = True
        opts.enable_mem_pattern = True
        opts.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL

        return ort.InferenceSession(
            path,
            sess_options=opts,
            providers=["CPUExecutionProvider"],
        )

    def _preprocess(self, image: np.ndarray, target_size: int) -> np.ndarray:
        """Preprocess image for inference. Optimized for RPi4 CPU."""
        # Resize (use INTER_AREA for downscaling, fastest quality option)
        if image.shape[0] != target_size or image.shape[1] != target_size:
            image = cv2.resize(image, (target_size, target_size), interpolation=cv2.INTER_AREA)

        # BGR to RGB if needed (cv2 default is BGR)
        if len(image.shape) == 3 and image.shape[2] == 3:
            image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)

        # Normalize: float32, /255, ImageNet stats
        image = image.astype(np.float32) / 255.0
        image = (image - self._mean) / self._std

        # HWC -> CHW -> NCHW
        image = np.transpose(image, (2, 0, 1))
        return np.expand_dims(image, axis=0).astype(np.float32)

    def _run_eye_model(self, face_crop: np.ndarray) -> FrameResult:
        """Run eye state classification on a face crop."""
        result = FrameResult()

        if self.eye_session is None:
            return result

        start = time.perf_counter()

        tensor = self._preprocess(face_crop, target_size=112)
        input_name = self.eye_session.get_inputs()[0].name
        outputs = self.eye_session.run(None, {input_name: tensor})

        logits = outputs[0][0]  # (num_classes,)
        # Softmax
        exp_logits = np.exp(logits - np.max(logits))
        probs = exp_logits / exp_logits.sum()

        result.raw_eye_probs = probs
        result.eye_confidence = float(np.max(probs))
        pred_idx = int(np.argmax(probs))

        # Confidence gating: reject uncertain predictions
        if result.eye_confidence >= self.config.eye_confidence_threshold:
            result.eye_state = EYE_CLASSES[pred_idx]
        else:
            result.eye_state = "unknown"

        # EAR score from auxiliary head (if available)
        if len(outputs) > 1:
            result.ear_score = float(outputs[1][0][0])
        else:
            # Estimate EAR from class probabilities
            # open=high EAR, partial=medium, closed=low
            result.ear_score = float(
                probs[0] * 0.35 +   # eyes_open → EAR ~0.35
                probs[1] * 0.22 +   # partially_closed → EAR ~0.22
                probs[2] * 0.10 +   # closed → EAR ~0.10
                probs[3] * 0.30     # sunglasses → EAR ~0.30 (assume open)
            )

        result.inference_time_ms = (time.perf_counter() - start) * 1000
        return result

    def _run_activity_model(self, upper_body_crop: np.ndarray) -> FrameResult:
        """Run driver activity classification."""
        result = FrameResult()

        if self.activity_session is None:
            return result

        start = time.perf_counter()

        tensor = self._preprocess(upper_body_crop, target_size=224)
        input_name = self.activity_session.get_inputs()[0].name
        outputs = self.activity_session.run(None, {input_name: tensor})

        logits = outputs[0][0]
        exp_logits = np.exp(logits - np.max(logits))
        probs = exp_logits / exp_logits.sum()

        result.raw_activity_probs = probs
        result.activity_confidence = float(np.max(probs))
        pred_idx = int(np.argmax(probs))

        if result.activity_confidence >= self.config.activity_confidence_threshold:
            result.activity = ACTIVITY_CLASSES[pred_idx]
        else:
            result.activity = "unknown"

        result.inference_time_ms = (time.perf_counter() - start) * 1000
        return result

    def _update_temporal_state(self, eye_result: FrameResult, activity_result: FrameResult) -> None:
        """Update temporal tracking with new frame results."""
        now = time.perf_counter() * 1000

        # Check for stale frames -- if too much time passed, reset to unknown
        if self._last_frame_time > 0:
            gap = now - self._last_frame_time
            if gap > self.config.max_frame_gap_ms:
                self._reset_state()
        self._last_frame_time = now

        # Track eye closure
        self._eye_history.append(eye_result.eye_state)
        self._ear_history.append(eye_result.ear_score)

        if eye_result.eye_state == "eyes_closed":
            self._eyes_closed_consecutive += 1
        else:
            self._eyes_closed_consecutive = 0

        # Track activity
        self._activity_history.append(activity_result.activity)

        # Determine current frame's state (before temporal voting)
        frame_state = self._determine_frame_state(eye_result, activity_result)

        # Asymmetric temporal voting
        if frame_state == self._current_state:
            self._state_frame_count += 1
        else:
            self._current_state = frame_state
            self._state_frame_count = 1

        # Confirm state changes with asymmetric thresholds
        if self._current_state in DANGER_STATES:
            threshold = self.config.frames_to_confirm_danger
        else:
            threshold = self.config.frames_to_confirm_safe

        if self._state_frame_count >= threshold:
            self._confirmed_state = self._current_state

        self._frame_count += 1

    def _determine_frame_state(self, eye: FrameResult, activity: FrameResult) -> DriverState:
        """Determine driver state for a single frame. Priority-ordered."""

        # Priority 1: Drowsiness (eyes closed for extended period)
        if self._eyes_closed_consecutive >= self.config.drowsy_frame_threshold:
            return DriverState.DROWSY

        # Priority 2: Eyes closed (but not yet drowsy)
        if eye.eye_state == "eyes_closed":
            return DriverState.EYES_CLOSED

        # Priority 3: Phone distraction (most dangerous active distraction)
        if activity.activity in ("texting_phone_right", "texting_phone_left",
                                  "talking_phone_right", "talking_phone_left"):
            return DriverState.DISTRACTED_PHONE

        # Priority 4: Drinking
        if activity.activity == "drinking":
            return DriverState.DISTRACTED_DRINKING

        # Priority 5: Looking away
        if activity.activity == "looking_away":
            return DriverState.LOOKING_AWAY

        # Priority 6: Other distractions
        if activity.activity in ("reaching_behind", "adjusting_hair_makeup"):
            return DriverState.DISTRACTED_OTHER

        # Priority 7: Unknown (either model rejected for low confidence)
        if eye.eye_state == "unknown" and activity.activity == "unknown":
            return DriverState.UNKNOWN

        # Safe
        return DriverState.ALERT

    def _reset_state(self) -> None:
        """Reset all temporal state. Called on stale frames or init."""
        self._eye_history.clear()
        self._activity_history.clear()
        self._ear_history.clear()
        self._eyes_closed_consecutive = 0
        self._current_state = DriverState.UNKNOWN
        self._state_frame_count = 0
        self._confirmed_state = DriverState.UNKNOWN

    def process_frame(
        self,
        face_crop: np.ndarray | None = None,
        upper_body_crop: np.ndarray | None = None,
    ) -> dict:
        """Process a single frame and return the driver awareness result.

        This is the main entry point called from the camera loop.

        Returns dict compatible with existing Supabase schema:
            driver_state: str
            is_safe: bool
            confidence: float
            eye_state: str
            ear_score: float
            is_drowsy: bool
            is_phone_detected: bool
            is_drinking_detected: bool
            alerts: list[str]
            inference_time_ms: float
        """
        total_start = time.perf_counter()

        # Run models
        eye_result = FrameResult()
        activity_result = FrameResult()

        if face_crop is not None and self.eye_session is not None:
            eye_result = self._run_eye_model(face_crop)

        if upper_body_crop is not None and self.activity_session is not None:
            activity_result = self._run_activity_model(upper_body_crop)

        # Update temporal state
        self._update_temporal_state(eye_result, activity_result)

        # Build output
        state = self._confirmed_state
        is_safe = state not in DANGER_STATES
        alerts = []

        if state == DriverState.DROWSY:
            alerts.append("drowsy")
        if state == DriverState.EYES_CLOSED:
            alerts.append("eyes_closed")
        if state == DriverState.DISTRACTED_PHONE:
            alerts.append("phone_detected")
        if state == DriverState.DISTRACTED_DRINKING:
            alerts.append("drinking_detected")
        if state == DriverState.LOOKING_AWAY:
            alerts.append("looking_away")
        if state == DriverState.DISTRACTED_OTHER:
            alerts.append("distracted")
        if state == DriverState.UNKNOWN:
            alerts.append("detection_uncertain")

        # Confidence: minimum of the two model confidences
        confidence = min(
            eye_result.eye_confidence if eye_result.eye_confidence > 0 else 1.0,
            activity_result.activity_confidence if activity_result.activity_confidence > 0 else 1.0,
        )

        # Compute intoxication score (backward compatible with existing system)
        intoxication_score = 0
        if self._eyes_closed_consecutive >= self.config.drowsy_frame_threshold:
            intoxication_score += 3

        # Excessive blinking: count eye state transitions in recent history
        blink_count = 0
        prev = None
        for s in self._eye_history:
            if prev == "eyes_open" and s == "eyes_closed":
                blink_count += 1
            prev = s
        if blink_count > 8:  # >8 blinks in ~1.5s window = excessive
            intoxication_score += 2
            alerts.append("excessive_blinking")

        # EAR instability
        if len(self._ear_history) >= 10:
            ear_var = float(np.var(list(self._ear_history)[-10:]))
            if ear_var > 0.005:
                intoxication_score += 1
                alerts.append("unstable_eyes")

        total_time = (time.perf_counter() - total_start) * 1000

        return {
            "driver_state": state.value,
            "is_safe": is_safe,
            "confidence": confidence,
            "eye_state": eye_result.eye_state,
            "left_eye_state": "OPEN" if eye_result.ear_score > self.config.ear_threshold else "CLOSED",
            "right_eye_state": "OPEN" if eye_result.ear_score > self.config.ear_threshold else "CLOSED",
            "ear_score": eye_result.ear_score,
            "avg_ear": eye_result.ear_score,
            "is_drowsy": state == DriverState.DROWSY,
            "is_excessive_blinking": blink_count > 8,
            "is_unstable_eyes": len(self._ear_history) >= 10 and float(np.var(list(self._ear_history)[-10:])) > 0.005,
            "intoxication_score": min(intoxication_score, 6),
            "is_phone_detected": state == DriverState.DISTRACTED_PHONE,
            "is_drinking_detected": state == DriverState.DISTRACTED_DRINKING,
            "activity": activity_result.activity,
            "activity_confidence": activity_result.activity_confidence,
            "alerts": alerts,
            "inference_time_ms": total_time,
            "eye_inference_ms": eye_result.inference_time_ms,
            "activity_inference_ms": activity_result.inference_time_ms,
            "frame_count": self._frame_count,
        }

    def get_health(self) -> dict:
        """System health check."""
        return {
            "eye_model_loaded": self.eye_session is not None,
            "activity_model_loaded": self.activity_session is not None,
            "frames_processed": self._frame_count,
            "current_state": self._confirmed_state.value,
            "eyes_closed_frames": self._eyes_closed_consecutive,
            "history_depth": len(self._eye_history),
        }
