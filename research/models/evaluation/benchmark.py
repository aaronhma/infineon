"""Benchmark inference speed across formats (PyTorch, ONNX FP32, ONNX INT8).

Targets Raspberry Pi 4 (ARM Cortex-A72, 4GB RAM, no GPU).
Goal: both models combined < 30ms per frame = 30+ FPS.

Usage:
    uv run python -m models.evaluation.benchmark --checkpoint models/checkpoints/driver_activity_best_acc.pt --config models/configs/driver_activity.yaml
    uv run python -m models.evaluation.benchmark --onnx models/checkpoints/driver_activity.onnx --input-size 224
    uv run python -m models.evaluation.benchmark --all-formats --checkpoint models/checkpoints/eye_state_best_acc.pt --config models/configs/eye_state.yaml
"""

import argparse
import os
import time
from pathlib import Path

import numpy as np
import torch

from ..configs import load_config
from ..training.train import build_model, detect_device
from ..architectures.backbone import count_parameters


def _sync_device(device: str) -> None:
    """Synchronize GPU to get accurate timing."""
    if device == "cuda":
        torch.cuda.synchronize()
    elif device == "mps":
        torch.mps.synchronize()


def benchmark_pytorch(model: torch.nn.Module, input_size: int, device: str, warmup: int = 10, iterations: int = 100) -> dict:
    """Benchmark PyTorch model inference."""
    model.eval()
    dummy = torch.randn(1, 3, input_size, input_size).to(device)

    with torch.no_grad():
        for _ in range(warmup):
            model(dummy)

    _sync_device(device)

    times = []
    with torch.no_grad():
        for _ in range(iterations):
            start = time.perf_counter()
            model(dummy)
            _sync_device(device)
            times.append((time.perf_counter() - start) * 1000)

    return {
        "format": f"PyTorch ({device})",
        "mean_ms": np.mean(times),
        "std_ms": np.std(times),
        "min_ms": np.min(times),
        "p95_ms": np.percentile(times, 95),
        "max_ms": np.max(times),
        "fps": 1000.0 / np.mean(times),
    }


def benchmark_onnx(onnx_path: str, input_size: int, warmup: int = 10, iterations: int = 100) -> dict:
    """Benchmark ONNX model inference (CPU, optimized for ARM)."""
    import onnxruntime as ort

    opts = ort.SessionOptions()
    opts.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
    opts.intra_op_num_threads = 4
    opts.inter_op_num_threads = 1
    opts.enable_cpu_mem_arena = True

    session = ort.InferenceSession(onnx_path, sess_options=opts, providers=["CPUExecutionProvider"])
    input_name = session.get_inputs()[0].name
    dummy = np.random.randn(1, 3, input_size, input_size).astype(np.float32)

    for _ in range(warmup):
        session.run(None, {input_name: dummy})

    times = []
    for _ in range(iterations):
        start = time.perf_counter()
        session.run(None, {input_name: dummy})
        times.append((time.perf_counter() - start) * 1000)

    size_mb = os.path.getsize(onnx_path) / (1024 * 1024)

    return {
        "format": f"ONNX ({size_mb:.1f}MB)",
        "mean_ms": np.mean(times),
        "std_ms": np.std(times),
        "min_ms": np.min(times),
        "p95_ms": np.percentile(times, 95),
        "max_ms": np.max(times),
        "fps": 1000.0 / np.mean(times),
    }


def benchmark_preprocessing(input_size: int, iterations: int = 100) -> dict:
    """Benchmark the preprocessing pipeline (resize + normalize).

    This matters on RPi4 -- preprocessing can take as long as inference.
    """
    import cv2

    # Simulate a typical camera frame (640x480 BGR)
    frame = np.random.randint(0, 255, (480, 640, 3), dtype=np.uint8)
    mean = np.array([0.485, 0.456, 0.406], dtype=np.float32).reshape(1, 1, 3)
    std = np.array([0.229, 0.224, 0.225], dtype=np.float32).reshape(1, 1, 3)

    times = []
    for _ in range(iterations):
        start = time.perf_counter()

        # Typical preprocessing pipeline
        img = cv2.resize(frame, (input_size, input_size), interpolation=cv2.INTER_AREA)
        img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        img = img.astype(np.float32) / 255.0
        img = (img - mean) / std
        img = np.transpose(img, (2, 0, 1))
        img = np.expand_dims(img, axis=0)

        times.append((time.perf_counter() - start) * 1000)

    return {
        "format": f"Preprocessing ({input_size}x{input_size})",
        "mean_ms": np.mean(times),
        "std_ms": np.std(times),
        "min_ms": np.min(times),
        "p95_ms": np.percentile(times, 95),
        "max_ms": np.max(times),
        "fps": 1000.0 / np.mean(times),
    }


