import os
import random
import time
import uuid
from collections import deque
from datetime import datetime

import cv2
import mediapipe as mp
import numpy as np
import pygame
from dotenv import load_dotenv
from mediapipe.tasks import python
from mediapipe.tasks.python import vision
from scipy.spatial import distance
from supabase import Client, create_client

# Load environment variables from .env file
load_dotenv()


class SupabaseUploader:
    """Handles uploading face detection data and vehicle telemetry to Supabase"""

    def __init__(self):
        # Load from environment variables
        supabase_url = os.environ.get("SUPABASE_URL")
        supabase_key = os.environ.get("SUPABASE_SECRET_KEY")
        self.vehicle_id = os.environ.get("VEHICLE_ID")
        self.vehicle_name = os.environ.get("VEHICLE_NAME", "Unknown Vehicle")

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

        self.client: Client = create_client(supabase_url, supabase_key)
        self.session_id = str(uuid.uuid4())
        self.last_upload_time = 0
        self.last_realtime_update = 0
        self.last_driver_check = 0
        self.upload_cooldown = 2.0  # Minimum seconds between face uploads
        self.realtime_cooldown = 0.5  # Update realtime every 500ms
        self.driver_check_cooldown = 5.0  # Check for driver identification every 5s

        # Driver identification
        self.driver_profiles = {}  # {profile_id: profile_data}
        self.current_driver_name = None
        self.current_driver_profile_id = None
        self.last_announced_driver = None

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
        self.last_trip_update = 0
        self.trip_update_cooldown = 5.0  # Update trip stats every 5 seconds
        self.was_speeding = False  # Track speeding state changes
        self.was_drowsy = False  # Track drowsy state changes
        self.was_excessive_blinking = False  # Track excessive blinking state changes
        self.was_unstable_eyes = False  # Track unstable eyes state changes

        # Register vehicle on startup
        self._register_vehicle()

        # Load driver profiles
        self._load_driver_profiles()

        # Create trip record for this session
        self._create_trip()

        print(
            f"Supabase connected. Vehicle ID: {self.vehicle_id}, Session ID: {self.session_id}"
        )

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
                        "updated_at": datetime.now().isoformat(),
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
                    "updated_at": datetime.now().isoformat(),
                }
            ).execute()

        except Exception as e:
            print(f"Error registering vehicle: {e}")
            raise

    def _load_driver_profiles(self):
        """Load all driver profiles for this vehicle"""
        try:
            response = (
                self.client.table("driver_profiles")
                .select("id, name, profile_image_path")
                .eq("vehicle_id", self.vehicle_id)
                .execute()
            )

            self.driver_profiles = {}
            for profile in response.data:
                self.driver_profiles[profile["id"]] = {
                    "name": profile["name"],
                    "image_path": profile.get("profile_image_path"),
                }

            if self.driver_profiles:
                print(f"Loaded {len(self.driver_profiles)} driver profile(s)")
                for profile_id, data in self.driver_profiles.items():
                    print(f"  - {data['name']}")
            else:
                print("No driver profiles found for this vehicle")

        except Exception as e:
            print(f"Error loading driver profiles: {e}")

    def _create_trip(self):
        """Create a new trip record for this session"""
        try:
            record = {
                "vehicle_id": self.vehicle_id,
                "session_id": self.session_id,
                "started_at": datetime.now().isoformat(),
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

    def update_trip_stats(
        self,
        speed: int,
        intox_score: int,
        is_speeding: bool,
        is_drowsy: bool,
        is_excessive_blinking: bool,
        is_unstable_eyes: bool,
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

        # Periodically update trip in database
        current_time = time.time()
        if current_time - self.last_trip_update >= self.trip_update_cooldown:
            self._sync_trip_to_db()
            self.last_trip_update = current_time

    def _sync_trip_to_db(self):
        """Sync current trip stats to database"""
        if not self.trip_id:
            return

        try:
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
            }

            # Add driver profile if identified
            if self.current_driver_profile_id:
                record["driver_profile_id"] = self.current_driver_profile_id

            self.client.table("vehicle_trips").update(record).eq("id", self.trip_id).execute()

        except Exception as e:
            print(f"Error syncing trip stats: {e}")

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
                "ended_at": datetime.now().isoformat(),
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
            }

            # Add driver profile if identified
            if self.current_driver_profile_id:
                record["driver_profile_id"] = self.current_driver_profile_id

            self.client.table("vehicle_trips").update(record).eq("id", self.trip_id).execute()
            print(f"Trip ended: {self.trip_id} (Status: {self._calculate_trip_status()})")

        except Exception as e:
            print(f"Error ending trip: {e}")

    def increment_face_detection_count(self):
        """Increment face detection count for current trip"""
        self.trip_face_detections += 1

    def check_current_driver(self):
        """Check the most recently identified driver for this vehicle"""
        current_time = time.time()
        if current_time - self.last_driver_check < self.driver_check_cooldown:
            return self.current_driver_name

        self.last_driver_check = current_time

        try:
            # Refresh driver profiles periodically
            self._load_driver_profiles()

            # Get the most recent face detection with a driver profile assigned
            response = (
                self.client.table("face_detections")
                .select("driver_profile_id, created_at")
                .eq("vehicle_id", self.vehicle_id)
                .not_.is_("driver_profile_id", "null")
                .order("created_at", desc=True)
                .limit(1)
                .execute()
            )

            if response.data and len(response.data) > 0:
                profile_id = response.data[0]["driver_profile_id"]
                if profile_id in self.driver_profiles:
                    driver_name = self.driver_profiles[profile_id]["name"]
                    self.current_driver_name = driver_name
                    self.current_driver_profile_id = profile_id

                    # Announce driver if changed
                    if driver_name != self.last_announced_driver:
                        print(f"\n>>> Driver detected: {driver_name} <<<\n")
                        self.last_announced_driver = driver_name

                    return driver_name

            # No identified driver found
            self.current_driver_name = None
            self.current_driver_profile_id = None
            return None

        except Exception as e:
            print(f"Error checking current driver: {e}")
            return None

    def get_current_driver(self):
        """Get the current driver name (cached)"""
        return self.current_driver_name

    def update_vehicle_realtime(
        self,
        speed_mph: int,
        heading_degrees: int,
        compass_direction: str,
        is_speeding: bool,
        driver_status: str = "unknown",
        intoxication_score: int = 0,
    ):
        """Update vehicle real-time location/status (called frequently)"""
        current_time = time.time()
        if current_time - self.last_realtime_update < self.realtime_cooldown:
            return None

        try:
            # Convert to native Python types to ensure JSON serialization
            record = {
                "vehicle_id": self.vehicle_id,
                "updated_at": datetime.now().isoformat(),
                "speed_mph": int(speed_mph),
                "heading_degrees": int(heading_degrees),
                "compass_direction": str(compass_direction),
                "is_speeding": bool(is_speeding),
                "is_moving": bool(speed_mph > 0),
                "driver_status": str(driver_status),
                "intoxication_score": int(intoxication_score),
            }

            self.client.table("vehicle_realtime").upsert(record).execute()
            self.last_realtime_update = current_time

        except Exception as e:
            print(f"Error updating vehicle realtime: {e}")

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
    ):
        """Upload face snapshot and metadata to Supabase"""
        if not self.should_upload():
            return None

        try:
            # Generate unique filename (vehicle_id/session_id/timestamp.jpg)
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
            filename = f"{self.vehicle_id}/{self.session_id}/{timestamp}.jpg"

            # Encode image to JPEG bytes
            _, buffer = cv2.imencode(".jpg", face_image, [cv2.IMWRITE_JPEG_QUALITY, 85])
            image_bytes = buffer.tobytes()

            # Upload image to storage
            storage_response = self.client.storage.from_("face-snapshots").upload(
                path=filename,
                file=image_bytes,
                file_options={"content-type": "image/jpeg"},
            )

            # Prepare metadata record (convert numpy types to Python native types)
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

            # Add current driver profile if identified
            if self.current_driver_profile_id:
                record["driver_profile_id"] = self.current_driver_profile_id

            # Add driving data if available
            if driving_data:
                record["speed_mph"] = int(driving_data.get("speed", 0))
                record["heading_degrees"] = int(driving_data.get("heading", 0))
                record["compass_direction"] = str(driving_data.get("direction", "N"))
                record["is_speeding"] = bool(driving_data.get("is_speeding", False))

            # Insert record into database
            db_response = self.client.table("face_detections").insert(record).execute()

            self.last_upload_time = time.time()

            # Print upload info with driver name if available
            if self.current_driver_name:
                print(
                    f"Uploaded face detection: {filename} (Driver: {self.current_driver_name})"
                )
            else:
                print(f"Uploaded face detection: {filename} (Unidentified)")

            return db_response

        except Exception as e:
            print(f"Error uploading to Supabase: {e}")
            return None


