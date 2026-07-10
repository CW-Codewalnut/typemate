# TypeMate Requirements

## Product goal

Build a free, local, desktop first dictation app for developers, AI agent users, writers, and heavy typers.

The core promise is simple: focus a text field, hold a shortcut, speak, release, and the transcript appears in the focused field.

## V1 platforms

V1 targets desktop users first:

- Windows
- macOS
- Linux

The app is built with Flutter so the same product shell can later expand to mobile and tablet. Mobile triggers will use touch buttons, gestures, or keyboard integration after the desktop loop is reliable.

## V1 user experience

1. The app runs in the background with a visible desktop UI for setup and status.
2. The user focuses any text field in another app.
3. The user holds a configurable global shortcut.
4. A compact listening animation appears at the top of the screen.
5. The app records while the shortcut is held.
6. The user releases the shortcut.
7. The app transcribes locally using one high quality default model selected by us.
8. The app inserts the transcript directly into the focused text field.

## Target users

- Developers who command AI agents often
- People who type long prompts
- Writers and operators who type many messages
- Users who want privacy, speed, and no subscription

## V1 must have

- Desktop Flutter app scaffold
- Desktop first architecture for Windows, macOS, and Linux
- Dictation state machine
- Listening overlay UI
- Settings screen for microphone and shortcut
- Platform bridge contract for hotkeys and text insertion
- STT engine contract for local model based transcription
- Model manager contract for first launch download or bundled model
- One default model path, no visible model picker in v1
- Local only privacy posture

## V1 non goals

- No cloud transcription
- No user visible model picker
- No mobile implementation yet
- No web system wide dictation
- No manual copy paste as the primary flow
- No account system

## Future scope

- Native global hold shortcut implementation per desktop OS
- Native text insertion per desktop OS
- Native tray or menu bar integration
- Local model download and checksum verification
- Whisper.cpp runtime adapter
- Parakeet or other high accuracy runtime adapter
- Android touch shortcut or keyboard integration
- Tablet keyboard shortcut support
- Personal vocabulary for technical terms
