# Docker Build Cache Management - Smart Invalidation Guide

## TL;DR - Quick Commands

```bash
# Full rebuild (nuclear option)
docker buildx prune -f && docker build --no-cache -t godot-joycon-fix:local .

# Selective cache invalidation (smart)
docker build --build-arg CACHE_BUST=$(date +%s) -t godot-joycon-fix:local .
```

---

## Smart Cache Invalidation by File Type

### 🎯 Only Java Changes (GodotInputHandler.java)

**What changed:** Android Java input handling code
**Cache needed:** Invalidate from Java compilation step onwards

```bash
# Option 1: Rebuild Android Java only (fastest - 2-5 min)
cd platform/android/java
./gradlew clean assembleDebug -x lint
cd ../../..

# Option 2: Rebuild with Docker but skip most cache
docker build \
  --build-arg CACHE_BUST=$(date +%s) \
  --target builder \
  -t godot-joycon-fix:local .
```

**Files that trigger this:**
- `platform/android/java/**/*.java`
- `platform/android/java/**/*.kt`
- `platform/android/java/**/build.gradle`

---

### ⚙️ C++ Code Changes (core, modules, drivers)

**What changed:** Core engine, drivers, or modules
**Cache needed:** Invalidate from SCons build step

```bash
# Rebuild C++ only (10-20 min with cache)
docker build \
  --build-arg CACHE_BUST=$(date +%s) \
  --build-arg SCONSFLAGS="platform=android target=template_debug arch=arm64v8" \
  -t godot-joycon-fix:local .
```

**Files that trigger this:**
- `core/**/*.cpp`, `core/**/*.h`
- `modules/**/*.cpp`, `modules/**/*.h`
- `drivers/**/*.cpp`, `drivers/**/*.h`
- `platform/android/**/*.cpp`, `platform/android/**/*.h`
- `servers/**/*.cpp`, `servers/**/*.h`

---

### 🐳 Dockerfile Changes

**What changed:** Build dependencies, base image, build steps
**Cache needed:** Full rebuild required

```bash
# No cache - rebuild everything (30-60 min)
docker buildx prune -f
docker build --no-cache -t godot-joycon-fix:local .
```

**Files that trigger this:**
- `Dockerfile`
- `SConstruct`
- `platform.py`

---

### 📦 Dependency Changes

**What changed:** Android SDK version, NDK version, build tools
**Cache needed:** Invalidate from dependency installation

```bash
# Rebuild from dependency layer
docker build --no-cache --target builder -t godot-joycon-fix:local .
```

**Files that trigger this:**
- `Dockerfile` (RUN apt-get, RUN sdkmanager)
- `platform/android/java/gradle/wrapper/**`

---

## Cache Inspection

### Check What's Cached

```bash
# View build cache usage
docker buildx du

# List cached layers
docker buildx imagetools inspect godot-joycon-fix:local
```

### Selective Cache Cleanup

```bash
# Remove cache older than 48 hours
docker buildx prune --filter "until=48h" -f

# Remove only dangling cache
docker buildx prune --filter "dangling=true" -f

# Remove all build cache
docker buildx prune --all -f
```

---

## Smart Dockerfile Patterns

### Current Issue: Everything Invalidates on Code Change

```dockerfile
# ❌ BAD: Any file change invalidates all cache
COPY . /build
RUN scons platform=android ...
```

### Solution: Layer Dependencies Separately

```dockerfile
# ✅ GOOD: Dependencies cached separately
# 1. Install system deps (rarely changes)
FROM ubuntu:24.04 AS builder
RUN apt-get update && apt-get install -y build-essential scons ...

# 2. Install Android SDK (rarely changes)
RUN mkdir -p ${ANDROID_HOME}/cmdline-tools && ...

# 3. Copy only build configs (changes occasionally)
COPY SConstruct platform.py /build/

# 4. Copy source code (changes frequently)
COPY core/ /build/core/
COPY modules/ /build/modules/
COPY platform/ /build/platform/

# 5. Build (only invalidated if source changes)
RUN scons platform=android ...
```

---

## Optimized Build Strategy by Change Type

### Scenario 1: Active Development (frequent Java changes)

```bash
# Use local Gradle for fast iteration
cd platform/android/java
./gradlew assembleDebug -x lint --no-daemon

# Docker only for final template build
docker build -t godot-joycon-fix:test .
```

### Scenario 2: Testing Engine Changes (C++ changes)