class WarningSound:
    def __init__(self):
        pygame.mixer.init(frequency=22050, size=-16, channels=2, buffer=512)
        self.last_speeding_alert = 0
        self.last_drowsy_alert = 0
        self.alert_cooldown = 3.0  # 3 seconds between alerts

    def generate_beep(self, frequency=800, duration=0.3):
        """Generate a warning beep sound"""
        sample_rate = 22050
        n_samples = int(duration * sample_rate)

        # Generate sine wave
        t = np.linspace(0, duration, n_samples)
        wave = np.sin(2 * np.pi * frequency * t)

        # Add envelope to prevent clicking
        envelope = np.ones(n_samples)
        fade_samples = int(0.01 * sample_rate)  # 10ms fade
        envelope[:fade_samples] = np.linspace(0, 1, fade_samples)
        envelope[-fade_samples:] = np.linspace(1, 0, fade_samples)
        wave = wave * envelope

        # Convert to 16-bit audio
        wave = (wave * 32767).astype(np.int16)

        # Create stereo sound
        stereo_wave = np.column_stack((wave, wave))

        return pygame.sndarray.make_sound(stereo_wave)

    def play_speeding_alert(self):
        """Play speeding warning sound (single beep)"""
        current_time = time.time()
        if current_time - self.last_speeding_alert > self.alert_cooldown:
            sound = self.generate_beep(frequency=900, duration=0.4)
            sound.play()
            self.last_speeding_alert = current_time

    def play_drowsy_alert(self):
        """Play drowsy/intoxicated warning sound (urgent double beep)"""
        current_time = time.time()
        if current_time - self.last_drowsy_alert > self.alert_cooldown:
            # Play urgent double beep
            sound1 = self.generate_beep(frequency=1200, duration=0.2)
            sound1.play()
            pygame.time.wait(250)
            sound2 = self.generate_beep(frequency=1200, duration=0.2)
            sound2.play()
            self.last_drowsy_alert = current_time


