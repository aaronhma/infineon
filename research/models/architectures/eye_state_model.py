"""Eye State Classifier with auxiliary EAR regression.

Takes a face crop and classifies eye state (open, partially closed,
closed, sunglasses) while also predicting a continuous EAR-like
alertness score for backward compatibility with the existing
intoxication scoring system.
"""

import torch
import torch.nn as nn

from .backbone import create_backbone


class EyeStateClassifier(nn.Module):
    """Eye state classification + EAR regression.

    Inputs:
        - Face crop tensor: (B, 3, 112, 112)

    Outputs:
        - class_logits: (B, num_classes) raw logits for eye state
        - ear_score: (B, 1) continuous alertness score in [0, 1]
          where 0 = fully closed, 1 = fully open
    """

    def __init__(
        self,
        backbone_name: str = "mobilenet_v3_small",
        num_classes: int = 4,
        pretrained: bool = True,
        dropout: float = 0.3,
    ):
        super().__init__()

        self.backbone, feat_dim = create_backbone(backbone_name, pretrained)
        self.pool = nn.AdaptiveAvgPool2d(1)

        # Classification head: eye state
        self.classifier = nn.Sequential(
            nn.Dropout(dropout),
            nn.Linear(feat_dim, num_classes),
        )

        # Auxiliary regression head: EAR-like score
        self.ear_regressor = nn.Sequential(
            nn.Dropout(dropout),
            nn.Linear(feat_dim, 64),
            nn.ReLU(inplace=True),
            nn.Linear(64, 1),
            nn.Sigmoid(),
        )

        self.num_classes = num_classes

    def forward(self, x: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor]:
        features = self.backbone(x)
        features = self.pool(features).flatten(1)

        class_logits = self.classifier(features)
        ear_score = self.ear_regressor(features)

        return class_logits, ear_score

    def predict(self, x: torch.Tensor) -> dict:
        """Run inference and return structured output."""
        self.eval()
        with torch.no_grad():
            logits, ear = self(x)
            probs = torch.softmax(logits, dim=-1)
            pred_class = probs.argmax(dim=-1)
            confidence = probs.max(dim=-1).values

        return {
            "class_idx": pred_class,
            "confidence": confidence,
            "probabilities": probs,
            "ear_score": ear.squeeze(-1),
        }
