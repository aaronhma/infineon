"""Loss functions for driver awareness model training."""

import torch
import torch.nn as nn
import torch.nn.functional as F


class FocalLoss(nn.Module):
    """Focal Loss for handling class imbalance in driver activity detection.

    Down-weights easy/well-classified examples so the model focuses on
    hard misclassified samples. Critical for datasets where "safe_driving"
    dominates.
    """

    def __init__(self, gamma: float = 2.0, alpha: torch.Tensor | None = None, label_smoothing: float = 0.0):
        super().__init__()
        self.gamma = gamma
        self.alpha = alpha
        self.label_smoothing = label_smoothing

    def forward(self, logits: torch.Tensor, targets: torch.Tensor) -> torch.Tensor:
        ce_loss = F.cross_entropy(
            logits, targets,
            weight=self.alpha,
            label_smoothing=self.label_smoothing,
            reduction="none",
        )
        pt = torch.exp(-ce_loss)
        focal_loss = ((1 - pt) ** self.gamma) * ce_loss
        return focal_loss.mean()


class MultiTaskLoss(nn.Module):
    """Combined classification + regression loss for eye state model.

    Combines focal loss for eye state classification with smooth L1
    loss for EAR score regression.
    """

    def __init__(
        self,
        cls_weight: float = 1.0,
        reg_weight: float = 0.5,
        focal_gamma: float = 2.0,
        label_smoothing: float = 0.0,
        class_weights: torch.Tensor | None = None,
    ):
        super().__init__()
        self.cls_weight = cls_weight
        self.reg_weight = reg_weight
        self.cls_loss = FocalLoss(
            gamma=focal_gamma,
            alpha=class_weights,
            label_smoothing=label_smoothing,
        )
        self.reg_loss = nn.SmoothL1Loss()

    def forward(
        self,
        class_logits: torch.Tensor,
        ear_pred: torch.Tensor,
        class_targets: torch.Tensor,
        ear_targets: torch.Tensor | None = None,
    ) -> dict[str, torch.Tensor]:
        cls = self.cls_loss(class_logits, class_targets)

        loss_dict = {"cls_loss": cls}

        if ear_targets is not None:
            reg = self.reg_loss(ear_pred.squeeze(-1), ear_targets)
            loss_dict["reg_loss"] = reg
            loss_dict["total"] = self.cls_weight * cls + self.reg_weight * reg
        else:
            loss_dict["total"] = cls

        return loss_dict


def create_loss(config: dict, class_weights: torch.Tensor | None = None) -> nn.Module:
    """Create loss function from config."""
    loss_config = config.get("loss", {})
    loss_type = loss_config.get("type", "focal")
    gamma = loss_config.get("focal_gamma", 2.0)
    smoothing = loss_config.get("label_smoothing", 0.0)

    if loss_type == "multi_task":
        return MultiTaskLoss(
            cls_weight=loss_config.get("classification_weight", 1.0),
            reg_weight=loss_config.get("regression_weight", 0.5),
            focal_gamma=gamma,
            label_smoothing=smoothing,
            class_weights=class_weights,
        )
    elif loss_type == "focal":
        return FocalLoss(
            gamma=gamma,
            alpha=class_weights,
            label_smoothing=smoothing,
        )
    elif loss_type == "cross_entropy":
        return nn.CrossEntropyLoss(
            weight=class_weights,
            label_smoothing=smoothing,
        )
    else:
        raise ValueError(f"Unknown loss type: {loss_type}")
