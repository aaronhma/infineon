"""Driver Activity Classifier.

Takes an upper-body/cabin crop and classifies driver activity
(safe driving, texting, drinking, etc.). Replaces the YOLO-based
distraction detection pipeline with a purpose-built classifier.
"""

import torch
import torch.nn as nn

from .backbone import create_backbone


class DriverActivityClassifier(nn.Module):
    """Driver activity classification from upper-body crops.

    Inputs:
        - Upper body crop tensor: (B, 3, 224, 224)

    Outputs:
        - class_logits: (B, num_classes) raw logits for activity
    """

    def __init__(
        self,
        backbone_name: str = "mobilenet_v3_small",
        num_classes: int = 10,
        pretrained: bool = True,
        dropout: float = 0.4,
        hidden_dim: int = 128,
    ):
        super().__init__()

        self.backbone, feat_dim = create_backbone(backbone_name, pretrained)
        self.pool = nn.AdaptiveAvgPool2d(1)

        self.classifier = nn.Sequential(
            nn.Dropout(dropout),
            nn.Linear(feat_dim, hidden_dim),
            nn.ReLU(inplace=True),
            nn.Dropout(dropout / 2),
            nn.Linear(hidden_dim, num_classes),
        )

        self.num_classes = num_classes

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        features = self.backbone(x)
        features = self.pool(features).flatten(1)
        return self.classifier(features)

    def predict(self, x: torch.Tensor) -> dict:
        """Run inference and return structured output."""
        self.eval()
        with torch.no_grad():
            logits = self(x)
            probs = torch.softmax(logits, dim=-1)
            pred_class = probs.argmax(dim=-1)
            confidence = probs.max(dim=-1).values

        return {
            "class_idx": pred_class,
            "confidence": confidence,
            "probabilities": probs,
        }
