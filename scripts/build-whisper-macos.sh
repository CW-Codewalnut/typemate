#!/usr/bin/env bash
# Builds the whisper.cpp v1.9.1 binaries TypeMate bundles on macOS
# (whisper.cpp publishes no macOS binaries). Static, Metal-accelerated,
# metallib embedded so the binaries are fully self-contained.
#
# Output: bin/whisper/whisper-cli and bin/whisper/whisper-server, plus a
# whisper-v1.9.1-macos-arm64.tar.gz alongside for upload to the models-v1
# release (which tool/fetch_whisper_runtime.dart downloads on other Macs).
set -euo pipefail

cd "$(dirname "$0")/.."
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT

git clone --depth 1 --branch v1.9.1 \
  https://github.com/ggml-org/whisper.cpp "$staging/whisper.cpp"
cmake -S "$staging/whisper.cpp" -B "$staging/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DGGML_METAL_EMBED_LIBRARY=ON \
  -DWHISPER_BUILD_TESTS=OFF
cmake --build "$staging/build" -j --target whisper-cli whisper-server

mkdir -p bin/whisper dist
cp "$staging/build/bin/whisper-cli" "$staging/build/bin/whisper-server" bin/whisper/
tar -czf dist/whisper-v1.9.1-macos-arm64.tar.gz -C bin/whisper whisper-cli whisper-server
echo "whisper_ready=$(pwd)/bin/whisper"
