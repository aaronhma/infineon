"""Knowledge distillation for maximum accuracy in small models.

Train a large "teacher" model (EfficientNet-B0, ~5M params), then
transfer its knowledge into a small "student" (MobileNetV3-Small or
TinyConvNet). The student learns from the teacher's soft probability
distribution, which contains richer information than hard labels.

This typically gives 2-5% accuracy improvement over training the
student from scratch, which matters for safety-critical applications.

Usage:
    # Step 1: Train teacher (larger, slower, more accurate)
    uv run python -m models.training.train --config models/configs/driver_activity_teacher.yaml

    # Step 2: Distill into student (smaller, faster, deployed on RPi4)
    uv run python -m models.training.distillation \
        --teacher-checkpoint models/checkpoints/driver_activity_teacher_best_acc.pt \
        --config models/configs/driver_activity.yaml \
        --device mps
"""

import argparse
import sys
import time
from pathlib import Path

import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.utils.data import DataLoader
from torch.utils.tensorboard import SummaryWriter
from tqdm import tqdm

from ..architectures.backbone import (
    count_parameters,
    freeze_backbone,
    unfreeze_backbone,
)
from ..configs import load_config
from ..datasets.dataset import create_dataloaders
from .train import build_model, detect_device


class DistillationLoss(nn.Module):
    """Combined hard label + soft teacher loss.

    L = alpha * KL(student_soft || teacher_soft) * T^2 + (1-alpha) * CE(student, labels)

    Temperature T controls how "soft" the teacher's distribution is:
        - T=1: normal softmax (hard)
        - T=3-5: softer, reveals inter-class relationships
        - T>10: too soft, loses discriminative power

    alpha balances teacher vs label supervision:
        - alpha=0.7: mostly learn from teacher (recommended)
        - alpha=0.5: equal weight
        - alpha=0.3: mostly learn from hard labels
    """

    def __init__(self, temperature: float = 4.0, alpha: float = 0.7):
        super().__init__()
        self.temperature = temperature
        self.alpha = alpha
        self.ce_loss = nn.CrossEntropyLoss()

    def forward(
        self,
        student_logits: torch.Tensor,
        teacher_logits: torch.Tensor,
        targets: torch.Tensor,
    ) -> dict[str, torch.Tensor]:
        # Soft targets from teacher
        teacher_soft = F.softmax(teacher_logits / self.temperature, dim=-1)
        student_soft = F.log_softmax(student_logits / self.temperature, dim=-1)

        # KL divergence (teacher -> student), scaled by T^2
        distill_loss = F.kl_div(student_soft, teacher_soft, reduction="batchmean") * (
            self.temperature**2
        )

        # Hard label loss
        hard_loss = self.ce_loss(student_logits, targets)

        # Combined
        total = self.alpha * distill_loss + (1 - self.alpha) * hard_loss

        return {
            "total": total,
            "distill_loss": distill_loss,
            "hard_loss": hard_loss,
        }


