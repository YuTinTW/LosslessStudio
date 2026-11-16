#!/bin/sh
set -eu
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
cp "$PROJECT_DIR/tests/document_adapter_main.swift" "$TEST_DIR/main.swift"
swiftc "$PROJECT_DIR/src/Engine/DocumentConversionEngine.swift" "$TEST_DIR/main.swift" -o "$TEST_DIR/run"
"$TEST_DIR/run"
