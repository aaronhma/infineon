# Driver Awareness Custom Models

Custom fine-tuned models for driver awareness detection. Replaces MediaPipe + YOLO with purpose-built classifiers optimized for Raspberry Pi 4 deployment.

## Safety-Critical Design

This is a safety-critical system. The design prioritizes **never missing a danger state** over avoiding false alarms.

- **Confidence thresholds** -- low-confidence predictions are rejected and treated as danger
- **Asymmetric temporal voting** -- 2 frames to trigger alert, 5 frames to clear it
- **Fail-safe defaults** -- if the model is uncertain or inference stalls, assume danger
- **Knowledge distillation** -- maximum accuracy squeezed from small models via teacher-student training

## Models

| Model | Input | Params | Size (INT8) | RPi4 Latency (INT8) |
|-------|-------|--------|-------------|---------------------|
| Eye State (TinyConvNet) | 112x112 | 44K | ~0.05 MB | ~3-5ms |
| Eye State (MobileNetV3) | 112x112 | 966K | ~1 MB | ~10-15ms |
| Activity (TinyConvNet) | 224x224 | 53K | ~0.06 MB | ~5-8ms |
| Activity (MobileNetV3) | 224x224 | 1M | ~1 MB | ~12-18ms |

**Recommended for RPi4**: MobileNetV3-Small with INT8 quantization. Both models combined: ~20-30ms per frame (30-50 FPS).

## Training Workflow

>[!WARNING]
> Run this in the `research` folder, not inside `models`!

>[!NOTE]
> Download the dataset ahead of time, as it is 4GB in size and can take a few minutes on slow networks.

```bash
# 1. Install dependencies
uv pip install -r models/requirements.txt

# on NVIDIA GPU:
uv pip uninstall torch torchvision

# run `nvidia-smi` to see your CUDA version
uv pip install torch torchvision --index-url https://download.pytorch.org/whl/cu130

# 2. Download and prepare dataset
uv run python -m models.datasets.download --dataset statefarm
uv run python -m models.datasets.prepare_statefarm

# make sure prepare_statefarm script prints out the manifest:
# `/home/aaronma/Desktop/infineon/research/models/data/processed/statefarm/manifest.csv`

# 3. Train teacher model (larger, more accurate)
uv run python -m models.training.train \
    --config models/configs/driver_activity_teacher.yaml --device mps # or `cuda` on NVIDIA GPUs

# 4. Distill into student (smaller, faster, deployed)
uv run python -m models.training.distillation \
    --teacher-checkpoint models/checkpoints/driver_activity_teacher_best_acc.pt \
    --config models/configs/driver_activity.yaml --device mps # or `cuda` on NVIDIA GPUs

# 5. Export with INT8 quantization for RPi4
uv run python -m models.export.to_quantized \
    --checkpoint models/checkpoints/driver_activity_distilled_best_acc.pt \
    --config models/configs/driver_activity.yaml

# 6. Validate export matches PyTorch
uv run python -m models.export.validate_export \
    --checkpoint models/checkpoints/driver_activity_distilled_best_acc.pt \
    --onnx models/checkpoints/driver_activity_int8_dynamic.onnx \
    --config models/configs/driver_activity.yaml

# 7. Benchmark on RPi4
uv run python -m models.evaluation.benchmark \
    --all-formats --config models/configs/driver_activity.yaml \
    --include-preprocessing
```

```bash
# 1. Download MRL Eyes dataset (~85K eye images)
uv run python -m models.datasets.download --dataset mrl_eyes

# 2. Prepare manifest (splits by subject to prevent data leakage)
uv run python -m models.datasets.prepare_mrl_eyes

# 3. Train eye state teacher (EfficientNet-B0)
uv run python -m models.training.train --config \
    models/configs/eye_state_teacher.yaml --device mps # or `cuda` on NVIDIA GPUs

# 4. Distill into student (MobileNetV3-Small)
uv run python -m models.training.distillation \
    --teacher-checkpoint models/checkpoints/eye_state_teacher_best_acc.pt \
    --config models/configs/eye_state.yaml --device mps # or `cuda` on NVIDIA GPUs

# 5. Export + quantize student
uv run python -m models.export.to_quantized \
    --checkpoint models/checkpoints/eye_state_distilled_best_acc.pt \
    --config models/configs/eye_state.yaml

# 6. Validate
uv run python -m models.export.validate_export \
    --checkpoint models/checkpoints/eye_state_distilled_best_acc.pt \
    --onnx models/checkpoints/eye_state_distilled_int8_dynamic.onnx \
    --config models/configs/eye_state.yaml
```

## Using in Production (main.py)

```python
from models.inference import DriverAwarenessSystem, SafetyConfig

system = DriverAwarenessSystem(
    eye_model_path="models/checkpoints/eye_state_int8_dynamic.onnx",
    activity_model_path="models/checkpoints/driver_activity_int8_dynamic.onnx",
    config=SafetyConfig(
        eye_confidence_threshold=0.70,     # reject uncertain predictions
        frames_to_confirm_danger=2,        # 2 frames to trigger alert
        frames_to_confirm_safe=5,          # 5 frames to clear alert
        drowsy_frame_threshold=15,         # ~750ms eyes closed = drowsy
    ),
)

# In camera loop:
result = system.process_frame(face_crop, upper_body_crop)
# result["driver_state"]       -> "alert" | "drowsy" | "distracted_phone" | ...
# result["is_safe"]            -> True/False
# result["is_phone_detected"]  -> bool (compatible with existing Supabase schema)
# result["intoxication_score"] -> 0-6 (compatible with existing scoring)
# result["inference_time_ms"]  -> total processing time
```

## Directory Structure

```
models/
├── inference.py           # Safety-critical inference wrapper (THE important file)
├── configs/               # YAML experiment configs (base, student, teacher)
├── datasets/              # Dataset download, preparation, PyTorch Dataset
├── architectures/         # Backbones (Tiny, MobileNetV3, EfficientNet) + model heads
├── training/              # Training loop, losses, knowledge distillation
├── evaluation/            # Metrics, evaluation, speed benchmarking
├── export/                # ONNX, INT8 quantization, CoreML, validation
├── checkpoints/           # Saved model weights (gitignored)
├── logs/                  # TensorBoard logs (gitignored)
└── data/                  # Downloaded datasets (gitignored)
```

## Datasets

| Dataset | Task | Size | Download |
|---------|------|------|----------|
| StateFarm Distracted Driver | Activity | ~22K images | `--dataset statefarm` |
| MRL Eye Dataset | Eye State | ~85K images | `--dataset mrl_eyes` |
| Custom (Supabase) | Both | Varies | `uv run python -m models.datasets.prepare_custom` |
