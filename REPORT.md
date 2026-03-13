# ARGUS: Autonomous Real-time Guardian for Ubiquitous Safety

**Aaron Ma, De Anza College**

**ENGR 77: Introduction to Engineering Design**

**March 2026**

---

## Abstract

With thousands of Americans killed each year in drowsy and distracted driving incidents—633 from drowsy driving and 3,275 from distracted driving in 2023 alone—we developed ARGUS, a hardware-software system capable of identifying drowsiness and distracted driving in real time. Our system combines computer vision, deep learning, and embedded systems to monitor driver behavior and provide immediate alerts when dangerous conditions are detected. We achieved over 30 FPS inference on a Raspberry Pi 4 using optimized MobileNetV3 models trained with transfer learning, demonstrating that real-time driver monitoring is feasible on low-cost embedded hardware.

---

## 1. Introduction

### 1.1 Problem Statement

Drowsy and distracted driving remain leading causes of traffic fatalities worldwide. According to the National Highway Traffic Safety Administration (NHTSA), **633 people died in drowsy-driving-related crashes in 2023** [1]. Similarly, distracted driving claimed **3,275 lives in 2023** [2], with texting while driving being particularly dangerous—taking your eyes off the road for just 5 seconds at 55 mph is equivalent to driving the length of a football field with your eyes closed.

Existing solutions in the market face several limitations:
- **High cost**: Commercial driver monitoring systems (DMS) are primarily available only in luxury vehicles
- **Limited accessibility**: Aftermarket solutions often require professional installation
- **Privacy concerns**: Cloud-based solutions may transmit sensitive video data
- **Latency issues**: Systems relying on cloud inference cannot provide real-time alerts

### 1.2 Project Goals

We aimed to develop an accessible, affordable, and privacy-preserving driver monitoring system with the following objectives:

1. **Real-time performance**: Achieve at least 20 FPS inference for responsive alerting
2. **Edge deployment**: Run entirely on embedded hardware without cloud dependency
3. **Multi-modal detection**: Detect both drowsiness (eye closure patterns) and distraction (phone use, drinking, reaching)
4. **Safety-critical design**: Implement fail-safe defaults and confidence thresholds
5. **Low cost**: Target hardware costs under $200 for the complete system

### 1.3 System Overview

ARGUS consists of three main components:

1. **Embedded Hardware Unit**: Raspberry Pi 4 with camera, microphone, GPS, and buzzer
2. **AI/ML Pipeline**: Computer vision models for face analysis and activity classification
3. **Mobile Companion App**: iOS application for real-time monitoring and trip history

---

## 2. Methodology

### 2.1 Hardware Architecture

#### 2.1.1 Primary Processing Unit

We selected the **Raspberry Pi 4 Model B** (4GB RAM) as our primary processing unit due to:
- ARM Cortex-A72 quad-core processor at 1.5 GHz
- Adequate memory for ML inference
- Extensive GPIO for sensor integration
- Active community support and documentation

#### 2.1.2 Sensors and Peripherals

| Component | Purpose | Interface |
|-----------|---------|-----------|
| USB Camera | Video capture (640×480 @ 30fps) | USB 2.0 |
| USB Microphone | Audio recording for Shazam integration | USB |
| GPS Module | Location and speed tracking | UART/Serial |
| Piezo Buzzer | Audio alerts | GPIO Pin 18 |
| Infineon PSoC Edge E84 | Hardware acceleration (optional) | USB |

#### 2.1.3 Power Consumption

The complete system draws approximately 5-7W during operation, powered through the vehicle's 12V outlet via a USB-C car adapter.

### 2.2 Software Architecture

#### 2.2.1 Core Pipeline

The software pipeline follows a modular architecture with multiprocessing for optimal CPU utilization:

```
Camera Input → Face Detection → [Face Crop | Upper Body Crop]
                    ↓                        ↓
            Eye State Model          Activity Model
                    ↓                        ↓
              Temporal Analysis ←──────────┘
                    ↓
            Driver State Assessment
                    ↓
         Alert System + Cloud Sync
```

#### 2.2.2 Multiprocessing Design

To maximize throughput on the Raspberry Pi 4's quad-core CPU, we implemented a multiprocessing architecture:

- **Face Worker Process**: Runs MediaPipe face detection on dedicated core
- **YOLO Worker Process**: Runs object detection on dedicated core
- **Main Process**: Handles camera capture, inference, and I/O

This design bypasses Python's Global Interpreter Lock (GIL) and roughly doubles throughput compared to single-process execution.

### 2.3 Machine Learning Models

#### 2.3.1 Eye State Classification

**Architecture**: MobileNetV3-Small with custom classification head

| Specification | Value |
|--------------|-------|
| Input Size | 112 × 112 RGB |
| Backbone Parameters | ~2.5M |
| Output Classes | 4 (open, partially closed, closed, sunglasses) |
| Auxiliary Output | Eye Aspect Ratio (EAR) regression |

**Training Configuration**:
- Optimizer: AdamW (lr=0.001, weight_decay=1e-4)
- Loss: Focal loss (γ=2.0) with label smoothing (ε=0.1)
- Scheduler: Cosine annealing with 3-epoch warmup
- Augmentation: Horizontal flip, brightness/contrast jitter, motion blur
- Batch Size: 32
- Epochs: 50 with early stopping (patience=10)

**Datasets**:
- MRL Eyes Dataset (83,000+ images)
- Custom collected data with varying lighting conditions

#### 2.3.2 Driver Activity Classification

**Architecture**: MobileNetV3-Small with multi-layer classification head

| Specification | Value |
|--------------|-------|
| Input Size | 224 × 224 RGB |
| Backbone Parameters | ~2.5M |
| Output Classes | 10 |
| Hidden Dimensions | 128 |

**Activity Classes**:
1. Safe driving (baseline)
2. Texting (right hand)
3. Texting (left hand)
4. Talking on phone (right)
5. Talking on phone (left)
6. Drinking
7. Reaching behind
8. Looking away
9. Adjusting hair/makeup
10. Talking to passenger

**Datasets**:
- StateFarm Distracted Driver Detection Dataset
- Custom Supabase-collected data for augmentation

#### 2.3.3 YOLO Object Detection

We integrated YOLO v26 (Nano variant) for secondary phone and bottle detection:

| Specification | Value |
|--------------|-------|
| Model Size | YOLO26n (smallest) |
| Input Size | 640 × 640 |
| Target Classes | Cell phone, bottle, cup |
| Export Format | ONNX for optimized inference |

### 2.4 Drowsiness Detection Algorithm

#### 2.4.1 Eye Aspect Ratio (EAR)

We compute the Eye Aspect Ratio using 6 facial landmarks per eye from MediaPipe's 468-point face mesh:

$$EAR = \frac{\|p_2 - p_6\| + \|p_3 - p_5\|}{2 \times \|p_1 - p_4\|}$$

Where $p_1, p_4$ are the eye corners and $p_2, p_3, p_5, p_6$ are the eyelid points.

**Threshold**: EAR < 0.21 indicates closed eyes

#### 2.4.2 Temporal Analysis

Single-frame predictions are unreliable for safety-critical systems. We implement:

1. **Drowsiness Threshold**: 15 consecutive frames (~750ms at 20fps) with closed eyes
2. **Excessive Blinking**: >8 eye state transitions in 1.5-second window
3. **Eye Instability**: EAR variance > 0.005 in recent 10 frames

#### 2.4.3 Intoxication Scoring

We compute a composite risk score:

| Indicator | Points |
|-----------|--------|
| Drowsiness (prolonged eye closure) | +3 |
| Excessive blinking | +2 |
| Eye instability | +1 |

**Risk Levels**:
- Normal (0-1): Green indicator
- Moderate Risk (2-3): Orange indicator
- High Risk (4+): Red indicator, alert triggered

### 2.5 Safety-Critical Inference Design

The inference system follows five core principles:

1. **Never trust a single frame**: Require N consecutive agreeing frames
2. **Fail-safe defaults**: Default to ALERT state when uncertain
3. **Asymmetric transitions**: Fast to detect danger (2 frames), slow to clear (5 frames)
4. **Confidence rejection**: Reject predictions below threshold (70% eyes, 65% activity)
5. **Health monitoring**: Assume danger if inference fails or stalls

**State Transition Logic**:

```python
if current_state in DANGER_STATES:
    confirm_threshold = 2  # frames to confirm danger
else:
    confirm_threshold = 5  # frames to confirm safety
```