def estimate_rpi4_time(local_ms: float) -> float:
    """Rough estimate: RPi4 ARM is ~4-6x slower than modern x86 for inference.

    This gives a ballpark for development. Always benchmark on actual hardware.
    """
    return local_ms * 5.0


def print_results(results: list[dict], show_rpi4_estimate: bool = True) -> None:
    """Print benchmark results as a table."""
    header = f"{'Format':<30s} {'Mean':>8s} {'P95':>8s} {'Min':>8s} {'Max':>8s} {'FPS':>7s}"
    if show_rpi4_estimate:
        header += f" {'~RPi4':>8s}"
    print(f"\n{header}")
    print("-" * len(header))

    total_inference_ms = 0.0
    for r in results:
        line = (
            f"{r['format']:<30s} "
            f"{r['mean_ms']:>7.1f}ms "
            f"{r['p95_ms']:>7.1f}ms "
            f"{r['min_ms']:>7.1f}ms "
            f"{r['max_ms']:>7.1f}ms "
            f"{r['fps']:>6.0f}"
        )
        if show_rpi4_estimate:
            est = estimate_rpi4_time(r["mean_ms"])
            line += f" {est:>7.1f}ms"
        print(line)

        if "Preprocessing" not in r["format"]:
            total_inference_ms += r["mean_ms"]

    if show_rpi4_estimate and len(results) > 1:
        est_total = estimate_rpi4_time(total_inference_ms)
        print(f"\n  Estimated RPi4 total inference: ~{est_total:.0f}ms (~{1000/max(est_total,1):.0f} FPS)")
        print(f"  Note: actual RPi4 timing varies. INT8 quantization typically gives 3-4x speedup.")


def main():
    parser = argparse.ArgumentParser(description="Benchmark model inference speed")
    parser.add_argument("--checkpoint", type=str, default=None, help="PyTorch checkpoint path")
    parser.add_argument("--config", type=str, default=None, help="Config YAML (required with --checkpoint)")
    parser.add_argument("--onnx", type=str, nargs="*", default=None, help="ONNX model path(s)")
    parser.add_argument("--input-size", type=int, default=None, help="Input image size (auto from config)")
    parser.add_argument("--device", type=str, default="auto", help="Device (auto/cpu/cuda/mps)")
    parser.add_argument("--warmup", type=int, default=20)
    parser.add_argument("--iterations", type=int, default=200)
    parser.add_argument("--all-formats", action="store_true",
                        help="Benchmark all available formats (FP32, FP16, INT8)")
    parser.add_argument("--include-preprocessing", action="store_true",
                        help="Also benchmark the preprocessing pipeline")
    args = parser.parse_args()

    if not args.checkpoint and not args.onnx:
        parser.print_help()
        print("\nProvide at least --checkpoint or --onnx")
        return

    # Auto-detect input size from config
    input_size = args.input_size
    if input_size is None and args.config:
        config = load_config(args.config)
        input_size = config.get("data", {}).get("image_size", 224)
    elif input_size is None:
        input_size = 224

    results = []

    # Preprocessing benchmark
    if args.include_preprocessing:
        results.append(benchmark_preprocessing(input_size, args.iterations))

    # PyTorch benchmark
    if args.checkpoint:
        if not args.config:
            print("Error: --config required with --checkpoint")
            return

        config = load_config(args.config)
        device = detect_device(args.device)
        model = build_model(config)

        ckpt = torch.load(args.checkpoint, map_location=device, weights_only=False)
        model.load_state_dict(ckpt["model_state_dict"])
        model = model.to(device)

        params = count_parameters(model)
        print(f"Model: {params['total']:,} params ({params['total_mb']:.1f} MB FP32)")
        print(f"Input: {input_size}x{input_size} | Warmup: {args.warmup} | Iters: {args.iterations}")

        results.append(benchmark_pytorch(model, input_size, device, args.warmup, args.iterations))

    # ONNX benchmarks
    onnx_paths = args.onnx or []

    # Auto-discover all formats if --all-formats
    if args.all_formats and args.config:
        task = load_config(args.config)["task"]
        ckpt_dir = Path("models/checkpoints")
        for suffix in ["_fp32.onnx", "_fp16.onnx", ".onnx", "_int8_dynamic.onnx", "_int8_static.onnx"]:
            candidate = ckpt_dir / f"{task}{suffix}"
            if candidate.exists() and str(candidate) not in onnx_paths:
                onnx_paths.append(str(candidate))

    for onnx_path in onnx_paths:
        if not Path(onnx_path).exists():
            print(f"Warning: {onnx_path} not found, skipping")
            continue
        try:
            results.append(benchmark_onnx(onnx_path, input_size, args.warmup, args.iterations))
        except Exception as e:
            print(f"Warning: failed to benchmark {onnx_path}: {e}")

    if results:
        print_results(results)
    else:
        print("No models to benchmark.")


if __name__ == "__main__":
    main()
