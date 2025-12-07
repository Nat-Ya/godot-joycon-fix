# Godot Fork Cleanup Tasks

This document outlines the cleanup tasks needed for the godot-joycon-fix fork to minimize changes from the official Godot 4.3-stable branch.

## Goal
Keep the fork as close as possible to official Godot 4.3-stable, with only the minimal essential changes needed for Joy-Con L/R D-pad button support on Android.

## Current Status

The godot-joycon-fix fork successfully fixes Joy-Con L/R D-pad buttons by:
1. Adding D-pad button name strings ("dpup", "dpdown", "dpleft", "dpright") to the input mapping parser
2. Dispatching InputEventJoypadButton events for buttons 11-14 (DPAD_UP, DPAD_DOWN, DPAD_LEFT, DPAD_RIGHT)

## Cleanup Tasks

### 1. Remove Debug Logging
**Priority: HIGH**

Remove all debug logging added during investigation:

**Files to clean:**
- `core/input/input.cpp`
  - Remove `[_get_mapped_button_event]` logs showing binding searches
  - Remove `[Parser]` logs
  - Keep only essential error messages

**Verification:**
```bash
cd godot-joycon-fix
git grep -n "\[_get_mapped_button_event\]" core/input/
git grep -n "\[Parser\]" core/input/
```

### 2. Verify Minimal Changes
**Priority: HIGH**

The fix should consist of approximately **1-3 lean changes**:

**Expected changes:**
1. **Parser fix** (core/input/input.cpp or similar):
   - Add "dpup", "dpdown", "dpleft", "dpright" to `_get_output_button()` string lookup
   - Or equivalent fix in the mapping parser

2. **Optional: Controller mapping update** (if needed):
   - Update `godotcontrollerdb.txt` for Joy-Con L/R if not already present

**Verification:**
```bash
cd godot-joycon-fix
git diff 4.3-stable...HEAD --stat
git diff 4.3-stable...HEAD core/input/
```

The diff should be small - ideally under 50 lines of actual code changes.

### 3. Remove Unnecessary Files
**Priority: MEDIUM**

Check for any temporary investigation files:
- Investigation notes
- Test scripts
- Temporary debugging tools

**Verification:**
```bash
cd godot-joycon-fix
git status
git clean -n -d  # Dry run to see what would be removed
```

### 4. Clean Commit History
**Priority: MEDIUM**

If the branch has multiple debugging commits, squash them into clean logical commits:

**Recommended commit structure:**
```
1. "fix: add D-pad button support for Joy-Con L/R on Android"
   - Add "dpup", "dpdown", "dpleft", "dpright" to parser
   - Update controller mapping database (if needed)

2. (Optional) "test: add Joy-Con D-pad button tests"
   - Only if tests were added
```

**Commands:**
```bash
cd godot-joycon-fix
git log --oneline 4.3-stable..HEAD
# If many commits, consider interactive rebase:
git rebase -i 4.3-stable
```

### 5. Documentation
**Priority: LOW**

Add minimal documentation:

**File: JOYCON_FIX_README.md** (in fork root)
```markdown
# Joy-Con D-Pad Fix for Godot 4.3

This fork adds support for Joy-Con L/R D-pad buttons on Android.

## Changes from Godot 4.3-stable

- Added D-pad button name recognition in input mapping parser
- Joy-Con D-pad buttons (11-14) now dispatch correctly

## Building

Follow standard Godot build instructions for Android.

## Testing

Connect Joy-Con L or R via Bluetooth on Android, press D-pad buttons.
Buttons 11-14 should be recognized as DPAD_UP/DOWN/LEFT/RIGHT.
```

### 6. Compare with Official Godot 4.3-stable
**Priority: HIGH**

Verify the fork doesn't break existing functionality:

**Tests to run:**
1. Build for Android
2. Test with Xbox controller (should work unchanged)
3. Test with PlayStation controller (should work unchanged)
4. Test with Pro Controller (should work unchanged)
5. Test Joy-Con L/R (should now work for D-pad)

**Verification:**
```bash
cd godot-joycon-fix
# Compare platform/android changes
git diff 4.3-stable...HEAD platform/android/
# Should be minimal or empty
```

## Checklist

- [ ] Remove all `[_get_mapped_button_event]` debug logs
- [ ] Remove all `[Parser]` debug logs
- [ ] Verify diff is under 50 lines of code changes
- [ ] Squash commits into 1-2 logical commits
- [ ] Test with multiple controller types (no regressions)
- [ ] Test Joy-Con L/R D-pad buttons work
- [ ] Create JOYCON_FIX_README.md
- [ ] Tag release (e.g., `v4.3-stable-joycon-fix`)

## Final State

**Expected git diff stats:**
```
core/input/input.cpp | 15 ++++++++++
(optional) core/input/godotcontrollerdb.txt | 5 ++++
2 files changed, 20 insertions(+)
```

**Expected commits:**
```
* fix: add D-pad button support for Joy-Con L/R on Android
* (base: 4.3-stable)
```

## Notes for Maintainer

- Keep this fork **minimal** - only Joy-Con D-pad fix
- Rebase periodically against upstream Godot 4.3-stable
- When Godot 4.4 is released, check if fix is upstreamed
- Consider submitting PR to official Godot repository

## Contact

For issues with this fork, reference the original investigation:
- Game project: a-treasure-for-lora
- Investigation docs: GODOT_FORK_DPAD_FIX.md, GODOT_FORK_FIX_INSTRUCTIONS.md