# CLAUDE.md

## TypeMate engineering guide

TypeMate is a local, desktop-first Flutter dictation app for developers, AI agent users, and heavy typers. The app should feel fast, private, and quiet: hold a shortcut, speak, release, and text appears in the focused field.

## Current stack

- Flutter and Dart
- Desktop targets: Windows, macOS, Linux
- Current Windows audio experiments use FFmpeg DirectShow through adapter contracts
- Tests use `flutter_test` and `integration_test`

## Folder strategy

Use a clean, layered layout with feature-oriented subfolders where the code naturally grows. Keep boundaries clear:

```text
lib/src/audio/       audio recording, microphone discovery, process runners
lib/src/core/        orchestration and state machines
lib/src/models/      simple shared models and enums
lib/src/platform/    global shortcut, overlay, active field, text insertion contracts
lib/src/stt/         local transcription engine contracts and adapters
lib/src/ui/          Flutter screens, widgets, presentation-only state
```

Rules:

- UI imports controllers and simple models, not process runners directly.
- `core` coordinates flows, but does not know FFmpeg command details.
- `audio`, `platform`, and `stt` hide native/process details behind interfaces.
- Prefer constructor injection so tests can use fake adapters.

## Product constraints

- V1 is local-only. No cloud transcription.
- V1 uses one default local model selected by the app. Do not add a user-visible model picker.
- Direct insertion into the focused field is the product path. Clipboard can be an internal fallback, not the primary UX.
- Desktop first. Mobile/tablet ideas belong in docs until the desktop loop works.

## Design principles

- YAGNI: build only the next needed v1 slice.
- DRY: remove meaningful duplication, but do not over-abstract early.
- Keep classes small and names explicit.
- Prefer boring, testable code over clever code.
- Fail clearly when native tools or permissions are missing.

## Testing policy

Every behavior change needs tests first unless it is pure documentation or generated boilerplate.

Use:

```bash
R:/Tools/flutter/bin/flutter test test/<targeted_test>.dart --reporter expanded
R:/Tools/flutter/bin/flutter analyze
R:/Tools/flutter/bin/flutter test --reporter expanded
```

Expected coverage:

- Unit tests for parsers, state machines, and adapters.
- Widget tests for screens and UI states.
- Integration/e2e tests for the app shell and eventually full dictation loop.

## Git workflow

- Conventional commits only:
  - `feat: ...`
  - `fix: ...`
  - `test: ...`
  - `docs: ...`
  - `chore: ...`
  - `ci: ...`
- Do not push until Ranjan validates proof and approves.
- Before commit or push, verify active account, remote, and local identity.
- Keep commits focused. Do not mix product code, formatting churn, and unrelated docs unless the change is intentionally repo setup.

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
