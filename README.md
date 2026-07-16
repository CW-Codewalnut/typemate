# TypeMate

A desktop-first, fully local speech-to-typing app for developers, AI agent users, and heavy typers.

Focus any text field, hold **Ctrl+Win**, speak, release — the transcript is typed straight into the focused field. No cloud, no account, no audio leaves your machine.

## Features

- **Hold-to-dictate global shortcut** (default Ctrl+Win, customizable in Settings, including fully custom key combos)
- **Direct insertion** into whatever field has focus, in any app
- **100% local transcription** — all models run on your machine
- **29 languages**, each backed by a model validated for quality and latency:
  - English + 24 European languages on a resident NVIDIA Parakeet server (~1s per utterance, automatic language detection between them, native punctuation)
  - Hindi (Vaani fine-tune, noise-robust Devanagari)
  - Hinglish (writes Hindi speech as romanized Hinglish)
  - Tamil (AI4Bharat Vistaar fine-tune)
- **RAM-friendly**: only the selected language's model stays loaded; switching languages swaps servers automatically
- **System tray**: closing the window hides to tray; dictation keeps working in the background
- **Launch at startup**, dictation history, and a local-only insights dashboard
- No telemetry, no network calls at runtime

## Install (Windows)

1. Download `TypeMate-Setup-vX.Y.Z.exe` from the [latest release](https://github.com/Ranjan-Bhagat/typemate/releases/latest) and run it.
2. Launch Type Mate from the Start menu.
3. Pick a microphone in Settings, focus a text field, hold **Ctrl+Win**, and speak.

Prefer a portable app? Each release also ships `TypeMate-vX.Y.Z-windows-x64.zip` — extract anywhere and run `typemate.exe` directly. All models and runtimes are bundled in both.

## Development

Requires Flutter (managed via FVM in this repo) and Windows for the full dictation loop.

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

The Windows build auto-fetches all speech runtimes (models, whisper.cpp, sherpa-onnx) via `tool/fetch_whisper_runtime.dart`, so a fresh clone builds without manual setup. While the repo is private, assets hosted on this repo's releases download through your authenticated `gh` CLI automatically.

Install local git hooks once per clone:

```bash
bash scripts/install-git-hooks.sh
```

The hooks run formatting, analyzer, tests, and conventional-commit checks before code reaches GitHub.

### Speech runtime notes

- Engine wiring and model table live in `lib/src/app.dart`; the curated language list in `lib/src/models/speech_language_options.dart`.
- `TYPEMATE_WHISPER_MODEL` overrides every bundled model (power-user escape hatch), e.g. point it at `ggml-large-v3.bin` on a high-memory machine.
- Benchmark any model against the persistent audio corpus (`test_assets/stt_benchmark/`):

```bash
dart run tool/benchmark_stt_corpus.dart --model <path.bin> --language hi
```

- Model choices, rejected candidates, and the validation bar are documented in `models/README.md` and `CLAUDE.md`.

## Documentation

- `CLAUDE.md` — engineering guide, STT runtime details, quality bars
- `DESIGN.md` — UI principles
- `models/README.md` — bundled models and why each was chosen
- `docs/requirements.md`, `docs/architecture.md`
