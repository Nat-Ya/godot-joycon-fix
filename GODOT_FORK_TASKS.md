# Godot Fork Tasks - Joy-Con D-pad Fix

**Repository:** `godot-joycon-fix`
**Branch:** `4.3-joycon-fix`
**File:** `platform/android/java/lib/src/org/godotengine/godot/input/GodotInputHandler.java`

---

## ✅ COMPLETED: Button Mapping Fixes

### Joy-Con Screenshot Button Fix
**Status:** Completed and committed
**Branch:** `claude/fix-godot-screenshot-button-1ysda`

**Changes Made:**
- **Screenshot/Capture Button:** `KEYCODE_SYSTEM_NAVIGATION_UP` → Button **15** (MISC1/Nintendo Capture)
- **L2 Trigger:** `KEYCODE_BUTTON_L2` → Button **16** (PADDLE1 slot)
- **R2 Trigger:** `KEYCODE_BUTTON_R2` → Button **19** (PADDLE4 slot)

**Rationale:**
- Button 15 (MISC1) is the standard SDL button for screenshot/capture (Xbox Share, PS5 Microphone, Nintendo Capture)
- L2/R2 moved to PADDLE slots to avoid conflicts with:
  - Button 15 (needed for screenshot)
  - Button 21 (SDL_MAX boundary marker - not a real button)
  - Buttons 20+ (reserved for default case: `KEYCODE_BUTTON_1` onwards)
- PADDLE slots (16, 19) are safe because Joy-Cons don't have paddle buttons

---

## Problem Summary

D-pad button events are logged by native Android but never reach GDScript.
L button and joystick work perfectly - only D-pad buttons fail.

---

# PHASE 1: DIAGNOSTIC LOGGING ✅ COMPLETED

## ✅ Task 1: Add Logging in `onKeyDown()` - COMPLETED

**Goal:** Trace exactly where D-pad events diverge from L button events.

**Implemented Logging:**
```java
// Phase 1 diagnostic: Log device lookup attempt
boolean deviceExists = mJoystickIds.indexOfKey(deviceId) >= 0;
Log.i(TAG, "[Phase1] KeyDown: dev=" + deviceId + " src=0x" + Integer.toHexString(source) +
    " keyCode=" + keyCode + " deviceRegistered=" + deviceExists);
```

This logs BEFORE the device check to capture all events, including unregistered devices.

---

## ✅ Task 2: Add Logging in `onKeyUp()` - COMPLETED

**Implemented Logging:**
```java
// Phase 1 diagnostic: Log device lookup attempt
boolean deviceExists = mJoystickIds.indexOfKey(deviceId) >= 0;
Log.i(TAG, "[Phase1] KeyUp: dev=" + deviceId + " src=0x" + Integer.toHexString(source) +
    " keyCode=" + keyCode + " deviceRegistered=" + deviceExists);
```

Same pattern as onKeyDown for consistency.

---

## ✅ Task 3: Add Logging in `handleJoystickButtonEvent()` - COMPLETED

**Implemented Logging:**
```java
private void handleJoystickButtonEvent(int device, int button, boolean pressed) {
    // Phase 1 diagnostic: Confirm method is called
    Log.i(TAG, "[Phase1] handleJoystickButtonEvent: device=" + device + " button=" + button + " pressed=" + pressed);
    // ... rest of method
}
```

This confirms whether the method is reached for both working (L button) and broken (D-pad) inputs.

---

## Task 4: Build and Test

1. Build APK with diagnostic logs
2. Connect Joy-Con L
3. Press **L button** → capture logs
4. Press **D-pad button** → capture logs
5. Compare: where do they diverge?

**Expected logs for L button (working):**
```
KeyDown TRACE: deviceId=8 keyCode=102 inMap=true
KeyDown DISPATCH: deviceId=8 -> godotJoyId=1
handleJoystickButtonEvent: device=1 button=9 pressed=true
```

**Expected logs for D-pad (broken) - one of these scenarios:**
- Scenario A: `inMap=false` → device not registered
- Scenario B: `inMap=true` but no DISPATCH log → code structure broken
- Scenario C: DISPATCH log present but no handleJoystickButtonEvent → call skipped
- Scenario D: All logs present → issue is in GodotLib.joybutton()

---

# PHASE 2: FIX BASED ON EVIDENCE (after logs confirm hypothesis)

## Task 5: Fix `onKeyDown()` Code Structure (lines 199-207)

⚠️ **Only do this after Phase 1 confirms the code structure is the issue!**

**Current broken code (hypothesis):**
```java
if (mJoystickIds.indexOfKey(deviceId) >= 0) {
} else {
    Log.w(TAG, "KeyDown: Device " + deviceId + " NOT in mJoystickIds! Map size=" + mJoystickIds.size());
}
    final int button = getGodotButton(keyCode);
    final int godotJoyId = mJoystickIds.get(deviceId);
    Log.i(TAG, "KeyDown dev=" + deviceId + " src=0x" + Integer.toHexString(source) + " keyCode=" + keyCode + " godotBtn=" + button);
    handleJoystickButtonEvent(godotJoyId, button, true);
}
```

