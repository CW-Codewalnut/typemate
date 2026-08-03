#!/usr/bin/env bash
# Strips the on-demand speech models from a release bundle before it is
# zipped/packaged. These models are large (0.15-0.7 GB each) and download
# on first use for the selected language instead of shipping in every
# installer (see lib/src/core/stt/speech_model_catalog.dart). The small
# always-needed files stay bundled: Silero VAD, the GTCRN denoiser model,
# and the whisper binaries.
#
# Also drops the retired bin/sherpa and bin/whisper executables if a
# cached runtime still carries them: every speech engine (Parakeet, the
# whisper fine-tunes, the GTCRN denoiser) runs in-process through plugins
# now. Linux keeps bin/ffmpeg, bin/xdotool, and bin/overlay — capture and
# typing tools, not speech engines.
set -euo pipefail

BUNDLE_DIR="${1:?usage: slim-speech-models.sh <bundle-dir>}"
test -d "$BUNDLE_DIR" || { echo "not a directory: $BUNDLE_DIR" >&2; exit 1; }

rm -rf "$BUNDLE_DIR/models/parakeet-tdt-0.6b-v3-int8" \
       "$BUNDLE_DIR/bin/sherpa" \
       "$BUNDLE_DIR/bin/whisper"
rm -f "$BUNDLE_DIR/models/ggml-small-vaani-hindi-q6.bin" \
      "$BUNDLE_DIR/models/ggml-hindi2hinglish-swift.bin" \
      "$BUNDLE_DIR/models/ggml-vistaar-tamil-small-q5_0.bin"

echo "slimmed on-demand speech models from $BUNDLE_DIR"
