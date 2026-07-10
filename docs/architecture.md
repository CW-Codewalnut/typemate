# Dictation Flow Architecture

## Overview

Dictation Flow is one Flutter app with a desktop first implementation. Flutter owns the product shell, state, onboarding, settings, and overlay. Platform specific code owns global shortcuts, focused field tracking, and direct text insertion. The local STT runtime owns transcription.

## Layers

```text
Flutter App
  Settings, status, overlay, onboarding, dictation state

Platform Bridge
  Global shortcut, active field tracking, text insertion, tray integration

Audio and STT Layer
  Recording, local model runtime, transcription result

Model Manager
  Default model install, checksum verification, runtime readiness
```

## Core contracts

### Dictation controller

Coordinates the user flow:

1. Start listening
2. Show overlay
3. Stop listening
4. Transcribe audio
5. Insert transcript
6. Return to idle

### Platform bridge

Platform specific implementations will provide:

- `isGlobalShortcutAvailable`
- `registerHoldShortcut`
- `showListeningOverlay`
- `hideListeningOverlay`
- `insertTextIntoFocusedField`

### STT engine

Runtime implementations will provide:

- `isReady`
- `prepare`
- `transcribe`

V1 starts with a mock engine in the Flutter scaffold. The first real runtime adapter should be selected after a short benchmark. The likely first production adapter is whisper.cpp because it packages more reliably across Windows, macOS, and Linux.

## Desktop implementation notes

### Windows

- Global shortcut through native Windows plugin
- Overlay through Flutter window or native always on top window
- Text insertion through UI automation or internal paste fallback

### macOS

- Requires accessibility permissions for system wide insertion
- Menu bar integration is expected
- Overlay can use a transparent Flutter window

### Linux

- X11 is more practical for global shortcuts and insertion
- Wayland may require documented limitations or desktop portal based approaches

## Mobile future

Mobile should reuse the same dictation state machine and UI language. The start and stop trigger changes:

- Phone, touch shortcut or gesture
- Tablet with keyboard, same shortcut concept as desktop
- Android, possible IME or accessibility integration
- iOS, keyboard extension constraints need feasibility testing
