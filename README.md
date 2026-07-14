# TypeMate

A desktop first local speech powered typing app for developers, AI agent users, and heavy typers.

Focus a text field, hold a shortcut, speak, release, and the transcript appears in the focused field.

## Status

The current app contains the product shell, dictation state machine, microphone discovery/selection UI, FFmpeg recording adapters, local STT contracts, a whisper.cpp CLI adapter, runtime-selection fallback, and failure recovery for recording, transcription, and insertion. Native global hotkey registration and real focused-field insertion are still pending.

## V1 direction

- Desktop first: Windows, macOS, Linux
- Local speech to text only
- One default model selected by us
- No visible model picker in v1
- Global hold to dictate shortcut
- Direct insertion into the focused text field

## Development

```bash
flutter pub get
flutter analyze
flutter test
flutter test integration_test
flutter run -d windows
```

### Local whisper.cpp runtime

TypeMate uses `MockSttEngine` unless both runtime environment variables are set:

```bash
export TYPEMATE_WHISPER_CLI="R:/Tools/whisper.cpp/v1.9.1-x64/Release/whisper-cli.exe"
export TYPEMATE_WHISPER_MODEL="R:/Models/whisper/ggml-base.bin"
```

With those set, the app constructs `WhisperCliSttEngine` and uses the configured local model. No model picker is exposed in the UI.

To benchmark/prove the real local STT path with a WAV sample:

```bash
dart run tool/benchmark_whisper_cli.dart --audio build/recordings/typemate-benchmark.wav
```

The benchmark prints the runtime path, model path, audio path, elapsed milliseconds, and transcript.

Install local git hooks once per clone:

```bash
bash scripts/install-git-hooks.sh
```

The hooks run formatting, analyzer, tests, and conventional commit checks before code reaches GitHub.

## Documentation

- `AGENTS.md`
- `CLAUDE.md`
- `PLAN.md`
- `DESIGN.md`
- `docs/requirements.md`
- `docs/architecture.md`
