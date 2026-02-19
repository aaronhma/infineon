"""Evaluation metrics for driver awareness models."""

import numpy as np
from sklearn.metrics import (
    accuracy_score,
    classification_report,
    confusion_matrix,
    f1_score,
    precision_score,
    recall_score,
)


def compute_metrics(y_true: np.ndarray, y_pred: np.ndarray, class_names: list[str]) -> dict:
    """Compute classification metrics."""
    acc = accuracy_score(y_true, y_pred)
    f1_macro = f1_score(y_true, y_pred, average="macro", zero_division=0)
    f1_weighted = f1_score(y_true, y_pred, average="weighted", zero_division=0)
    precision = precision_score(y_true, y_pred, average="macro", zero_division=0)
    recall = recall_score(y_true, y_pred, average="macro", zero_division=0)

    cm = confusion_matrix(y_true, y_pred)
    report = classification_report(
        y_true, y_pred,
        target_names=class_names,
        zero_division=0,
        output_dict=True,
    )

    return {
        "accuracy": acc,
        "f1_macro": f1_macro,
        "f1_weighted": f1_weighted,
        "precision_macro": precision,
        "recall_macro": recall,
        "confusion_matrix": cm,
        "classification_report": report,
    }


def print_metrics(metrics: dict, class_names: list[str]) -> None:
    """Print metrics in a readable format."""
    print(f"\n{'='*60}")
    print(f"  Accuracy:         {metrics['accuracy']:.4f}")
    print(f"  F1 (macro):       {metrics['f1_macro']:.4f}")
    print(f"  F1 (weighted):    {metrics['f1_weighted']:.4f}")
    print(f"  Precision (macro):{metrics['precision_macro']:.4f}")
    print(f"  Recall (macro):   {metrics['recall_macro']:.4f}")
    print(f"{'='*60}")

    print("\nPer-class results:")
    report = metrics["classification_report"]
    print(f"  {'Class':<30s} {'Prec':>6s} {'Rec':>6s} {'F1':>6s} {'N':>6s}")
    print(f"  {'-'*54}")
    for cls in class_names:
        if cls in report:
            r = report[cls]
            print(f"  {cls:<30s} {r['precision']:>6.3f} {r['recall']:>6.3f} {r['f1-score']:>6.3f} {int(r['support']):>6d}")

    print(f"\nConfusion matrix:")
    cm = metrics["confusion_matrix"]
    # Print header
    header = "  " + " " * 20 + "".join(f"{c[:8]:>9s}" for c in class_names)
    print(header)
    for i, row in enumerate(cm):
        label = class_names[i] if i < len(class_names) else f"class_{i}"
        row_str = "".join(f"{v:>9d}" for v in row)
        print(f"  {label:<20s}{row_str}")
