#!/usr/bin/env python3
"""
Convert all YOLO26 models to NCNN format for deployment on Raspberry Pi

NCNN format is optimized for edge devices and runs without GPU requirements.
This script converts all yolo26*.pt models in the current directory.
"""

import glob
import os
from pathlib import Path

from ultralytics import YOLO


def convert_to_ncnn():
    """Convert all YOLO26 models to NCNN format"""

    # Get current directory
    current_dir = Path(__file__).parent

    # Find all yolo26*.pt files
    model_files = sorted(glob.glob(str(current_dir / "yolo26*.pt")))

    if not model_files:
        print("❌ No YOLO26 models found (yolo26*.pt)")
        return

    print(f"Found {len(model_files)} YOLO26 model(s)\n")

    for model_path in model_files:
        model_name = Path(model_path).name
        print(f"Converting {model_name}...")

        try:
            # Load model
            model = YOLO(model_path)

            # Export to NCNN format
            export_result = model.export(format="ncnn")

            print(f"✓ Successfully converted {model_name}")
            print(f"  Output: {export_result}\n")

        except Exception as e:
            print(f"❌ Failed to convert {model_name}: {e}\n")

    # List all generated NCNN models
    print("=" * 60)
    print("Generated NCNN Models:")
    print("=" * 60)

    ncnn_models = sorted(glob.glob(str(current_dir / "*_ncnn_model")))

    if ncnn_models:
        for ncnn_path in ncnn_models:
            size = sum(
                os.path.getsize(os.path.join(ncnn_path, f))
                for f in os.listdir(ncnn_path)
                if os.path.isfile(os.path.join(ncnn_path, f))
            )
            size_mb = size / (1024 * 1024)
            print(f"  📦 {Path(ncnn_path).name} ({size_mb:.1f} MB)")
    else:
        print("  No NCNN models found yet")

    print("\n✓ Conversion complete!")


if __name__ == "__main__":
    convert_to_ncnn()
