# Video Recording Fix - Implementation Summary

## Date: 2026-03-10

## Problem
The video recording system had frame lagging and appeared slow during playback. Investigation revealed that while the system was already recording to a single MP4 file (not chunking), it was using time-gating that dropped frames to maintain a 10 FPS recording rate, causing the slow/lagging appearance.

## Solution Overview

### 1. Fixed Video Recording in `main.py`

#### Changes to `DashcamRecorder` class:

**Before:**
- FPS: 10
- Time-gating: Enabled (dropped frames if not enough time passed)
- Frame interval: 0.1 seconds (100ms between frames)
- Queue buffer: 30 frames

**After:**
- FPS: 30 (matches camera better)
- Time-gating: **REMOVED** (records all frames continuously)
- Queue buffer: 120 frames (increased to handle 30 FPS)
- Frame counting: Added for tracking

**Key Changes:**
```python
# Removed time-gating logic
- self._frame_interval = 1.0 / fps
- self._last_write_time = 0.0
- if now - self._last_write_time < self._frame_interval:
-     return  # not time for next frame yet

# Now records every frame without dropping
def write_frame(self, frame, hud_data=None):
    """Accept a frame for recording (non-blocking).
    Enqueues every frame for continuous recording without time-gating.
    """
    if not self._running or self._queue is None:
        return
    try:
        self._queue.put_nowait((frame.copy(), hud_data))
        self._frame_count += 1
    except Exception:
        pass  # queue full — drop frame
```

### 2. Added Bluetooth Recording Control

#### New Bluetooth Characteristic in `components/bluetooth.py`:

**UUID:** `A1B2C3D4-E5F6-7890-ABCD-123456780006` (CHAR_RECORDING_UUID)

**Purpose:** Allow iOS app to start/stop recording remotely via Bluetooth

**Handler in `main.py`:**
```python
def _ble_recording_write(data):
    """Handle recording commands from iOS via BLE."""
    nonlocal dashcam
    command = data.get("command", "")
    if command == "stop":
        if dashcam:
            print("[BLE] Stopping dashcam recording...")
            dashcam.stop()
            dashcam = None
            print("[BLE] Dashcam recording stopped successfully")
    elif command == "start":
        if not dashcam and cap:
            print("[BLE] Starting dashcam recording...")
            dashcam = DashcamRecorder()
            dashcam.start(supabase_uploader.trip_id, width, height)
            print("[BLE] Dashcam recording started successfully")
```

### 3. iOS App Updates

#### `BluetoothManager.swift`:

**Added:**
- New characteristic UUID: `recordingCharUUID`
- New characteristic property: `recordingCharacteristic`
- New method: `writeRecordingCommand(command: String)`

```swift
func writeRecordingCommand(command: String) {
    guard let char = recordingCharacteristic, 
          let peripheral = connectedPeripheral else { return }
    let payload: [String: Any] = ["command": command]
    guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
    peripheral.writeValue(data, for: char, type: .withResponse)
}
```

#### `VehicleSettingsView.swift`:

**Added:** "Stop Recording" button in Hardware section

**Visibility:** Only shown when connected via Bluetooth

**Features:**
- Red destructive button style
- Sends "stop" command to Raspberry Pi
- Provides visual feedback with icon and description
- Safely finalizes video before Pi shutdown

```swift
if bluetooth.isConnected {
    Button(role: .destructive) {
        bluetooth.writeRecordingCommand(command: "stop")
    } label: {
        HStack {
            Label {
                Text("Stop Recording")
            } icon: {
                Image(systemName: "stop.circle.fill")
                    .foregroundStyle(.red)
            }
            Spacer()
            Text("Save video safely")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
```

## Benefits

1. **Smooth Video Playback:** All frames are now recorded continuously without artificial throttling
2. **Better Frame Rate:** 30 FPS recording matches modern camera capabilities
3. **Remote Control:** Users can stop recording from the iOS app before unplugging the Pi
4. **Safe Shutdown:** Video is properly finalized and saved before power loss
5. **Larger Buffer:** 120-frame queue handles processing spikes better

## Testing Recommendations

1. **Recording Test:**
   - Start recording with dashcam enabled
   - Record for 5-10 minutes
   - Verify video plays smoothly at 30 FPS
   - Check for dropped frames

2. **Remote Stop Test:**
   - Connect iOS app via Bluetooth
   - Start recording
   - Use "Stop Recording" button in Vehicle Settings
   - Verify video file is saved correctly
   - Check video plays back completely

3. **Bluetooth Command Test:**
   - Test both "start" and "stop" commands
   - Verify proper error handling
   - Check console logs for confirmation messages

## Files Modified

1. `main.py` - DashcamRecorder class improvements and BLE handler
2. `components/bluetooth.py` - New recording characteristic
3. `../iOS/InfineonProject/Services/BluetoothManager.swift` - Recording command support
4. `../iOS/InfineonProject/Views/V2LaunchUI/VehicleSettingsView.swift` - Stop Recording button

## Backward Compatibility

- All changes are backward compatible
- Existing recordings remain unaffected
- Bluetooth characteristic discovery handles missing recording characteristic gracefully
- Time-gating removal doesn't break existing functionality

## Performance Impact

- **CPU:** Slightly increased due to higher frame rate (10 FPS → 30 FPS)
- **I/O:** Increased due to writing more frames
- **Storage:** Video files will be ~3x larger (30 FPS vs 10 FPS)
- **Memory:** Larger queue buffer (120 frames vs 30 frames)

## Next Steps

1. Test on actual Raspberry Pi hardware
2. Monitor CPU and memory usage during recording
3. Verify video quality and smoothness
4. Test Bluetooth remote control functionality
5. Consider adding recording status indicator in iOS app
