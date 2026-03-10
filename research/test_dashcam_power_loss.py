#!/usr/bin/env python3
"""Test script to verify dashcam power-loss protection.

This script simulates recording and then abruptly killing the process
to verify that recorded video chunks are playable.
"""

import os
import sys
import time
import signal
import subprocess
import numpy as np
import cv2

# Import the DashcamRecorder from main.py
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from main import DashcamRecorder


def create_test_frame(frame_num, width=640, height=480):
    """Create a test frame with frame number overlay."""
    frame = np.zeros((height, width, 3), dtype=np.uint8)
    
    # Add some color gradient
    for y in range(height):
        for x in range(width):
            frame[y, x] = [
                int(255 * x / width) % 256,
                int(255 * y / height) % 256,
                frame_num % 256
            ]
    
    # Add frame number text
    cv2.putText(frame, f"Frame {frame_num}", (50, 50),
                cv2.FONT_HERSHEY_SIMPLEX, 2, (255, 255, 255), 3)
    
    # Add timestamp
    timestamp = time.strftime("%H:%M:%S")
    cv2.putText(frame, timestamp, (50, height - 50),
                cv2.FONT_HERSHEY_SIMPLEX, 1, (255, 255, 255), 2)
    
    return frame


def test_chunked_recording():
    """Test that chunked recording creates multiple files."""
    print("\n=== Test 1: Chunked Recording ===")
    
    test_dir = "test_recordings"
    trip_id = f"test_{int(time.time())}"
    
    # Create recorder with 5-second chunks for testing
    recorder = DashcamRecorder(
        output_dir=test_dir,
        fps=30,
        max_width=640,
        chunk_duration_sec=5  # Short chunks for testing
    )
    
    recorder.start(trip_id, 640, 480)
    
    # Record for 12 seconds (should create 3 chunks)
    print("Recording for 12 seconds...")
    for i in range(12 * 30):  # 12 seconds at 30 fps
        frame = create_test_frame(i)
        recorder.write_frame(frame, hud_data={
            "speed": 45 + (i % 30),
            "heading": 90.0,
            "direction": "E"
        })
        time.sleep(1/30)  # Real-time recording
        
        if i % 30 == 0:
            print(f"  Second {i // 30}...")
    
    recorder.stop()
    
    # Verify chunks were created
    trip_dir = os.path.join(test_dir, trip_id)
    chunks = sorted([f for f in os.listdir(trip_dir) if f.endswith('.mkv')])
    
    print(f"\nCreated {len(chunks)} chunks: {chunks}")
    
    if len(chunks) >= 2:
        print("✓ PASS: Multiple chunks created")
    else:
        print("✗ FAIL: Expected at least 2 chunks")
        return False
    
    # Verify each chunk is playable
    for chunk in chunks:
        chunk_path = os.path.join(trip_dir, chunk)
        cap = cv2.VideoCapture(chunk_path)
        
        if not cap.isOpened():
            print(f"✗ FAIL: Cannot open {chunk}")
            return False
        
        frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        cap.release()
        
        print(f"  {chunk}: {frame_count} frames")
    
    print("✓ PASS: All chunks are playable")
    return True