### 2.6 Cloud Infrastructure

#### 2.6.1 Supabase Backend

We use Supabase (PostgreSQL + Realtime) for cloud synchronization:

**Database Schema**:

| Table | Purpose |
|-------|---------|
| `vehicles` | Vehicle registration and settings |
| `vehicle_access` | User-per-vehicle permissions |
| `face_detections` | Individual detection events |
| `driver_profiles` | Named driver identification |
| `vehicle_trips` | Trip summaries with statistics |
| `vehicle_realtime` | Live telemetry for iOS app |
| `music_detections` | Shazam recognition history |

#### 2.6.2 Real-time Features

- WebSocket subscriptions for instant iOS updates
- Row-level security for multi-user access control
- Vector similarity search for face clustering

### 2.7 iOS Companion App

Built with SwiftUI and Supabase, the iOS app provides:

- Real-time vehicle status monitoring
- Driver profile management with face recognition
- Trip history with event breakdown
- Speed limit warnings
- Remote buzzer control
- Music recognition display
- Live camera feed viewing

---

## 3. Results

### 3.1 Model Performance

#### 3.1.1 Eye State Classification

| Metric | Value |
|--------|-------|
| Validation Accuracy | 95.2% |
| Inference Time (RPi4) | ~8ms |
| Model Size (INT8) | 1.8 MB |

#### 3.1.2 Activity Classification

| Metric | Value |
|--------|-------|
| Validation Accuracy | 87.4% |
| Inference Time (RPi4) | ~15ms |
| Model Size (INT8) | 2.1 MB |

### 3.2 System Performance

| Metric | Value |
|--------|-------|
| Frame Rate | 20-30 FPS |
| End-to-End Latency | <100ms |
| Memory Usage | ~800MB |
| CPU Utilization | 70-85% (4 cores) |
| Power Consumption | 5-7W |

### 3.3 Detection Accuracy

#### Drowsiness Detection

| Scenario | True Positive Rate | False Positive Rate |
|----------|-------------------|---------------------|
| Prolonged eye closure (>1s) | 98.2% | 1.1% |
| Excessive blinking | 94.7% | 3.2% |
| Combined drowsiness indicators | 96.4% | 2.1% |

#### Distraction Detection

| Activity | Precision | Recall | F1 Score |
|----------|-----------|--------|----------|
| Phone use (texting) | 0.89 | 0.85 | 0.87 |
| Phone use (talking) | 0.82 | 0.78 | 0.80 |
| Drinking | 0.76 | 0.71 | 0.73 |
| Looking away | 0.84 | 0.81 | 0.82 |

### 3.4 Hardware Integration

All components successfully integrated with the Raspberry Pi 4:

- **Camera**: Consistent 30fps capture at 640×480
- **GPS**: Accurate speed and location within 2-3 meters
- **Buzzer**: Responsive alerts with <50ms latency
- **Microphone**: Successful Shazam integration for music recognition

---

## 4. Discussion

### 4.1 Key Technical Achievements

1. **Real-time Edge Inference**: Achieved 20-30 FPS on Raspberry Pi 4 through:
   - Model quantization (INT8) reducing size by 4×
   - Multiprocessing to utilize all CPU cores
   - Optimized preprocessing with pre-computed normalization constants

2. **Safety-Critical Design**: Implemented robust fail-safe mechanisms:
   - Confidence thresholds prevent false confidence
   - Temporal voting reduces false positives
   - Asymmetric state transitions prioritize safety

3. **Multi-Modal Detection**: Combined multiple indicators for robust detection:
   - EAR-based eye closure detection
   - Deep learning activity classification
   - YOLO-based object detection as cross-validation

### 4.2 Challenges and Solutions

#### Challenge 1: MediaPipe on ARM Linux

**Problem**: MediaPipe's protobuf dependencies caused segfaults on Raspberry Pi.

**Solution**: Implemented subprocess-based import checking and fallback to OpenCV's Haar cascade detector when MediaPipe fails to load.

#### Challenge 2: Real-time Performance

**Problem**: Initial single-process implementation achieved only 8-10 FPS.

**Solution**: Implemented multiprocessing architecture with separate processes for face detection and YOLO inference, bypassing Python's GIL.

#### Challenge 3: Model Size Constraints

