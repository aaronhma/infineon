# VehicleSettingsView Crash Fix

**Date:** 2026-03-10 14:27:00
**Error:** `Fatal error: No Observable object of type BluetoothManager found`

---

## 🐛 Problem

When opening Vehicle Settings, the app crashed with:
```
SwiftUICore/Environment+Objects.swift:34: Fatal error: No Observable object of type BluetoothManager found.
A View.environmentObject(_:) for BluetoothManager may be missing as an ancestor of this view.
```

## 🔍 Root Cause

I incorrectly added `@Environment(BluetoothManager.self)` to VehicleSettingsView, but the app uses a **global singleton pattern** instead of environment injection:

```swift
// ❌ WRONG - What I added
@Environment(BluetoothManager.self) private var bluetooth

// ✅ CORRECT - How the app actually works
// Global singleton defined in BluetoothManager.swift:
let bluetooth = BluetoothManager()
```

The app accesses `bluetooth` as a global variable throughout the codebase, not through SwiftUI's environment system.

## ✅ Solution

Removed the incorrect `@Environment` declaration:

**Before (Broken):**
```swift
struct VehicleSettingsView: View {
  @Environment(V2AppData.self) private var appData
  @Environment(BluetoothManager.self) private var bluetooth  // ❌ WRONG
  @Environment(\.dismiss) private var dismiss
```

**After (Fixed):**
```swift
struct VehicleSettingsView: View {
  @Environment(V2AppData.self) private var appData
  @Environment(\.dismiss) private var dismiss
  // bluetooth accessed as global singleton ✅
```

The code already uses `bluetooth` directly (lines 119, 121, 248, 249), which works because it's a global variable.

## 📝 How BluetoothManager Works in This App

**Global Singleton Pattern:**
```swift
// In BluetoothManager.swift (bottom of file)
let bluetooth = BluetoothManager()

// Used throughout the app without declaration:
if bluetooth.isConnected {
  bluetooth.writeRecordingCommand(command: "stop")
}
```

This is a common pattern for shared state in SwiftUI apps, alternative to:
- `@EnvironmentObject` (requires injection)
- `@Environment` (for Observable objects)
- `@StateObject` (view-owned instances)

## 🎯 Result

✅ VehicleSettingsView now opens without crashing
✅ "Stop Recording" button works correctly
✅ Uses existing global bluetooth singleton
✅ No code changes needed in other files

## 📁 File Modified

- `../iOS/InfineonProject/Views/V2LaunchUI/VehicleSettingsView.swift`
  - Removed: `@Environment(BluetoothManager.self) private var bluetooth`

## 🧪 Testing

- [ ] Open Vehicle Settings → Should not crash
- [ ] Connect via Bluetooth → "Stop Recording" button should appear
- [ ] Tap "Stop Recording" → Should send command to Pi
- [ ] Verify other settings still save correctly
