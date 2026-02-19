"""Export PyTorch model to CoreML format for iOS on-device inference.

Usage:
    uv run python -m models.export.to_coreml --checkpoint models/checkpoints/driver_activity_best_acc.pt --config models/configs/driver_activity.yaml
"""

import argparse
from pathlib import Path

import torch

from ..configs import load_config
from ..training.train import build_model


def export_to_coreml(
    model: torch.nn.Module,
    task: str,
    classes: list[str],
    input_size: int = 224,
    output_path: str | None = None,
) -> str:
    """Export a PyTorch model to CoreML."""
    try:
        import coremltools as ct
    except ImportError:
        print("Error: coremltools not installed. Install with: uv pip install coremltools")
        return ""

    model.eval()
    model = model.cpu()

    if output_path is None:
        output_path = f"models/checkpoints/{task}.mlpackage"

    Path(output_path).parent.mkdir(parents=True, exist_ok=True)

    # Trace the model
    dummy_input = torch.randn(1, 3, input_size, input_size)

    if task.removesuffix("_teacher") == "eye_state":
        # Wrap to return only classification logits for CoreML
        class CoreMLWrapper(torch.nn.Module):
            def __init__(self, model):
                super().__init__()
                self.model = model

            def forward(self, x):
                logits, ear = self.model(x)
                return logits, ear

        wrapper = CoreMLWrapper(model)
        traced = torch.jit.trace(wrapper, dummy_input)
    else:
        traced = torch.jit.trace(model, dummy_input)

    print("Converting to CoreML...")
    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.ImageType(
                name="input",
                shape=(1, 3, input_size, input_size),
                scale=1.0 / 255.0,
                bias=[-0.485 / 0.229, -0.456 / 0.224, -0.406 / 0.225],
            )
        ],
        minimum_deployment_target=ct.target.iOS17,
        convert_to="mlprogram",
    )

    # Add metadata
    mlmodel.author = "Infineon Driver Awareness"
    mlmodel.short_description = f"Driver awareness {task} classifier"
    mlmodel.version = "1.0"

    # Add class labels
    labels = ct.ClassifierConfig(classes)
    mlmodel.user_defined_metadata["classes"] = ",".join(classes)

    mlmodel.save(output_path)
    print(f"  Saved: {output_path}")

    return output_path


def main():
    parser = argparse.ArgumentParser(description="Export model to CoreML")
    parser.add_argument("--checkpoint", type=str, required=True)
    parser.add_argument("--config", type=str, required=True)
    parser.add_argument("--output", type=str, default=None)
    args = parser.parse_args()

    config = load_config(args.config)
    task = config["task"]
    classes = config["classes"]
    input_size = config.get("data", {}).get("image_size", 224)

    model = build_model(config)
    ckpt = torch.load(args.checkpoint, map_location="cpu", weights_only=False)
    model.load_state_dict(ckpt["model_state_dict"])

    print(f"Task: {task}")
    print(f"Classes: {classes}")
    print(f"Input size: {input_size}x{input_size}")

    export_to_coreml(
        model=model,
        task=task,
        classes=classes,
        input_size=input_size,
        output_path=args.output,
    )


if __name__ == "__main__":
    main()
