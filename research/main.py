import os
import random
import time
import uuid
from collections import deque
from datetime import datetime, timedelta, timezone

# PST timezone (UTC-8)
PST = timezone(timedelta(hours=-8))

import cv2

# import face_recognition  # Temporarily disabled due to dlib issues
import mediapipe as mp
import numpy as np
from dotenv import load_dotenv
from mediapipe.tasks import python
from mediapipe.tasks.python import vision
from scipy.spatial import distance
from supabase import Client, create_client
from ultralytics import YOLO

from buzzer import BuzzerController
from gps import GPSReader

# Load environment variables from .env file
load_dotenv()


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

        # Subscribe to realtime buzzer commands
        self._subscribe_to_buzzer_commands()

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
                "excessive_blinking_event_count": int(
                    self.trip_excessive_blinking_events
                ),
                "unstable_eyes_event_count": int(self.trip_unstable_eyes_events),
                "face_detection_count": int(self.trip_face_detections),
                "speed_sample_count": len(self.trip_speed_samples),
                "speed_sample_sum": int(sum(self.trip_speed_samples)),
                "status": self._calculate_trip_status(),
            }

            # Add driver profile if identified
            if self.current_driver_profile_id:
                record["driver_profile_id"] = self.current_driver_profile_id

            self.client.table("vehicle_trips").update(record).eq(
                "id", self.trip_id
            ).execute()

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
            }

            # Add driver profile if identified
            if self.current_driver_profile_id:
                record["driver_profile_id"] = self.current_driver_profile_id

            self.client.table("vehicle_trips").update(record).eq(
                "id", self.trip_id
            ).execute()
            print(
                f"Trip ended: {self.trip_id} (Status: {self._calculate_trip_status()})"
            )

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
        """Poll for buzzer command changes (called from main loop)"""
        if not self.buzzer:
            return

        current_time = time.time()
        if current_time - self.last_buzzer_check < self.buzzer_check_interval:
            return

        self.last_buzzer_check = current_time

        try:
            # Query current buzzer state
            response = (
                self.client.table("vehicle_realtime")
                .select("buzzer_active, buzzer_type")
                .eq("vehicle_id", self.vehicle_id)
                .execute()
            )

            if response.data and len(response.data) > 0:
                buzzer_active = response.data[0].get("buzzer_active", False)
                buzzer_type = response.data[0].get("buzzer_type", "alert")

                # Only react to state changes
                if buzzer_active != self.last_buzzer_state:
                    if buzzer_active:
                        print(f"\n>>> REMOTE BUZZER ACTIVATED ({buzzer_type}) <<<\n")
                        self.buzzer.start_continuous(buzzer_type)
                    else:
                        print("\n>>> REMOTE BUZZER DEACTIVATED <<<\n")
                        self.buzzer.stop_continuous()

                    self.last_buzzer_state = buzzer_active

        except Exception as e:
            print(f"Error checking buzzer commands: {e}")

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
        """Update vehicle real-time location/status (called frequently)"""
        current_time = time.time()
        if current_time - self.last_realtime_update < self.realtime_cooldown:
            return None

        try:
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
        distraction_data: dict = None,
    ):
        """Upload face snapshot and metadata to Supabase with face clustering"""
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

            # Generate face embedding for clustering similar faces
            face_embedding = self.generate_face_embedding(face_image)
            face_cluster_id = None

            if face_embedding:
                # Find existing cluster or create new one
                face_cluster_id = self.find_or_create_cluster(face_embedding)

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

            # Add face embedding and cluster for similarity matching
            if face_embedding:
                # Format as PostgreSQL vector string
                record["face_embedding"] = (
                    "[" + ",".join(str(x) for x in face_embedding) + "]"
                )
            if face_cluster_id:
                record["face_cluster_id"] = face_cluster_id

            # Add current driver profile if identified
            if self.current_driver_profile_id:
                record["driver_profile_id"] = self.current_driver_profile_id

            # Add driving data if available
            if driving_data:
                record["speed_mph"] = int(driving_data.get("speed", 0))
                record["heading_degrees"] = int(driving_data.get("heading", 0))
                record["compass_direction"] = str(driving_data.get("direction", "N"))
                record["is_speeding"] = bool(driving_data.get("is_speeding", False))

            # Add distraction data if available
            if distraction_data:
                record["is_phone_detected"] = bool(
                    distraction_data.get("phone_detected", False)
                )
                record["is_drinking_detected"] = bool(
                    distraction_data.get("drinking_detected", False)
                )

            # Insert record into database
            db_response = self.client.table("face_detections").insert(record).execute()

            self.last_upload_time = time.time()

            # Print upload info with driver name and cluster info
            cluster_info = (
                f", Cluster: {face_cluster_id[:8]}..." if face_cluster_id else ""
            )
            if self.current_driver_name:
                print(
                    f"Uploaded face detection: {filename} (Driver: {self.current_driver_name}{cluster_info})"
                )
            else:
                print(
                    f"Uploaded face detection: {filename} (Unidentified{cluster_info})"
                )

            return db_response

        except Exception as e:
            print(f"Error uploading to Supabase: {e}")
            return None


