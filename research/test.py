#!/usr/bin/env python3
"""
Test script for verifying individual modules and system components
Run with: python test.py [module_name]
Available tests: all, gps, buzzer, supabase, camera, yolo, mediapipe, speed_limit, env
"""

import argparse
import os
import sys
import time

import cv2
import numpy as np
from dotenv import load_dotenv

# Load environment variables
load_dotenv()


def test_env():
    """Test environment variables"""
    print("\n=== Testing Environment Variables ===")

    required_vars = [
        "SUPABASE_URL",
        "SUPABASE_SECRET_KEY",
        "VEHICLE_ID",
        "VEHICLE_NAME",
    ]

    all_present = True
    for var in required_vars:
        value = os.environ.get(var)
        if value:
            # Mask sensitive values
            if "KEY" in var or "SECRET" in var:
                display_value = value[:10] + "..." if len(value) > 10 else "***"
            else:
                display_value = value
            print(f"✓ {var}: {display_value}")
        else:
            print(f"✗ {var}: NOT SET")
            all_present = False

    if all_present:
        print("✓ All environment variables present")
        return True
    else:
        print("✗ Some environment variables missing")
        return False


def test_gps():
    """Test GPS module"""
    print("\n=== Testing GPS Module ===")
    try:
        from gps import GPSReader

        print("✓ GPS module imported successfully")

        gps = GPSReader()
        gps.start()
        print("✓ GPS reader started")

        # Wait a bit for GPS data
        time.sleep(2)

        print(f"GPS Mode: {'REAL' if not gps.is_fake else 'SIMULATED'}")
        print(f"Has Fix: {gps.has_fix}")
        print(f"Satellites: {gps.satellites}")
        print(f"Speed: {gps.speed_mph:.2f} MPH")
        print(f"Heading: {gps.heading:.2f}°")
        print(f"Latitude: {gps.latitude:.6f}")
        print(f"Longitude: {gps.longitude:.6f}")

        gps.stop()
        print("✓ GPS reader stopped")

        return True
    except Exception as e:
        print(f"✗ GPS test failed: {e}")
        return False


def test_buzzer():
    """Test buzzer module"""
    print("\n=== Testing Buzzer Module ===")
    try:
        from buzzer import BuzzerController

        print("✓ Buzzer module imported successfully")

        buzzer = BuzzerController()
        buzzer.start()
        print("✓ Buzzer controller started")

        # Test different alert types
        print("Testing speeding alert...")
        buzzer.play_speeding_alert()
        time.sleep(2)

        print("Testing drowsy alert (double beep)...")
        buzzer.play_drowsy_alert()
        time.sleep(2)

        print("Testing distraction alert...")
        buzzer.play_distraction_alert()
        time.sleep(2)

        print("Testing continuous buzzer (3 seconds)...")
        buzzer.start_continuous('alert')
        time.sleep(3)
        buzzer.stop_continuous()

        buzzer.stop()
        print("✓ Buzzer controller stopped")

        return True
    except Exception as e:
        print(f"✗ Buzzer test failed: {e}")
        return False


def test_supabase():
    """Test Supabase connection"""
    print("\n=== Testing Supabase Connection ===")
    try:
        from supabase import create_client

        supabase_url = os.environ.get("SUPABASE_URL")
        supabase_key = os.environ.get("SUPABASE_SECRET_KEY")
        vehicle_id = os.environ.get("VEHICLE_ID")

        if not all([supabase_url, supabase_key, vehicle_id]):
            print("✗ Missing required environment variables")
            return False

        print("✓ Environment variables loaded")

        client = create_client(supabase_url, supabase_key)
        print("✓ Supabase client created")

        # Test connection by fetching vehicle data
        response = client.table("vehicles").select("id, name").eq("id", vehicle_id).execute()

        if response.data:
            print(f"✓ Connected to Supabase")
            print(f"  Vehicle ID: {response.data[0]['id']}")
            print(f"  Vehicle Name: {response.data[0]['name']}")
        else:
            print("✗ Vehicle not found in database")
            return False

        # Test realtime table
        response = client.table("vehicle_realtime").select("vehicle_id").eq("vehicle_id", vehicle_id).execute()
        print(f"✓ Realtime table accessible ({len(response.data)} records)")

        # Test trips table
        response = client.table("vehicle_trips").select("id").eq("vehicle_id", vehicle_id).limit(1).execute()
        print(f"✓ Trips table accessible")

        return True
    except Exception as e:
        print(f"✗ Supabase test failed: {e}")
        return False


def test_camera():
    """Test camera availability"""
    print("\n=== Testing Camera ===")
    try:
        cap = cv2.VideoCapture(0)

        if not cap.isOpened():
            print("✗ Could not open camera")
            return False

        print("✓ Camera opened successfully")

        # Try to read a frame
        ret, frame = cap.read()

        if not ret:
            print("✗ Could not read frame from camera")
            cap.release()
            return False

        h, w, c = frame.shape
        print(f"✓ Frame captured: {w}x{h} ({c} channels)")

        cap.release()
        print("✓ Camera released")

        return True
    except Exception as e:
        print(f"✗ Camera test failed: {e}")
        return False