class Settings:
    def __init__(self):
        self.zoom_level = 1.0
        self.zoom_levels = [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 7.0, 10.0]
        self.show_settings = False
        self.show_help = True

    def increase_zoom(self):
        """Increase zoom to next level"""
        current_idx = (
            self.zoom_levels.index(self.zoom_level)
            if self.zoom_level in self.zoom_levels
            else 1
        )
        if current_idx < len(self.zoom_levels) - 1:
            self.zoom_level = self.zoom_levels[current_idx + 1]
            return True
        return False

    def decrease_zoom(self):
        """Decrease zoom to previous level"""
        current_idx = (
            self.zoom_levels.index(self.zoom_level)
            if self.zoom_level in self.zoom_levels
            else 1
        )
        if current_idx > 0:
            self.zoom_level = self.zoom_levels[current_idx - 1]
            return True
        return False

    def set_zoom(self, level):
        """Set zoom to specific level"""
        if level in self.zoom_levels:
            self.zoom_level = level
            return True
        return False

    def reset_zoom(self):
        """Reset zoom to 1x"""
        self.zoom_level = 1.0

    def toggle_settings(self):
        """Toggle settings menu visibility"""
        self.show_settings = not self.show_settings


class DrivingSimulator:
    def __init__(self):
        self.speed = 45.0  # Start at 45 MPH
        self.speed_limit = 65  # Speed limit
        self.min_speed = 0
        self.max_speed = 100
        self.direction = "forward"
        self.update_counter = 0
        self.update_frequency = 5  # Update every 5 frames for smoother changes

        # Compass direction (0-360 degrees, 0=North, 90=East, 180=South, 270=West)
        self.heading = 45.0  # Start heading Northeast
        self.compass_directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

    def update_speed(self):
        """Update speed with random realistic changes"""
        self.update_counter += 1

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
        """Manually increase speed (for testing)"""
        self.speed = min(self.max_speed, self.speed + amount)
        self.direction = "accelerating"

    def manual_speed_decrease(self, amount=10):
        """Manually decrease speed (for testing)"""
        self.speed = max(self.min_speed, self.speed - amount)
        self.direction = "decelerating"

    def set_speeding_mode(self):
        """Set speed to 75 MPH for testing speeding alerts"""
        self.speed = 75.0
        self.direction = "speeding"

    def reset_speed(self):
        """Reset speed to safe default"""
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
        # Each direction covers 45 degrees
        # 0-22.5 and 337.5-360 = N
        # 22.5-67.5 = NE
        # etc.
        index = int((self.heading + 22.5) / 45.0) % 8
        return self.compass_directions[index]

    def get_heading(self):
        """Get current heading in degrees"""
        return int(self.heading)