class DistractionDetector:
    """YOLO-based detector for phone usage and drinking detection"""

    # COCO class IDs for objects we care about
    CELL_PHONE = 67
    BOTTLE = 39
    CUP = 41

    def __init__(self, model_path="yolov8m.pt"):
        """Initialize YOLO model for object detection

        Args:
            model_path: Path to YOLO model weights. Use 'yolov8n.pt' for nano (fast),
                       'yolov8s.pt' for small, 'yolov8m.pt' for medium accuracy.
        """
        print(f"Loading YOLO model: {model_path}")
        self.model = YOLO(model_path)
        self.confidence_threshold = 0.25  # Lower threshold for better detection

        # Detection state
        self.phone_detected = False
        self.drinking_detected = False
        self.phone_bbox = None
        self.bottle_bbox = None

        # Smoothing - require multiple consecutive frames
        self.phone_frames = 0
        self.drinking_frames = 0
        self.detection_threshold = 2  # Frames needed to confirm detection

        print("YOLO model loaded successfully")

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

        return dx < extended_width and dy < extended_height

    def detect(self, frame, face_bbox=None):
        """Run YOLO detection on frame

        Args:
            frame: BGR image from OpenCV
            face_bbox: Optional face bounding box dict with x_min, y_min, x_max, y_max

        Returns:
            dict with detection results
        """
        # Run YOLO inference
        results = self.model(frame, verbose=False, conf=self.confidence_threshold)

        current_phone = None
        current_bottle = None

        # Process detections
        for result in results:
            boxes = result.boxes
            if boxes is None:
                continue

            for box in boxes:
                cls = int(box.cls[0])
                conf = float(box.conf[0])
                xyxy = box.xyxy[0].cpu().numpy()
                bbox = (int(xyxy[0]), int(xyxy[1]), int(xyxy[2]), int(xyxy[3]))

                # Get class name for debugging
                class_name = self.model.names[cls]

                if cls == self.CELL_PHONE:
                    current_phone = bbox
                    print(f"YOLO: PHONE (class {cls}: {class_name}) conf={conf:.2f}")
                elif cls in (self.BOTTLE, self.CUP):
                    current_bottle = bbox
                    print(
                        f"YOLO: BOTTLE/CUP (class {cls}: {class_name}) conf={conf:.2f}"
                    )
                # Debug: show other common objects being detected
                elif conf > 0.4:
                    print(
                        f"YOLO: Other object (class {cls}: {class_name}) conf={conf:.2f}"
                    )

        # Update phone detection with smoothing
        if current_phone is not None:
            self.phone_bbox = current_phone
            self.phone_frames += 1
        else:
            self.phone_frames = max(0, self.phone_frames - 1)
            if self.phone_frames == 0:
                self.phone_bbox = None

        # Update drinking detection with smoothing
        if current_bottle is not None:
            self.bottle_bbox = current_bottle
            self.drinking_frames += 1
        else:
            self.drinking_frames = max(0, self.drinking_frames - 1)
            if self.drinking_frames == 0:
                self.bottle_bbox = None

        # Confirm detections based on frame threshold
        self.phone_detected = self.phone_frames >= self.detection_threshold
        self.drinking_detected = self.drinking_frames >= self.detection_threshold

        return {
            "phone_detected": self.phone_detected,
            "drinking_detected": self.drinking_detected,
            "phone_bbox": self.phone_bbox,
            "bottle_bbox": self.bottle_bbox,
            "phone_frames": self.phone_frames,
            "drinking_frames": self.drinking_frames,
        }

    def draw_detections(self, frame):
        """Draw detection boxes on frame"""
        if self.phone_bbox:
            x1, y1, x2, y2 = self.phone_bbox
            color = (0, 0, 255) if self.phone_detected else (0, 165, 255)
            cv2.rectangle(frame, (x1, y1), (x2, y2), color, 2)
            label = "PHONE - DISTRACTED!" if self.phone_detected else "Phone"
            cv2.putText(
                frame, label, (x1, y1 - 10), cv2.FONT_HERSHEY_SIMPLEX, 0.6, color, 2
            )

        if self.bottle_bbox:
            x1, y1, x2, y2 = self.bottle_bbox
            color = (0, 165, 255) if self.drinking_detected else (255, 165, 0)
            cv2.rectangle(frame, (x1, y1), (x2, y2), color, 2)
            label = "DRINKING!" if self.drinking_detected else "Bottle/Cup"
            cv2.putText(
                frame, label, (x1, y1 - 10), cv2.FONT_HERSHEY_SIMPLEX, 0.6, color, 2
            )

        return frame


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
    def __init__(self, gps_reader: GPSReader = None):
        self.gps = gps_reader
        self.speed = 45.0  # Start at 45 MPH (used for simulation mode)
        self.speed_limit = 65  # Speed limit
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

    def update_speed(self):
        """Update speed - from GPS if available, otherwise simulate"""
        self.update_counter += 1

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
        # Threshold increased - 0.005 was way too sensitive, normal blinking causes that
        ear_variance = np.var(self.ear_history) if len(self.ear_history) > 10 else 0
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

                # Note: Eye landmark circles removed for performance

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


