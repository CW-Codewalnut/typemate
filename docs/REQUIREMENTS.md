# TypeMate Requirements

## Product goal

A free, local dictation app for developers, AI agent users, writers,
and heavy typers.

The core promise: focus a text field, hold a shortcut, speak, release,
and the transcript appears in the focused field — with nothing leaving
the device.

## Platforms

Shipped and supported:

- **Windows** (installer + portable zip)
- **Linux, X11** (.deb, .rpm, portable tarball; Wayland is out of scope
  by design — no synthetic input)
- **Android** (sideload APK; in-app dictation plus a floating mic
  accessibility overlay for dictating into any app)

Preview:

- **macOS** (unsigned developer preview zip; full loop works once the
  Mac grants Input Monitoring and Accessibility permissions)

One Flutter codebase serves all of them; desktop and mobile differ only
in UI scaling and each platform's native trigger/insertion idiom.

## User experience contract

1. The app runs in the background with a visible UI for setup, history,
   insights, and status.
2. The user focuses any text field in another app.
3. The user holds the global shortcut (Ctrl+Win on Windows, Ctrl+Super
   on Linux; on Android, holds the floating mic or a hardware
   keyboard's Ctrl+Meta).
4. A compact listening pill appears on screen, outside the app window.
5. Release stops recording; the transcript is typed into the focused
   field as if from the keyboard.
6. Failures surface as a toast at the overlay position with the reason;
   dictation is refused with a reason while the selected language's
   model is not downloaded.

## Speech quality bar

- One validated model per language, chosen by us — no user-visible
  model picker, no Auto language detection (both proved to hurt quality
  or latency).
- A language is only visible in the picker if its model passed the
  persistent benchmark corpus for accuracy, latency, AND
  repeat-request stability (see CLAUDE.md for the current model table
  and the rejected candidates).

## Privacy posture

- Local-only transcription; the only network use is the one-time,
  size- and SHA-256-verified model download per selected language.
- Dictation audio is transcribe-and-delete; history stores text only,
  locally, clearable.
- Anonymous error reporting is opt-in, off by default, and scrubbed of
  paths and user text.

## Non-goals

- No cloud transcription
- No user-visible model picker, no Auto language option
- No account system, no subscription
- No manual copy-paste as the primary flow
- No placeholder UI: if it is visible, it must work

## Future scope

See BACKLOG.md.
