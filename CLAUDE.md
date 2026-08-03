# CLAUDE.md

## TypeMate engineering guide

TypeMate is a local, desktop-first Flutter dictation app for developers, AI agent users, and heavy typers. The app should feel fast, private, and quiet: hold a shortcut, speak, release, and text appears in the focused field.

## Current stack

- Flutter and Dart
- Desktop targets: Windows, macOS, Linux
- Windows audio uses the `record` plugin (MediaFoundation, built into Windows 10/11 — no external binaries) behind adapter contracts; the FFmpeg DirectShow adapter remains only as a non-default fallback
- Linux (X11) support is fully self-contained — users install NOTHING: a bundled static ffmpeg captures via ALSA's `default` device (PipeWire/Pulse route it to the system-selected mic; the picker shows a single "System default microphone" entry), a bundled xdotool+libxdo (LD_LIBRARY_PATH set at spawn) types the transcript, libX11 FFI keymap polling drives the global shortcut, XDG config/autostart. All Linux tool binaries (static ffmpeg, xdotool, our static whisper v1.9.1 build) are hosted on the models-v1 release; sherpa uses the upstream linux-x64-static-no-tts archive. CRITICAL: build the Linux whisper.cpp binaries with `-DGGML_NATIVE=OFF -DGGML_AVX2=ON -DGGML_AVX512=OFF` (portable AVX2 baseline). A `-march=native` build on an AVX-512 machine bakes in AVX-512 and dies with SIGILL ("Illegal instruction") on the majority of user CPUs that lack it — this silently broke every whisper language (Hindi/Hinglish/Tamil) on Linux while Parakeet/sherpa kept working. Verify a rebuilt whisper binary loads a model on a non-AVX-512 CPU (the Lubuntu VM) before shipping. Wayland is unsupported by design (no synthetic input); the bridge reports it via `isGlobalShortcutAvailable`. WSL2+WSLg on this machine builds and runs the Linux app for local verification (`wsl -e bash`, repo copied to `~/typemate`, Flutter SDK at `~/sdk/flutter`) but has no ALSA devices — mic capture verifies only on a real desktop/VM.
- Local transcription uses whisper.cpp CLI when configured
- Tests use `flutter_test` and `integration_test`
- GitNexus is installed as a repo dev tool for code graph/indexing. It is not JavaScript/TypeScript-only; keep it available through `npm run gitnexus:analyze` and `npm run gitnexus:status`.

## Folder strategy

Keep `lib/src/` as the implementation root. In Dart packages, `lib/src` is the normal convention for private package internals; only intentionally public APIs should live directly under `lib/`.

Use feature folders for product areas and keep feature-only UI inside that feature:

```text
lib/
  main.dart
  src/
    app.dart
    features/
      home/
        home_screen.dart
      dictate/
        dictate_page.dart
        components/
      insights/
        insights_page.dart
        components/
      settings/
        settings_page.dart
        components/
        utils/
    components/        shared UI components used by multiple features
    utils/             shared non-UI helpers
    core/
      audio/           audio recording, microphone discovery, recorder factories
      platform/        global shortcut, overlay, active field, text insertion contracts
        windows/       Win32 adapters (bridge, polling shortcut registrar)
        linux/         X11 adapters (bridge, keymap-polling shortcut registrar)
      stt/             local transcription engine contracts/adapters
      *_controller.dart
      *_store.dart
      insights_stats.dart
    models/            simple shared models and enums
```

Rules:

- Feature pages own page composition.
- Feature-only widgets live in that feature's `components/` folder.
- Feature-only helpers live in that feature's `utils/` folder.
- Shared widgets go in `lib/src/components/` only when used by multiple features.
- Shared pure helpers go in `lib/src/utils/`.
- Core services/adapters that back the product flow live under `lib/src/core/`.
- UI imports controllers, simple models, and service contracts. It should not know low-level process command details.
- `core/audio`, `core/stt`, and `core/platform` hide native/process details behind interfaces.
- Prefer constructor injection so tests can use fake adapters.

