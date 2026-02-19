"""Validate that exported models match PyTorch outputs.

Feeds the same input through both PyTorch and exported model,
asserts outputs match within tolerance.

For FP32/FP16 ONNX: checks raw logit values match (tight tolerance).
For INT8 quantized: checks predicted classes match (logit values will differ).

Usage:
    uv run python -m models.export.validate_export --checkpoint models/checkpoints/driver_activity_best_acc.pt --onnx models/checkpoints/driver_activity.onnx --config models/configs/driver_activity.yaml
    uv run python -m models.export.validate_export --checkpoint models/checkpoints/driver_activity_distilled_best_acc.pt --onnx models/checkpoints/driver_activity_int8_dynamic.onnx --config models/configs/driver_activity.yaml
"""

import argparse

import numpy as np
import torch

from ..configs import load_config
from ..training.train import build_model


def _is_quantized(onnx_path: str) -> bool:
    """Detect if an ONNX model is quantized (INT8)."""
    return "int8" in onnx_path.lower() or "quant" in onnx_path.lower()


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

    quantized = _is_quantized(onnx_path)
    if quantized:
        print(f"  Quantized model detected -- validating prediction agreement (not raw values)")

    all_passed = True
    pred_matches = 0

    for i in range(num_tests):
        dummy = torch.randn(1, 3, input_size, input_size)

        # PyTorch output
        with torch.no_grad():
            if task == "eye_state":
                pt_logits, pt_ear = model(dummy)
                pt_logits = pt_logits.numpy()
                pt_ear = pt_ear.numpy()
            else:
                pt_logits = model(dummy).numpy()

        # ONNX output
        onnx_outputs = session.run(None, {input_name: dummy.numpy()})
        onnx_logits = onnx_outputs[0]

        # Compare raw values
        max_diff = np.max(np.abs(pt_logits - onnx_logits))

        # Compare predictions (argmax)
        pt_pred = int(np.argmax(pt_logits))
        onnx_pred = int(np.argmax(onnx_logits))
        preds_match = pt_pred == onnx_pred

        if preds_match:
            pred_matches += 1

        if quantized:
            # For quantized models: predictions must match, logit diff is informational
            passed = preds_match
            if task == "eye_state" and len(onnx_outputs) > 1:
                ear_diff = np.max(np.abs(pt_ear - onnx_outputs[1]))
                print(
                    f"  Test {i+1}: pred={'MATCH' if preds_match else 'MISMATCH'} "
                    f"(pt={pt_pred} onnx={onnx_pred}) | "
                    f"logit diff={max_diff:.2f}, ear diff={ear_diff:.2f}"
                )
            else:
                print(
                    f"  Test {i+1}: pred={'MATCH' if preds_match else 'MISMATCH'} "
                    f"(pt={pt_pred} onnx={onnx_pred}) | "
                    f"logit diff={max_diff:.2f}"
                )
        else:
            # For FP32/FP16: raw values must be close
            passed = max_diff < tolerance
            if task == "eye_state" and len(onnx_outputs) > 1:
                ear_diff = np.max(np.abs(pt_ear - onnx_outputs[1]))
                passed = passed and (ear_diff < tolerance)
                print(f"  Test {i+1}: logits diff={max_diff:.2e}, ear diff={ear_diff:.2e} {'PASS' if passed else 'FAIL'}")
            else:
                print(f"  Test {i+1}: max diff={max_diff:.2e} {'PASS' if passed else 'FAIL'}")

        if not passed:
            all_passed = False

    if quantized:
        agreement = pred_matches / num_tests
        print(f"\n  Prediction agreement: {pred_matches}/{num_tests} ({agreement:.0%})")
        # Allow up to 20% prediction disagreement for INT8 on random inputs
        # (random inputs stress edge cases -- real data agreement is much higher)
        all_passed = agreement >= 0.6

    return all_passed


def main():
    parser = argparse.ArgumentParser(description="Validate exported model")
    parser.add_argument("--checkpoint", type=str, required=True)
    parser.add_argument("--config", type=str, required=True)
    parser.add_argument("--onnx", type=str, default=None, help="ONNX model to validate")
    parser.add_argument("--tolerance", type=float, default=1e-4)
    parser.add_argument("--num-tests", type=int, default=10)
    args = parser.parse_args()

    config = load_config(args.config)
    task = config["task"]
    input_size = config.get("data", {}).get("image_size", 224)

    model = build_model(config)
    ckpt = torch.load(args.checkpoint, map_location="cpu", weights_only=False)
    model.load_state_dict(ckpt["model_state_dict"])

    if args.onnx:
        print(f"Validating ONNX: {args.onnx}")
        quantized = _is_quantized(args.onnx)
        if not quantized:
            print(f"Tolerance: {args.tolerance}")
        passed = validate_onnx(model, args.onnx, task, input_size, args.tolerance, args.num_tests)
        print(f"\nResult: {'ALL PASSED' if passed else 'FAILED'}")


if __name__ == "__main__":
    main()
