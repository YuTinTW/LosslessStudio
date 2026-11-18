#!/bin/zsh
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

OUTPUT="${1:-build/LosslessStudio}"
mkdir -p "$(dirname "$OUTPUT")"

echo "==> Compiling LosslessStudio executable..."
swiftc -target arm64-apple-macos14.0 -O \
    src/L10n.swift \
    src/main.swift \
    src/Engine/Types.swift \
    src/Engine/Limitations.swift \
    src/Engine/VideoLosslessVerifier.swift \
    src/Engine/FFmpegRunner.swift \
    src/Engine/ImageLosslessEngine.swift \
    src/Engine/PDFConversionEngine.swift \
    src/Engine/ConversionManager.swift \
    src/UI/LimitationsView.swift \
    src/UI/ShibaPixelView.swift \
    src/UI/EncodingMonitorView.swift \
    src/UI/ContentView.swift \
    -o "$OUTPUT"

echo "==> Compilation successful: $OUTPUT"
