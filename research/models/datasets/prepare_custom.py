"""Prepare custom dataset from Supabase face detections.

Pulls labeled face crops from the existing driver monitoring system
and converts them into the unified manifest format.

Usage:
    uv run python -m models.datasets.prepare_custom
    uv run python -m models.datasets.prepare_custom --limit 5000
"""

import argparse
import csv
import os
from collections import defaultdict
from pathlib import Path

import numpy as np

DATA_DIR = Path(__file__).parent.parent / "data"


def map_supabase_to_eye_label(detection: dict) -> str | None:
    """Map Supabase face detection fields to eye state label."""
    if detection.get("is_drowsy"):
        return "eyes_closed"

    left = detection.get("left_eye_state", "").upper()
    right = detection.get("right_eye_state", "").upper()

    if left == "CLOSED" and right == "CLOSED":
        return "eyes_closed"
    elif left == "OPEN" and right == "OPEN":
        avg_ear = detection.get("avg_ear", 0.3)
        if avg_ear and avg_ear < 0.25:
            return "eyes_partially_closed"
        return "eyes_open"
    elif left == "CLOSED" or right == "CLOSED":
        return "eyes_partially_closed"

    return None


def map_supabase_to_activity_label(detection: dict) -> str | None:
    """Map Supabase face detection fields to driver activity label."""
    if detection.get("is_phone_detected"):
        return "texting_phone_right"
    if detection.get("is_drinking_detected"):
        return "drinking"
    # Default to safe driving if no alerts
    if not detection.get("is_drowsy") and not detection.get("is_excessive_blinking"):
        return "safe_driving"
    return None


def main():
    parser = argparse.ArgumentParser(description="Prepare custom Supabase dataset")
    parser.add_argument("--output", type=str, default=str(DATA_DIR / "processed" / "custom"),
                        help="Output directory for processed data")
    parser.add_argument("--task", type=str, choices=["eye_state", "driver_activity", "both"],
                        default="both", help="Which task to prepare data for")
    parser.add_argument("--limit", type=int, default=10000, help="Max images to download")
    parser.add_argument("--val-ratio", type=float, default=0.15)
    parser.add_argument("--test-ratio", type=float, default=0.15)
    args = parser.parse_args()

    # Check for Supabase credentials
    try:
        from dotenv import load_dotenv
        load_dotenv(Path(__file__).parent.parent.parent / ".env")
    except ImportError:
        pass

    supabase_url = os.environ.get("SUPABASE_URL")
    supabase_key = os.environ.get("SUPABASE_SECRET_KEY")

    if not supabase_url or not supabase_key:
        print("Error: SUPABASE_URL and SUPABASE_SECRET_KEY required in .env")
        print("This script pulls face crops from your existing driver monitoring data.")
        return

    try:
        from supabase import create_client
    except ImportError:
        print("Error: supabase package required. Install with: uv pip install supabase")
        return

    client = create_client(supabase_url, supabase_key)
    output_dir = Path(args.output)
    images_dir = output_dir / "images"
    images_dir.mkdir(parents=True, exist_ok=True)

    # Query face detections with image paths
    print("Querying face detections from Supabase...")
    response = (
        client.table("face_detections")
        .select("*")
        .not_.is_("image_path", "null")
        .order("created_at", desc=True)
        .limit(args.limit)
        .execute()
    )

    detections = response.data
    print(f"Found {len(detections)} face detections with images")

    if not detections:
        print("No face detections found. Run the driver monitoring system to collect data first.")
        return

    # Download face crops and create samples
    samples_eye = []
    samples_activity = []
    downloaded = 0

    for det in detections:
        image_path = det.get("image_path")
        if not image_path:
            continue

        # Download from Supabase storage
        local_filename = f"{det['id']}.jpg"
        local_path = images_dir / local_filename

        if not local_path.exists():
            try:
                data = client.storage.from_("face-snapshots").download(image_path)
                with open(local_path, "wb") as f:
                    f.write(data)
                downloaded += 1
            except Exception as e:
                print(f"  Skip {image_path}: {e}")
                continue

        rel_path = str((images_dir / local_filename).resolve())

        # Map to eye state label
        if args.task in ("eye_state", "both"):
            eye_label = map_supabase_to_eye_label(det)
            if eye_label:
                samples_eye.append({
                    "path": rel_path,
                    "label": eye_label,
                    "source": "custom_supabase",
                })

        # Map to activity label
        if args.task in ("driver_activity", "both"):
            activity_label = map_supabase_to_activity_label(det)
            if activity_label:
                samples_activity.append({
                    "path": rel_path,
                    "label": activity_label,
                    "source": "custom_supabase",
                })

    print(f"Downloaded {downloaded} new images")

    # Assign splits randomly
    rng = np.random.RandomState(42)

    for samples, task_name in [(samples_eye, "eye_state"), (samples_activity, "driver_activity")]:
        if not samples:
            continue

        indices = np.arange(len(samples))
        rng.shuffle(indices)
        n_test = int(len(samples) * args.test_ratio)
        n_val = int(len(samples) * args.val_ratio)

        for i, idx in enumerate(indices):
            if i < n_test:
                samples[idx]["split"] = "test"
            elif i < n_test + n_val:
                samples[idx]["split"] = "val"
            else:
                samples[idx]["split"] = "train"

        manifest_path = output_dir / f"manifest_{task_name}.csv"
        with open(manifest_path, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=["path", "label", "split", "source"])
            writer.writeheader()
            writer.writerows(samples)

        split_counts = defaultdict(int)
        for s in samples:
            split_counts[s["split"]] += 1

        print(f"\n{task_name}: {len(samples)} samples → {manifest_path}")
        for split, count in sorted(split_counts.items()):
            print(f"  {split}: {count}")


if __name__ == "__main__":
    main()
