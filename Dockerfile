# Godot Engine with Joy-Con Fix - Docker Image
# Multi-stage build for Godot editor + Android export templates
#
# CACHE INVALIDATION STRATEGY:
# - Uses selective COPY to minimize layer invalidation
# - Build system files (SConstruct, etc.) copied first - rarely change
# - Platform/module sources copied in logical groups
# - SCons cache handled externally via GCS (not Docker layer cache)
#
# KANIKO COMPATIBLE:
# - No --mount=type=cache (not supported by Kaniko)
# - SCons cache downloaded/uploaded via GCS in cloudbuild.yaml
#
# LAYER INVALIDATION ORDER:
# 1. Base OS + dependencies    → Changes rarely (Ubuntu/SDK updates)
# 2. Build system files        → Changes rarely (SConstruct updates)
# 3. Third-party libraries     → Changes occasionally (dependency updates)
# 4. Core engine sources       → Changes often (engine development)
# 5. Platform-specific sources → Changes per-platform
# 6. Build execution           → Depends on source changes + SCons cache

# ============================================================================
# Stage 1: Builder - Full build environment
# ============================================================================
FROM ubuntu:24.04 AS builder

# Avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive
ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV PATH="${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"

# SCons cache configuration (populated from GCS by cloudbuild.yaml)
ENV SCONS_CACHE=/opt/scons-cache
ENV SCONS_CACHE_LIMIT=10000

# Build arguments
ARG GODOT_VERSION=4.3.stable
ARG SCONSFLAGS="verbose=yes warnings=extra werror=no debug_symbols=no"

# Layer 1: Install build dependencies (rarely changes)
RUN apt-get update && apt-get install -y \
    build-essential \
    scons \
    pkg-config \
    libx11-dev \
    libxcursor-dev \
    libxinerama-dev \
    libgl1-mesa-dev \
    libglu1-mesa-dev \
    libasound2-dev \
    libpulse-dev \
    libudev-dev \
    libxi-dev \
    libxrandr-dev \
    openjdk-17-jdk \
    python3 \
    python3-pip \
    git \
    wget \
    unzip \
    zip \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Layer 2: Set up Android SDK (rarely changes)
RUN mkdir -p ${ANDROID_HOME}/cmdline-tools && \
    cd ${ANDROID_HOME}/cmdline-tools && \
    wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip && \
    unzip commandlinetools-linux-11076708_latest.zip && \
    mv cmdline-tools latest && \
    rm commandlinetools-linux-11076708_latest.zip

# Accept licenses and install Android build tools
RUN yes | sdkmanager --licenses && \
    sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.0" "ndk;23.2.8568313" "cmake;3.22.1"

# Create working directory and SCons cache directory
WORKDIR /opt/godot
RUN mkdir -p ${SCONS_CACHE}

# ============================================================================
# Layer 3: Build system files (changes rarely)
# These files define HOW to build, not WHAT to build
# ============================================================================
COPY SConstruct methods.py version.py gles3_builders.py scu_builders.py ./
COPY platform/SCsub platform/

# ============================================================================
# Layer 4: Third-party libraries (changes occasionally)
# Large but stable - good cache candidate
# ============================================================================
COPY thirdparty/ thirdparty/

# ============================================================================
# Layer 5: Core engine sources (changes often)
# ============================================================================
COPY core/ core/
COPY servers/ servers/
COPY scene/ scene/
COPY drivers/ drivers/
COPY main/ main/
COPY tests/ tests/
COPY modules/ modules/
COPY doc/ doc/

# ============================================================================
# Layer 6: Editor sources (only needed for editor builds)
# ============================================================================
COPY editor/ editor/

# ============================================================================
# Layer 7: Platform-specific sources
# Copy all platforms - selective building happens in RUN commands
# ============================================================================
COPY platform/linuxbsd/ platform/linuxbsd/
COPY platform/android/ platform/android/
COPY platform/windows/ platform/windows/

