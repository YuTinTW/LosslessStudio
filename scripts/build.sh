#!/bin/zsh
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

mkdir -p build dist

echo "==> Compiling LosslessStudio executable..."
swiftc -target arm64-apple-macos14.0 -O \
    src/main.swift \
    src/Engine/Types.swift \
    src/Engine/Limitations.swift \
    src/Engine/FFmpegRunner.swift \
    src/Engine/ImageLosslessEngine.swift \
    src/Engine/DocumentConversionEngine.swift \
    src/Engine/ConversionManager.swift \
    src/UI/LimitationsView.swift \
    src/UI/ShibaPixelView.swift \
    src/UI/EncodingMonitorView.swift \
    src/UI/ContentView.swift \
    -o build/LosslessStudio

echo "==> Compilation successful: build/LosslessStudio"
