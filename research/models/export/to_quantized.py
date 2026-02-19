"""Export INT8 quantized models for Raspberry Pi 4.

INT8 quantization reduces model size 4x and inference time 3-4x
compared to FP32 on ARM CPUs. This is critical for RPi4 which
has no GPU and only 4GB RAM.

Supports:
    - ONNX Runtime INT8 quantization (static + dynamic)
    - TFLite INT8 quantization (broadest edge support)

Usage:
    uv run python -m models.export.to_quantized --checkpoint models/checkpoints/driver_activity_best_acc.pt --config models/configs/driver_activity.yaml
    uv run python -m models.export.to_quantized --checkpoint models/checkpoints/eye_state_best_acc.pt --config models/configs/eye_state.yaml --calibration-dir models/data/processed/mrl_eyes
"""

import argparse
from pathlib import Path

import numpy as np
import torch

from ..configs import load_config
from ..training.train import build_model
from .to_onnx import export_to_onnx


def _ensure_inline_onnx(onnx_path: str) -> None:
    """Reload and save ONNX model with all weights inline (no external data).

    ONNX can split large models into .onnx + .onnx.data files.
    onnxruntime quantization breaks when external data references
    become stale, so we force everything inline.
    """
    import onnx

    data_path = Path(onnx_path + ".data")
    if not data_path.exists():
        return

    print("  Converting external data to inline format...")
    model = onnx.load(onnx_path, load_external_data=True)
    onnx.save(model, onnx_path, save_as_external_data=False)

    # Remove the now-unused external data file
    if data_path.exists():
        data_path.unlink()


class CalibrationDataReader:
    """Provides calibration data for static INT8 quantization.

    Static quantization uses a small set of representative inputs
    to determine optimal quantization ranges. This produces better
    accuracy than dynamic quantization.
    """

    def __init__(self, calibration_dir: str, input_size: int, num_samples: int = 200):
        import cv2

        self.input_size = input_size
        self.samples = []

        # ImageNet normalization
        mean = np.array([0.485, 0.456, 0.406], dtype=np.float32).reshape(1, 1, 3)
        std = np.array([0.229, 0.224, 0.225], dtype=np.float32).reshape(1, 1, 3)

        cal_dir = Path(calibration_dir)
        image_files = []
        for ext in ("*.jpg", "*.jpeg", "*.png", "*.bmp"):
            image_files.extend(cal_dir.rglob(ext))

        if not image_files:
            raise ValueError(f"No images found in {calibration_dir} for calibration")

        # Sample up to num_samples images
        if len(image_files) > num_samples:
            rng = np.random.RandomState(42)
            indices = rng.choice(len(image_files), num_samples, replace=False)
            image_files = [image_files[i] for i in indices]

        print(f"Loading {len(image_files)} calibration images...")
        for img_path in image_files:
            img = cv2.imread(str(img_path))
            if img is None:
                continue
            img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
            img = cv2.resize(img, (input_size, input_size))
            img = img.astype(np.float32) / 255.0
            img = (img - mean) / std
            img = np.transpose(img, (2, 0, 1))
            img = np.expand_dims(img, axis=0)
            self.samples.append(img)

        self.index = 0
        print(f"Loaded {len(self.samples)} calibration samples")

    def get_next(self):
        if self.index >= len(self.samples):
            return None
        data = {"input": self.samples[self.index]}
        self.index += 1
        return data

    def rewind(self):
        self.index = 0


def quantize_onnx_dynamic(onnx_path: str, output_path: str) -> str:
    """Apply dynamic INT8 quantization to ONNX model.

    Fast, no calibration data needed, ~2-3x speedup on ARM.
    """
    from onnxruntime.quantization import quantize_dynamic, QuantType

    quantize_dynamic(
        model_input=onnx_path,
        model_output=output_path,
        weight_type=QuantType.QInt8,
    )

    size_mb = Path(output_path).stat().st_size / (1024 * 1024)
    print(f"  Dynamic INT8: {output_path} ({size_mb:.1f} MB)")
    return output_path


def quantize_onnx_static(onnx_path: str, output_path: str, calibration_dir: str, input_size: int) -> str:
    """Apply static INT8 quantization with calibration data.

    Better accuracy than dynamic, ~3-4x speedup on ARM.
    Requires representative calibration images.
    """
    from onnxruntime.quantization import quantize_static, QuantType, CalibrationMethod

    calibrator = CalibrationDataReader(calibration_dir, input_size)

    quantize_static(
        model_input=onnx_path,
        model_output=output_path,
        calibration_data_reader=calibrator,
        quant_format=3,  # QDQ format
        weight_type=QuantType.QInt8,
        activation_type=QuantType.QInt8,
        calibrate_method=CalibrationMethod.MinMax,
    )

    size_mb = Path(output_path).stat().st_size / (1024 * 1024)
    print(f"  Static INT8: {output_path} ({size_mb:.1f} MB)")
    return output_path