# ============================================================================
# BUILD STAGE 1: Linux Editor
# ============================================================================
RUN echo "🔨 Building Godot Linux Editor..." && \
    scons platform=linuxbsd tools=yes target=editor ${SCONSFLAGS} -j$(nproc) && \
    strip bin/godot.linuxbsd.editor.x86_64 && \
    echo "✅ Linux Editor: $(ls -lh bin/godot.linuxbsd.editor.x86_64 | awk '{print $5}')"

# ============================================================================
# BUILD STAGE 2: Android ARM64 Templates
# ============================================================================
RUN echo "🔨 Building Android ARM64 Release Template..." && \
    scons platform=android target=template_release arch=arm64 ${SCONSFLAGS} -j$(nproc) && \
    echo "✅ Android ARM64 Release built"

RUN echo "🔨 Building Android ARM64 Debug Template..." && \
    scons platform=android target=template_debug arch=arm64 ${SCONSFLAGS} -j$(nproc) && \
    echo "✅ Android ARM64 Debug built"

# ============================================================================
# BUILD STAGE 3: Android ARM32 Templates
# ============================================================================
RUN echo "🔨 Building Android ARM32 Release Template..." && \
    scons platform=android target=template_release arch=arm32 ${SCONSFLAGS} -j$(nproc) && \
    echo "✅ Android ARM32 Release built"

RUN echo "🔨 Building Android ARM32 Debug Template..." && \
    scons platform=android target=template_debug arch=arm32 ${SCONSFLAGS} -j$(nproc) && \
    echo "✅ Android ARM32 Debug built"

# ============================================================================
# BUILD STAGE 4: Generate Android APKs via Gradle
# ============================================================================
WORKDIR /opt/godot/platform/android/java
RUN echo "📦 Generating Android templates via Gradle..." && \
    ./gradlew generateGodotTemplates --quiet && \
    cd /opt/godot && \
    echo "✅ Android APKs generated:" && \
    ls -lh bin/android_*.apk || true

# ============================================================================
# BUILD STAGE 5: Package export templates
# ============================================================================
WORKDIR /opt/godot
RUN mkdir -p /root/.local/share/godot/export_templates/${GODOT_VERSION} && \
    cd bin && \
    cp android_debug.apk /root/.local/share/godot/export_templates/${GODOT_VERSION}/ 2>/dev/null || true && \
    cp android_release.apk /root/.local/share/godot/export_templates/${GODOT_VERSION}/ 2>/dev/null || true && \
    echo "✅ Export templates packaged" && \
    ls -lh /root/.local/share/godot/export_templates/${GODOT_VERSION}/

# ============================================================================
# Stage 2: Runtime - Clean image with Godot + templates
# ============================================================================
FROM ubuntu:24.04

# Install minimal runtime dependencies
RUN apt-get update && apt-get install -y \
    libx11-6 \
    libxcursor1 \
    libxinerama1 \
    libgl1 \
    libglu1-mesa \
    libasound2t64 \
    libpulse0 \
    openjdk-17-jdk \
    && rm -rf /var/lib/apt/lists/*

# Copy Godot binary
COPY --from=builder /opt/godot/bin/godot.linuxbsd.editor.x86_64 /opt/godot/bin/godot.linuxbsd.editor.x86_64
COPY --from=builder /opt/godot/bin/android_*.apk /opt/godot/bin/

# Copy export templates
COPY --from=builder /root/.local/share/godot /root/.local/share/godot

# Copy Android SDK (needed for export)
COPY --from=builder /opt/android-sdk /opt/android-sdk

# Set environment variables
ENV GODOT_BIN=/opt/godot/bin/godot.linuxbsd.editor.x86_64
ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV PATH="${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

# Verify installation
RUN ${GODOT_BIN} --version && \
    echo "📦 Export templates:" && \
    ls -lh /root/.local/share/godot/export_templates/

WORKDIR /workspace

CMD ["${GODOT_BIN}", "--version"]
