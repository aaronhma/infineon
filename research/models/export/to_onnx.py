"""Export PyTorch model to ONNX format.

Usage:
    uv run python -m models.export.to_onnx --checkpoint models/checkpoints/driver_activity_best_acc.pt --config models/configs/driver_activity.yaml
    uv run python -m models.export.to_onnx --checkpoint models/checkpoints/eye_state_best_acc.pt --config models/configs/eye_state.yaml --fp16
"""

import argparse
from pathlib import Path

import torch

from ..configs import load_config
from ..training.train import build_model


def export_to_onnx(
    model: torch.nn.Module,
    task: str,
    input_size: int = 224,
    output_path: str | None = None,
    fp16: bool = False,
    opset_version: int = 17,
) -> str:
    """Export a PyTorch model to ONNX."""
    model.eval()
    model = model.cpu()

    if output_path is None:
        suffix = "_fp16" if fp16 else ""
        output_path = f"models/checkpoints/{task}{suffix}.onnx"

    Path(output_path).parent.mkdir(parents=True, exist_ok=True)

    dummy_input = torch.randn(1, 3, input_size, input_size)

    # Define output names based on task
    if task == "eye_state":
        output_names = ["class_logits", "ear_score"]
    else:
        output_names = ["class_logits"]

    print(f"Exporting to ONNX (opset {opset_version})...")
    torch.onnx.export(
        model,
        dummy_input,
        output_path,
        export_params=True,
        opset_version=opset_version,
        do_constant_folding=True,
        input_names=["input"],
        output_names=output_names,
        dynamic_axes={
            "input": {0: "batch_size"},
            "class_logits": {0: "batch_size"},
        },
    )

    # Validate and optimize
    import onnx
    onnx_model = onnx.load(output_path)
    onnx.checker.check_model(onnx_model)

    # Simplify if onnxsim is available
    try:
        import onnxsim
        onnx_model, check = onnxsim.simplify(onnx_model)
        if check:
            onnx.save(onnx_model, output_path)
            print("  Applied onnx-simplifier")
    except ImportError:
        pass

    # Convert to FP16 if requested
    if fp16:
        try:
            from onnxconverter_common import float16
            fp16_model = float16.convert_float_to_float16(onnx_model)
            onnx.save(fp16_model, output_path)
            print("  Converted to FP16")
        except ImportError:
            print("  Warning: onnxconverter-common not installed, skipping FP16 conversion")

    size_mb = Path(output_path).stat().st_size / (1024 * 1024)
    print(f"  Saved: {output_path} ({size_mb:.1f} MB)")

    return output_path


def main():
    parser = argparse.ArgumentParser(description="Export model to ONNX")
    parser.add_argument("--checkpoint", type=str, required=True)
    parser.add_argument("--config", type=str, required=True)
    parser.add_argument("--output", type=str, default=None)
    parser.add_argument("--fp16", action="store_true", help="Convert to FP16")
    parser.add_argument("--opset", type=int, default=17)
    args = parser.parse_args()

    config = load_config(args.config)
    task = config["task"]
    input_size = config.get("data", {}).get("image_size", 224)

    model = build_model(config)
    ckpt = torch.load(args.checkpoint, map_location="cpu", weights_only=False)
    model.load_state_dict(ckpt["model_state_dict"])

    print(f"Task: {task}")
    print(f"Input size: {input_size}x{input_size}")
    print(f"Checkpoint epoch: {ckpt.get('epoch', '?')}")

    export_to_onnx(
        model=model,
        task=task,
        input_size=input_size,
        output_path=args.output,
        fp16=args.fp16,
        opset_version=args.opset,
    )


if __name__ == "__main__":
    main()