class FaceAnalyzer:
    def __init__(self):
        # Initialize MediaPipe Face Landmarker
        base_options = python.BaseOptions(model_asset_path="face_landmarker.task")
        options = vision.FaceLandmarkerOptions(
            base_options=base_options,
            running_mode=vision.RunningMode.VIDEO,
            num_faces=5,
            min_face_detection_confidence=0.5,
            min_face_presence_confidence=0.5,
            min_tracking_confidence=0.5,
        )
        self.landmarker = vision.FaceLandmarker.create_from_options(options)

        # Eye landmarks indices for MediaPipe Face Mesh
        self.LEFT_EYE = [362, 385, 387, 263, 373, 380]
        self.RIGHT_EYE = [33, 160, 158, 133, 153, 144]

        # Thresholds
        self.EAR_THRESHOLD = 0.21
        self.DROWSINESS_FRAMES = 20
        self.BLINK_THRESHOLD = 30

        # Tracking variables
        self.eye_closed_counter = 0
        self.blink_counter = 0
        self.blink_history = deque(maxlen=100)
        self.ear_history = deque(maxlen=50)

    def calculate_ear(self, eye_landmarks):
        """Calculate Eye Aspect Ratio"""
        # Vertical eye landmarks
        A = distance.euclidean(eye_landmarks[1], eye_landmarks[5])
        B = distance.euclidean(eye_landmarks[2], eye_landmarks[4])
        # Horizontal eye landmark
        C = distance.euclidean(eye_landmarks[0], eye_landmarks[3])

        # EAR formula
        ear = (A + B) / (2.0 * C)
        return ear

    def get_eye_landmarks(self, face_landmarks, eye_indices, w, h):
        """Extract eye landmark coordinates"""
        landmarks = []
        for idx in eye_indices:
            landmark = face_landmarks[idx]
            x = int(landmark.x * w)
            y = int(landmark.y * h)
            landmarks.append((x, y))
        return landmarks

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
        ear_variance = np.var(self.ear_history) if len(self.ear_history) > 10 else 0
        unstable_eyes = ear_variance > 0.005

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

    def process_frame(self, frame, timestamp_ms):
        """Process a single frame for face and eye detection

        Returns:
            tuple: (processed_frame, detection_data)
                detection_data contains: intox_data, face_crop, face_bbox, eye_states
        """
        h, w, _ = frame.shape
        rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)

        # Convert to MediaPipe Image
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb_frame)

        # Detect face landmarks
        results = self.landmarker.detect_for_video(mp_image, timestamp_ms)

        # Detection data to return
        detection_data = None

        if results.face_landmarks:
            for face_landmarks in results.face_landmarks:
                # Get face bounding box
                x_coords = [landmark.x for landmark in face_landmarks]
                y_coords = [landmark.y for landmark in face_landmarks]

                x_min = int(min(x_coords) * w)
                x_max = int(max(x_coords) * w)
                y_min = int(min(y_coords) * h)
                y_max = int(max(y_coords) * h)

                # Draw face rectangle
                cv2.rectangle(frame, (x_min, y_min), (x_max, y_max), (0, 255, 0), 2)

                # Get eye landmarks
                left_eye = self.get_eye_landmarks(face_landmarks, self.LEFT_EYE, w, h)
                right_eye = self.get_eye_landmarks(face_landmarks, self.RIGHT_EYE, w, h)

                # Calculate EAR for both eyes
                left_ear = self.calculate_ear(left_eye)
                right_ear = self.calculate_ear(right_eye)

                # Determine eye state
                left_eye_state = "CLOSED" if left_ear < self.EAR_THRESHOLD else "OPEN"
                right_eye_state = "CLOSED" if right_ear < self.EAR_THRESHOLD else "OPEN"

                # Draw eye landmarks
                for point in left_eye:
                    cv2.circle(frame, point, 2, (255, 0, 0), -1)
                for point in right_eye:
                    cv2.circle(frame, point, 2, (255, 0, 0), -1)

                # Detect intoxication
                intox_data = self.detect_intoxication(left_ear, right_ear)

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
                }

                # Display information
                y_offset = y_min - 10
                cv2.putText(
                    frame,
                    f"L Eye: {left_eye_state} ({left_ear:.2f})",
                    (x_min, y_offset),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.5,
                    (0, 255, 0),
                    2,
                )
                y_offset -= 20
                cv2.putText(
                    frame,
                    f"R Eye: {right_eye_state} ({right_ear:.2f})",
                    (x_min, y_offset),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.5,
                    (0, 255, 0),
                    2,
                )

                # Display intoxication status
                y_offset = y_max + 20
                if intox_data["score"] >= 4:
                    status = "HIGH RISK - INTOXICATED"
                    color = (0, 0, 255)
                elif intox_data["score"] >= 2:
                    status = "MODERATE RISK - IMPAIRED"
                    color = (0, 165, 255)
                else:
                    status = "NORMAL - ALERT"
                    color = (0, 255, 0)

                cv2.putText(
                    frame,
                    f"Status: {status}",
                    (x_min, y_offset),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.6,
                    color,
                    2,
                )
                y_offset += 25

                # Display specific indicators
                if intox_data["drowsy"]:
                    cv2.putText(
                        frame,
                        "WARNING: Drowsy",
                        (x_min, y_offset),
                        cv2.FONT_HERSHEY_SIMPLEX,
                        0.5,
                        (0, 0, 255),
                        2,
                    )
                    y_offset += 20
                if intox_data["excessive_blinking"]:
                    cv2.putText(
                        frame,
                        "WARNING: Excessive Blinking",
                        (x_min, y_offset),
                        cv2.FONT_HERSHEY_SIMPLEX,
                        0.5,
                        (0, 165, 255),
                        2,
                    )
                    y_offset += 20
                if intox_data["unstable_eyes"]:
                    cv2.putText(
                        frame,
                        "WARNING: Eye Instability",
                        (x_min, y_offset),
                        cv2.FONT_HERSHEY_SIMPLEX,
                        0.5,
                        (0, 165, 255),
                        2,
                    )

        return frame, detection_data


def apply_zoom(frame, zoom_level):
    """Apply digital zoom to frame by cropping and resizing"""
    if zoom_level == 1.0:
        return frame

    h, w = frame.shape[:2]

    # Calculate crop dimensions
    crop_h = int(h / zoom_level)
    crop_w = int(w / zoom_level)

    # Calculate center crop coordinates
    start_y = (h - crop_h) // 2
    start_x = (w - crop_w) // 2

    # Crop the center region
    cropped = frame[start_y : start_y + crop_h, start_x : start_x + crop_w]

    # Resize back to original dimensions
    zoomed = cv2.resize(cropped, (w, h), interpolation=cv2.INTER_LINEAR)

    return zoomed


