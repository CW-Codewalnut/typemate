# CLAUDE.md

## TypeMate engineering guide

TypeMate is a local, desktop-first Flutter dictation app for developers, AI agent users, and heavy typers. The app should feel fast, private, and quiet: hold a shortcut, speak, release, and text appears in the focused field.

## Current stack

- Flutter and Dart
- Desktop targets: Windows, macOS, Linux
- Windows audio uses FFmpeg DirectShow behind adapter contracts
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
      history/
        history_page.dart
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
      platform/        global shortcut, overlay, active field, text insertion contracts/adapters
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
- V1 uses one default local model selected by the app. Do not add a user-visible model picker.
- Direct insertion into the focused field is the product path. Clipboard can be an internal fallback, not the primary UX.
- Desktop first. Mobile/tablet ideas belong in docs until the desktop loop works.
- Do not show placeholder tabs, buttons, metrics, or destinations. If it is visible, it must work.

## Local STT runtime

- The whisper runtime is fully bundled with the app: the model at `models/ggml-large-v3-turbo-q5_0.bin` and the CLI (whisper.cpp v1.9.1 OpenBLAS build) at `bin/whisper/whisper-cli.exe`. No machine-specific paths.
- Both are gitignored (the model exceeds GitHub's 100 MB file limit). The Windows CMake build fetches anything missing automatically via `tool/fetch_whisper_runtime.dart`, so `flutter build windows` and `flutter run -d windows` work on a fresh clone; the script can also be run manually. Release builds copy `models/` and `bin/` next to the executable.
- Resolution order for each piece: env override (`TYPEMATE_WHISPER_CLI` / `TYPEMATE_WHISPER_MODEL`), then the bundled path relative to the working directory, then relative to the executable directory.
- There is no mock fallback in production. If the CLI or model cannot be found, `createDefaultSttEngine` throws `SttRuntimeException` — a missing runtime is an installation defect, not a mode.
- `MockSttEngine` exists for tests only, injected explicitly (e.g. `DictationFlowApp(sttEngine: MockSttEngine())`). Do not use it as proof that real dictation works.
- The engine uses greedy decoding and, when an explicit language is selected, right-sizes `--audio-ctx` to the clip length; both are required for acceptable push-to-talk latency on laptop CPUs. Do not pass a reduced `--audio-ctx` with `auto` language — detection misfires and produces garbage transcripts.
- Optional high-quality override: `R:/Models/whisper/ggml-large-v3.bin` via `TYPEMATE_WHISPER_MODEL` on high-memory machines.
- The language picker is curated (`lib/src/models/speech_language_options.dart`): only languages the bundled model transcribes well are visible. Do not re-add a language without validating real dictation quality first.
- Use `tool/benchmark_whisper_cli.dart` to prove real transcription with a WAV sample.
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
