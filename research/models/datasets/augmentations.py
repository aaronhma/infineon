"""Augmentation pipelines for driver awareness training."""

import albumentations as A
from albumentations.pytorch import ToTensorV2


def get_train_transforms(image_size: int = 224, config: dict | None = None) -> A.Compose:
    """Training augmentations: simulate real driving conditions."""
    cfg = config or {}

    return A.Compose([
        A.Resize(image_size, image_size),
        A.HorizontalFlip(p=cfg.get("horizontal_flip", 0.5)),

        # Lighting variations (day/night/tunnel transitions)
        A.OneOf([
            A.RandomBrightnessContrast(
                brightness_limit=cfg.get("brightness_limit", 0.2),
                contrast_limit=cfg.get("contrast_limit", 0.2),
            ),
            A.RandomGamma(
                gamma_limit=cfg.get("gamma_limit", (80, 120)),
            ),
            A.CLAHE(clip_limit=4.0, tile_grid_size=(8, 8)),
        ], p=cfg.get("brightness_contrast_p", 0.4)),

        # Low-light simulation
        A.RandomToneCurve(scale=0.1, p=0.15),

        # Motion/vibration blur from driving
        A.OneOf([
            A.MotionBlur(blur_limit=cfg.get("motion_blur_limit", 5)),
            A.GaussianBlur(blur_limit=cfg.get("gaussian_blur_limit", 3)),
        ], p=cfg.get("motion_blur_p", 0.15)),

        # Sensor noise
        A.GaussNoise(std_range=(0.02, 0.08), p=0.1),

        # Partial occlusion (steering wheel, sun visor, seat belt)
        A.CoarseDropout(
            num_holes_range=(1, cfg.get("coarse_dropout_max_holes", 8)),
            hole_height_range=(4, cfg.get("coarse_dropout_max_height", 16)),
            hole_width_range=(4, cfg.get("coarse_dropout_max_width", 16)),
            p=cfg.get("coarse_dropout_p", 0.2),
        ),

        # Color jitter (different camera sensors)
        A.HueSaturationValue(
            hue_shift_limit=10,
            sat_shift_limit=15,
            val_shift_limit=10,
            p=0.2,
        ),

        # Normalize to ImageNet stats
        A.Normalize(
            mean=cfg.get("normalize_mean", [0.485, 0.456, 0.406]),
            std=cfg.get("normalize_std", [0.229, 0.224, 0.225]),
        ),
        ToTensorV2(),
    ])


def get_val_transforms(image_size: int = 224, config: dict | None = None) -> A.Compose:
    """Validation/test transforms: resize and normalize only."""
    cfg = config or {}

    return A.Compose([
        A.Resize(image_size, image_size),
        A.Normalize(
            mean=cfg.get("normalize_mean", [0.485, 0.456, 0.406]),
            std=cfg.get("normalize_std", [0.229, 0.224, 0.225]),
        ),
        ToTensorV2(),
    ])
