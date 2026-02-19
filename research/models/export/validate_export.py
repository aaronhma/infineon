"""Validate that exported models match PyTorch outputs.

Feeds the same input through both PyTorch and exported model,
asserts outputs match within tolerance.

Usage:
    uv run python -m models.export.validate_export --checkpoint models/checkpoints/driver_activity_best_acc.pt --onnx models/checkpoints/driver_activity.onnx --config models/configs/driver_activity.yaml
"""

import argparse

import numpy as np
import torch

from ..configs import load_config
from ..training.train import build_model


def validate_onnx(
    model: torch.nn.Module,
    onnx_path: str,
    task: str,
    input_size: int = 224,
    tolerance: float = 1e-4,
    num_tests: int = 5,
) -> bool:
    """Compare PyTorch and ONNX outputs."""
    import onnxruntime as ort

    model.eval()
    model = model.cpu()

    session = ort.InferenceSession(onnx_path, providers=["CPUExecutionProvider"])
    input_name = session.get_inputs()[0].name

    all_passed = True

    for i in range(num_tests):
        dummy = torch.randn(1, 3, input_size, input_size)

        # PyTorch output
        with torch.no_grad():
            if task.removesuffix("_teacher") == "eye_state":
                pt_logits, pt_ear = model(dummy)
                pt_logits = pt_logits.numpy()
                pt_ear = pt_ear.numpy()
            else:
                pt_logits = model(dummy).numpy()

        # ONNX output
        onnx_outputs = session.run(None, {input_name: dummy.numpy()})
        onnx_logits = onnx_outputs[0]

        # Compare
        max_diff = np.max(np.abs(pt_logits - onnx_logits))
        passed = max_diff < tolerance

        if task.removesuffix("_teacher") == "eye_state" and len(onnx_outputs) > 1:
            ear_diff = np.max(np.abs(pt_ear - onnx_outputs[1]))
            passed = passed and (ear_diff < tolerance)
            print(f"  Test {i+1}: logits diff={max_diff:.2e}, ear diff={ear_diff:.2e} {'PASS' if passed else 'FAIL'}")
        else:
            print(f"  Test {i+1}: max diff={max_diff:.2e} {'PASS' if passed else 'FAIL'}")

        if not passed:
            all_passed = False

    return all_passed


def main():
    parser = argparse.ArgumentParser(description="Validate exported model")
    parser.add_argument("--checkpoint", type=str, required=True)
    parser.add_argument("--config", type=str, required=True)
    parser.add_argument("--onnx", type=str, default=None, help="ONNX model to validate")
    parser.add_argument("--tolerance", type=float, default=1e-4)
    args = parser.parse_args()

    config = load_config(args.config)
    task = config["task"]
    input_size = config.get("data", {}).get("image_size", 224)

    model = build_model(config)
    ckpt = torch.load(args.checkpoint, map_location="cpu", weights_only=False)
    model.load_state_dict(ckpt["model_state_dict"])

    if args.onnx:
        print(f"Validating ONNX: {args.onnx}")
        print(f"Tolerance: {args.tolerance}")
        passed = validate_onnx(model, args.onnx, task, input_size, args.tolerance)
        print(f"\nResult: {'ALL PASSED' if passed else 'FAILED'}")


if __name__ == "__main__":
    main()