def draw_distraction_warning(frame, distraction_data):
    """Draw prominent distraction warning banner on frame"""
    if not distraction_data:
        return frame

    h, w = frame.shape[:2]

    if distraction_data["phone_detected"]:
        # Red banner for phone usage - use direct rectangle with reduced opacity
        cv2.rectangle(frame, (0, h - 80), (w, h), (0, 0, 128), -1)

        cv2.putText(
            frame,
            "WARNING: PHONE DETECTED - EYES ON ROAD!",
            (w // 2 - 280, h - 45),
            cv2.FONT_HERSHEY_DUPLEX,
            0.8,
            (255, 255, 255),
            2,
        )
        cv2.putText(
            frame,
            "Put down your phone immediately",
            (w // 2 - 180, h - 20),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.6,
            (200, 200, 200),
            1,
        )

    elif distraction_data["drinking_detected"]:
        # Orange banner for drinking - use direct rectangle
        cv2.rectangle(frame, (0, h - 60), (w, h), (0, 80, 128), -1)

        cv2.putText(
            frame,
            "CAUTION: Drinking Detected",
            (w // 2 - 180, h - 25),
            cv2.FONT_HERSHEY_DUPLEX,
            0.8,
            (255, 255, 255),
            2,
        )

    return frame


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

    if settings.show_settings:
        # Draw settings panel background directly - no overlay blending
        cv2.rectangle(frame, (20, 20), (450, 480), (40, 40, 40), -1)
        cv2.rectangle(frame, (20, 20), (450, 480), (0, 255, 0), 2)

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

        # Combine keyboard shortcuts into fewer text calls
        shortcuts = [
            "'+/-' : Zoom In/Out",
            "'r'  : Reset zoom",
            "'1-5': Quick zoom",
        ]

        for text in shortcuts:
            cv2.putText(frame, text, (30, y_offset), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (200, 200, 200), 1)
            y_offset += 25

        y_offset += 10
        cv2.line(frame, (30, y_offset), (440, y_offset), (0, 255, 0), 1)
        y_offset += 25

        # Speed test controls (simplified)
        cv2.putText(frame, "SPEED TEST", (30, y_offset), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 2)
        y_offset += 30

        speed_controls = [
            "'X' : Speeding (75 MPH)",
            "'C' : Reset (45 MPH)",
            "Arrows: +/- 10 MPH",
        ]

        for text in speed_controls:
            cv2.putText(frame, text, (30, y_offset), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (200, 200, 200), 1)
            y_offset += 25

        y_offset += 10
        cv2.line(frame, (30, y_offset), (440, y_offset), (0, 255, 0), 1)
        y_offset += 25

        # Other controls (simplified)
        other_controls = [
            "'s' : Settings",
            "'h' : Help",
            "'q' : Quit",
        ]

        for text in other_controls:
            cv2.putText(frame, text, (30, y_offset), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (200, 200, 200), 1)
            y_offset += 25

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


def draw_driving_info(frame, driving_sim, buzzer=None):
    """Draw driving speed and speed limit information (text-based for performance)"""
    h, w = frame.shape[:2]

    # Position for driving info (top-left area)
    x_pos = 20
    y_pos = 20

    # Calculate required height based on content
    info_height = 180
    info_width = 300

    # Draw semi-transparent background
    cv2.rectangle(frame, (x_pos, y_pos), (x_pos + info_width, y_pos + info_height), (30, 30, 30), -1)
    cv2.rectangle(frame, (x_pos, y_pos), (x_pos + info_width, y_pos + info_height), (255, 255, 255), 2)

    y_offset = y_pos + 25

    # Current speed
    speed = driving_sim.get_speed()
    speed_color = driving_sim.get_speed_status()
    cv2.putText(
        frame,
        f"Speed: {speed} MPH",
        (x_pos + 10, y_offset),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.6,
        speed_color,
        2,
    )
    y_offset += 25

    # Speed limit
    cv2.putText(
        frame,
        "Limit: 65 MPH",
        (x_pos + 10, y_offset),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.5,
        (200, 200, 200),
        1,
    )
    y_offset += 25

    # Speeding warning
    if driving_sim.is_speeding():
        cv2.putText(
            frame,
            ">>> SPEEDING! <<<",
            (x_pos + 10, y_offset),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.5,
            (0, 0, 255),
            2,
        )
        y_offset += 25

        # Play speeding alert sound
        if buzzer:
            buzzer.play_speeding_alert()

    # Heading/Direction
    heading_str = driving_sim.get_direction_string()
    cv2.putText(
        frame,
        f"Heading: {heading_str}",
        (x_pos + 10, y_offset),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.5,
        (0, 255, 255),
        1,
    )
    y_offset += 25

    # Status (accelerating/decelerating/steady)
    status = driving_sim.direction.upper()
    status_color = (0, 255, 0) if status == "STEADY" else (200, 200, 200)
    cv2.putText(
        frame,
        f"Status: {status}",
        (x_pos + 10, y_offset),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.5,
        status_color,
        1,
    )
    y_offset += 25

    # Buzzer status
    buzzer_status = "OFF"
    if buzzer and hasattr(buzzer, 'is_active') and buzzer.is_active:
        buzzer_status = "ACTIVE"
    cv2.putText(
        frame,
        f"Buzzer: {buzzer_status}",
        (x_pos + 10, y_offset),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.5,
        (255, 255, 0) if buzzer_status == "ACTIVE" else (200, 200, 200),
        1,
    )
    y_offset += 25

    # GPS coordinates
    latitude = driving_sim.get_latitude()
    longitude = driving_sim.get_longitude()
    cv2.putText(
        frame,
        f"Lat: {latitude:.6f}",
        (x_pos + 10, y_offset),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.4,
        (200, 200, 200),
        1,
    )
    y_offset += 20
    cv2.putText(
        frame,
        f"Lon: {longitude:.6f}",
        (x_pos + 10, y_offset),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.4,
        (200, 200, 200),
        1,
    )
    y_offset += 20

    # GPS status
    satellites = driving_sim.get_satellites()
    if driving_sim.is_using_gps():
        gps_status = f"GPS: {satellites} sats"
        gps_color = (0, 255, 0) if driving_sim.has_gps_fix() else (0, 165, 255)
    else:
        gps_status = "GPS: SIMULATED"
        gps_color = (128, 128, 128)

    cv2.putText(
        frame,
        gps_status,
        (x_pos + 10, y_offset),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.4,
        gps_color,
        1,
    )

    return frame


def main():
    # Initialize GPS reader (will fallback to Apple Park coordinates if unavailable)
    gps_reader = GPSReader()
    gps_reader.start()

    # Open the default camera (index 0)
    cap = cv2.VideoCapture(0)

    if not cap.isOpened():
        print("Error: Could not open camera")
        gps_reader.stop()
        return

    print("Camera opened successfully!")
    print("Press 'q' to quit")
    print("\nDetection Features:")
    print("- Face detection with bounding boxes")
    print("- Real-time eye state detection (Open/Closed)")
    print("- Intoxication risk assessment")
    print("- Phone usage detection (YOLO)")
    print("- Drinking detection (YOLO)")
    print("- Camera zoom control (0.5x - 10x)")
    print("- GPS tracking (real or simulated)")
    print("- Warning sound alerts for speeding and drowsiness")
    print("- Supabase cloud sync with real-time vehicle tracking")
    print("\nGPS Data:")
    print("- Satellites, Speed (mph), Direction (e.g., 342NW)")
    print("- Latitude, Longitude")
    print("- Falls back to Apple Park coordinates if GPS unavailable")
    print("\nDistraction Detection:")
    print("- Phone usage near face")
    print("- Drinking from bottle/cup")
    print("\nIntoxication Indicators:")
    print("- Drowsiness (prolonged eye closure)")
    print("- Excessive blinking patterns")
    print("- Eye movement instability")
    print("\nControls:")
    print("- Press 's' to open Settings Menu")
    print("- Press '+/-' to zoom in/out")
    print("- Press '1-5' or '0' for quick zoom levels")
    print("\nSpeed Test Controls (simulation mode only):")
    print("- Press 'X' to simulate speeding (75 MPH)")
    print("- Press 'C' to reset speed to normal (45 MPH)")
    print("- Press UP/DOWN arrows to adjust speed by 10 MPH")

    analyzer = FaceAnalyzer()
    distraction_detector = DistractionDetector()  # YOLO-based phone/drinking detection
    settings = Settings()
    driving_sim = DrivingSimulator(gps_reader=gps_reader)
    buzzer = BuzzerController()
    buzzer.start()
    supabase_uploader = SupabaseUploader(buzzer_controller=buzzer)
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

        # Run YOLO distraction detection (phone/drinking)
        face_bbox = detection_data["face_bbox"] if detection_data else None
        distraction_data = distraction_detector.detect(processed_frame, face_bbox)

        # Draw distraction detection boxes
        processed_frame = distraction_detector.draw_detections(processed_frame)

        # Check for drowsy/intoxicated driver and play alert
        if intox_data and intox_data["score"] >= 4:
            buzzer.play_drowsy_alert()

        # Check for distraction (phone/drinking) and play alert
        if distraction_data["phone_detected"]:
            buzzer.play_distraction_alert()

        # Determine driver status for realtime update
        if distraction_data["phone_detected"]:
            driver_status = "distracted_phone"
            intox_score = intox_data["score"] if intox_data else 0
        elif distraction_data["drinking_detected"]:
            driver_status = "distracted_drinking"
            intox_score = intox_data["score"] if intox_data else 0
        elif intox_data:
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
            latitude=driving_sim.get_latitude(),
            longitude=driving_sim.get_longitude(),
            satellites=driving_sim.get_satellites(),
            is_phone_detected=distraction_data["phone_detected"],
            is_drinking_detected=distraction_data["drinking_detected"],
        )

        # Update trip statistics
        is_drowsy = intox_data["drowsy"] if intox_data else False
        is_excessive_blinking = (
            intox_data["excessive_blinking"] if intox_data else False
        )
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
                distraction_data=distraction_data,
            )
            supabase_uploader.increment_face_detection_count()

        # Check for identified driver (every 5s when face detected)
        if detection_data:
            supabase_uploader.check_current_driver()

        # Check for remote buzzer commands (every 2s)
        supabase_uploader.check_buzzer_commands()

        # Draw driving info with buzzer
        processed_frame = draw_driving_info(processed_frame, driving_sim, buzzer)

        # Draw distraction warning banner if detected
        processed_frame = draw_distraction_warning(processed_frame, distraction_data)

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
    buzzer.stop()
    gps_reader.stop()
    cap.release()
    cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
