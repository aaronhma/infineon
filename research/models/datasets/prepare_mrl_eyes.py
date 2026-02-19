"""Prepare the MRL Eye Dataset for eye state classification.

The MRL Eye Dataset contains ~85K eye images labeled as open/closed.
We map these to our eye_state schema.

Dataset structure:
    mrlEyes_2018_01/
        s0001_00001_0_0_0_0_0_01.png  (subject_imgnum_gender_glasses_eyestate_...)
        ...

Filename format: s{subject}_{imgnum}_{gender}_{glasses}_{eye_state}_{reflections}_{...}
    eye_state: 0 = closed, 1 = open

Usage:
    uv run python -m models.datasets.prepare_mrl_eyes
"""

import argparse
import csv
from collections import defaultdict
from pathlib import Path

import numpy as np

DATA_DIR = Path(__file__).parent.parent / "data"


def parse_mrl_filename(filename: str) -> dict | None:
    """Parse MRL eye dataset filename into metadata."""
    stem = Path(filename).stem
    parts = stem.split("_")

    if len(parts) < 5:
        return None

    try:
        return {
            "subject": parts[0],           # e.g., "s0001"
            "image_num": parts[1],
            "gender": int(parts[2]),        # 0=male, 1=female
            "glasses": int(parts[3]),       # 0=no, 1=yes
            "eye_state": int(parts[4]),     # 0=closed, 1=open
        }
    except (ValueError, IndexError):
        return None


def main():
    parser = argparse.ArgumentParser(description="Prepare MRL Eye Dataset")
    parser.add_argument("--input", type=str, default=str(DATA_DIR / "raw" / "mrl_eyes"),
                        help="Path to raw MRL eye data")
    parser.add_argument("--output", type=str, default=str(DATA_DIR / "processed" / "mrl_eyes"),
                        help="Output directory for processed data")
    parser.add_argument("--val-ratio", type=float, default=0.15)
    parser.add_argument("--test-ratio", type=float, default=0.15)
    args = parser.parse_args()

    input_dir = Path(args.input)
    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)

    # Find image files
    image_files = list(input_dir.rglob("*.png")) + list(input_dir.rglob("*.jpg"))
    if not image_files:
        print(f"Error: No images found in {input_dir}")
        print("Download first: uv run python -m models.datasets.download --dataset mrl_eyes")
        return

    # Parse filenames and create samples
    samples = []
    skipped = 0
    subjects = defaultdict(list)

    for img_path in sorted(image_files):
        meta = parse_mrl_filename(img_path.name)
        if meta is None:
            skipped += 1
            continue

        # Map eye state to our labels
        if meta["eye_state"] == 0:
            label = "eyes_closed"
        elif meta["eye_state"] == 1:
            if meta["glasses"] == 1:
                label = "sunglasses"
            else:
                label = "eyes_open"
        else:
            skipped += 1
            continue

        sample = {
            "path": str(img_path.resolve()),
            "label": label,
            "source": "mrl_eyes",
            "subject": meta["subject"],
        }
        samples.append(sample)
        subjects[meta["subject"]].append(sample)

    print(f"Found {len(samples)} images ({skipped} skipped)")
    print(f"Subjects: {len(subjects)}")

    # Split by subject to prevent leakage
    rng = np.random.RandomState(42)
    subject_ids = sorted(subjects.keys())
    rng.shuffle(subject_ids)

    n_subjects = len(subject_ids)
    n_test = max(1, int(n_subjects * args.test_ratio))
    n_val = max(1, int(n_subjects * args.val_ratio))

    test_subjects = set(subject_ids[:n_test])
    val_subjects = set(subject_ids[n_test:n_test + n_val])

    for s in samples:
        if s["subject"] in test_subjects:
            s["split"] = "test"
        elif s["subject"] in val_subjects:
            s["split"] = "val"
        else:
            s["split"] = "train"

    # Write manifest
    manifest_path = output_dir / "manifest.csv"
    with open(manifest_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["path", "label", "split", "source"])
        writer.writeheader()
        for s in samples:
            writer.writerow({
                "path": s["path"],
                "label": s["label"],
                "split": s["split"],
                "source": s["source"],
            })

    # Print summary
    split_counts = defaultdict(lambda: defaultdict(int))
    for s in samples:
        split_counts[s["split"]][s["label"]] += 1

    print(f"\nManifest written to: {manifest_path}")
    for split in ["train", "val", "test"]:
        counts = split_counts[split]
        total = sum(counts.values())
        print(f"\n  {split}: {total} images")
        for label, count in sorted(counts.items()):
            print(f"    {label}: {count}")


if __name__ == "__main__":
    main()
