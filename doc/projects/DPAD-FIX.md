# Joy-Con L D-pad Button Fix for godot-joycon-fix

**Repository:** https://github.com/Nat-Ya/godot-joycon-fix
**Branch:** 4.3-joycon-fix
**Issue:** D-pad buttons (11-14) don't reach GDScript on Android

---

## Problem Summary

Joy-Con L D-pad buttons (11-14) reach the C++ Input layer but NEVER reach GDScript:

**Evidence:**
```
✅ [GodotInputHandler] KeyDown: keyCode=20 godotBtn=12         (Java layer)
✅ [JNI] joybutton: device=1 button=12 pressed=1               (JNI layer)
✅ [Input] joy_button: HAS MAPPING index=289, looking up button=12  (C++ layer)
❌ NO GDScript logs - InputEventJoypadButton never reaches _input() callbacks
❌ Input.is_joy_button_pressed(1, 12) returns FALSE
```

**Working comparison:** Button 9 (L shoulder) works perfectly through the same code path.

---

## Code Investigation Results

### 1. Controller Mapping (godotcontrollerdb.txt)

**Location:** `core/input/godotcontrollerdb.txt`

**Joy-Con L mapping:**
```
Android0000057e00002006,Nintendo Switch Joy-Con L,leftx:a0,lefty:a1,dpup:b11,dpdown:b12,dpleft:b13,dpright:b14,leftshoulder:b9,lefttrigger:b16,back:b4,leftstick:b7,platform:Android,
```

**Analysis:**
- Button 9 → "leftshoulder" → JoyButton::LEFT_SHOULDER (enum 9) ✅ WORKS
- Button 12 → "dpdown" → JoyButton::DPAD_DOWN (enum 12) ❌ DOESN'T WORK
- Both are TYPE_BUTTON mappings (not converted to axes)
- Both are 1:1 mappings (input button == output button)

### 2. JoyButton Enum (input_enums.h)

**Location:** `core/input/input_enums.h`

```cpp
enum class JoyButton {
    // ...
    LEFT_SHOULDER = 9,      // ✅ Works
    RIGHT_SHOULDER = 10,
    DPAD_UP = 11,           // ❌ Doesn't work
    DPAD_DOWN = 12,         // ❌ Doesn't work
    DPAD_LEFT = 13,         // ❌ Doesn't work
    DPAD_RIGHT = 14,        // ❌ Doesn't work
    // ...
};
```

### 3. Event Flow (input.cpp)

**Function:** `Input::joy_button()`
**Location:** `core/input/input.cpp` ~line 1484

```cpp
void Input::joy_button(int p_device, JoyButton p_button, bool p_pressed) {
    // ...

    // Updates ORIGINAL button state
    joy.last_buttons[(size_t)p_button] = p_pressed;

    if (joy.mapping == -1) {
        _button_event(p_device, p_button, p_pressed);  // Direct pass-through
        return;
    }

    // With mapping (index 289 for Joy-Con L)
    print_verbose("[Input] joy_button: HAS MAPPING index=%d, looking up button=%d",
                  joy.mapping, (int)p_button);

    JoyEvent map = _get_mapped_button_event(map_db[joy.mapping], p_button);

    if (map.type == TYPE_BUTTON) {
        _button_event(p_device, (JoyButton)map.index, p_pressed);  // ← Should create event
        return;
    }

    if (map.type == TYPE_AXIS) {
        _axis_event(p_device, (JoyAxis)map.index, p_pressed ? map.value : 0.0);
    }
}
```

**Function:** `Input::_button_event()`

```cpp
void Input::_button_event(int p_device, JoyButton p_index, bool p_pressed) {
    Ref<InputEventJoypadButton> ievent;
    ievent.instantiate();
    ievent->set_device(p_device);
    ievent->set_button_index(p_index);  // ← Sets to JoyButton::DPAD_DOWN (12)
    ievent->set_pressed(p_pressed);

    parse_input_event(ievent);  // ← Should dispatch to GDScript
}
```

**Function:** `Input::_parse_input_event_impl()`

```cpp
void Input::_parse_input_event_impl(const Ref<InputEvent> &p_event, bool p_is_emulated) {
    // ...

    // Process joypad button
    Ref<InputEventJoypadButton> jb = p_event;
    if (jb.is_valid()) {
        JoyButton c = _combine_device(jb->get_button_index(), jb->get_device());

        if (jb->is_pressed()) {
            joy_buttons_pressed.insert(c);  // ← Should track button state
        } else {
            joy_buttons_pressed.erase(c);
        }
    }

    // ... action matching (doesn't consume event) ...

    // Dispatch event to scene tree
    if (event_dispatch_function) {
        event_dispatch_function(p_event);  // ← Should reach GDScript
    }
}
```

**Expected behavior:** Both button 9 and button 12 should follow this exact same path.

**Actual behavior:** Button 9 reaches GDScript, button 12 doesn't.

---

## Investigation Tasks

### Task 1: Add Debug Logging to Identify Break Point

