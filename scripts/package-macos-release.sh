#!/usr/bin/env bash
# Builds the release .app and bundles the speech runtimes inside it
# (models/ and bin/ go to Contents/MacOS, next to the executable, where the
# runtime resolution already looks). Produces dist/TypeMate-macos-arm64.tar.gz
# and prints the ready-to-install .app path.
#
# Prerequisites: dart run tool/fetch_whisper_runtime.dart (models + sherpa)
# and scripts/build-whisper-macos.sh (whisper binaries) have populated
# models/ and bin/.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
APP_PATH="build/macos/Build/Products/Release/Type Mate.app"
DIST_DIR="dist"
ARCHIVE_PATH="$DIST_DIR/TypeMate-macos-arm64.tar.gz"

test -f bin/whisper/whisper-cli
test -f bin/whisper/whisper-server
test -f bin/sherpa/sherpa-onnx-offline-websocket-server
test -f models/ggml-silero-v5.1.2.bin

"$FLUTTER_BIN" build macos --release

# Runtimes live in Contents/Resources: data files inside Contents/MacOS
# would break the bundle's code signature. The app searches
# <executable dir>/../Resources on macOS.
BUNDLE_RUNTIME_DIR="$APP_PATH/Contents/Resources"
rm -rf "$BUNDLE_RUNTIME_DIR/models" "$BUNDLE_RUNTIME_DIR/bin"
mkdir -p "$BUNDLE_RUNTIME_DIR/bin"
cp -R models "$BUNDLE_RUNTIME_DIR/models"
cp -R bin/whisper bin/sherpa "$BUNDLE_RUNTIME_DIR/bin/"

# Re-sign (ad-hoc): bundling the runtimes invalidated the build signature.
for helper in \
  "$BUNDLE_RUNTIME_DIR/bin/whisper/whisper-cli" \
  "$BUNDLE_RUNTIME_DIR/bin/whisper/whisper-server" \
  "$BUNDLE_RUNTIME_DIR/bin/sherpa/sherpa-onnx-offline-websocket-server"; do
  codesign --force -s - "$helper"
done
codesign --force -s - "$APP_PATH"

mkdir -p "$DIST_DIR"
rm -f "$ARCHIVE_PATH"
tar -czf "$ARCHIVE_PATH" -C "$(dirname "$APP_PATH")" "Type Mate.app"

printf '%s\n' "$APP_PATH"
printf '%s\n' "$ARCHIVE_PATH"
