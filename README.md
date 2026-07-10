# VoiceMate

A desktop first local voice typing app for developers, AI agent users, and heavy typers.

Focus a text field, hold a shortcut, speak, release, and the transcript appears in the focused field.

## Status

Initial Flutter scaffold. The current app contains the product shell, dictation state machine, settings UI, overlay preview, platform bridge contracts, and STT engine contracts. Native hotkey, microphone capture, model runtime, and text insertion are the next implementation steps.

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
flutter run -d windows
```

## Documentation

- `docs/requirements.md`
- `docs/architecture.md`