**Fix - move button handling INSIDE the if block:**
```java
if (mJoystickIds.indexOfKey(deviceId) >= 0) {
    final int button = getGodotButton(keyCode);
    final int godotJoyId = mJoystickIds.get(deviceId);
    Log.i(TAG, "KeyDown dev=" + deviceId + " src=0x" + Integer.toHexString(source) + " keyCode=" + keyCode + " godotBtn=" + button);
    handleJoystickButtonEvent(godotJoyId, button, true);
} else {
    Log.w(TAG, "KeyDown: Device " + deviceId + " NOT in mJoystickIds! Map size=" + mJoystickIds.size());
}
```

---

## Task 6: Fix `onKeyUp()` Code Structure (lines 159-167)

⚠️ **Only do this after Phase 1 confirms the code structure is the issue!**

**Current broken code (hypothesis):**
```java
if (mJoystickIds.indexOfKey(deviceId) >= 0) {
    final int button = getGodotButton(keyCode);
    final int godotJoyId = mJoystickIds.get(deviceId);
    Log.i(TAG, "KeyUp dev=" + deviceId + " src=0x" + Integer.toHexString(source) + " keyCode=" + keyCode + " godotBtn=" + button);
} else {
    Log.w(TAG, "KeyUp: Device " + deviceId + " NOT in mJoystickIds! Map size=" + mJoystickIds.size());
}
    handleJoystickButtonEvent(godotJoyId, button, false);
}
```

**Fix - move handleJoystickButtonEvent INSIDE the if block:**
```java
if (mJoystickIds.indexOfKey(deviceId) >= 0) {
    final int button = getGodotButton(keyCode);
    final int godotJoyId = mJoystickIds.get(deviceId);
    Log.i(TAG, "KeyUp dev=" + deviceId + " src=0x" + Integer.toHexString(source) + " keyCode=" + keyCode + " godotBtn=" + button);
    handleJoystickButtonEvent(godotJoyId, button, false);
} else {
    Log.w(TAG, "KeyUp: Device " + deviceId + " NOT in mJoystickIds! Map size=" + mJoystickIds.size());
}
```

---

## Task 7: Fix `onInputDeviceAdded()` Misplaced Log (lines 343-350)

⚠️ **Lower priority - this is a log issue, not blocking D-pad events**

**Current broken code:**
```java
    Log.w(TAG, "onInputDeviceAdded: Device " + deviceId + " (" + device.getName() + ") rejected - not GAMEPAD/JOYSTICK/DPAD");
// Device may not be a joystick or gamepad
// Joy-Con L and some controllers report as SOURCE_DPAD, so include that
if (!device.supportsSource(InputDevice.SOURCE_GAMEPAD) &&
        !device.supportsSource(InputDevice.SOURCE_JOYSTICK) &&
        !device.supportsSource(InputDevice.SOURCE_DPAD)) {
    return;
}
```

**Fix - move log INSIDE the if block (before return):**
```java
// Device may not be a joystick or gamepad
// Joy-Con L and some controllers report as SOURCE_DPAD, so include that
if (!device.supportsSource(InputDevice.SOURCE_GAMEPAD) &&
        !device.supportsSource(InputDevice.SOURCE_JOYSTICK) &&
        !device.supportsSource(InputDevice.SOURCE_DPAD)) {
    Log.w(TAG, "onInputDeviceAdded: Device " + deviceId + " (" + device.getName() + ") rejected - not GAMEPAD/JOYSTICK/DPAD");
    return;
}
```

---

## Task 8: Fix `onInputDeviceAdded()` Log Order (line 354)

⚠️ **Lower priority - this would cause a crash, but device registration works (L button proves it)**

**Current code uses `joystick.name` before `joystick` is created:**
```java
final int id = assignJoystickIdNumber(deviceId);
Log.i(TAG, "onInputDeviceAdded: Registering device " + deviceId + " (" + joystick.name + ") -> godotJoyId=" + id);

final Joystick joystick = new Joystick();
```

**Fix - move log AFTER joystick creation:**
```java
final int id = assignJoystickIdNumber(deviceId);

final Joystick joystick = new Joystick();
joystick.device_id = deviceId;
joystick.name = device.getName();

Log.i(TAG, "onInputDeviceAdded: Registering device " + deviceId + " (" + joystick.name + ") -> godotJoyId=" + id);
```

---

## Verification

After fixes, test with Joy-Con L:
1. **L button** → Should still work (device=1, button=9)
2. **D-pad buttons** → Should now work (device=1, button=11/12/13/14)
3. **Joystick** → Should still work (axis motion events)

---

## Commit Message

```
fix(android): Joy-Con D-pad button events not reaching GDScript

- Fix onKeyDown(): move handleJoystickButtonEvent inside device check
- Fix onKeyUp(): move handleJoystickButtonEvent inside device check  
- Fix onInputDeviceAdded(): move rejection log inside if block
- Fix onInputDeviceAdded(): move registration log after joystick creation

Fixes D-pad buttons (indices 11-14) not dispatching to Godot while
L button (index 9) and joystick motion events worked correctly.
```