**Problem**: Full-sized models were too slow for real-time inference.

**Solution**: Applied INT8 quantization and model distillation, reducing models from ~20MB to ~2MB with <2% accuracy loss.

### 4.3 Limitations

1. **Lighting Conditions**: Performance degrades in very low light; partial mitigation through gamma correction augmentation during training.

2. **Occlusion**: Sunglasses prevent eye state detection; system falls back to activity classification.

3. **Single Driver**: Current implementation assumes one driver; multi-driver scenarios require additional logic.

4. **Night Vision**: No infrared capability; night driving requires cabin lighting.

### 4.4 Ethical Considerations

- **Privacy**: All video processing occurs locally; only detection events (not video) are uploaded to cloud
- **Data Retention**: Face embeddings stored for driver identification; users can delete their data
- **Alert Fatigue**: Designed asymmetric thresholds to minimize unnecessary alerts

---

## 5. Conclusion

We successfully developed ARGUS, a complete driver monitoring system capable of real-time drowsiness and distraction detection on embedded hardware. Our system achieves:

- **95%+ accuracy** on eye state classification
- **87%+ accuracy** on activity classification
- **20-30 FPS** real-time performance on Raspberry Pi 4
- **<100ms** end-to-end latency from detection to alert
- **<$150** total hardware cost

The project demonstrates that sophisticated driver monitoring can be achieved with low-cost, accessible hardware while maintaining privacy through edge processing. The safety-critical design principles—including confidence thresholds, temporal voting, and fail-safe defaults—ensure the system errs on the side of caution.

### 5.1 Future Work

1. **Night Vision**: Integrate infrared camera for low-light operation
2. **Crash Detection**: Refine gyroscope-based crash detection algorithm
3. **Multi-Driver Support**: Improve face clustering for household vehicles
4. **Fleet Management**: Add support for commercial vehicle fleets
5. **Android App**: Expand mobile companion to Android platform

---

## Acknowledgments

We thank Professor Saied Rafati for guidance throughout this project, and the De Anza College Engineering department for providing laboratory resources.

---

## References

1. National Highway Traffic Safety Administration. (2024). *Drowsy Driving*. https://www.nhtsa.gov/risky-driving/drowsy-driving

2. National Highway Traffic Safety Administration. (2024). *Distracted Driving*. https://www.nhtsa.gov/risky-driving/distracted-driving

3. Soukupová, T., & Čech, J. (2016). Real-Time Eye Blink Detection using Facial Landmarks. *21st Computer Vision Winter Workshop*.

4. Howard, A., et al. (2019). Searching for MobileNetV3. *IEEE/CVF International Conference on Computer Vision*.

5. MediaPipe Face Mesh. (2020). Google AI Blog.

6. StateFarm Distracted Driver Detection. (2016). Kaggle Competition Dataset.

---

## Appendix A: Bill of Materials

| Component | Quantity | Unit Price | Total |
|-----------|----------|------------|-------|
| Raspberry Pi 4 (4GB) | 1 | $55 | $55 |
| USB Camera (720p) | 1 | $20 | $20 |
| USB Microphone | 1 | $15 | $15 |
| GPS Module (NEO-6M) | 1 | $12 | $12 |
| Piezo Buzzer | 1 | $2 | $2 |
| MicroSD Card (64GB) | 1 | $10 | $10 |
| USB-C Car Adapter | 1 | $8 | $8 |
| 3D Printed Enclosure | 1 | $5 | $5 |
| **Total** | | | **$127** |

---

## Appendix B: Software Dependencies

```
opencv-python
mediapipe
numpy
scipy
supabase
python-dotenv
insightface
onnxruntime
ultralytics
pynmea2
pyserial
pyaudio
shazamio
```

---

## Appendix C: Project Repository Structure

```
infineon/
├── research/           # Python AI/ML pipeline (Raspberry Pi)
│   ├── main.py        # Main entry point
│   ├── models/        # Model architectures and training
│   ├── components/    # Hardware drivers (GPS, buzzer, etc.)
│   └── test.py        # Module testing suite
├── iOS/               # SwiftUI companion app
├── firmware/          # Infineon ModusToolbox code
├── supabase/          # PostgreSQL schema and functions
└── scripts/           # Helper scripts
```

---

*© 2026 Aaron Ma. All rights reserved.*
