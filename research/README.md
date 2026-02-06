# Infineon - AI-Powered Face & Eye Analysis

Advanced face detection system with real-time eye state monitoring and intoxication detection using AI models.

## Features

### Face Detection
- Real-time face detection with bounding rectangles
- Supports multiple faces simultaneously (up to 5)
- High-accuracy facial landmark detection using MediaPipe

### Eye State Detection
- Detects if eyes are OPEN or CLOSED in real-time
- Uses Eye Aspect Ratio (EAR) algorithm for precise detection
- Displays EAR values for both left and right eyes

### Intoxication Detection
The system uses multiple AI-based indicators to assess intoxication risk:

1. **Drowsiness Detection**: Monitors prolonged eye closure
2. **Excessive Blinking**: Tracks abnormal blinking patterns
3. **Eye Instability**: Analyzes eye movement variance

**Risk Levels:**
- NORMAL - ALERT (Green): No indicators detected
- MODERATE RISK - IMPAIRED (Orange): Some indicators present
- HIGH RISK - INTOXICATED (Red): Multiple indicators detected

### Settings Menu & Camera Zoom
- Interactive settings menu with keyboard controls
- Digital zoom from 0.5x to 10x magnification
- Available zoom levels: 0.5x, 1.0x, 1.5x, 2.0x, 2.5x, 3.0x, 4.0x, 5.0x, 7.0x, 10.0x
- Real-time zoom indicator overlay
- Quick zoom shortcuts for instant level changes

### Driving Speed Simulation
- Real-time driving speed simulation (0-100 MPH)
- Random speed fluctuations for realistic driving behavior
- Direction indicator (accelerating, decelerating, steady)
- Speed limit display (65 MPH) with Apple Maps-style white/black sign design
- Color-coded speed status:
  - **Green**: Within speed limit
  - **Orange**: Speeding (65-75 MPH)
  - **Red**: Excessive speeding (>75 MPH)
- Real-time "SPEEDING!" warning when over the limit
- **Audio alert beep** when speeding detected
- Manual speed controls for testing alerts (X, C, Arrow keys)
- Simulates realistic driver monitoring scenarios

### Warning Sound System
- **Speeding Alert**: Single beep (900 Hz) when speed exceeds 65 MPH
- **Drowsy Driver Alert**: Urgent double beep (1200 Hz) when HIGH RISK intoxication detected
- 3-second cooldown between alerts to prevent audio spam
- Generated using pygame with smooth audio envelopes

## Technology Stack

- **MediaPipe Face Mesh**: 468 facial landmark detection with refined landmarks
- **YOLO v26**: State-of-the-art object detection for phone and distraction detection
- **OpenCV**: Computer vision and image processing
- **Eye Aspect Ratio (EAR)**: Industry-standard eye state detection
- **SciPy**: Euclidean distance calculations for landmark analysis
- **NumPy**: Statistical analysis and variance detection
- **Shazamio**: Free music recognition for identifying currently playing songs
- **PyAudio**: Real-time microphone audio capture
- **Supabase**: Real-time database and cloud storage for vehicle telemetry

## Getting Data

### MediaPipe Models

```zsh
$ curl -L -o face_landmarker.task https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task
$ curl -L -o hand_landmarker.task https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task
```

### YOLO v26 Models (Object Detection)

Download one of the following models based on your performance needs:

```zsh
# YOLO26 Nano - Fastest, lowest accuracy (recommended for Raspberry Pi)
$ curl -L -o yolo26n.pt https://huggingface.co/Ultralytics/YOLO26/resolve/main/yolo26n.pt

# YOLO26 Small - Balanced speed and accuracy
$ curl -L -o yolo26s.pt https://huggingface.co/Ultralytics/YOLO26/resolve/main/yolo26s.pt

# YOLO26 Medium - Higher accuracy, slower (recommended for desktop)
$ curl -L -o yolo26m.pt https://huggingface.co/Ultralytics/YOLO26/resolve/main/yolo26m.pt
```