```bash
# Use Docker with build cache
docker build --build-arg CACHE_BUST=$(git log -1 --format=%H -- core/) \
  -t godot-joycon-fix:test .
```

### Scenario 3: Release Build (everything clean)

```bash
# Full clean build
docker buildx prune -f
docker build --no-cache --platform linux/amd64 \
  -t godot-joycon-fix:release .
```

---

## File-Specific Cache Invalidation

### Modified: `platform/android/java/lib/src/org/godotengine/godot/input/GodotInputHandler.java`

```bash
# Just rebuild Android library (2-5 min)
cd platform/android/java
./gradlew :lib:assembleDebug -x lint

# Extract APK
cp lib/build/outputs/apk/debug/lib-debug.apk ../../../bin/android_debug.apk
```

### Modified: `core/input/input_enums.h`

```bash
# Rebuild engine core + Android (15-25 min)
docker build \
  --build-arg CACHE_BUST=$(date +%s) \
  --build-arg SCONSFLAGS="platform=android target=template_debug" \
  -t godot-joycon-fix:test .
```

### Modified: `GODOT_FORK_TASKS.md`, `*.md` files

```bash
# No rebuild needed! Documentation only.
git add -A && git commit -m "docs: update documentation"
```

---

## Auto-Detection Script

Create `check-rebuild-needed.sh`:

```bash
#!/bin/bash
# Detect what type of rebuild is needed based on changed files

CHANGED_FILES=$(git diff --name-only HEAD~1)

if echo "$CHANGED_FILES" | grep -q "\.md$\|\.txt$\|LICENSE\|README"; then
    echo "📝 Documentation only - no rebuild needed"
    exit 0
fi

if echo "$CHANGED_FILES" | grep -q "Dockerfile\|SConstruct"; then
    echo "🔥 Full rebuild required (Dockerfile/SConstruct changed)"
    echo "Run: docker buildx prune -f && docker build --no-cache ..."
    exit 0
fi

if echo "$CHANGED_FILES" | grep -q "platform/android/java/.*\.java$"; then
    echo "☕ Java changes detected - fast Gradle rebuild"
    echo "Run: cd platform/android/java && ./gradlew assembleDebug -x lint"
    exit 0
fi

if echo "$CHANGED_FILES" | grep -q "\.cpp$\|\.h$"; then
    echo "⚙️  C++ changes detected - SCons rebuild with cache"
    echo "Run: docker build --build-arg CACHE_BUST=\$(date +%s) ..."
    exit 0
fi

echo "❓ Unknown changes - consider full rebuild"
```

---

## Pro Tips

### 1. **Use BuildKit for Better Caching**

```bash
# Enable BuildKit (better layer caching)
export DOCKER_BUILDKIT=1
docker build -t godot-joycon-fix:local .
```

### 2. **Parallel Builds for Multi-Arch**

```bash
# Build arm64 and x86_64 in parallel (if needed)
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t godot-joycon-fix:multi \
  --cache-from type=registry,ref=godot-joycon-fix:cache \
  --cache-to type=registry,ref=godot-joycon-fix:cache,mode=max \
  .
```

### 3. **GCP Cloud Build Handles This Automatically**

When using `cloudbuild.yaml`:
- ✅ Automatic layer caching
- ✅ 100GB disk space
- ✅ No local cache management needed
- ✅ Cache shared across builds

```bash
# Just push and let Cloud Build handle caching
git push origin 4.3-joycon-fix
```

---

## Decision Tree

```
File changed?
├─ *.md, *.txt, LICENSE → No rebuild needed
├─ Dockerfile, SConstruct → Full rebuild (docker buildx prune -f)
├─ **/*.java → Gradle rebuild (./gradlew assembleDebug)
├─ **/*.cpp, **/*.h → Docker rebuild with cache
└─ Unknown → Ask or full rebuild
```

---

## Current Project State (Phase 1 Complete)

**Recent Changes:**
- ✅ `GodotInputHandler.java` - Phase 1 diagnostic logging added
- ✅ `GODOT_FORK_TASKS.md` - Documentation updated
- ✅ `input_enums.h` - SDL button enum reference

**Next Build Should:**
- Invalidate Java layer (GodotInputHandler.java changed)
- Keep C++ core cache (no C++ changes)
- Fast rebuild: ~5-10 minutes with cache

**Recommended:**
```bash
# Quick test build
cd platform/android/java
./gradlew assembleDebug -x lint

# Or full Docker build with cache
docker build --build-arg CACHE_BUST=$(date +%s) -t godot-joycon-fix:phase1-test .
```
