"""Evaluate a trained model on the test set.

Usage:
    uv run python -m models.evaluation.evaluate --checkpoint models/checkpoints/driver_activity_best_acc.pt --config models/configs/driver_activity.yaml
    uv run python -m models.evaluation.evaluate --checkpoint models/checkpoints/eye_state_best_acc.pt --config models/configs/eye_state.yaml
"""

import argparse
import sys
from pathlib import Path

import numpy as np
import torch

from ..configs import load_config
from ..datasets.dataset import create_dataloaders
from ..training.train import build_model, detect_device
from .metrics import compute_metrics, print_metrics


def run_evaluation(
    model: torch.nn.Module,
    dataloader: torch.utils.data.DataLoader,
    task: str,
    device: str,
) -> tuple[np.ndarray, np.ndarray]:
    """Run model on dataloader, return (y_true, y_pred)."""
    model.eval()
    all_preds = []
    all_targets = []

    with torch.no_grad():
        for images, targets in dataloader:
            images = images.to(device)

            if task == "eye_state":
                logits, _ = model(images)
            else:
                logits = model(images)

            preds = logits.argmax(dim=-1).cpu().numpy()
            all_preds.extend(preds)
            all_targets.extend(targets.numpy())

    return np.array(all_targets), np.array(all_preds)


def main():
    parser = argparse.ArgumentParser(description="Evaluate driver awareness model")
    parser.add_argument("--checkpoint", type=str, required=True, help="Path to model checkpoint")
    parser.add_argument("--config", type=str, required=True, help="Path to config YAML")
    parser.add_argument("--device", type=str, default="auto")
    parser.add_argument("--manifest", type=str, default=None, help="Override manifest path")
    parser.add_argument("--split", type=str, default="test", choices=["val", "test"])
    parser.add_argument("--save-cm", type=str, default=None, help="Save confusion matrix to PNG")
    args = parser.parse_args()

    config = load_config(args.config)
    task = config["task"]
    classes = config["classes"]
    device = detect_device(args.device)

    print(f"Evaluating: {task}")
    print(f"Checkpoint: {args.checkpoint}")
    print(f"Device: {device}")

    # Build model and load weights
    model = build_model(config)
    checkpoint = torch.load(args.checkpoint, map_location=device, weights_only=False)
    model.load_state_dict(checkpoint["model_state_dict"])
    model = model.to(device)

    print(f"Loaded checkpoint from epoch {checkpoint.get('epoch', '?')}")
    print(f"  Val acc at checkpoint: {checkpoint.get('val_acc', 0):.4f}")

    # Load data
    manifest = args.manifest
    if not manifest:
        data_dir = Path("models/data/processed")
        candidates = [
            data_dir / task / "manifest.csv",
            data_dir / "statefarm" / "manifest.csv",
            data_dir / "mrl_eyes" / "manifest.csv",
        ]
        for c in candidates:
            if c.exists():
                manifest = str(c)
                break

    if not manifest:
        print("Error: No manifest found. Specify with --manifest")
        sys.exit(1)

    loaders = create_dataloaders(manifest, classes, config)

    if args.split not in loaders:
        print(f"Error: Split '{args.split}' not found in manifest")
        sys.exit(1)

    # Run evaluation
    y_true, y_pred = run_evaluation(model, loaders[args.split], task, device)
    metrics = compute_metrics(y_true, y_pred, classes)
    print_metrics(metrics, classes)

    # Save confusion matrix plot
    if args.save_cm:
        try:
            import matplotlib.pyplot as plt
            import seaborn as sns

            fig, ax = plt.subplots(figsize=(10, 8))
            sns.heatmap(
                metrics["confusion_matrix"],
                annot=True,
                fmt="d",
                xticklabels=classes,
                yticklabels=classes,
                cmap="Blues",
                ax=ax,
            )
            ax.set_xlabel("Predicted")
            ax.set_ylabel("True")
            ax.set_title(f"{task} - Confusion Matrix (acc={metrics['accuracy']:.3f})")
            plt.tight_layout()
            plt.savefig(args.save_cm, dpi=150)
            print(f"\nConfusion matrix saved to: {args.save_cm}")
        except ImportError:
            print("Warning: matplotlib/seaborn not installed, skipping plot")


if __name__ == "__main__":
    main()
