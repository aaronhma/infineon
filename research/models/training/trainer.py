"""Training loop for driver awareness models.

Handles: mixed precision, gradient accumulation, backbone freeze/unfreeze,
early stopping, checkpointing, TensorBoard logging, and mixup/cutmix
augmentation for maximum accuracy on safety-critical tasks.
"""

import time
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader
from torch.utils.tensorboard import SummaryWriter
from tqdm import tqdm

from ..architectures.backbone import freeze_backbone, unfreeze_backbone, count_parameters


def mixup_data(x: torch.Tensor, y: torch.Tensor, alpha: float = 0.2) -> tuple:
    """Mixup: blend two random samples and their labels.

    Produces softer decision boundaries and prevents overconfident predictions.
    Critical for safety-critical models where overconfidence = false sense of security.
    """
    if alpha <= 0:
        return x, y, y, 1.0

    lam = np.random.beta(alpha, alpha)
    batch_size = x.size(0)
    index = torch.randperm(batch_size, device=x.device)

    mixed_x = lam * x + (1 - lam) * x[index]
    return mixed_x, y, y[index], lam


def mixup_criterion(loss_fn, pred, y_a, y_b, lam):
    """Compute loss for mixup-blended samples."""
    if isinstance(loss_fn(pred, y_a), dict):
        # Multi-task loss -- only apply to classification
        loss_a = loss_fn(pred, y_a)
        loss_b = loss_fn(pred, y_b)
        return {"total": lam * loss_a["total"] + (1 - lam) * loss_b["total"]}
    return lam * loss_fn(pred, y_a) + (1 - lam) * loss_fn(pred, y_b)


