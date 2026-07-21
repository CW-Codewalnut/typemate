# TypeMate

**Hold a key. Speak. Your words are typed into whatever app you're using.**

TypeMate is a desktop dictation app for Windows, macOS, and Linux that runs **100% locally** — every word you speak is transcribed by AI models running on your own machine. No cloud, no account, no subscription, and no audio ever leaves your computer.

![TypeMate dictating into a browser](docs/media/demo.gif)

*Dictating straight into Chrome — hold **Ctrl+Win**, speak, release. ([full-quality video](https://github.com/Ranjan-Bhagat/typemate/releases/download/v1.0.0/TypeMate-demo.mp4))*

## Why TypeMate?

- **Your voice stays on your machine.** Cloud dictation tools stream your microphone to someone else's servers. TypeMate bundles the speech models inside the app; it works with Wi-Fi off. Dictation audio is deleted the instant it's transcribed — only the text is kept, in a local history you can clear.
- **It types where you're looking.** No copy-paste, no separate window. Whatever field has focus — a code editor, a browser, a chat box, an AI agent prompt — the transcript is typed there directly, like a keyboard.
- **It's fast enough to replace typing.** English transcribes in about a second per utterance on an ordinary laptop CPU (no GPU needed). Speaking is 3–4× faster than typing for most people; for long prompts to AI agents it's dramatically less tiring.
- **It speaks your languages.** 29 languages, including Hindi, **Hinglish** (Hindi speech written in romanized form — the way people actually text), and Tamil — each backed by a model we validated for accuracy and speed before shipping.
- **It stays out of the way.** Lives in the system tray, starts with Windows if you want, and does nothing until you hold the shortcut.

## See it

![Dictating into a browser with the listening overlay](docs/media/dictate-anywhere.png)

*Works in any app — the pill at the bottom shows TypeMate listening while the shortcut is held.*

![Settings page](docs/media/settings.png)

*One page of settings: language, microphone, shortcut. No accounts, no cloud toggles.*

![Language picker](docs/media/languages.png)

*29 languages, every one backed by a locally validated model.*

![Speech history](docs/media/history.png)

*Every dictation lands in a local-only history you can copy from or clear.*

![Insights dashboard](docs/media/insights.png)

*A usage dashboard — words per minute, streaks, activity — computed entirely from your local history.*

## Install

1. Download the **`TypeMate-Setup-*.exe`** installer from the [latest release](https://github.com/Ranjan-Bhagat/typemate/releases/latest) and run it.
2. Launch **Type Mate** from the Start menu.
3. Pick your microphone in Settings, focus any text field, hold **Ctrl+Win**, and speak.

Prefer a portable app? Each release also ships a `TypeMate-*-windows-x64.zip` — extract anywhere and run `typemate.exe`. All models and runtimes are bundled in both (~1.3 GB installed).

> **SmartScreen note:** the installer is not yet code-signed, so Windows may show "Windows protected your PC" — click *More info → Run anyway*.

## Install (Linux, X11)

1. Download the `TypeMate-*-linux-x64.tar.gz` archive from the [latest release](https://github.com/Ranjan-Bhagat/typemate/releases/latest) and extract it anywhere.
2. Run `./TypeMate/typemate`, hold **Ctrl+Super**, and speak.

Everything is bundled — models, speech engines, audio capture, and typing tools. No packages to install. Recording uses the system-default microphone (change it in your desktop's sound settings).

Linux support targets **X11 sessions** (or apps running under XWayland). Pure Wayland blocks global shortcuts and synthetic typing by design — support for the Wayland portal APIs is planned.

## Install (macOS)

1. Download `TypeMate-macos-arm64.tar.gz` from the [latest release](https://github.com/Ranjan-Bhagat/typemate/releases/latest), extract it, and drag **Type Mate.app** into Applications.
2. Launch it and enable **Type Mate** under System Settings > Privacy & Security > **Accessibility** when prompted. TypeMate types into other apps, and macOS gates that behind this permission.
3. Focus any text field, hold **Ctrl+Cmd**, and speak. Allow **Microphone** access on first use.

Everything is bundled here too: models, speech engines, and typing all live inside the app. Apple Silicon only for now.

> **Gatekeeper note:** the app is not notarized yet, so the first open may be blocked. Right-click **Type Mate.app**, choose *Open*, then *Open* again.

## How it works

![TypeMate architecture: the dictation pipeline and the app's three layers — Flutter app, native platform adapters, bundled speech runtimes](docs/media/architecture.svg)

One dictation, end to end:

```
you hold Ctrl+Win
   └─ FFmpeg records your selected microphone to a WAV
you release
   └─ Silero VAD trims the silence around your speech
   └─ the resident speech server for your language transcribes it
        (the model is already loaded in RAM, so there is no model-load wait)
   └─ the transcript is typed into the focused field with synthetic
        keystrokes (SendInput on Windows, CGEventPost on macOS, xdotool
        on Linux) — exactly as if you had typed it
   └─ the WAV is deleted; the text is saved to your local history
```

The key design decision is the **resident model server**. Loading a speech model from disk takes far longer than actually transcribing a few seconds of audio, so TypeMate starts a small local server for your selected language when the app opens and keeps the model warm in memory. Each dictation then only pays for the transcription itself:

| Language | Model | Typical latency* |
|---|---|---|
| English + 24 European languages | NVIDIA Parakeet TDT 0.6B v3 (int8) | ~1s |
| Hindi | Vaani whisper fine-tune (noise-robust Devanagari) | ~3s |
| Hinglish | Oriserve Swift whisper fine-tune (romanized output) | ~1.5s |
| Tamil | AI4Bharat Vistaar whisper fine-tune | ~2s |

*\*per utterance on a mid-range laptop CPU (i5-11300H), no GPU.*

To keep memory honest, **only the selected language's server stays loaded** — switching languages shuts the old server down and warms the new one up in the background, so RAM isn't wasted on models you aren't using.

## How it's made

- **App shell:** [Flutter](https://flutter.dev) for the desktop UI, with the OS-specific pieces (global hold-shortcut polling, system tray, focused-field text insertion, listening overlay) implemented per platform - `SendInput` in the Win32 runner, `CGEventPost` and an `NSPanel` overlay on macOS, `xdotool` and an X11 helper on Linux - and hidden behind small Dart interfaces so everything is testable with fakes.
- **English + European speech:** [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) serving NVIDIA's Parakeet TDT 0.6B v3 — the most accurate model we benchmarked at any size for Indian-accented English, with automatic language detection across its 25 languages and native punctuation.
- **Indian-language speech:** [whisper.cpp](https://github.com/ggml-org/whisper.cpp) HTTP servers running community fine-tunes of OpenAI's Whisper, one dedicated model per language. Audio is pre-trimmed with Silero voice-activity detection (without it, Whisper hallucinates and repeats sentences while decoding silence).
- **Model curation:** every language in the picker earned its place on a persistent benchmark corpus (`test_assets/stt_benchmark/` — identical audio clips with expected transcripts, replayed against every candidate model). Models that hallucinated, corrupted output, or decoded non-deterministically were **rejected** — which is why some Indian languages aren't in the list yet: Telugu, Kannada, and Gujarati checkpoints all failed repeat-request stability testing (the same audio flips between a correct transcript and fabricated text), and Marathi passed but was cut because its only checkpoint adds ~514 MB. The bar is simple: *if a language is visible, it must work.*
- **Distribution:** models are fetched at build time (they're too large for git), bundled next to the executable, and packaged with [Inno Setup](https://jrsoftware.org/isinfo.php) into the installer. CI runs the analyzer and the full test suite (130+ unit, widget, and adapter tests) on every commit.

## Privacy, concretely

- No network calls at runtime — transcription, history, and insights are all local files under your user profile.
- Dictation audio is transcribe-and-delete; a startup sweep also removes anything a crash left behind.
- No telemetry, no crash reporting, no analytics. The insights dashboard is computed from your local history and never leaves your machine.

## Development

Requires Flutter (managed via FVM in this repo) and Windows for the full dictation loop.

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

The Windows build auto-fetches all speech runtimes (models, whisper.cpp, sherpa-onnx) via `tool/fetch_whisper_runtime.dart`, so a fresh clone builds without manual setup.

Install local git hooks once per clone:

```bash
bash scripts/install-git-hooks.sh
```

The hooks run formatting, analyzer, tests, and conventional-commit checks before code reaches GitHub.

Package a Windows release (zip + Setup installer, version taken from
`pubspec.yaml`):

```bash
bash scripts/package-windows-release.sh
```

### Speech runtime notes

- Engine wiring and the per-language server table live in `lib/src/app.dart`; the curated language list in `lib/src/models/speech_language_options.dart`.
- `TYPEMATE_WHISPER_MODEL` overrides every bundled model (power-user escape hatch), e.g. point it at `ggml-large-v3.bin` on a high-memory machine.
- Benchmark any model against the persistent audio corpus:

```bash
dart run tool/benchmark_stt_corpus.dart --model <path.bin> --language hi
```

- Model choices, rejected candidates, and the validation bar are documented in `models/README.md` and `CLAUDE.md`.

## Documentation

- `CLAUDE.md` — engineering guide, STT runtime details, quality bars
- `DESIGN.md` — UI principles
- `models/README.md` — bundled models and why each was chosen
- `docs/requirements.md`, `docs/architecture.md`

## 🌐 Connect with Us

Stay connected and get support through our community channels:

### 🏢 Official Links

- **🌍 Website:** [codewalnut.com](https://codewalnut.com)
- **📧 Email:** [nattu@codewalnut.com](mailto:nattu@codewalnut.com)
- **📖 Blogs:**
  - **insights:** [codewalnut.com/insights](https://www.codewalnut.com/insights)
  - **learn:** [codewalnut.com/learn](https://www.codewalnut.com/learn)

### 📱 Social Media

- **💼 LinkedIn:** [CodeWalnut](https://www.linkedin.com/company/codewalnut)
- **📺 YouTube:** [CodeWalnut Channel](https://www.youtube.com/@CodeWalnut)
- **🐦 Twitter/X:** [@codewalnut](https://x.com/codewalnut)
- **📷 Instagram:** [@codewalnut](https://www.instagram.com/codewalnut)

### 💬 Community Support

- **📧 Newsletter:** [Subscribe to CodeWalnut Newsletter](https://codewalnut.com/) (scroll down to find the email subscription option)
- **🐙 GitHub:** [codewalnut](https://github.com/CW-Codewalnut)

### 🤝 Professional Services

- **Consulting:** Custom desktop apps, local-first AI, and speech-to-text solutions
- **Training:** Flutter desktop and on-device AI workshops
- **Support:** Enterprise-grade support and maintenance

📢 **Follow us for updates on new tools, AI integrations, and local-first products!**

## 📜 License

This project is licensed under the [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0).

You can find the full license text in the [`LICENSE`](./LICENSE) file.
