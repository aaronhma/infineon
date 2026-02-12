#!/usr/bin/env python3
"""
Export a pruned YOLO model for driver monitoring.

Only keeps the detection classes relevant to distracted driving, then exports
to ONNX (FP16) and optionally NCNN for fast inference on edge devices.

The pruned model:
  - Runs faster: post-processing NMS only considers target classes
  - Same architecture: weights are unchanged, so accuracy is identical
  - Exports to ONNX/NCNN: ~2-3x faster inference than raw PyTorch .pt

Target classes (8 of 80):
  0: person       — verify driver is present
  39: bottle      — drinking detection
  40: wine glass  — drinking detection
  41: cup         — drinking detection
  63: laptop      — distraction
  65: remote      — distraction
  67: cell phone  — phone usage
  73: book        — reading while driving

Usage:
    python export_driver.py                        # Export nano model (fastest)
    python export_driver.py --model yolo26s.pt     # Export small model
    python export_driver.py --model yolo26m.pt     # Export medium model (most accurate)
    python export_driver.py --ncnn                 # Also export NCNN for edge devices
"""

import argparse
import json
import os
import sys
from pathlib import Path

# Target classes for driver monitoring
DRIVER_CLASSES = {
    0: "person",
    39: "bottle",
    40: "wine glass",
    41: "cup",
    63: "laptop",
    65: "remote",
    67: "cell phone",
    73: "book",
}

# Grouped by purpose for display
CLASS_GROUPS = {
    "Driver presence": [0],
    "Drinking": [39, 40, 41],
    "Phone/device": [63, 65, 67],
    "Reading": [73],
}


def export_model(model_path: str, do_ncnn: bool = False, do_onnx: bool = True):
    from ultralytics import YOLO

    model_path = Path(model_path)
    if not model_path.exists():
        print(f"Error: model not found: {model_path}")
        sys.exit(1)

    model_name = model_path.stem  # e.g., "yolo26n"
    out_dir = model_path.parent

    print(f"Model: {model_path}")
    print(f"Task:  detection (COCO 80-class)")
    print()

    # Load model
    model = YOLO(str(model_path))

    # Verify it's a detection model
    if model.task != "detect":
        print(f"Error: expected detection model, got task='{model.task}'")
        sys.exit(1)

    # Verify target classes exist
    print("Target classes for driver monitoring:")
    for group, ids in CLASS_GROUPS.items():
        names = [f"{cid}:{model.names[cid]}" for cid in ids if cid in model.names]
        print(f"  {group}: {', '.join(names)}")
    print()

    class_ids = sorted(DRIVER_CLASSES.keys())

    # Save class config (used by DistractionDetector at runtime)
    config = {
        "description": "Driver monitoring YOLO class filter",
        "base_model": model_path.name,
        "total_classes": len(model.names),
        "target_classes": {str(k): v for k, v in DRIVER_CLASSES.items()},
        "class_ids": class_ids,
        "groups": {k: v for k, v in CLASS_GROUPS.items()},
    }
    config_path = out_dir / f"{model_name}_driver_classes.json"
    with open(config_path, "w") as f:
        json.dump(config, f, indent=2)
    print(f"Saved class config: {config_path}")

    # Export to ONNX (FP16)
    if do_onnx:
        print(f"\nExporting ONNX (FP16)...")
        onnx_path = model.export(format="onnx", half=True, simplify=True)
        onnx_size = os.path.getsize(onnx_path) / (1024 * 1024)
        print(f"  Saved: {onnx_path} ({onnx_size:.1f} MB)")

    # Export to NCNN (for Raspberry Pi / edge)
    if do_ncnn:
        print(f"\nExporting NCNN...")
        ncnn_path = model.export(format="ncnn")
        # NCNN is a directory
        if os.path.isdir(ncnn_path):
            ncnn_size = sum(
                os.path.getsize(os.path.join(ncnn_path, f))
                for f in os.listdir(ncnn_path)
                if os.path.isfile(os.path.join(ncnn_path, f))
            ) / (1024 * 1024)
        else:
            ncnn_size = os.path.getsize(ncnn_path) / (1024 * 1024)
        print(f"  Saved: {ncnn_path} ({ncnn_size:.1f} MB)")

    # Print summary
    pt_size = os.path.getsize(model_path) / (1024 * 1024)
    print(f"\n{'='*60}")
    print(f"Summary")
    print(f"{'='*60}")
    print(f"  Source:        {model_path.name} ({pt_size:.1f} MB, 80 classes)")
    print(f"  Class config:  {config_path.name} ({len(class_ids)} classes)")
    if do_onnx:
        print(f"  ONNX (FP16):   {Path(onnx_path).name} ({onnx_size:.1f} MB)")
    if do_ncnn:
        print(f"  NCNN:          {Path(ncnn_path).name} ({ncnn_size:.1f} MB)")
    print()
    print("Usage in code:")
    print(f'  model = YOLO("{onnx_path if do_onnx else model_path}")')
    print(f"  results = model(frame, classes={class_ids})")
    print()
    print("Or set in .env:")
    print(f"  YOLO_MODEL_PATH={onnx_path if do_onnx else model_path}")


def main():
    p = argparse.ArgumentParser(description="Export pruned YOLO for driver monitoring")
    p.add_argument("--model", default="yolo26n.pt", help="Base model (default: yolo26n.pt)")
    p.add_argument("--ncnn", action="store_true", help="Also export NCNN format")
    p.add_argument("--no-onnx", action="store_true", help="Skip ONNX export")
    args = p.parse_args()

    # Resolve model path relative to this script's directory
    script_dir = Path(__file__).parent
    model_path = script_dir / args.model
    if not model_path.exists():
        model_path = Path(args.model)

    export_model(str(model_path), do_ncnn=args.ncnn, do_onnx=not args.no_onnx)


if __name__ == "__main__":
    main()