def draw_settings_overlay(frame, settings):
    """Draw settings menu overlay on frame"""
    h, w = frame.shape[:2]

    # Create semi-transparent overlay
    overlay = frame.copy()

    if settings.show_settings:
        # Draw settings panel background (larger to fit speed controls)
        cv2.rectangle(overlay, (20, 20), (450, 480), (40, 40, 40), -1)
        cv2.rectangle(overlay, (20, 20), (450, 480), (0, 255, 0), 2)

        # Add transparency
        frame = cv2.addWeighted(overlay, 0.85, frame, 0.15, 0)

        # Draw title
        cv2.putText(
            frame,
            "SETTINGS MENU",
            (30, 50),
            cv2.FONT_HERSHEY_DUPLEX,
            0.8,
            (0, 255, 0),
            2,
        )

        # Draw separator
        cv2.line(frame, (30, 60), (440, 60), (0, 255, 0), 1)

        # Draw zoom controls
        y_offset = 90
        cv2.putText(
            frame,
            "ZOOM CONTROLS",
            (30, y_offset),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.6,
            (255, 255, 255),
            2,
        )
        y_offset += 30

        cv2.putText(
            frame,
            f"Current Zoom: {settings.zoom_level}x",
            (30, y_offset),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.5,
            (0, 255, 255),
            1,
        )
        y_offset += 25

        # Keyboard shortcuts
        cv2.putText(
            frame,
            "'+' or '=' : Zoom In",
            (30, y_offset),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.5,
            (200, 200, 200),
            1,
        )
        y_offset += 25
        cv2.putText(
            frame,
            "'-' or '_' : Zoom Out",
            (30, y_offset),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.5,
            (200, 200, 200),
            1,
        )
        y_offset += 25
        cv2.putText(
            frame,
            "'r'        : Reset to 1x",
            (30, y_offset),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.5,
            (200, 200, 200),
            1,
        )
        y_offset += 35

        # Quick zoom levels
        cv2.putText(
            frame,
            "QUICK ZOOM LEVELS",
            (30, y_offset),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.6,
            (255, 255, 255),
            2,
        )
        y_offset += 30

        quick_zooms = [
            ("'1' : 1.0x", "'2' : 2.0x"),
            ("'3' : 3.0x", "'4' : 4.0x"),
            ("'5' : 5.0x", "'0' : 10.0x"),
        ]

        for left, right in quick_zooms:
            cv2.putText(
                frame,
                left,
                (30, y_offset),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.5,
                (200, 200, 200),
                1,
            )
            cv2.putText(
                frame,
                right,
                (230, y_offset),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.5,
                (200, 200, 200),
                1,
            )
            y_offset += 25

        y_offset += 10
        cv2.line(frame, (30, y_offset), (440, y_offset), (0, 255, 0), 1)
        y_offset += 25

        # Speed test controls
        cv2.putText(
            frame,
            "SPEED TEST CONTROLS",
            (30, y_offset),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.6,
            (255, 255, 255),
            2,
        )
        y_offset += 30

        cv2.putText(
            frame,
            "'X'       : Simulate Speeding (75 MPH)",
            (30, y_offset),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.5,
            (200, 200, 200),
            1,
        )
        y_offset += 25
        cv2.putText(
            frame,
            "'C'       : Reset Speed (45 MPH)",
            (30, y_offset),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.5,
            (200, 200, 200),
            1,
        )
        y_offset += 25
        cv2.putText(
            frame,
            "UP Arrow  : +10 MPH",
            (30, y_offset),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.5,
            (200, 200, 200),
            1,
        )
        y_offset += 25
        cv2.putText(
            frame,
            "DOWN Arrow: -10 MPH",
            (30, y_offset),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.5,
            (200, 200, 200),
            1,
        )

        y_offset += 35
        cv2.line(frame, (30, y_offset), (440, y_offset), (0, 255, 0), 1)
        y_offset += 25

        # Other controls
        cv2.putText(
            frame,
            "'s' : Toggle Settings Menu",
            (30, y_offset),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.5,
            (200, 200, 200),
            1,
        )
        y_offset += 25
        cv2.putText(
            frame,
            "'h' : Toggle Help Overlay",
            (30, y_offset),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.5,
            (200, 200, 200),
            1,
        )
        y_offset += 25
        cv2.putText(
            frame,
            "'q' : Quit Application",
            (30, y_offset),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.5,
            (200, 200, 200),
            1,
        )

    # Always show zoom indicator and help hint
    if settings.show_help:
        cv2.putText(
            frame,
            f"Zoom: {settings.zoom_level}x",
            (w - 150, 30),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.7,
            (0, 255, 255),
            2,
        )
        cv2.putText(
            frame,
            "Press 's' for Settings",
            (w - 220, h - 20),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.5,
            (200, 200, 200),
            1,
        )

    return frame


