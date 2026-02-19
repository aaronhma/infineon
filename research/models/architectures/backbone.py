"""Backbone factory for driver awareness models.

Provides lightweight pretrained backbones suitable for
edge deployment on Raspberry Pi 4 (ARM Cortex-A72, no GPU).

Performance targets on RPi4 with INT8 quantization:
    - TinyNet:           ~3ms  per inference (custom ultra-light)
    - MobileNetV3-Small: ~8ms  per inference
    - MobileNetV3-Large: ~20ms per inference
    - EfficientNet-B0:   ~35ms per inference (teacher model only)
"""

import torch
import torch.nn as nn
import torchvision.models as models


class TinyConvNet(nn.Module):
    """Ultra-lightweight CNN for RPi4. ~150K params, <3ms INT8 inference.

    Purpose-built for face crops where the input is already small (112x112)
    and the task is simple (4-class eye state). No need for a full
    ImageNet-pretrained backbone when the domain is this narrow.
    """

    def __init__(self):
        super().__init__()
        self.features = nn.Sequential(
            # 112x112x3 -> 56x56x16
            nn.Conv2d(3, 16, 3, stride=2, padding=1, bias=False),
            nn.BatchNorm2d(16),
            nn.ReLU6(inplace=True),

            # 56x56x16 -> 28x28x32
            nn.Conv2d(16, 32, 3, stride=2, padding=1, bias=False),
            nn.BatchNorm2d(32),
            nn.ReLU6(inplace=True),

            # Depthwise separable: 28x28x32 -> 14x14x64
            nn.Conv2d(32, 32, 3, stride=2, padding=1, groups=32, bias=False),
            nn.BatchNorm2d(32),
            nn.ReLU6(inplace=True),
            nn.Conv2d(32, 64, 1, bias=False),
            nn.BatchNorm2d(64),
            nn.ReLU6(inplace=True),

            # Depthwise separable: 14x14x64 -> 7x7x128
            nn.Conv2d(64, 64, 3, stride=2, padding=1, groups=64, bias=False),
            nn.BatchNorm2d(64),
            nn.ReLU6(inplace=True),
            nn.Conv2d(64, 128, 1, bias=False),
            nn.BatchNorm2d(128),
            nn.ReLU6(inplace=True),

            # Depthwise separable: 7x7x128 -> 4x4x128
            nn.Conv2d(128, 128, 3, stride=2, padding=1, groups=128, bias=False),
            nn.BatchNorm2d(128),
            nn.ReLU6(inplace=True),
            nn.Conv2d(128, 128, 1, bias=False),
            nn.BatchNorm2d(128),
            nn.ReLU6(inplace=True),
        )

    def forward(self, x):
        return self.features(x)


BACKBONES = {
    "tiny": {
        "factory": lambda pretrained: TinyConvNet(),  # no pretrained, trains from scratch
        "feature_dim": 128,
        "extract": lambda m: m,  # already returns features
    },
    "mobilenet_v3_small": {
        "factory": lambda pretrained: models.mobilenet_v3_small(
            weights=models.MobileNet_V3_Small_Weights.IMAGENET1K_V1 if pretrained else None
        ),
        "feature_dim": 576,
        "extract": lambda m: m.features,
    },
    "mobilenet_v3_large": {
        "factory": lambda pretrained: models.mobilenet_v3_large(
            weights=models.MobileNet_V3_Large_Weights.IMAGENET1K_V2 if pretrained else None
        ),
        "feature_dim": 960,
        "extract": lambda m: m.features,
    },
    "efficientnet_b0": {
        "factory": lambda pretrained: models.efficientnet_b0(
            weights=models.EfficientNet_B0_Weights.IMAGENET1K_V1 if pretrained else None
        ),
        "feature_dim": 1280,
        "extract": lambda m: m.features,
    },
    "squeezenet1_1": {
        "factory": lambda pretrained: models.squeezenet1_1(
            weights=models.SqueezeNet1_1_Weights.IMAGENET1K_V1 if pretrained else None
        ),
        "feature_dim": 512,
        "extract": lambda m: m.features,
    },
}


def create_backbone(name: str, pretrained: bool = True) -> tuple[nn.Module, int]:
    """Create a backbone network and return (features_module, feature_dim).

    Args:
        name: Backbone name (e.g., "mobilenet_v3_small")
        pretrained: Whether to load ImageNet pretrained weights

    Returns:
        Tuple of (backbone nn.Module, output feature dimension)
    """
    if name not in BACKBONES:
        available = ", ".join(BACKBONES.keys())
        raise ValueError(f"Unknown backbone '{name}'. Available: {available}")

    spec = BACKBONES[name]
    model = spec["factory"](pretrained)
    features = spec["extract"](model)
    feature_dim = spec["feature_dim"]

    return features, feature_dim


def freeze_backbone(backbone: nn.Module) -> None:
    """Freeze all backbone parameters (for transfer learning warm-up)."""
    for param in backbone.parameters():
        param.requires_grad = False


def unfreeze_backbone(backbone: nn.Module) -> None:
    """Unfreeze all backbone parameters."""
    for param in backbone.parameters():
        param.requires_grad = True


def count_parameters(model: nn.Module) -> dict:
    """Count total and trainable parameters."""
    total = sum(p.numel() for p in model.parameters())
    trainable = sum(p.numel() for p in model.parameters() if p.requires_grad)
    return {
        "total": total,
        "trainable": trainable,
        "frozen": total - trainable,
        "total_mb": total * 4 / (1024 * 1024),  # FP32 size
    }
