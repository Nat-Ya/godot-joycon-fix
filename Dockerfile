# Godot Engine with Joy-Con Fix - Docker Image
# Multi-stage build for Godot editor + Android export templates

FROM ubuntu:24.04 AS builder

# Avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive
ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV PATH="${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"

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
ARG GODOT_BRANCH=4.3-joycon-fix
ARG GODOT_VERSION=4.3.stable
ARG SCONSFLAGS=verbose=yes warnings=extra werror=yes debug_symbols=no

# Clone Godot source
WORKDIR /opt
RUN git clone --depth 1 --branch ${GODOT_BRANCH} https://github.com/Nat-Ya/godot-joycon-fix.git godot

# Build Godot editor (Linux)
WORKDIR /opt/godot
RUN scons platform=linuxbsd tools=yes target=editor ${SCONSFLAGS} -j$(nproc) && \
    strip bin/godot.linuxbsd.editor.x86_64

# Build Android export templates (arm32 and arm64) - matching Android builds workflow
# Build arm64 templates
RUN scons platform=android target=template_release arch=arm64 ${SCONSFLAGS} -j$(nproc) && \
    scons platform=android target=template_debug arch=arm64 ${SCONSFLAGS} -j$(nproc)

# Build arm32 templates
RUN scons platform=android target=template_release arch=arm32 ${SCONSFLAGS} -j$(nproc) && \
    scons platform=android target=template_debug arch=arm32 ${SCONSFLAGS} -j$(nproc)

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