def draw_driving_info(frame, driving_sim, warning_sound=None):
    """Draw driving speed and speed limit information"""
    h, w = frame.shape[:2]

    # Position for driving info (top-left area)
    x_pos = 20
    y_pos = 20

    # Draw semi-transparent background for driving info (expanded for compass)
    overlay = frame.copy()
    cv2.rectangle(overlay, (x_pos, y_pos), (x_pos + 400, y_pos + 190), (30, 30, 30), -1)
    cv2.rectangle(
        overlay, (x_pos, y_pos), (x_pos + 400, y_pos + 190), (255, 255, 255), 2
    )
    frame = cv2.addWeighted(overlay, 0.7, frame, 0.3, 0)

    # Draw current speed
    y_offset = y_pos + 35
    cv2.putText(
        frame,
        "CURRENT SPEED",
        (x_pos + 10, y_offset),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.5,
        (255, 255, 255),
        1,
    )

    y_offset += 45
    speed = driving_sim.get_speed()
    speed_color = driving_sim.get_speed_status()

    # Large speed display
    cv2.putText(
        frame,
        f"{speed}",
        (x_pos + 30, y_offset),
        cv2.FONT_HERSHEY_DUPLEX,
        2.0,
        speed_color,
        3,
    )
    cv2.putText(
        frame,
        "MPH",
        (x_pos + 180, y_offset - 5),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.8,
        speed_color,
        2,
    )

    # Direction indicator
    y_offset += 30
    direction_text = f"Status: {driving_sim.direction.upper()}"
    cv2.putText(
        frame,
        direction_text,
        (x_pos + 10, y_offset),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.45,
        (200, 200, 200),
        1,
    )

    # Compass visualization
    y_offset += 30
    compass_center_x = x_pos + 240
    compass_center_y = y_offset + 35
    compass_radius = 45

    # Draw compass circle (dark background)
    cv2.circle(
        frame, (compass_center_x, compass_center_y), compass_radius, (50, 50, 50), -1
    )
    cv2.circle(
        frame, (compass_center_x, compass_center_y), compass_radius, (200, 200, 200), 2
    )

    # Draw cardinal direction markers
    cardinal_positions = {"N": 0, "E": 90, "S": 180, "W": 270}

    for direction, angle in cardinal_positions.items():
        angle_rad = np.radians(angle - 90)  # -90 to start from top
        # Outer point for direction label
        label_x = int(compass_center_x + (compass_radius - 10) * np.cos(angle_rad))
        label_y = int(compass_center_y + (compass_radius - 10) * np.sin(angle_rad))

        # Color N in red, others in white
        color = (0, 0, 255) if direction == "N" else (200, 200, 200)
        cv2.putText(
            frame,
            direction,
            (label_x - 5, label_y + 5),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.4,
            color,
            2,
        )

    # Draw heading needle (points to current heading)
    heading = driving_sim.heading
    heading_rad = np.radians(heading - 90)  # -90 to start from top (North)

    # Needle tip (pointing to heading direction)
    needle_length = compass_radius - 15
    needle_tip_x = int(compass_center_x + needle_length * np.cos(heading_rad))
    needle_tip_y = int(compass_center_y + needle_length * np.sin(heading_rad))

    # Needle base (opposite direction, smaller)
    base_length = 10
    needle_base_x = int(compass_center_x - base_length * np.cos(heading_rad))
    needle_base_y = int(compass_center_y - base_length * np.sin(heading_rad))

    # Draw red needle
    cv2.line(
        frame,
        (needle_base_x, needle_base_y),
        (needle_tip_x, needle_tip_y),
        (0, 0, 255),
        3,
    )
    # Draw needle tip arrow
    cv2.circle(frame, (needle_tip_x, needle_tip_y), 4, (0, 0, 255), -1)

    # Center dot
    cv2.circle(frame, (compass_center_x, compass_center_y), 3, (255, 255, 255), -1)

    # Display compass direction and heading below compass
    compass_dir = driving_sim.get_compass_direction()
    heading_degrees = driving_sim.get_heading()
    cv2.putText(
        frame,
        f"{compass_dir} ({heading_degrees}°)",
        (compass_center_x - 35, compass_center_y + compass_radius + 20),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.5,
        (0, 255, 255),
        2,
    )

    # Compass label
    cv2.putText(
        frame,
        "HEADING",
        (compass_center_x - 30, y_offset),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.4,
        (255, 255, 255),
        1,
    )

    # Speed limit sign - Apple Maps style
    y_offset += 110
    cv2.line(
        frame,
        (x_pos + 10, y_offset - 10),
        (x_pos + 180, y_offset - 10),
        (150, 150, 150),
        1,
    )

    # Draw Apple Maps style speed limit sign (white with black border)
    sign_x = x_pos + 95
    sign_y = y_offset + 15
    sign_width = 70
    sign_height = 80
    corner_radius = 8

    # Create rounded rectangle for sign background (white)
    overlay_sign = frame.copy()

    # Draw rounded rectangle (white background)
    cv2.rectangle(
        overlay_sign,
        (sign_x, sign_y + corner_radius),
        (sign_x + sign_width, sign_y + sign_height - corner_radius),
        (255, 255, 255),
        -1,
    )
    cv2.rectangle(
        overlay_sign,
        (sign_x + corner_radius, sign_y),
        (sign_x + sign_width - corner_radius, sign_y + sign_height),
        (255, 255, 255),
        -1,
    )

    # Draw corners
    cv2.circle(
        overlay_sign,
        (sign_x + corner_radius, sign_y + corner_radius),
        corner_radius,
        (255, 255, 255),
        -1,
    )
    cv2.circle(
        overlay_sign,
        (sign_x + sign_width - corner_radius, sign_y + corner_radius),
        corner_radius,
        (255, 255, 255),
        -1,
    )
    cv2.circle(
        overlay_sign,
        (sign_x + corner_radius, sign_y + sign_height - corner_radius),
        corner_radius,
        (255, 255, 255),
        -1,
    )
    cv2.circle(
        overlay_sign,
        (sign_x + sign_width - corner_radius, sign_y + sign_height - corner_radius),
        corner_radius,
        (255, 255, 255),
        -1,
    )

    # Blend for slight transparency
    cv2.addWeighted(overlay_sign, 0.95, frame, 0.05, 0, frame)

    # Draw black border
    cv2.rectangle(
        frame,
        (sign_x, sign_y + corner_radius),
        (sign_x + sign_width, sign_y + sign_height - corner_radius),
        (0, 0, 0),
        2,
    )
    cv2.rectangle(
        frame,
        (sign_x + corner_radius, sign_y),
        (sign_x + sign_width - corner_radius, sign_y + sign_height),
        (0, 0, 0),
        2,
    )

    # Draw corner arcs for border
    cv2.ellipse(
        frame,
        (sign_x + corner_radius, sign_y + corner_radius),
        (corner_radius, corner_radius),
        180,
        0,
        90,
        (0, 0, 0),
        2,
    )
    cv2.ellipse(
        frame,
        (sign_x + sign_width - corner_radius, sign_y + corner_radius),
        (corner_radius, corner_radius),
        270,
        0,
        90,
        (0, 0, 0),
        2,
    )
    cv2.ellipse(
        frame,
        (sign_x + corner_radius, sign_y + sign_height - corner_radius),
        (corner_radius, corner_radius),
        90,
        0,
        90,
        (0, 0, 0),
        2,
    )
    cv2.ellipse(
        frame,
        (sign_x + sign_width - corner_radius, sign_y + sign_height - corner_radius),
        (corner_radius, corner_radius),
        0,
        0,
        90,
        (0, 0, 0),
        2,
    )

    # Black text on white background
    cv2.putText(
        frame,
        "SPEED",
        (sign_x + 8, sign_y + 23),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.45,
        (0, 0, 0),
        2,
    )
    cv2.putText(
        frame,
        "LIMIT",
        (sign_x + 8, sign_y + 41),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.45,
        (0, 0, 0),
        2,
    )

    # Large speed limit number
    cv2.putText(
        frame,
        "65",
        (sign_x + 15, sign_y + 70),
        cv2.FONT_HERSHEY_DUPLEX,
        1.2,
        (0, 0, 0),
        2,
    )

    # Speeding warning
    if driving_sim.is_speeding():
        warning_y = y_pos + 195
        cv2.putText(
            frame,
            "SPEEDING!",
            (x_pos + 80, warning_y),
            cv2.FONT_HERSHEY_DUPLEX,
            0.7,
            (0, 0, 255),
            2,
        )

        # Play speeding alert sound
        if warning_sound:
            warning_sound.play_speeding_alert()

    return frame


