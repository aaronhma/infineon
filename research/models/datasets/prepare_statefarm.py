"""Prepare the State Farm Distracted Driver dataset.

Maps StateFarm's 10 classes to our driver_activity label schema.
Ensures no driver leakage between train/val/test splits.

Usage:
    uv run python -m models.datasets.prepare_statefarm
    uv run python -m models.datasets.prepare_statefarm --input data/raw/statefarm --output data/processed/statefarm
"""

import argparse
import csv
from collections import defaultdict
from pathlib import Path

import numpy as np

DATA_DIR = Path(__file__).parent.parent / "data"

# StateFarm class mapping → our unified labels
STATEFARM_CLASS_MAP = {
    "c0": "safe_driving",
    "c1": "texting_phone_right",
    "c2": "talking_phone_right",
    "c3": "texting_phone_left",
    "c4": "talking_phone_left",
    "c5": "adjusting_hair_makeup",
    "c6": "drinking",
    "c7": "reaching_behind",
    "c8": "looking_away",
    "c9": "talking_passenger",
}


def load_driver_ids(input_dir: Path) -> dict[str, str]:
    """Load driver ID for each image from driver_imgs_list.csv."""
    driver_map = {}
    csv_path = input_dir / "driver_imgs_list.csv"

    if not csv_path.exists():
        print(f"Warning: {csv_path} not found. Splits will be random (may have driver leakage).")
        return driver_map

    with open(csv_path) as f:
        reader = csv.DictReader(f)
        for row in reader:
            driver_map[row["img"]] = row["subject"]

    return driver_map


def create_splits(
    samples: list[dict],
    driver_map: dict[str, str],
    val_ratio: float = 0.15,
    test_ratio: float = 0.15,
    seed: int = 42,
) -> list[dict]:
    """Create train/val/test splits without driver leakage."""
    rng = np.random.RandomState(seed)

    if driver_map:
        # Group by driver to prevent leakage
        drivers = defaultdict(list)
        for s in samples:
            img_name = Path(s["path"]).name
            driver_id = driver_map.get(img_name, "unknown")
            drivers[driver_id].append(s)

        driver_ids = sorted(drivers.keys())
        rng.shuffle(driver_ids)

        n_drivers = len(driver_ids)
        n_test = max(1, int(n_drivers * test_ratio))
        n_val = max(1, int(n_drivers * val_ratio))

        test_drivers = set(driver_ids[:n_test])
        val_drivers = set(driver_ids[n_test:n_test + n_val])

        for s in samples:
            img_name = Path(s["path"]).name
            driver_id = driver_map.get(img_name, "unknown")
            if driver_id in test_drivers:
                s["split"] = "test"
            elif driver_id in val_drivers:
                s["split"] = "val"
            else:
                s["split"] = "train"

        print(f"Split by driver ID: {n_drivers} drivers total")
        print(f"  Train: {n_drivers - n_val - n_test} drivers")
        print(f"  Val: {n_val} drivers")
        print(f"  Test: {n_test} drivers")
    else:
        # Random split (fallback)
        indices = np.arange(len(samples))
        rng.shuffle(indices)
        n_test = int(len(samples) * test_ratio)
        n_val = int(len(samples) * val_ratio)

        for i, idx in enumerate(indices):
            if i < n_test:
                samples[idx]["split"] = "test"
            elif i < n_test + n_val:
                samples[idx]["split"] = "val"
            else:
                samples[idx]["split"] = "train"

    return samples


def main():
    parser = argparse.ArgumentParser(description="Prepare StateFarm dataset")
    parser.add_argument("--input", type=str, default=str(DATA_DIR / "raw" / "statefarm"),
                        help="Path to raw StateFarm data")
    parser.add_argument("--output", type=str, default=str(DATA_DIR / "processed" / "statefarm"),
                        help="Output directory for processed data")
    args = parser.parse_args()

    input_dir = Path(args.input)
    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)

    # Find training images directory
    train_dir = input_dir / "imgs" / "train"
    if not train_dir.exists():
        train_dir = input_dir / "train"
    if not train_dir.exists():
        print(f"Error: Could not find training images in {input_dir}")
        print("Expected structure: <input>/imgs/train/c0/*.jpg or <input>/train/c0/*.jpg")
        print()
        print("Download first: uv run python -m models.datasets.download --dataset statefarm")
        return

    # Load driver IDs for leak-free splits
    driver_map = load_driver_ids(input_dir)

    # Collect all samples
    samples = []
    for class_dir in sorted(train_dir.iterdir()):
        if not class_dir.is_dir():
            continue
        statefarm_class = class_dir.name
        if statefarm_class not in STATEFARM_CLASS_MAP:
            print(f"Skipping unknown class: {statefarm_class}")
            continue

        our_label = STATEFARM_CLASS_MAP[statefarm_class]

        for img_path in sorted(class_dir.glob("*.jpg")):
            samples.append({
                "path": str(img_path.resolve()),
                "label": our_label,
                "source": "statefarm",
            })

    print(f"Found {len(samples)} images across {len(STATEFARM_CLASS_MAP)} classes")

    # Create splits
    samples = create_splits(samples, driver_map)

    # Write manifest
    manifest_path = output_dir / "manifest.csv"
    with open(manifest_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["path", "label", "split", "source"])
        writer.writeheader()
        writer.writerows(samples)

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
