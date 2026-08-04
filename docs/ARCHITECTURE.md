# TypeMate Architecture

## Overview

TypeMate is one Flutter app serving Windows, Linux, macOS, and Android.
Flutter owns the product shell, state, settings, history, and insights.
Small per-platform native pieces own the global shortcut, overlays, and
text insertion, hidden behind Dart interfaces so everything is testable
with fakes. Every speech engine runs **in-process** through Flutter
plugins — there are no helper server processes and no speech binaries.
The desktop dictation overlay is a second Flutter window
(desktop_multi_window) restyled from Dart FFI
(lib/src/core/platform/overlay/) — never-focusable by construction.
The macOS driver is build-verified only; it awaits a real-hardware
pass.

A rendered diagram lives at `docs/media/architecture.svg` (embedded in
the README).

## Layers

```text
Flutter app (lib/src/features, lib/src/components)
  Dictate shell, settings, insights, download cards, mic FAB

Core (lib/src/core)
  dictation_controller.dart   the dictation state machine
  audio/                      recording + GTCRN noise suppression
  stt/                        engines, model catalog, provisioners
  platform/                   per-OS bridges (shortcut, overlay, insertion)

Native, per platform
  windows/  Win32 runner: key polling, tray, SendInput
  linux/    bundled ffmpeg (capture), xdotool (typing)
  macos/    osascript paste, key polling
  android/  accessibility service: floating mic, focused-field insertion
```

## The speech stack

- `createSpeechRuntime` (lib/src/core/stt/speech_runtime.dart) builds
  the whole stack for **every** platform: a `LanguageRoutingSttEngine`
  over the in-process engines, the GTCRN denoiser, and per-language
  model provisioners.
- **English + 24 European languages**: `SherpaParakeetSttEngine` — the
  sherpa_onnx plugin running NVIDIA Parakeet TDT 0.6B v3 int8 in a
  long-lived isolate.
- **Hindi / Hinglish / Tamil**: `WhisperGgmlSttEngine` — a thin FFI
  client of the whisper_ggml plugin's native layer (whisper.cpp
  v1.9.1, AVX2 baseline; our fork adds a resident-model cache and
  Silero VAD, offered upstream). Greedy decoding, no prompts, VAD trim
  — all corpus-locked (see CLAUDE.md).
- **RAM policy**: only the selected language's engine stays loaded;
  switching languages releases the old model and warms the new one.
- **Models**: `speech_model_catalog.dart` pins every model's URL, exact
  byte size, and SHA-256. Slim installs download on first use through
  `SttModelProvisioner` (background_downloader); a bundled copy always
  wins over downloading. Nothing unverified can reach a native loader.

## Core contracts

- `DictationController` — the state machine: start listening → overlay
  → stop → transcribe → insert → idle, with failure states and the
  `dictationBlocker` that refuses dictation (with a reason) while the
  selected model is missing.
- `PlatformBridge` — `isGlobalShortcutAvailable`,
  `registerHoldShortcut`, `showListeningOverlay` /
  `showTranscribingOverlay` / `hideListeningOverlay`,
  `showErrorOverlay`, `insertTextIntoFocusedField`,
  `ensureLaunchAtStartup`.
- `SttEngine` / `DisposableSttEngine` — `isReady`, `prepare`,
  `transcribe`, `shutdown`. `MockSttEngine` exists for tests only.
- `SpeechModelProvisioner` — phases (downloadRequired → downloading →
  ready/failed), progress, and resume/adoption semantics (Android
  adopts OS-managed downloads; desktop clears stale records).

## Platform notes

- **Windows**: capture via the record plugin (MediaFoundation);
  insertion via SendInput; polling hold-shortcut registrar. The
  overlay is the shared Flutter overlay window (Win32 layered
  no-activate popup via Dart FFI).
- **Linux**: X11 only. Fully self-contained `bin/`: static ffmpeg
  (ALSA capture via the system-default device) and xdotool + libxdo
  (typing). libX11 FFI keymap polling drives the shortcut. Wayland
  reports unavailable by design.
- **macOS**: clipboard + synthesized Cmd+V via osascript (needs
  Accessibility); shared Flutter overlay via ObjC-runtime FFI;
  preview status.
- **Android**: an accessibility service hosts the floating mic bubble
  and inserts text into the focused field; dictation failures render as
  an overlay pill (background services may not toast); a headless
  service entrypoint (`dictationServiceMain`) runs dictation without
  the full UI.

## Testing

Unit and widget tests fake every native boundary; integration tests run
the real app shell on each platform in CI (Windows, Linux, macOS on
flutter-tester, and an Android emulator), including a real slim-install
model download. Speech quality is proven against the persistent corpus
in `test_assets/stt_benchmark/` via the tools in `tool/`.
