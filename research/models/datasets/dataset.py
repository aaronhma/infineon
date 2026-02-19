"""PyTorch Dataset for driver awareness training.

Uses a CSV manifest approach to unify multiple data sources.
Manifest columns: path, label, split, source
"""

import csv
from pathlib import Path

import cv2
import numpy as np
import torch
from torch.utils.data import Dataset, DataLoader, WeightedRandomSampler

from .augmentations import get_train_transforms, get_val_transforms


class DriverDataset(Dataset):
    """Dataset that reads images from a CSV manifest.

    Manifest CSV format:
        path,label,split,source
        data/statefarm/img_001.jpg,safe_driving,train,statefarm
        data/mrl/eye_002.png,eyes_open,train,mrl_eyes
    """

    def __init__(
        self,
        manifest_path: str,
        classes: list[str],
        split: str = "train",
        transform=None,
        image_size: int = 224,
        data_root: str | None = None,
    ):
        self.classes = classes
        self.class_to_idx = {c: i for i, c in enumerate(classes)}
        self.split = split
        self.image_size = image_size
        self.data_root = Path(data_root) if data_root else Path(manifest_path).parent

        if transform is not None:
            self.transform = transform
        elif split == "train":
            self.transform = get_train_transforms(image_size)
        else:
            self.transform = get_val_transforms(image_size)

        # Load manifest
        self.samples = []
        with open(manifest_path) as f:
            reader = csv.DictReader(f)
            for row in reader:
                if row["split"] != split:
                    continue
                label = row["label"]
                if label not in self.class_to_idx:
                    continue
                # Support both absolute paths and relative (to data_root)
                raw_path = row["path"]
                path = Path(raw_path) if Path(raw_path).is_absolute() else self.data_root / raw_path
                self.samples.append({
                    "path": str(path),
                    "label": self.class_to_idx[label],
                    "label_name": label,
                    "source": row.get("source", "unknown"),
                })

        if len(self.samples) == 0:
            raise ValueError(
                f"No samples found for split='{split}' in {manifest_path}. "
                f"Available classes: {classes}"
            )

    def __len__(self) -> int:
        return len(self.samples)

    def __getitem__(self, idx: int) -> tuple[torch.Tensor, int]:
        sample = self.samples[idx]

        # Load image as RGB
        image = cv2.imread(sample["path"])
        if image is None:
            raise FileNotFoundError(f"Could not load image: {sample['path']}")
        image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)

        # Apply transforms
        if self.transform:
            transformed = self.transform(image=image)
            image = transformed["image"]

        return image, sample["label"]

    def get_class_weights(self) -> torch.Tensor:
        """Compute inverse frequency weights for class balancing."""
        counts = np.zeros(len(self.classes))
        for s in self.samples:
            counts[s["label"]] += 1

        # Inverse frequency, normalized
        weights = 1.0 / (counts + 1e-6)
        weights = weights / weights.sum() * len(self.classes)
        return torch.FloatTensor(weights)

    def get_sampler(self) -> WeightedRandomSampler:
        """Create a weighted sampler for class-balanced training."""
        class_weights = self.get_class_weights()
        sample_weights = [class_weights[s["label"]].item() for s in self.samples]
        return WeightedRandomSampler(
            weights=sample_weights,
            num_samples=len(self.samples),
            replacement=True,
        )

    def summary(self) -> str:
        """Print dataset summary."""
        counts = {}
        sources = {}
        for s in self.samples:
            counts[s["label_name"]] = counts.get(s["label_name"], 0) + 1
            sources[s["source"]] = sources.get(s["source"], 0) + 1

        lines = [
            f"DriverDataset: {len(self.samples)} samples, split={self.split}",
            f"  Classes ({len(self.classes)}):"
        ]
        for cls in self.classes:
            n = counts.get(cls, 0)
            lines.append(f"    {cls}: {n}")
        lines.append(f"  Sources:")
        for src, n in sorted(sources.items()):
            lines.append(f"    {src}: {n}")
        return "\n".join(lines)


def create_dataloaders(
    manifest_path: str,
    classes: list[str],
    config: dict,
    data_root: str | None = None,
) -> dict[str, DataLoader]:
    """Create train/val/test dataloaders from a manifest."""
    import platform

    image_size = config.get("data", {}).get("image_size", 224)
    batch_size = config.get("training", {}).get("batch_size", 32)
    num_workers = config.get("data", {}).get("num_workers", 4)
    pin_memory = config.get("data", {}).get("pin_memory", True)

    # macOS: multiprocessing workers deadlock, and pin_memory isn't supported on MPS
    if platform.system() == "Darwin":
        num_workers = 0
        pin_memory = False

    aug_config = config.get("augmentation", {}).get("train", {})
    aug_config["normalize_mean"] = config.get("data", {}).get("normalize_mean", [0.485, 0.456, 0.406])
    aug_config["normalize_std"] = config.get("data", {}).get("normalize_std", [0.229, 0.224, 0.225])

    loaders = {}

    for split in ["train", "val", "test"]:
        try:
            ds = DriverDataset(
                manifest_path=manifest_path,
                classes=classes,
                split=split,
                image_size=image_size,
                data_root=data_root,
            )
        except ValueError:
            if split == "test":
                continue
            raise

        sampler = ds.get_sampler() if split == "train" else None

        loaders[split] = DataLoader(
            ds,
            batch_size=batch_size,
            shuffle=(split == "train" and sampler is None),
            sampler=sampler,
            num_workers=num_workers,
            pin_memory=pin_memory,
            drop_last=(split == "train"),
        )

        print(ds.summary())

    return loaders