## Running Locally

1. Initialize the project:

```zsh
$ uv init
$ uv venv
$ source .venv/bin/activate
```

2. Install dependencies:

```zsh
$ uv pip install -r requirements.txt
```

3. Run the camera viewer:

```zsh
$ uv run python main.py
```

4. Press 'q' to quit the application

## Keyboard Controls

### Settings Menu
- **'s'** - Toggle settings menu on/off
- **'h'** - Toggle help overlay on/off
- **'q'** - Quit application

### Zoom Controls
- **'+'** or **'='** - Zoom in (increase magnification)
- **'-'** or **'_'** - Zoom out (decrease magnification)
- **'r'** - Reset zoom to 1.0x (default)

### Quick Zoom Levels
- **'1'** - Set zoom to 1.0x (default)
- **'2'** - Set zoom to 2.0x
- **'3'** - Set zoom to 3.0x
- **'4'** - Set zoom to 4.0x
- **'5'** - Set zoom to 5.0x
- **'0'** - Set zoom to 10.0x (maximum)

### Speed Test Controls (for testing alerts)
- **'X'** - Simulate speeding (instantly set to 75 MPH)
- **'C'** - Reset speed to normal (45 MPH)
- **UP Arrow** - Increase speed by 10 MPH
- **DOWN Arrow** - Decrease speed by 10 MPH

## How It Works

### Eye Aspect Ratio (EAR)
The system calculates the Eye Aspect Ratio using the formula:
```
EAR = (||p2-p6|| + ||p3-p5||) / (2 * ||p1-p4||)
```
Where p1-p6 are eye landmark points. When EAR falls below the threshold (0.21), eyes are considered closed.

### Intoxication Scoring
- **Drowsiness** (+3 points): Eyes closed for 20+ consecutive frames
- **Excessive Blinking** (+2 points): More than 30 blinks in 100-frame window
- **Eye Instability** (+1 point): EAR variance > 0.005

Score ≥ 4: HIGH RISK, Score 2-3: MODERATE RISK, Score < 2: NORMAL

### Digital Zoom
The system implements digital zoom by:
1. Cropping the center region of the frame (size = original / zoom_level)
2. Resizing the cropped region back to original dimensions using bilinear interpolation
3. Processing the zoomed frame through the AI detection pipeline

This allows for magnification from 0.5x (zoom out) to 10x (maximum zoom in) while maintaining full frame processing.

### Driving Speed Simulation
The driving simulator generates realistic speed changes:
1. **Random Speed Changes**: Speed fluctuates by ±3 MPH every 5 frames for smooth transitions
2. **Speed Bounds**: Constrained between 0-100 MPH
3. **Direction Detection**: Determines if vehicle is accelerating (>0.5 MPH increase), decelerating (<-0.5 MPH decrease), or steady
4. **Speed Status**: Color-coded based on speed limit (65 MPH):
   - Green: ≤65 MPH (within limit)
   - Orange: 66-75 MPH (speeding)
   - Red: >75 MPH (excessive speeding)
5. **Visual Display**: Includes large speed readout, direction indicator, and official-style octagonal speed limit sign

## Accuracy

The system uses state-of-the-art AI models:
- MediaPipe Face Mesh: 468-point facial landmark detection with 95%+ accuracy
- Refined landmarks mode for improved eye region detection
- Real-time tracking at 30+ FPS on standard hardware

## Notes

This system is designed for educational and research purposes. It simulates a driver monitoring system that could be used in:
- Driver safety research
- Distracted driving studies
- Drowsy driving detection research
- Advanced driver assistance systems (ADAS) development

The intoxication detection is based on behavioral indicators and should not be used as the sole basis for medical or legal decisions. The driving speed simulation is for demonstration purposes and does not represent actual vehicle speeds.
