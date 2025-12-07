# Joy-Con Button Fix Instructions for godot-joycon-fix

## Status Summary

**✅ FIXED - D-pad buttons (11-14):** Working perfectly with parser fix
**❌ BROKEN - Capture button (15):** Same parser issue as D-pad had
**❌ BROKEN - ZR trigger (19):** Mapped as axis instead of button

## Bug Details

### Capture Button (15) - Parser Issue

**Symptoms:**
```
[Input] joy_button: mapped button=15 to type=3 index=-1
```

Button 15 returns `type=3 index=-1` (invalid), same issue D-pad buttons had before the fix.

**Root Cause:** Parser's `_get_output_button()` function doesn't recognize the button name string for Capture button. Likely "capture", "misc1", or "screenshot" string is missing from the lookup table.

**Fix Needed:** Add the appropriate string to `_get_output_button()` string array, same fix applied to D-pad buttons.

### ZR Trigger (19) - Wrong Type Mapping

**Symptoms:**
```
[Input] joy_button: mapped button=19 to type=1 index=5
[Input] joy_button: calling _axis_event with mapped index=5
```

Button 19 (ZR) is mapped as **TYPE_AXIS (1)** instead of **TYPE_BUTTON (0)**.

**Actual Behavior:** ZR is a **digital button**, identical to ZL (button 16), not an analog trigger.

**Expected:**
```
[Input] joy_button: mapped button=19 to type=0 index=19
[Input] joy_button: calling _button_event with mapped index=19
```

**Root Cause:** Controller mapping database (godotcontrollerdb.txt) has incorrect entry. Likely says `righttrigger:a5` instead of `righttrigger:b19`.

**Fix Needed:**
1. Find the Joy-Con R mapping string in `godotcontrollerdb.txt`
2. Change `righttrigger:a5` to `righttrigger:b19`
3. OR fix the parser to recognize ZR as button 19

### Comparison: What Works vs What's Broken

**Joy-Con L - All Working ✅**
```
L shoulder (9):   type=0 index=9  ✅
ZL trigger (16):  type=0 index=16 ✅
Stick click (7):  type=0 index=7  ✅
D-pad UP (11):    type=0 index=11 ✅
D-pad DOWN (12):  type=0 index=12 ✅
D-pad LEFT (13):  type=0 index=13 ✅
D-pad RIGHT (14): type=0 index=14 ✅
Capture (15):     type=3 index=-1 ❌
```

**Joy-Con R - Partial Working**
```
A button (1):     type=0 index=1  ✅
B button (0):     type=0 index=0  ✅
X button (3):     type=0 index=3  ✅
Y button (2):     type=0 index=2  ✅
R shoulder (10):  type=0 index=10 ✅
Stick click (8):  type=0 index=8  ✅
Plus (6):         type=0 index=6  ✅
ZR trigger (19):  type=1 index=5  ❌ (should be type=0 index=19)
```

## Fix Instructions

### Fix 1: Capture Button (15)

**File:** Likely `core/input/input.cpp` or similar input mapping parser

**Method:** Add button name string to `_get_output_button()` lookup:

```cpp
// Find the function that maps button name strings to JoyButton enum
static struct {
    const char *name;
    JoyButton button;
} _joy_buttons[] = {
    // ... existing mappings ...
    { "dpup", JOY_BUTTON_DPAD_UP },        // ✅ Already fixed
    { "dpdown", JOY_BUTTON_DPAD_DOWN },    // ✅ Already fixed
    { "dpleft", JOY_BUTTON_DPAD_LEFT },    // ✅ Already fixed
    { "dpright", JOY_BUTTON_DPAD_RIGHT },  // ✅ Already fixed

    // 🔧 ADD THESE for Capture button:
    { "capture", JOY_BUTTON_MISC1 },       // Button 15
    { "misc1", JOY_BUTTON_MISC1 },         // Button 15 (alternative name)
    { "screenshot", JOY_BUTTON_MISC1 },    // Button 15 (alternative name)

    { nullptr, JOY_BUTTON_INVALID }
};
```

**Testing:** After fix, button 15 should show:
```
[Input] joy_button: mapped button=15 to type=0 index=15
[ControllerHandler] 🎮 Button event: index=15, device=1
```

### Fix 2: ZR Trigger (19)

**Option A: Fix Controller Database (Recommended)**

**File:** `core/input/godotcontrollerdb.txt`

Find the Joy-Con R mapping line (search for "Nintendo Switch Right Joy-Con" or similar):

```
# BEFORE (broken):
...righttrigger:a5...

# AFTER (fixed):
...righttrigger:b19...
```

**Option B: Fix Parser**

If the database is correct but parser is broken, add to `_get_output_button()`:

```cpp
{ "righttrigger", JOY_BUTTON_RIGHT_TRIGGER },  // Should map to button 19 for Joy-Con R
```

**Testing:** After fix, button 19 should show:
```
[Input] joy_button: mapped button=19 to type=0 index=19
[Input] joy_button: calling _button_event with mapped index=19
[ControllerHandler] 🎮 Button event: index=19, device=1
```

## Testing Checklist

After implementing fixes:

**Capture Button (15):**
- [ ] Logs show `type=0 index=15` (not `type=3 index=-1`)
- [ ] GDScript receives `InputEventJoypadButton` with `button_index=15`
- [ ] `Input.is_joy_button_pressed(1, 15)` returns true when pressed

**ZR Trigger (19):**
- [ ] Logs show `type=0 index=19` (not `type=1 index=5`)
- [ ] Logs show `calling _button_event` (not `calling _axis_event`)
- [ ] GDScript receives `InputEventJoypadButton` with `button_index=19`
- [ ] `Input.is_joy_button_pressed(1, 19)` returns true when pressed

**Regression Testing:**
- [ ] D-pad buttons (11-14) still work
- [ ] ZL button (16) still works
- [ ] All other buttons unchanged

## Summary

**What needs fixing in godot-joycon-fix:**

1. **Capture (15):** Add "capture"/"misc1"/"screenshot" string to button name parser
2. **ZR (19):** Change `righttrigger:a5` to `righttrigger:b19` in controller database

Both are similar to the D-pad fix already applied - just need the same treatment for these two buttons.