**File:** `core/input/input.cpp`

**In `_button_event()` function:** Add log IMMEDIATELY after creating InputEventJoypadButton:

```cpp
void Input::_button_event(int p_device, JoyButton p_index, bool p_pressed) {
    Ref<InputEventJoypadButton> ievent;
    ievent.instantiate();
    ievent->set_device(p_device);
    ievent->set_button_index(p_index);
    ievent->set_pressed(p_pressed);

    // 🔍 DEBUG: Log ALL button events
    print_line(vformat("[Input::_button_event] device=%d button=%d (%s) pressed=%s",
                       p_device, (int)p_index,
                       (int)p_index == 9 ? "L_SHOULDER" :
                       (int)p_index == 12 ? "DPAD_DOWN" : "OTHER",
                       p_pressed ? "true" : "false"));

    parse_input_event(ievent);
}
```

**In `_parse_input_event_impl()` function:** Add log when processing InputEventJoypadButton:

```cpp
Ref<InputEventJoypadButton> jb = p_event;
if (jb.is_valid()) {
    // 🔍 DEBUG: Log joypad button processing
    print_line(vformat("[Input::_parse_input_event_impl] Processing button device=%d button=%d pressed=%s",
                       jb->get_device(), (int)jb->get_button_index(), jb->is_pressed() ? "true" : "false"));

    JoyButton c = _combine_device(jb->get_button_index(), jb->get_device());

    if (jb->is_pressed()) {
        joy_buttons_pressed.insert(c);
        // 🔍 DEBUG: Confirm button added to set
        print_line(vformat("[Input::_parse_input_event_impl] Added button %d to joy_buttons_pressed set", (int)jb->get_button_index()));
    } else {
        joy_buttons_pressed.erase(c);
    }
}
```

**Before `event_dispatch_function` call:** Add log to confirm dispatch:

```cpp
if (event_dispatch_function) {
    // 🔍 DEBUG: Log event dispatch
    Ref<InputEventJoypadButton> jb_dispatch = p_event;
    if (jb_dispatch.is_valid()) {
        print_line(vformat("[Input::_parse_input_event_impl] Dispatching button event device=%d button=%d to scene tree",
                           jb_dispatch->get_device(), (int)jb_dispatch->get_button_index()));
    }

    _THREAD_SAFE_UNLOCK_
    event_dispatch_function(p_event);
    _THREAD_SAFE_LOCK_
}
```

**Expected result:** When pressing button 9 vs button 12, compare logs to find where they diverge.

---

### Task 2: Check Event Buffering

**File:** `core/input/input.cpp`

**In `parse_input_event()` function:** Add log to show if event is buffered or immediately processed:

```cpp
void Input::parse_input_event(const Ref<InputEvent> &p_event) {
    _THREAD_SAFE_METHOD_
    ERR_FAIL_COND(p_event.is_null());

    // 🔍 DEBUG: Log buffering decision for joypad buttons
    Ref<InputEventJoypadButton> jb_check = p_event;
    if (jb_check.is_valid()) {
        print_line(vformat("[Input::parse_input_event] Button %d: use_accumulated_input=%s, agile_flushing=%s, immediate=%s",
                           (int)jb_check->get_button_index(),
                           use_accumulated_input ? "true" : "false",
                           agile_input_event_flushing ? "true" : "false",
                           (!use_accumulated_input && !agile_input_event_flushing) ? "true" : "false"));
    }

    if (use_accumulated_input) {
        // ...
    } else if (agile_input_event_flushing) {
        // ...
    } else {
        _parse_input_event_impl(p_event, false);
    }
}
```

**Expected result:** Confirm both button 9 and button 12 take the same path (buffered vs immediate).

---

### Task 3: Verify joy_buttons_pressed State

**File:** `core/input/input.cpp`

**In `is_joy_button_pressed()` function:** Add debug logging:

```cpp
bool Input::is_joy_button_pressed(int p_device, JoyButton p_button) const {
    _THREAD_SAFE_METHOD_

    JoyButton c = _combine_device(p_button, p_device);
    bool result = joy_buttons_pressed.has(c);

    // 🔍 DEBUG: Log button state queries for DPAD buttons
    if ((int)p_button >= 11 && (int)p_button <= 14) {
        print_line(vformat("[Input::is_joy_button_pressed] device=%d button=%d combined=%d result=%s set_size=%d",
                           p_device, (int)p_button, (int)c, result ? "true" : "false", joy_buttons_pressed.size()));
    }

    return result;
}
```

**Expected result:** When GDScript polls button 12, see if it's actually in the set or not.

---

### Task 4: Search for DPAD-Specific Filtering

**Search locations:**

1. **Scene tree event dispatch:**
   - `scene/main/viewport.cpp`
   - `scene/main/window.cpp`
   - Look for code that filters InputEventJoypadButton before sending to nodes

2. **Display server layer:**
   - `platform/android/display_server_android.cpp`
   - Check if there's Android-specific event filtering

3. **Input action system:**
   - `core/input/input_map.cpp`
   - Verify action matching doesn't consume DPAD button events

