"""Main training entry point for driver awareness models.

Usage:
    uv run python -m models.training.train --config models/configs/driver_activity.yaml
    uv run python -m models.training.train --config models/configs/eye_state.yaml --device mps
    uv run python -m models.training.train --config models/configs/eye_state.yaml --resume models/checkpoints/eye_state_best_acc.pt
"""

import argparse
import sys
from pathlib import Path

import torch

from ..configs import load_config
from ..datasets.dataset import create_dataloaders
from ..architectures.eye_state_model import EyeStateClassifier
from ..architectures.driver_activity_model import DriverActivityClassifier
from ..architectures.backbone import count_parameters
from .losses import create_loss
from .trainer import Trainer


def detect_device(requested: str | None = None) -> str:
    """Auto-detect the best available device."""
    if requested and requested != "auto":
        return requested
    if torch.cuda.is_available():
        return "cuda"
    if torch.backends.mps.is_available():
        return "mps"
    return "cpu"


def build_model(config: dict) -> torch.nn.Module:
    """Build model from config."""
    task = config["task"]
    model_cfg = config.get("model", {})
    backbone = model_cfg.get("backbone", config.get("backbone", {}).get("name", "mobilenet_v3_small"))
    pretrained = config.get("backbone", {}).get("pretrained", True)

    if task == "eye_state":
        return EyeStateClassifier(
            backbone_name=backbone,
            num_classes=model_cfg.get("num_classes", len(config.get("classes", []))),
            pretrained=pretrained,
            dropout=model_cfg.get("head_dropout", 0.3),
        )
    elif task == "driver_activity":
        return DriverActivityClassifier(
            backbone_name=backbone,
            num_classes=model_cfg.get("num_classes", len(config.get("classes", []))),
            pretrained=pretrained,
            dropout=model_cfg.get("head_dropout", 0.4),
            hidden_dim=model_cfg.get("hidden_dim", 128),
        )
    else:
        raise ValueError(f"Unknown task: {task}")


def main():
    parser = argparse.ArgumentParser(description="Train driver awareness models")
    parser.add_argument("--config", type=str, required=True, help="Path to YAML config file")
    parser.add_argument("--device", type=str, default="auto", help="Device (auto/cpu/cuda/mps)")
    parser.add_argument("--resume", type=str, default=None, help="Path to checkpoint to resume from")
    parser.add_argument("--manifest", type=str, default=None, help="Override manifest path")
    parser.add_argument("--data-root", type=str, default=None, help="Override data root directory")
    args = parser.parse_args()

    # Load config
    config = load_config(args.config)
    task = config["task"]
    classes = config["classes"]
    device = detect_device(args.device)

    print(f"Task: {task}")
    print(f"Classes: {classes}")
    print(f"Device: {device}")

    # Find manifest -- task-aware so eye_state doesn't pick up statefarm
    TASK_DATASETS = {
        "driver_activity": ["statefarm"],
        "eye_state": ["mrl_eyes"],
    }
    manifest = args.manifest
    if not manifest:
        data_dir = Path("models/data/processed")
        # Task-specific dir first, then dataset dirs matching this task
        candidates = [data_dir / task / "manifest.csv"]
        for ds_name in TASK_DATASETS.get(task, []):
            candidates.append(data_dir / ds_name / "manifest.csv")
        for c in candidates:
            if c.exists():
                manifest = str(c)
                break

    if not manifest:
        ds_name = TASK_DATASETS.get(task, ["unknown"])[0]
        print("\nError: No dataset manifest found.")
        print("Prepare a dataset first:")
        print(f"  uv run python -m models.datasets.download --dataset {ds_name}")
        print(f"  uv run python -m models.datasets.prepare_{ds_name}")
        sys.exit(1)

    print(f"Manifest: {manifest}")

    # Create dataloaders
    loaders = create_dataloaders(
        manifest_path=manifest,
        classes=classes,
        config=config,
        data_root=args.data_root,
    )

    if "train" not in loaders or "val" not in loaders:
        print("Error: Need both train and val splits in manifest")
        sys.exit(1)

    # Build model
    model = build_model(config)
    params = count_parameters(model)
    print(f"\nModel: {params['total']:,} parameters ({params['total_mb']:.1f} MB)")

    # Resume from checkpoint if specified
    if args.resume:
        print(f"Resuming from: {args.resume}")
        checkpoint = torch.load(args.resume, map_location=device, weights_only=False)
        model.load_state_dict(checkpoint["model_state_dict"])

    # Create loss
    class_weights = loaders["train"].dataset.get_class_weights().to(device)
    loss_fn = create_loss(config, class_weights=class_weights)

    # Train
    trainer = Trainer(
        model=model,
        train_loader=loaders["train"],
        val_loader=loaders["val"],
        config=config,
        task=task,
        device=device,
    )

    trainer.train(loss_fn)


if __name__ == "__main__":
    main()