def export_tflite_int8(
    model: torch.nn.Module,
    task: str,
    input_size: int,
    output_path: str | None = None,
    calibration_dir: str | None = None,
) -> str:
    """Export to TFLite with INT8 quantization.

    TFLite INT8 is the fastest option on RPi4's ARM Cortex-A72.
    """
    import cv2

    if output_path is None:
        output_path = f"models/checkpoints/{task}_int8.tflite"

    Path(output_path).parent.mkdir(parents=True, exist_ok=True)

    # First export to ONNX
    tmp_onnx = f"/tmp/{task}_tmp.onnx"
    model.eval()
    model = model.cpu()
    dummy = torch.randn(1, 3, input_size, input_size)

    if task == "eye_state":
        # Wrap to return only logits for TFLite
        class Wrapper(torch.nn.Module):
            def __init__(self, m):
                super().__init__()
                self.m = m
            def forward(self, x):
                logits, _ = self.m(x)
                return logits
        export_model = Wrapper(model)
    else:
        export_model = model

    torch.onnx.export(export_model, dummy, tmp_onnx, opset_version=13,
                       input_names=["input"], output_names=["output"],
                       dynamo=False)

    # Convert ONNX -> TFLite with INT8
    try:
        import onnx
        from onnx_tf.backend import prepare
        import tensorflow as tf

        onnx_model = onnx.load(tmp_onnx)
        tf_rep = prepare(onnx_model)
        tf_rep.export_graph(f"/tmp/{task}_tf")

        converter = tf.lite.TFLiteConverter.from_saved_model(f"/tmp/{task}_tf")
        converter.optimizations = [tf.lite.Optimize.DEFAULT]

        if calibration_dir:
            mean = np.array([0.485, 0.456, 0.406], dtype=np.float32).reshape(1, 1, 3)
            std = np.array([0.229, 0.224, 0.225], dtype=np.float32).reshape(1, 1, 3)

            def representative_dataset():
                cal_path = Path(calibration_dir)
                images = list(cal_path.rglob("*.jpg")) + list(cal_path.rglob("*.png"))
                for img_path in images[:100]:
                    img = cv2.imread(str(img_path))
                    if img is None:
                        continue
                    img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
                    img = cv2.resize(img, (input_size, input_size))
                    img = img.astype(np.float32) / 255.0
                    img = (img - mean) / std
                    img = np.transpose(img, (2, 0, 1))
                    yield [np.expand_dims(img, 0)]

            converter.representative_dataset = representative_dataset
            converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
            converter.inference_input_type = tf.int8
            converter.inference_output_type = tf.int8

        tflite_model = converter.convert()
        with open(output_path, "wb") as f:
            f.write(tflite_model)

        size_mb = Path(output_path).stat().st_size / (1024 * 1024)
        print(f"  TFLite INT8: {output_path} ({size_mb:.1f} MB)")

    except ImportError:
        print("  Warning: onnx-tf or tensorflow not installed, skipping TFLite export")
        print("  Install with: uv pip install onnx-tf tensorflow")
        output_path = ""

    # Cleanup
    Path(tmp_onnx).unlink(missing_ok=True)

    return output_path


def main():
    parser = argparse.ArgumentParser(description="Export INT8 quantized models for RPi4")
    parser.add_argument("--checkpoint", type=str, required=True)
    parser.add_argument("--config", type=str, required=True)
    parser.add_argument("--output", type=str, default=None)
    parser.add_argument("--method", choices=["dynamic", "static", "both"], default="dynamic",
                        help="Quantization method (static needs --calibration-dir)")
    parser.add_argument("--calibration-dir", type=str, default=None,
                        help="Directory with calibration images (for static quantization)")
    parser.add_argument("--tflite", action="store_true", help="Also export TFLite INT8")
    args = parser.parse_args()

    config = load_config(args.config)
    task = config["task"]
    input_size = config.get("data", {}).get("image_size", 224)

    model = build_model(config)
    ckpt = torch.load(args.checkpoint, map_location="cpu", weights_only=False)
    model.load_state_dict(ckpt["model_state_dict"])

    print(f"Task: {task}")
    print(f"Input: {input_size}x{input_size}")
    print(f"Method: {args.method}")

    # First export FP32 ONNX as base
    fp32_path = f"models/checkpoints/{task}_fp32.onnx"

    # Clean up stale external data files from previous exports (e.g. teacher model)
    # to prevent shape mismatches during quantization
    stale_data = Path(fp32_path + ".data")
    if stale_data.exists():
        stale_data.unlink()
        print(f"Removed stale external data: {stale_data}")

    export_to_onnx(model, task, input_size, fp32_path, fp16=False)

    # Ensure all weights are inline (not external data) for quantization compatibility
    _ensure_inline_onnx(fp32_path)

    fp32_size = Path(fp32_path).stat().st_size / (1024 * 1024)
    print(f"\nFP32 baseline: {fp32_size:.1f} MB")

    # Dynamic quantization (no calibration needed)
    if args.method in ("dynamic", "both"):
        out = args.output or f"models/checkpoints/{task}_int8_dynamic.onnx"
        quantize_onnx_dynamic(fp32_path, out)

    # Static quantization (needs calibration data)
    if args.method in ("static", "both"):
        if not args.calibration_dir:
            print("\nError: --calibration-dir required for static quantization")
            print("Example: --calibration-dir models/data/processed/statefarm/imgs/train/c0")
            return
        out = args.output or f"models/checkpoints/{task}_int8_static.onnx"
        quantize_onnx_static(fp32_path, out, args.calibration_dir, input_size)

    # TFLite
    if args.tflite:
        export_tflite_int8(model, task, input_size,
                           calibration_dir=args.calibration_dir)

    # Print size comparison
    print(f"\n{'='*50}")
    print("Size comparison:")
    print(f"  FP32 ONNX: {fp32_size:.1f} MB")
    for suffix in ["_int8_dynamic.onnx", "_int8_static.onnx", "_int8.tflite"]:
        path = Path(f"models/checkpoints/{task}{suffix}")
        if path.exists():
            print(f"  {suffix}: {path.stat().st_size / (1024*1024):.1f} MB")
    print(f"\nExpected RPi4 inference improvement: ~3-4x faster than FP32")


if __name__ == "__main__":
    main()
