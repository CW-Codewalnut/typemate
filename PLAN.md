# PLAN.md

## Current milestone

Build the desktop v1 proof path:

```text
focus text field -> hold shortcut -> record -> transcribe locally -> insert text
```

## Current local slices

- Recording adapter through FFmpeg process runner.
- Microphone discovery parser for FFmpeg DirectShow output.
- Unit tests proving adapter command construction, stop behavior, and microphone parsing.

## Next slices

1. **Microphone selection UI**
   - Show discovered microphones in the app shell.
   - Pick a default microphone.
   - Persist selection later, not before it is needed.

2. **Real recording wiring**
   - Wire the selected microphone into the controller through `AudioRecorder`.
   - Show clear error state if FFmpeg or mic permissions fail.

3. **Local STT runtime spike**
   - Benchmark a small whisper.cpp path first.
   - Keep the `SttEngine` interface stable.
   - Do not expose a model picker.

4. **Windows focused-field insertion**
   - Start with the least risky direct insertion path.
   - Clipboard fallback is allowed internally only.

5. **Global hold shortcut**
   - Register a native hold shortcut.
   - Keep a preview button for development and tests.

## Quality gates

Before handoff:

```bash
R:/Tools/flutter/bin/dart format lib test integration_test tool
R:/Tools/flutter/bin/flutter analyze
R:/Tools/flutter/bin/flutter test
```

Before push:

- Ranjan validates proof.
- Local identity and remote are verified.
- Git hooks pass.
- CI is expected to pass on GitHub.

## Open clarification

Ranjan asked to add “git nexus”. This needs clarification if it refers to a specific tool or service. Until clarified, this repo uses git hooks and GitHub Actions as the quality gate.
