# syntax=docker/dockerfile:1.4
# Godot Engine with Joy-Con Fix - Docker Image (Development Build)
# Multi-stage build for Godot editor + Android export templates
# Uses local source code - run 'docker build' from repository root
#
# BUILD CACHING STRATEGY:
# - Uses Docker BuildKit cache mounts for SCons cache
# - Each build target is cached independently
# - Rebuild only what changed between runs
# - Use with: DOCKER_BUILDKIT=1 docker build --cache-from ...
#
# RESILIENT BUILD TIPS:
# - Enable BuildKit: export DOCKER_BUILDKIT=1
# - Use cache from previous builds: --cache-from type=registry,ref=<registry>/godot-cache
# - Save cache for future builds: --cache-to type=registry,ref=<registry>/godot-cache

FROM ubuntu:24.04 AS builder

# Avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive
ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV PATH="${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"
# SCons cache directory for faster rebuilds
ENV SCONS_CACHE=/root/.scons_cache
ENV SCONS_CACHE_LIMIT=10000

# Install build dependencies
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

# Set up Android SDK for export templates
RUN mkdir -p ${ANDROID_HOME}/cmdline-tools && \
    cd ${ANDROID_HOME}/cmdline-tools && \
    wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip && \
    unzip commandlinetools-linux-11076708_latest.zip && \
    mv cmdline-tools latest && \
    rm commandlinetools-linux-11076708_latest.zip

# Accept licenses and install Android build tools
RUN yes | sdkmanager --licenses && \
    sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.0" "ndk;23.2.8568313" "cmake;3.22.1"

# Build arguments
ARG GODOT_VERSION=4.3.stable
ARG SCONSFLAGS=verbose=yes warnings=extra werror=yes debug_symbols=no

# Copy local Godot source code
WORKDIR /opt/godot
COPY . /opt/godot

# ============================================================================
# Build Stage 1: Linux Editor
# Uses BuildKit cache mount for SCons cache - survives across builds
# ============================================================================
RUN --mount=type=cache,target=/root/.scons_cache,id=scons-cache \
    echo "🔨 Building Godot Linux Editor..." && \
    scons platform=linuxbsd tools=yes target=editor ${SCONSFLAGS} -j$(nproc) && \
    strip bin/godot.linuxbsd.editor.x86_64 && \
    echo "✅ Linux Editor built successfully"

# ============================================================================
# Build Stage 2: Android ARM64 Templates
# Each architecture is built separately for better caching granularity
# ============================================================================
RUN --mount=type=cache,target=/root/.scons_cache,id=scons-cache \
    echo "🔨 Building Android ARM64 Release Template..." && \
    scons platform=android target=template_release arch=arm64 ${SCONSFLAGS} -j$(nproc) && \
    echo "✅ Android ARM64 Release built successfully"

RUN --mount=type=cache,target=/root/.scons_cache,id=scons-cache \
    echo "🔨 Building Android ARM64 Debug Template..." && \
    scons platform=android target=template_debug arch=arm64 ${SCONSFLAGS} -j$(nproc) && \
    echo "✅ Android ARM64 Debug built successfully"

# ============================================================================
# Build Stage 3: Android ARM32 Templates
# ============================================================================
RUN --mount=type=cache,target=/root/.scons_cache,id=scons-cache \
    echo "🔨 Building Android ARM32 Release Template..." && \
    scons platform=android target=template_release arch=arm32 ${SCONSFLAGS} -j$(nproc) && \
    echo "✅ Android ARM32 Release built successfully"

RUN --mount=type=cache,target=/root/.scons_cache,id=scons-cache \
    echo "🔨 Building Android ARM32 Debug Template..." && \
    scons platform=android target=template_debug arch=arm32 ${SCONSFLAGS} -j$(nproc) && \
    echo "✅ Android ARM32 Debug built successfully"

# Generate Android export templates using Gradle (matching Android builds workflow)
# This packages the native libraries into APKs for both arm32 and arm64
WORKDIR /opt/godot/platform/android/java
RUN ./gradlew generateGodotTemplates --quiet && \
    cd /opt/godot && \
    ls -lh bin/android_*.apk || true

# Package Android export templates
WORKDIR /opt/godot
RUN mkdir -p /root/.local/share/godot/export_templates/${GODOT_VERSION} && \
    cd bin && \
    mkdir -p android_source && \
    cp android_*.apk android_source/ 2>/dev/null || true && \
    cp -r misc/dist/android_source/* android_source/ 2>/dev/null || true && \
    cd android_source && \
    zip -r /root/.local/share/godot/export_templates/${GODOT_VERSION}/android_source.zip . && \
    cd /opt/godot/bin && \
    cp android_debug.apk /root/.local/share/godot/export_templates/${GODOT_VERSION}/ 2>/dev/null || true && \
    cp android_release.apk /root/.local/share/godot/export_templates/${GODOT_VERSION}/ 2>/dev/null || true

# ============================================================================
# Stage 2: Runtime - Clean image with Godot + templates
# ============================================================================
FROM ubuntu:24.04

# Install minimal runtime dependencies
# Note: libasound2 is a virtual package in Ubuntu 24.04, use libasound2t64 instead
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
    ls -lh /root/.local/share/godot/export_templates/

WORKDIR /workspace

CMD ["${GODOT_BIN}", "--version"]