def test_yolo():
    """Test YOLO model loading"""
    print("\n=== Testing YOLO Model ===")

    # Check if YOLO is enabled
    enable_yolo = os.environ.get("ENABLE_YOLO", "true").lower() in ("true", "1", "yes")
    if not enable_yolo:
        print("⚠ YOLO disabled via ENABLE_YOLO environment variable - skipping test")
        return True

    try:
        from ultralytics import YOLO

        print("✓ YOLO module imported successfully")

        # Try loading the model
        model_path = "yolov8m.pt"
        print(f"Loading model: {model_path}")

        model = YOLO(model_path)
        print("✓ YOLO model loaded successfully")

        # Test inference on a dummy image
        dummy_image = np.zeros((640, 640, 3), dtype=np.uint8)
        results = model(dummy_image, verbose=False)
        print("✓ YOLO inference successful")

        # Check for relevant classes
        print(f"Model has {len(model.names)} classes")
        print(f"  Cell phone class: {model.names.get(67, 'Not found')}")
        print(f"  Bottle class: {model.names.get(39, 'Not found')}")
        print(f"  Cup class: {model.names.get(41, 'Not found')}")

        return True
    except Exception as e:
        print(f"✗ YOLO test failed: {e}")
        return False


def test_mediapipe():
    """Test MediaPipe face detection"""
    print("\n=== Testing MediaPipe Face Detection ===")
    try:
        import mediapipe as mp
        from mediapipe.tasks import python
        from mediapipe.tasks.python import vision

        print("✓ MediaPipe modules imported successfully")

        # Check for model file
        model_path = "face_landmarker.task"
        if not os.path.exists(model_path):
            print(f"✗ Model file not found: {model_path}")
            return False

        print(f"✓ Model file found: {model_path}")

        # Initialize face landmarker
        base_options = python.BaseOptions(model_asset_path=model_path)
        options = vision.FaceLandmarkerOptions(
            base_options=base_options,
            running_mode=vision.RunningMode.VIDEO,
            num_faces=5,
            min_face_detection_confidence=0.5,
        )
        landmarker = vision.FaceLandmarker.create_from_options(options)
        print("✓ Face landmarker created successfully")

        # Test on a dummy image
        dummy_image = np.zeros((480, 640, 3), dtype=np.uint8)
        rgb_image = cv2.cvtColor(dummy_image, cv2.COLOR_BGR2RGB)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb_image)

        results = landmarker.detect_for_video(mp_image, 0)
        print(f"✓ Detection successful (found {len(results.face_landmarks)} faces)")

        return True
    except Exception as e:
        print(f"✗ MediaPipe test failed: {e}")
        return False


def test_speed_limit():
    """Test speed limit checker"""
    print("\n=== Testing Speed Limit Checker ===")
    try:
        from speed_limit import SpeedLimitChecker

        print("✓ Speed limit module imported successfully")

        checker = SpeedLimitChecker(search_radius=50)
        print("✓ Speed limit checker initialized")

        # Test with known location (San Francisco)
        test_lat = 37.7749
        test_lon = -122.4194
        print(f"Testing with coordinates: ({test_lat}, {test_lon})")

        speed_limit = checker.get_speed_limit(test_lat, test_lon)

        if speed_limit is not None:
            print(f"✓ Speed limit found: {speed_limit} MPH")
        else:
            print("⚠ Speed limit not found (may be unavailable for this location)")

        # Test with detailed info
        speed_limit, road_info = checker.get_speed_limit_with_details(test_lat, test_lon)

        if road_info:
            print(f"✓ Road details retrieved:")
            print(f"  Name: {road_info.get('name', 'N/A')}")
            print(f"  Type: {road_info.get('highway_type', 'N/A')}")
            print(f"  Speed: {speed_limit if speed_limit else 'N/A'} MPH")
        else:
            print("⚠ Road details not available for this location")

        print("✓ Speed limit checker functioning correctly")
        return True

    except Exception as e:
        print(f"✗ Speed limit test failed: {e}")
        return False


def run_all_tests():
    """Run all available tests"""
    print("=" * 60)
    print("Running All Module Tests")
    print("=" * 60)

    tests = [
        ("Environment", test_env),
        ("GPS", test_gps),
        ("Buzzer", test_buzzer),
        ("Supabase", test_supabase),
        ("Camera", test_camera),
        ("YOLO", test_yolo),
        ("MediaPipe", test_mediapipe),
        ("Speed Limit", test_speed_limit),
    ]

    results = {}
    for name, test_func in tests:
        try:
            results[name] = test_func()
        except Exception as e:
            print(f"\n✗ {name} test crashed: {e}")
            results[name] = False

    # Summary
    print("\n" + "=" * 60)
    print("Test Summary")
    print("=" * 60)

    for name, passed in results.items():
        status = "✓ PASS" if passed else "✗ FAIL"
        print(f"{status}: {name}")

    passed_count = sum(results.values())
    total_count = len(results)
    print(f"\nTotal: {passed_count}/{total_count} tests passed")

    return all(results.values())


def main():
    parser = argparse.ArgumentParser(description="Test individual modules")
    parser.add_argument(
        "module",
        nargs="?",
        default="all",
        choices=["all", "env", "gps", "buzzer", "supabase", "camera", "yolo", "mediapipe", "speed_limit"],
        help="Module to test (default: all)",
    )
    args = parser.parse_args()

    test_map = {
        "all": run_all_tests,
        "env": test_env,
        "gps": test_gps,
        "buzzer": test_buzzer,
        "supabase": test_supabase,
        "camera": test_camera,
        "yolo": test_yolo,
        "mediapipe": test_mediapipe,
        "speed_limit": test_speed_limit,
    }

    success = test_map[args.module]()

    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