## Product constraints

- V1 is local-only. No cloud transcription.
- The app selects one model per supported language. Do not add a user-visible model picker.
- Direct insertion into the focused field is the product path. Clipboard can be an internal fallback, not the primary UX.
- Desktop first. Mobile/tablet ideas belong in docs until the desktop loop works.
- Do not show placeholder tabs, buttons, metrics, or destinations. If it is visible, it must work.

## Local STT runtime

- There are NO speech binaries anymore: every engine runs in-process. English (Parakeet) and the GTCRN noise-suppression denoiser run through the sherpa_onnx plugin; Hindi, Hinglish, and Tamil run through the whisper_ggml plugin (whisper.cpp v1.9.1, AVX2 baseline), consumed as a pinned git dependency on our patched fork `CW-Codewalnut/whisper_ggml` (adds resident-model cache, audio_ctx, and Silero VAD passthrough; offered upstream as sk3llo/whisper_ggml#27). `bin/` exists only on Linux, for ffmpeg (capture), xdotool (typing), and the X11 overlay — tools, not speech engines. The LARGE models are NOT shipped in release installers: `scripts/slim-speech-models.sh` strips them from every artifact, and the app downloads the selected language's model on first use into `<data dir>/models/` (size + SHA-256 verified against `lib/src/core/stt/speech_model_catalog.dart` before a file can look complete — a corrupt model aborts the native loader, so nothing unverified may reach it). A bundled copy always wins over downloading, so dev checkouts and `flutter run` (which fetch everything via `tool/fetch_whisper_runtime.dart`) never download at runtime. Small always-needed models stay bundled: Silero VAD and GTCRN.
- English runs IN-PROCESS: `LanguageRoutingSttEngine` routes `en` (and the 24 other Parakeet languages) to `SherpaParakeetSttEngine`, which loads NVIDIA Parakeet TDT 0.6B v3 int8 through the sherpa_onnx FFI plugin in a long-lived isolate — the same engine Android uses, 4 decode threads on desktop. No server process, no port, no startup handshake; a load failure surfaces as a real exception instead of a connection timeout (this replaced the retired sherpa websocket server and eliminated its "server did not start"/60s-timeout failure class seen in Sentry). Per-utterance English is ~1s with the best accuracy of every model benchmarked.
- Hindi, Hinglish, and Tamil run IN-PROCESS through `WhisperGgmlSttEngine` on every platform including Android: the model loads once (`keep_model_loaded` in our fork) and stays resident in native process globals; Silero VAD trims hold-to-talk silence per request (without it whisper loops over silent lead/tail); greedy decoding with `no_fallback` (temperature fallback measurably slowed Tamil 50%+ with no quality change); NO initial prompts (the fine-tunes carry their scripts natively — a prompt bleeds its own characters into the transcript and slows decoding, corpus-verified). Hindi: `ggml-small-vaani-hindi-q6.bin` (Vaani small, noise-robust Devanagari). Hinglish: `ggml-hindi2hinglish-swift.bin` (Oriserve Swift base, romanized; our GGML conversion on this repo's releases). Tamil: AI4Bharat Vistaar small q5_0 (our quantization, `models-v1` release). Corpus-verified per-utterance (13s clips, warm): Hindi ~5s, Hinglish ~1.5s, Tamil ~11s (scales with clip length). `audio_ctx` is deliberately NOT used on this path: on the plugin's no-BLAS AVX2 build it measured slower and produced artifacts. Telugu, Kannada, and Gujarati were evaluated and REJECTED: their checkpoints decode non-deterministically (thin logit margins — identical requests flip between correct output and hallucinations, at every quantization level and even fp16; disabling temperature fallback does not help). Marathi validated cleanly (word-perfect, ~5.5s) but was CUT for install size — its only checkpoint is medium (~514 MB); the quantized GGML is archived at `R:/Models/whisper/` and on the `models-v1` release for an easy re-add. Vistaar Hindi was benchmarked against Vaani and lost (first-char corruption, slightly slower) — keep Vaani for Hindi. Always validate repeat-request stability (3+ identical requests to a warm server) before shipping a new whisper fine-tune.
- RAM policy: only the SELECTED language's engine is kept loaded. `LanguageRoutingSttEngine` shuts every other disposable engine down before preparing or using the active one, and the app preloads the newly selected engine on language change (`speechSettingsController` listener) — unless that language's model is not downloaded yet, in which case the Dictate-tab dictation surface (`DictationCard`, shared with mobile) offers the download and prepares once it completes; the global shortcut is refused with a failure toast until then (`dictationBlocker`).
- `TYPEMATE_WHISPER_MODEL` overrides everything: it routes every language through the in-process whisper engine with that model file and the selected language's flag. (`TYPEMATE_WHISPER_CLI` is retired with the binaries.)
- `hinglish` is a TypeMate-internal language code: the engine maps it to whisper's `hi` flag and sends no script prompt (the fine-tune romanizes on its own).
- There is no Auto language option: detection needs the full encoder window (several times slower) and misfires into garbage transcripts. Default language is English.
- All models are gitignored (they exceed practical git limits). The Windows CMake build fetches anything missing automatically via `tool/fetch_whisper_runtime.dart`, so `flutter build windows` and `flutter run -d windows` work on a fresh clone; the script can also be run manually. Release builds copy `models/` and `bin/` next to the executable, then packaging strips the on-demand models (see `scripts/slim-speech-models.sh`).
- Resolution order for each piece: env override (`TYPEMATE_WHISPER_CLI` / `TYPEMATE_WHISPER_MODEL`), then the bundled path relative to the working directory, then relative to the executable directory. Large models have one more step: when no bundled copy exists, the engine points into `<data dir>/models/` and `LanguageAwareModelProvisioner` downloads there on demand.
- There is no mock fallback in production. If the CLI or model cannot be found, `createDefaultSttEngine` throws `SttRuntimeException` — a missing runtime is an installation defect, not a mode.
- `MockSttEngine` exists for tests only, injected explicitly (e.g. `TypeMateApp(sttEngine: MockSttEngine())`). Do not use it as proof that real dictation works.
- The engine uses greedy decoding and, when an explicit language is selected, right-sizes `--audio-ctx` to the clip length; both are required for acceptable push-to-talk latency on laptop CPUs. Do not pass a reduced `--audio-ctx` with `auto` language — detection misfires and produces garbage transcripts.
- The engine always runs Silero VAD (`models/ggml-silero-v5.1.2.bin`, `--vad-speech-pad-ms 100`) to trim hold-to-talk silence. Without it whisper loops and repeats sentences while decoding the silent lead/tail; 100ms padding keeps the first word intact (larger padding garbles segment boundaries).
- Optional high-quality override: `R:/Models/whisper/ggml-large-v3.bin` via `TYPEMATE_WHISPER_MODEL` on high-memory machines.
- The language picker is curated (`lib/src/models/speech_language_options.dart`): the 25 Parakeet languages (English + 24 European, all served by the resident server with automatic language detection) plus Hindi, Hinglish, and Tamil. Do not add a language without a validated dedicated model (quality and latency) first.
- Use `tool/benchmark_whisper_cli.dart` to prove real transcription with a WAV sample, and `tool/benchmark_stt_corpus.dart` with the persistent corpus at `test_assets/stt_benchmark/` (TTS clips + `manifest.json` expected transcripts) to compare models on identical audio.
- Keep stderr diagnostics out of successful transcripts; whisper.cpp writes model/timing logs to stderr.

## Design principles

- YAGNI: build only the next needed v1 slice.
- DRY: remove meaningful duplication, but do not over-abstract early.
- Keep classes small and names explicit.
- Prefer boring, testable code over clever code.
- Fail clearly when native tools or permissions are missing.

## Testing policy

Every behavior change needs tests first unless it is pure documentation or generated boilerplate.

Use the repo FVM Flutter/Dart binaries on this machine:

```bash
/c/Users/ranja/fvm/versions/3.44.6/bin/dart.bat format lib test tool integration_test
/c/Users/ranja/fvm/versions/3.44.6/bin/flutter.bat analyze
/c/Users/ranja/fvm/versions/3.44.6/bin/flutter.bat test
/c/Users/ranja/fvm/versions/3.44.6/bin/flutter.bat build windows --release
```

Expected coverage:

- Unit tests for parsers, state machines, stats, and adapters.
- Widget tests for screens and UI states.
- Integration/e2e tests for the app shell and eventually full dictation loop.

## GitNexus

GitNexus is installed as a dev dependency and should be kept unless Ranjan explicitly asks to remove repo indexing tools.

```bash
npm run gitnexus:analyze
npm run gitnexus:status
```

The analyzer may warn that LadybugDB FTS/BM25 search is unavailable. That warning does not mean indexing failed; basic graph indexing still works.

## Release process

Every release follows this checklist — no partial releases:

1. **Version** comes only from `pubspec.yaml` (`version:`). It flows to the
   Settings label (package_info), the Windows exe metadata (Runner.rc via
   FLUTTER_VERSION), the installer filename, and the .deb/.rpm metadata.
   Never hardcode a version anywhere else (README included).
2. **All platforms ship together.** A release is not done until it carries:
   - `TypeMate-Setup-vX.Y.Z.exe` (Inno Setup, `installer/typemate.iss`)
   - `TypeMate-vX.Y.Z-windows-x64.zip`
   - `TypeMate-vX.Y.Z-linux-x64.tar.gz` (portable)
   - `typemate_X.Y.Z_amd64.deb` (`scripts/package-linux-deb.sh`)
   - `typemate-X.Y.Z-1.x86_64.rpm` (`scripts/package-linux-rpm.sh`)
   Windows packaging: `scripts/package-windows-release.sh` (zip + Setup exe).
3. **Verify on real systems before uploading**: Windows build runs on this
   machine (screenshot proof); Linux artifacts install and run in the
   Lubuntu VM (SSH access: key `~/.ssh/typemate_vm`, port 2222 via VBox NAT
   forward). Test the full loop: install, launch from menu, hotkey/overlay,
   close-to-background, relaunch-resurface.
4. **Release PR**: raise a PR from `dev` to `main` for every release so it
   gets an external review before merge. Do not merge it yourself.
   (`tip` is a stale historical branch — not the release target.)
5. **Publishing needs Ranjan's explicit go-ahead** — for creating a
   release, replacing an asset, or deleting one. Build and show proof
   first, then wait.

## Git workflow

- Conventional commits only:
  - `feat: ...`
  - `fix: ...`
  - `refactor: ...`
  - `test: ...`
  - `docs: ...`
  - `chore: ...`
  - `ci: ...`
- Do not push until Ranjan validates proof and approves.
- Before commit or push, verify active account, remote, and local identity.
- Keep commits focused. Do not mix unrelated product code, formatting churn, and docs.

## CI and hooks

The repo should enforce quality in two places:

1. Local git hooks for fast feedback before commit and push.
2. GitHub Actions CI for clean verification on the remote.

If hooks block a commit, fix the code instead of bypassing hooks unless Ranjan explicitly approves.

## UI and design

Follow `DESIGN.md`. Keep the app calm, focused, and desktop-native. Avoid adding visual complexity before the core dictation loop is proven.

## Proof expectations

Before asking for push approval, show:

1. What changed.
2. What behavior it proves.
3. Targeted test output.
4. Full analyzer and test output.
5. Git status showing the change is local only.
6. Anything not yet proven.

Use text or screenshots for terminal-only proof. For UI proof, use an actual app screenshot or video where icons and text render correctly. Crop screenshots to the app window only; never share full desktop or multi-monitor captures. Do not create synthetic UI proof images or golden-test screenshots unless Ranjan explicitly asks for them.