def test_power_loss_simulation():
    """Simulate power loss by killing the process abruptly."""
    print("\n=== Test 2: Power Loss Simulation ===")
    
    test_dir = "test_recordings_power"
    trip_id = f"power_test_{int(time.time())}"
    
    # Create a subprocess that records video
    test_script = """
import os
import sys
import time
import numpy as np
import cv2

sys.path.insert(0, '{}')
from main import DashcamRecorder

def create_frame(num):
    frame = np.zeros((480, 640, 3), dtype=np.uint8)
    cv2.putText(frame, f"Frame {{num}}", (50, 50),
                cv2.FONT_HERSHEY_SIMPLEX, 2, (255, 255, 255), 3)
    return frame

recorder = DashcamRecorder(output_dir='{}', fps=30, chunk_duration_sec=5)
recorder.start('{}', 640, 480)

for i in range(300):  # 10 seconds at 30fps
    frame = create_frame(i)
    recorder.write_frame(frame)
    time.sleep(1/30)
    
    if i % 30 == 0:
        print(f"Recording second {{i // 30}}...")

# Don't call stop() - simulate power loss
print("Simulating power loss (process will be killed)...")
time.sleep(2)  # Give time for last writes
""".format(
        os.path.dirname(os.path.abspath(__file__)),
        test_dir,
        trip_id
    )
    
    # Start the recording process
    proc = subprocess.Popen(
        ["python3", "-c", test_script],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )
    
    # Wait for it to record for a bit
    print("Starting recording subprocess...")
    time.sleep(7)  # Let it record for 7 seconds
    
    # Kill the process abruptly (simulating power loss)
    print("Killing process (simulating power loss)...")
    proc.kill()
    proc.wait()
    
    # Check if chunks are playable
    trip_dir = os.path.join(test_dir, trip_id)
    if not os.path.exists(trip_dir):
        print("✗ FAIL: No recording directory created")
        return False
    
    chunks = sorted([f for f in os.listdir(trip_dir) if f.endswith('.mkv')])
    print(f"Found {len(chunks)} chunks after power loss: {chunks}")
    
    playable_count = 0
    for chunk in chunks:
        chunk_path = os.path.join(trip_dir, chunk)
        
        # Try to open with OpenCV
        cap = cv2.VideoCapture(chunk_path)
        if cap.isOpened():
            frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
            cap.release()
            print(f"  {chunk}: {frame_count} frames - ✓ PLAYABLE")
            playable_count += 1
        else:
            print(f"  {chunk}: ✗ NOT PLAYABLE")
    
    # At least one chunk should be playable
    if playable_count >= 1:
        print(f"\n✓ PASS: {playable_count}/{len(chunks)} chunks are playable after power loss")
        return True
    else:
        print(f"\n✗ FAIL: No playable chunks after power loss")
        return False


def test_ffmpeg_availability():
    """Test that FFmpeg is available and supports fragmented MP4."""
    print("\n=== Test 0: FFmpeg Availability ===")
    
    try:
        result = subprocess.run(
            ["ffmpeg", "-version"],
            capture_output=True,
            text=True,
            timeout=5
        )
        
        if result.returncode == 0:
            version_line = result.stdout.split('\n')[0]
            print(f"✓ FFmpeg found: {version_line}")
            
            # Check for libx264 support
            if "libx264" in result.stdout or "--enable-libx264" in result.stdout:
                print("✓ libx264 codec available")
                return True
            else:
                print("⚠ libx264 may not be available")
                return True  # Still try to proceed
        else:
            print("✗ FAIL: FFmpeg not working properly")
            return False
            
    except FileNotFoundError:
        print("✗ FAIL: FFmpeg not found - please install it")
        print("  On macOS: brew install ffmpeg")
        print("  On Raspberry Pi: sudo apt install ffmpeg")
        return False
    except Exception as e:
        print(f"✗ FAIL: Error checking FFmpeg: {e}")
        return False


def cleanup_test_files():
    """Remove test recording directories."""
    import shutil
    
    for test_dir in ["test_recordings", "test_recordings_power"]:
        if os.path.exists(test_dir):
            print(f"\nCleaning up {test_dir}...")
            shutil.rmtree(test_dir)


if __name__ == "__main__":
    print("=" * 60)
    print("Dashcam Power-Loss Protection Test Suite")
    print("=" * 60)
    
    # Run tests
    results = []
    
    # Test 0: Check FFmpeg
    if not test_ffmpeg_availability():
        print("\n✗ Cannot proceed without FFmpeg")
        sys.exit(1)
    
    # Test 1: Chunked recording
    results.append(("Chunked Recording", test_chunked_recording()))
    
    # Test 2: Power loss simulation
    results.append(("Power Loss Simulation", test_power_loss_simulation()))
    
    # Summary
    print("\n" + "=" * 60)
    print("Test Summary")
    print("=" * 60)
    
    for test_name, passed in results:
        status = "✓ PASS" if passed else "✗ FAIL"
        print(f"{test_name}: {status}")
    
    all_passed = all(result for _, result in results)
    
    if all_passed:
        print("\n✓ All tests passed! Power-loss protection is working.")
    else:
        print("\n✗ Some tests failed. Please check the implementation.")
    
    # Cleanup
    cleanup = input("\nClean up test files? (y/n): ").lower().strip()
    if cleanup == 'y':
        cleanup_test_files()
    
    sys.exit(0 if all_passed else 1)