class Trainer:
    def __init__(
        self,
        model: nn.Module,
        train_loader: DataLoader,
        val_loader: DataLoader,
        config: dict,
        task: str = "driver_activity",
        device: str = "cpu",
    ):
        self.model = model.to(device)
        self.train_loader = train_loader
        self.val_loader = val_loader
        self.config = config
        self.task = task
        self.device = device

        t_cfg = config.get("training", {})
        self.epochs = t_cfg.get("epochs", 50)
        self.lr = t_cfg.get("learning_rate", 0.001)
        self.weight_decay = t_cfg.get("weight_decay", 1e-4)
        self.warmup_epochs = t_cfg.get("warmup_epochs", 3)
        self.patience = t_cfg.get("early_stopping_patience", 10)
        # GradScaler only works on CUDA; autocast works on both CUDA and MPS
        self.use_amp = t_cfg.get("mixed_precision", True) and device == "cuda"
        self.use_autocast = t_cfg.get("mixed_precision", True) and device != "cpu"
        self.grad_accum_steps = t_cfg.get("gradient_accumulation_steps", 1)
        self.freeze_epochs = config.get("backbone", {}).get("freeze_epochs", 5)
        self.use_mixup = t_cfg.get("mixup_alpha", 0.0) > 0
        self.mixup_alpha = t_cfg.get("mixup_alpha", 0.2)

        # Optimizer
        optimizer_name = t_cfg.get("optimizer", "adamw")
        if optimizer_name == "adamw":
            self.optimizer = torch.optim.AdamW(
                model.parameters(), lr=self.lr, weight_decay=self.weight_decay
            )
        else:
            self.optimizer = torch.optim.SGD(
                model.parameters(), lr=self.lr, momentum=0.9, weight_decay=self.weight_decay
            )

        # Scheduler
        scheduler_name = t_cfg.get("scheduler", "cosine")
        if scheduler_name == "cosine":
            self.scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(
                self.optimizer, T_max=self.epochs - self.warmup_epochs
            )
        else:
            self.scheduler = torch.optim.lr_scheduler.StepLR(
                self.optimizer, step_size=10, gamma=0.1
            )

        # AMP -- GradScaler is CUDA-only
        self.scaler = torch.amp.GradScaler(device=device, enabled=self.use_amp)

        # Logging
        log_dir = config.get("logging", {}).get("log_dir", "models/logs")
        self.writer = SummaryWriter(log_dir=f"{log_dir}/{task}_{int(time.time())}")
        self.log_every = config.get("logging", {}).get("log_every_n_steps", 10)

        # Checkpointing
        self.save_dir = Path(config.get("checkpointing", {}).get("save_dir", "models/checkpoints"))
        self.save_dir.mkdir(parents=True, exist_ok=True)
        self.save_top_k = config.get("logging", {}).get("save_top_k", 3)

        # State
        self.best_val_acc = 0.0
        self.best_val_loss = float("inf")
        self.epochs_without_improvement = 0
        self.global_step = 0

    def train(self, loss_fn: nn.Module) -> dict:
        """Run the full training loop."""
        params = count_parameters(self.model)
        print(f"\nModel: {params['total']:,} params ({params['total_mb']:.1f} MB)")
        print(f"Trainable: {params['trainable']:,} | Frozen: {params['frozen']:,}")
        print(f"Device: {self.device} | Autocast: {self.use_autocast} | GradScaler: {self.use_amp}")
        print(f"Epochs: {self.epochs} | LR: {self.lr} | Patience: {self.patience}")
        print(f"Backbone frozen for first {self.freeze_epochs} epochs\n")

        # Freeze backbone initially
        if self.freeze_epochs > 0 and hasattr(self.model, "backbone"):
            freeze_backbone(self.model.backbone)
            print("Backbone frozen for transfer learning warm-up")

        history = {"train_loss": [], "val_loss": [], "val_acc": []}

        for epoch in range(self.epochs):
            # Unfreeze backbone after warm-up
            if epoch == self.freeze_epochs and hasattr(self.model, "backbone"):
                unfreeze_backbone(self.model.backbone)
                print(f"\nEpoch {epoch}: Backbone unfrozen")
                params = count_parameters(self.model)
                print(f"  Trainable params: {params['trainable']:,}")

            # Warmup LR
            if epoch < self.warmup_epochs:
                warmup_lr = self.lr * (epoch + 1) / self.warmup_epochs
                for pg in self.optimizer.param_groups:
                    pg["lr"] = warmup_lr

            # Train epoch
            train_loss = self._train_epoch(loss_fn, epoch)

            # Validate
            val_loss, val_acc = self._validate(loss_fn, epoch)

            # Step scheduler after warmup
            if epoch >= self.warmup_epochs:
                self.scheduler.step()

            current_lr = self.optimizer.param_groups[0]["lr"]
            history["train_loss"].append(train_loss)
            history["val_loss"].append(val_loss)
            history["val_acc"].append(val_acc)

            print(
                f"Epoch {epoch+1}/{self.epochs} | "
                f"Train Loss: {train_loss:.4f} | "
                f"Val Loss: {val_loss:.4f} | "
                f"Val Acc: {val_acc:.2%} | "
                f"LR: {current_lr:.6f}"
            )

            # Checkpointing
            improved = False
            if val_acc > self.best_val_acc:
                self.best_val_acc = val_acc
                self._save_checkpoint(epoch, val_acc, val_loss, tag="best_acc")
                improved = True

            if val_loss < self.best_val_loss:
                self.best_val_loss = val_loss
                self._save_checkpoint(epoch, val_acc, val_loss, tag="best_loss")
                improved = True

            if improved:
                self.epochs_without_improvement = 0
            else:
                self.epochs_without_improvement += 1

            # Early stopping
            if self.epochs_without_improvement >= self.patience:
                print(f"\nEarly stopping after {epoch+1} epochs (no improvement for {self.patience})")
                break

        self.writer.close()
        print(f"\nTraining complete. Best val acc: {self.best_val_acc:.2%}")
        print(f"Checkpoints saved to: {self.save_dir}")

        return history

    def _train_epoch(self, loss_fn: nn.Module, epoch: int) -> float:
        self.model.train()
        total_loss = 0.0
        n_batches = 0

        self.optimizer.zero_grad()

        # Autocast device type: MPS autocast uses "mps", CUDA uses "cuda"
        autocast_dtype = self.device if self.device in ("cuda", "mps") else "cpu"

        pbar = tqdm(
            self.train_loader,
            desc=f"  Train {epoch+1}/{self.epochs}",
            leave=False,
            unit="batch",
        )

        for batch_idx, (images, targets) in enumerate(pbar):
            images = images.to(self.device)
            targets = targets.to(self.device)

            # Apply mixup augmentation (blends pairs of samples)
            if self.use_mixup:
                images, targets_a, targets_b, lam = mixup_data(images, targets, self.mixup_alpha)
            else:
                targets_a = targets_b = targets
                lam = 1.0

            with torch.autocast(device_type=autocast_dtype, enabled=self.use_autocast):
                if self.task == "eye_state":
                    class_logits, ear_pred = self.model(images)
                    if self.use_mixup:
                        loss_a = loss_fn(class_logits, ear_pred, targets_a)
                        loss_b = loss_fn(class_logits, ear_pred, targets_b)
                        total_a = loss_a["total"] if isinstance(loss_a, dict) else loss_a
                        total_b = loss_b["total"] if isinstance(loss_b, dict) else loss_b
                        loss = lam * total_a + (1 - lam) * total_b
                    else:
                        loss_dict = loss_fn(class_logits, ear_pred, targets)
                        loss = loss_dict["total"] if isinstance(loss_dict, dict) else loss_dict
                else:
                    logits = self.model(images)
                    if self.use_mixup:
                        loss = lam * loss_fn(logits, targets_a) + (1 - lam) * loss_fn(logits, targets_b)
                    else:
                        loss = loss_fn(logits, targets)

                loss = loss / self.grad_accum_steps

            # GradScaler only active on CUDA; on MPS/CPU this is a passthrough
            self.scaler.scale(loss).backward()

            if (batch_idx + 1) % self.grad_accum_steps == 0:
                self.scaler.step(self.optimizer)
                self.scaler.update()
                self.optimizer.zero_grad()

            batch_loss = loss.item() * self.grad_accum_steps
            total_loss += batch_loss
            n_batches += 1
            self.global_step += 1

            pbar.set_postfix(loss=f"{batch_loss:.4f}")

            if self.global_step % self.log_every == 0:
                self.writer.add_scalar("train/loss", batch_loss, self.global_step)
                self.writer.add_scalar("train/lr", self.optimizer.param_groups[0]["lr"], self.global_step)

        pbar.close()
        return total_loss / max(n_batches, 1)

    @torch.no_grad()
    def _validate(self, loss_fn: nn.Module, epoch: int) -> tuple[float, float]:
        self.model.eval()
        total_loss = 0.0
        correct = 0
        total = 0

        pbar = tqdm(
            self.val_loader,
            desc=f"  Val   {epoch+1}/{self.epochs}",
            leave=False,
            unit="batch",
        )

        for images, targets in pbar:
            images = images.to(self.device)
            targets = targets.to(self.device)

            if self.task == "eye_state":
                class_logits, ear_pred = self.model(images)
                loss_dict = loss_fn(class_logits, ear_pred, targets)
                loss = loss_dict["total"] if isinstance(loss_dict, dict) else loss_dict
                preds = class_logits.argmax(dim=-1)
            else:
                logits = self.model(images)
                loss = loss_fn(logits, targets)
                preds = logits.argmax(dim=-1)

            total_loss += loss.item()
            correct += (preds == targets).sum().item()
            total += targets.size(0)

            acc_so_far = correct / max(total, 1)
            pbar.set_postfix(acc=f"{acc_so_far:.2%}")

        pbar.close()

        avg_loss = total_loss / max(len(self.val_loader), 1)
        accuracy = correct / max(total, 1)

        self.writer.add_scalar("val/loss", avg_loss, epoch)
        self.writer.add_scalar("val/accuracy", accuracy, epoch)

        return avg_loss, accuracy

    def _save_checkpoint(self, epoch: int, val_acc: float, val_loss: float, tag: str) -> None:
        checkpoint = {
            "epoch": epoch,
            "model_state_dict": self.model.state_dict(),
            "optimizer_state_dict": self.optimizer.state_dict(),
            "scheduler_state_dict": self.scheduler.state_dict(),
            "val_acc": val_acc,
            "val_loss": val_loss,
            "config": self.config,
            "task": self.task,
        }
        # Include backbone name to prevent teacher/student checkpoint collisions
        backbone_name = self.config.get("model", {}).get("backbone", "")
        if "teacher" in backbone_name or "efficientnet" in backbone_name:
            prefix = f"{self.task}_teacher"
        else:
            prefix = self.task
        path = self.save_dir / f"{prefix}_{tag}.pt"
        torch.save(checkpoint, path)

    @staticmethod
    def load_checkpoint(path: str, model: nn.Module, device: str = "cpu") -> dict:
        """Load a checkpoint and restore model weights."""
        checkpoint = torch.load(path, map_location=device, weights_only=False)
        model.load_state_dict(checkpoint["model_state_dict"])
        return checkpoint