class DistillationTrainer:
    """Train a student model using knowledge distillation from a teacher."""

    def __init__(
        self,
        teacher: nn.Module,
        student: nn.Module,
        train_loader: DataLoader,
        val_loader: DataLoader,
        config: dict,
        task: str,
        device: str,
        temperature: float = 4.0,
        alpha: float = 0.7,
    ):
        self.teacher = teacher.to(device).eval()
        self.student = student.to(device)
        self.train_loader = train_loader
        self.val_loader = val_loader
        self.config = config
        self.task = task
        self.device = device

        # Freeze teacher -- never updated
        for p in self.teacher.parameters():
            p.requires_grad = False

        t_cfg = config.get("training", {})
        self.epochs = t_cfg.get("epochs", 50)
        self.lr = t_cfg.get("learning_rate", 0.001)
        self.patience = t_cfg.get("early_stopping_patience", 10)
        self.freeze_epochs = config.get("backbone", {}).get("freeze_epochs", 5)

        self.optimizer = torch.optim.AdamW(
            self.student.parameters(),
            lr=self.lr,
            weight_decay=t_cfg.get("weight_decay", 1e-4),
        )
        self.scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(
            self.optimizer, T_max=self.epochs
        )

        self.loss_fn = DistillationLoss(temperature=temperature, alpha=alpha)

        save_dir = Path(
            config.get("checkpointing", {}).get("save_dir", "models/checkpoints")
        )
        save_dir.mkdir(parents=True, exist_ok=True)
        self.save_dir = save_dir

        log_dir = config.get("logging", {}).get("log_dir", "models/logs")
        self.writer = SummaryWriter(f"{log_dir}/{task}_distill_{int(time.time())}")

        self.best_val_acc = 0.0
        self.epochs_no_improve = 0

    def train(self) -> dict:
        """Run knowledge distillation training."""
        teacher_params = count_parameters(self.teacher)
        student_params = count_parameters(self.student)

        print(f"\nKnowledge Distillation")
        print(
            f"  Teacher: {teacher_params['total']:,} params ({teacher_params['total_mb']:.1f} MB)"
        )
        print(
            f"  Student: {student_params['total']:,} params ({student_params['total_mb']:.1f} MB)"
        )
        print(
            f"  Compression: {teacher_params['total'] / student_params['total']:.1f}x fewer params"
        )
        print(
            f"  Temperature: {self.loss_fn.temperature} | Alpha: {self.loss_fn.alpha}"
        )
        print()

        # Freeze student backbone initially
        if self.freeze_epochs > 0 and hasattr(self.student, "backbone"):
            freeze_backbone(self.student.backbone)

        history = {"train_loss": [], "val_loss": [], "val_acc": []}

        for epoch in range(self.epochs):
            if epoch == self.freeze_epochs and hasattr(self.student, "backbone"):
                unfreeze_backbone(self.student.backbone)
                print(f"Epoch {epoch}: Student backbone unfrozen")

            train_loss = self._train_epoch(epoch)
            val_loss, val_acc = self._validate(epoch)

            self.scheduler.step()
            lr = self.optimizer.param_groups[0]["lr"]

            history["train_loss"].append(train_loss)
            history["val_loss"].append(val_loss)
            history["val_acc"].append(val_acc)

            print(
                f"Epoch {epoch + 1}/{self.epochs} | "
                f"Train: {train_loss:.4f} | "
                f"Val: {val_loss:.4f} | "
                f"Acc: {val_acc:.2%} | "
                f"LR: {lr:.6f}"
            )

            if val_acc > self.best_val_acc:
                self.best_val_acc = val_acc
                self._save_checkpoint(epoch, val_acc, val_loss)
                self.epochs_no_improve = 0
            else:
                self.epochs_no_improve += 1

            if self.epochs_no_improve >= self.patience:
                print(f"\nEarly stopping at epoch {epoch + 1}")
                break

        self.writer.close()
        print(f"\nDistillation complete. Best val acc: {self.best_val_acc:.2%}")
        return history

    def _train_epoch(self, epoch: int) -> float:
        self.student.train()
        total_loss = 0.0
        n = 0

        pbar = tqdm(
            self.train_loader,
            desc=f"  Train {epoch + 1}/{self.epochs}",
            leave=False,
            unit="batch",
        )

        for images, targets in pbar:
            images = images.to(self.device)
            targets = targets.to(self.device)

            # Get teacher predictions (no grad)
            with torch.no_grad():
                if self.task == "eye_state":
                    teacher_logits, _ = self.teacher(images)
                else:
                    teacher_logits = self.teacher(images)

            # Get student predictions
            if self.task == "eye_state":
                student_logits, _ = self.student(images)
            else:
                student_logits = self.student(images)

            loss_dict = self.loss_fn(student_logits, teacher_logits, targets)
            loss = loss_dict["total"]

            self.optimizer.zero_grad()
            loss.backward()
            self.optimizer.step()

            total_loss += loss.item()
            n += 1
            pbar.set_postfix(loss=f"{loss.item():.4f}")

        pbar.close()
        avg = total_loss / max(n, 1)
        self.writer.add_scalar("distill/train_loss", avg, epoch)
        return avg

    @torch.no_grad()
    def _validate(self, epoch: int) -> tuple[float, float]:
        self.student.eval()
        total_loss = 0.0
        correct = 0
        total = 0

        pbar = tqdm(
            self.val_loader,
            desc=f"  Val   {epoch + 1}/{self.epochs}",
            leave=False,
            unit="batch",
        )

        for images, targets in pbar:
            images = images.to(self.device)
            targets = targets.to(self.device)

            if self.task == "eye_state":
                student_logits, _ = self.student(images)
                teacher_logits, _ = self.teacher(images)
            else:
                student_logits = self.student(images)
                teacher_logits = self.teacher(images)

            loss_dict = self.loss_fn(student_logits, teacher_logits, targets)
            total_loss += loss_dict["total"].item()

            preds = student_logits.argmax(dim=-1)
            correct += (preds == targets).sum().item()
            total += targets.size(0)

            acc_so_far = correct / max(total, 1)
            pbar.set_postfix(acc=f"{acc_so_far:.2%}")

        pbar.close()

        avg_loss = total_loss / max(len(self.val_loader), 1)
        accuracy = correct / max(total, 1)

        self.writer.add_scalar("distill/val_loss", avg_loss, epoch)
        self.writer.add_scalar("distill/val_accuracy", accuracy, epoch)

        return avg_loss, accuracy

    def _save_checkpoint(self, epoch: int, val_acc: float, val_loss: float) -> None:
        torch.save(
            {
                "epoch": epoch,
                "model_state_dict": self.student.state_dict(),
                "val_acc": val_acc,
                "val_loss": val_loss,
                "config": self.config,
                "task": self.task,
                "distilled": True,
            },
            self.save_dir / f"{self.task}_distilled_best_acc.pt",
        )