**Search patterns:**
```bash
# Search for DPAD-specific conditionals
grep -r "DPAD_UP\|DPAD_DOWN\|DPAD_LEFT\|DPAD_RIGHT" core/input/ platform/android/

# Search for button range filters
grep -r "button.*>.*11\|button.*<.*14\|button.*==.*1[1-4]" core/input/ platform/android/

# Search for special button handling
grep -r "dpup\|dpdown\|dpleft\|dpright" core/input/
```

---

## Hypotheses to Test

### Hypothesis 1: Event dispatch function filters DPAD buttons

**Where to look:** Find what `event_dispatch_function` is set to and check if it filters button indices 11-14.

**Search:**
```bash
grep -r "set_event_dispatch_function" .
```

### Hypothesis 2: Scene tree doesn't dispatch DPAD button events to input callbacks

**Where to look:** `scene/main/viewport.cpp` - check `_gui_input_event()` or similar functions.

**Test:** Add logging in the viewport's input event processing to see if button 12 events reach there.

### Hypothesis 3: Android platform layer has special DPAD handling

**Where to look:** `platform/android/display_server_android.cpp`

**Search for:** Code that converts DPAD buttons to navigation events or filters them.

---

## Expected Fix

Once the break point is identified, the fix will likely be ONE of:

### Fix Option A: Remove DPAD button filter
If there's code filtering buttons 11-14, remove or modify it to allow them through.

### Fix Option B: Update button state tracking
If `joy_buttons_pressed.insert()` is being skipped for DPAD buttons, ensure it's called.

### Fix Option C: Force DPAD button event dispatch
If events are created but not dispatched, ensure `event_dispatch_function()` is called for DPAD buttons.

### Fix Option D: Use direct button mapping (bypass controller DB)
If mapping layer is broken for DPAD buttons, add special case to pass them through unmapped:

```cpp
// In joy_button() function
if (joy.mapping != -1) {
    // 🔧 FIX: DPAD buttons bypass mapping on Android
    if (OS::get_singleton()->get_name() == "Android" &&
        (int)p_button >= 11 && (int)p_button <= 14) {
        _button_event(p_device, p_button, p_pressed);
        return;
    }

    // Normal mapping for other buttons
    JoyEvent map = _get_mapped_button_event(map_db[joy.mapping], p_button);
    // ...
}
```

---

## Testing Instructions

After implementing debug logging:

1. **Build Godot editor with debug logs**
2. **Export Android APK**
3. **Run on device with Joy-Con L connected**
4. **Press button 9 (L shoulder) - capture logs**
5. **Press button 12 (D-pad Down) - capture logs**
6. **Compare logs to find divergence point**

**Expected log sequence for WORKING button (9):**
```
[JNI] joybutton: device=1 button=9 pressed=1
[Input] joy_button: HAS MAPPING index=289, looking up button=9
[Input::_button_event] device=1 button=9 (L_SHOULDER) pressed=true
[Input::parse_input_event] Button 9: immediate=true
[Input::_parse_input_event_impl] Processing button device=1 button=9 pressed=true
[Input::_parse_input_event_impl] Added button 9 to joy_buttons_pressed set
[Input::_parse_input_event_impl] Dispatching button event device=1 button=9 to scene tree
[ControllerHandler] 🎮 Button event: index=9, device=1   ← GDScript receives it!
```

**Expected log sequence for BROKEN button (12):**
```
[JNI] joybutton: device=1 button=12 pressed=1
[Input] joy_button: HAS MAPPING index=289, looking up button=12
[Input::_button_event] device=1 button=12 (DPAD_DOWN) pressed=true  ← Check if this appears
[Input::parse_input_event] Button 12: immediate=true  ← Check if this appears
[Input::_parse_input_event_impl] Processing button device=1 button=12 pressed=true  ← Check if this appears
[Input::_parse_input_event_impl] Added button 12 to joy_buttons_pressed set  ← Check if this appears
[Input::_parse_input_event_impl] Dispatching button event device=1 button=12 to scene tree  ← Check if this appears
??? NO GDSCRIPT LOG - Event never reaches scene tree ???
```

**The first log that DOESN'T appear for button 12 is where the bug is.**

---

## References

- **Mapping definition:** `core/input/godotcontrollerdb.txt` line with "Nintendo Switch Joy-Con L"
- **JoyButton enum:** `core/input/input_enums.h`
- **Main input processing:** `core/input/input.cpp`
- **Android input handler:** `platform/android/android_input_handler.cpp`
- **Java input handler:** `platform/android/java/lib/src/org/godotengine/godot/input/GodotInputHandler.java`

---

## Summary for Agent

**Goal:** Find where button 12 (DPAD_DOWN) stops being processed compared to button 9 (LEFT_SHOULDER).

**Method:** Add comprehensive debug logging at every step of the input pipeline.

**Deliverable:** Logs showing exact function where button 12 path diverges from button 9 path.

**Then:** Implement fix to make button 12 behave like button 9.