def main():
    # Open the default camera (index 0)
    cap = cv2.VideoCapture(0)

    if not cap.isOpened():
        print("Error: Could not open camera")
        return

    print("Camera opened successfully!")
    print("Press 'q' to quit")
    print("\nDetection Features:")
    print("- Face detection with bounding boxes")
    print("- Real-time eye state detection (Open/Closed)")
    print("- Intoxication risk assessment")
    print("- Camera zoom control (0.5x - 10x)")
    print("- Driving speed simulation (0-100 MPH)")
    print("- Warning sound alerts for speeding and drowsiness")
    print("- Supabase cloud sync with real-time vehicle tracking")
    print("\nIntoxication Indicators:")
    print("- Drowsiness (prolonged eye closure)")
    print("- Excessive blinking patterns")
    print("- Eye movement instability")
    print("\nControls:")
    print("- Press 's' to open Settings Menu")
    print("- Press '+/-' to zoom in/out")
    print("- Press '1-5' or '0' for quick zoom levels")
    print("\nSpeed Test Controls:")
    print("- Press 'X' to simulate speeding (75 MPH)")
    print("- Press 'C' to reset speed to normal (45 MPH)")
    print("- Press UP/DOWN arrows to adjust speed by 10 MPH")

    analyzer = FaceAnalyzer()
    settings = Settings()
    driving_sim = DrivingSimulator()
    warning_sound = WarningSound()
    supabase_uploader = SupabaseUploader()
    frame_count = 0

    while True:
        # Capture frame-by-frame
        ret, frame = cap.read()

        if not ret:
            print("Error: Could not read frame")
            break

        # Apply zoom before processing
        zoomed_frame = apply_zoom(frame, settings.zoom_level)

        # Calculate timestamp in milliseconds
        timestamp_ms = int(frame_count * 33.33)  # Assuming ~30 FPS
        frame_count += 1

        # Update driving simulation
        driving_sim.update_speed()

        # Process frame with AI detection
        processed_frame, detection_data = analyzer.process_frame(
            zoomed_frame, timestamp_ms
        )

        # Extract intox_data for alerts
        intox_data = detection_data["intox_data"] if detection_data else None

        # Check for drowsy/intoxicated driver and play alert
        if intox_data and intox_data["score"] >= 4:
            warning_sound.play_drowsy_alert()

        # Determine driver status for realtime update
        if intox_data:
            if intox_data["score"] >= 4:
                driver_status = "impaired"
            elif intox_data["score"] >= 2:
                driver_status = "drowsy"
            else:
                driver_status = "alert"
            intox_score = intox_data["score"]
        else:
            driver_status = "unknown"
            intox_score = 0

        # Update vehicle realtime data (every 500ms)
        supabase_uploader.update_vehicle_realtime(
            speed_mph=driving_sim.get_speed(),
            heading_degrees=driving_sim.get_heading(),
            compass_direction=driving_sim.get_compass_direction(),
            is_speeding=driving_sim.is_speeding(),
            driver_status=driver_status,
            intoxication_score=intox_score,
        )

        # Update trip statistics
        is_drowsy = intox_data["drowsy"] if intox_data else False
        is_excessive_blinking = intox_data["excessive_blinking"] if intox_data else False
        is_unstable_eyes = intox_data["unstable_eyes"] if intox_data else False
        supabase_uploader.update_trip_stats(
            speed=driving_sim.get_speed(),
            intox_score=intox_score,
            is_speeding=driving_sim.is_speeding(),
            is_drowsy=is_drowsy,
            is_excessive_blinking=is_excessive_blinking,
            is_unstable_eyes=is_unstable_eyes,
        )

        # Upload face detection to Supabase (every 2s when face detected)
        if detection_data and supabase_uploader.should_upload():
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
            )
            supabase_uploader.increment_face_detection_count()

        # Check for identified driver (every 5s when face detected)
        if detection_data:
            supabase_uploader.check_current_driver()

        # Draw driving info with warning sound
        processed_frame = draw_driving_info(processed_frame, driving_sim, warning_sound)

        # Draw settings overlay
        final_frame = draw_settings_overlay(processed_frame, settings)

        # Display the frame
        cv2.imshow("Face & Eye Analysis - Press Q to Quit", final_frame)

        # Handle keyboard input
        key = cv2.waitKey(1) & 0xFF

        if key == ord("q"):
            break
        elif key == ord("s"):
            settings.toggle_settings()
        elif key == ord("h"):
            settings.show_help = not settings.show_help
        elif key == ord("+") or key == ord("="):
            if settings.increase_zoom():
                print(f"Zoom: {settings.zoom_level}x")
        elif key == ord("-") or key == ord("_"):
            if settings.decrease_zoom():
                print(f"Zoom: {settings.zoom_level}x")
        elif key == ord("r"):
            settings.reset_zoom()
            print("Zoom reset to 1.0x")
        elif key == ord("1"):
            settings.set_zoom(1.0)
            print("Zoom: 1.0x")
        elif key == ord("2"):
            settings.set_zoom(2.0)
            print("Zoom: 2.0x")
        elif key == ord("3"):
            settings.set_zoom(3.0)
            print("Zoom: 3.0x")
        elif key == ord("4"):
            settings.set_zoom(4.0)
            print("Zoom: 4.0x")
        elif key == ord("5"):
            settings.set_zoom(5.0)
            print("Zoom: 5.0x")
        elif key == ord("0"):
            settings.set_zoom(10.0)
            print("Zoom: 10.0x")

        # Speed control keys (for testing)
        elif key == 82 or key == 0:  # Up arrow (different codes on different systems)
            driving_sim.manual_speed_increase(10)
            print(f"Speed increased to: {driving_sim.get_speed()} MPH")
        elif key == 84 or key == 1:  # Down arrow
            driving_sim.manual_speed_decrease(10)
            print(f"Speed decreased to: {driving_sim.get_speed()} MPH")
        elif key == ord("x"):
            driving_sim.set_speeding_mode()
            print(f"SPEEDING MODE: Speed set to {driving_sim.get_speed()} MPH")
        elif key == ord("c"):
            driving_sim.reset_speed()
            print(f"Speed reset to: {driving_sim.get_speed()} MPH")

    # End trip and release resources
    supabase_uploader.end_trip()
    cap.release()
    cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