def main():
    parser = argparse.ArgumentParser(description="Knowledge distillation training")
    parser.add_argument(
        "--teacher-checkpoint", type=str, required=True, help="Teacher model checkpoint"
    )
    parser.add_argument(
        "--teacher-config",
        type=str,
        default=None,
        help="Teacher config (defaults to student config with efficientnet_b0 backbone)",
    )
    parser.add_argument("--config", type=str, required=True, help="Student config")
    parser.add_argument("--manifest", type=str, default=None)
    parser.add_argument("--device", type=str, default="auto")
    parser.add_argument("--temperature", type=float, default=4.0)
    parser.add_argument("--alpha", type=float, default=0.7)
    args = parser.parse_args()

    config = load_config(args.config)
    task = config["task"]
    classes = config["classes"]
    device = detect_device(args.device)

    # Build student (small model from config)
    student = build_model(config)

    # Build teacher (load from checkpoint)
    ckpt = torch.load(args.teacher_checkpoint, map_location=device, weights_only=False)

    if args.teacher_config:
        teacher_config = load_config(args.teacher_config)
    elif "config" in ckpt:
        # Use the config saved inside the checkpoint -- guarantees architecture match
        teacher_config = ckpt["config"]
    else:
        # Last resort: copy student config and guess teacher settings
        teacher_config = config.copy()
        teacher_config["model"] = teacher_config.get("model", {}).copy()
        teacher_config["model"]["backbone"] = "efficientnet_b0"
        teacher_config["model"]["hidden_dim"] = 256

    teacher = build_model(teacher_config)
    teacher.load_state_dict(ckpt["model_state_dict"])
    print(f"Teacher loaded from: {args.teacher_checkpoint}")
    print(f"  Teacher val acc: {ckpt.get('val_acc', 'N/A')}")

    # Load data
    manifest = args.manifest
    if not manifest:
        data_dir = Path("models/data/processed")
        for name in [task, "statefarm", "mrl_eyes"]:
            candidate = data_dir / name / "manifest.csv"
            if candidate.exists():
                manifest = str(candidate)
                break

    if not manifest:
        print("Error: No manifest found. Specify with --manifest")
        sys.exit(1)

    loaders = create_dataloaders(manifest, classes, config)

    # Distill
    trainer = DistillationTrainer(
        teacher=teacher,
        student=student,
        train_loader=loaders["train"],
        val_loader=loaders["val"],
        config=config,
        task=task,
        device=device,
        temperature=args.temperature,
        alpha=args.alpha,
    )

    trainer.train()


if __name__ == "__main__":
    main()
