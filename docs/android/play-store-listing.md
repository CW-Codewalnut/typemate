# Play Store listing draft

Draft copy for the Google Play Console listing. Everything here is a
proposal for review; nothing is published from this file.

## App identity

- **App name (30 chars max):** TypeMate: Private Dictation
- **Package id:** `com.codewalnut.typemate` (permanent after first upload;
  confirm before uploading)
- **Category:** Productivity
- **Contains ads:** No. **In-app purchases:** No (v1; a Pro tier may come
  later).

## Short description (80 chars max)

> Private voice typing. Everything transcribes on your phone, nothing in
> the cloud.

## Full description (4000 chars max)

> TypeMate turns your voice into text without sending a single word to
> the internet.
>
> Hold the mic button, speak, release. Your words appear on screen and
> are copied to the clipboard, ready to paste into any app: chats,
> notes, emails, prompts.
>
> **Private by design**
> Speech recognition runs entirely on your phone with a state-of-the-art
> local model (NVIDIA Parakeet). No cloud transcription, no account, no
> audio ever leaves your device. Recordings are deleted the moment they
> are transcribed.
>
> **Made for fast typers and AI power users**
> TypeMate is built for people who write a lot: developers, writers, and
> anyone who talks to AI assistants all day. Speak naturally and paste
> polished text with punctuation.
>
> **25 languages**
> English plus 24 European languages, with automatic language detection.
>
> **History and insights**
> Every dictation is saved locally so you can copy it again later, and
> the Insights view shows how much typing your voice has replaced.
>
> **One-time model download**
> On first use TypeMate downloads its speech model (about 640 MB) so all
> transcription can happen offline afterwards. Wi-Fi recommended.
>
> TypeMate is also available for Windows and Linux, where it types
> directly into any focused app via a global hotkey.

Notes for reviewers of this draft:

- The description intentionally does not promise "types into any app" on
  Android; that is Phase 2 (keyboard/IME).
- RAM guidance: the Parakeet model needs roughly 1.2 GB at runtime, so
  the store listing device targeting should exclude low-RAM devices
  (Play Console device catalog filter), or the description should state
  a recommendation once real-device numbers exist.

## Data safety form (Play Console)

- Data collected: none by default.
- Optional diagnostics: anonymous crash reporting (Sentry) only when the
  user turns on "Share anonymous error reports" in Settings; no audio,
  no transcripts, no identifiers beyond what Sentry requires.
- Audio: recorded only while the user holds the mic button, processed
  on-device, deleted after transcription, never transmitted.

## Assets still needed

- 512x512 icon (have: desktop master `assets/typemate_icon_1024.png`,
  needs export) and 1024x500 feature graphic.
- At least 2 phone screenshots (Dictate ready state, transcript state,
  download state, Settings) — capture from a real device or emulator
  without the debug banner (use a release/profile build).
- Privacy policy URL (see `privacy-policy.md`; must be hosted, e.g.
  `typemate.codewalnut.com/privacy`).

## Release checklist (Android addition to the desktop checklist)

1. Real upload keystore configured in `android/key.properties` +
   `build.gradle.kts` signing config (never commit the keystore).
2. `flutter build appbundle --release` (verified working, 101.8 MB).
   **versionCode:** Play requires a strictly increasing `versionCode`
   per upload. It comes from the `+buildNumber` suffix in
   `pubspec.yaml`'s `version:` — bump it (e.g. `1.5.0+9`) for every
   Play upload, not just the semantic version.
3. Closed testing track first; Play requires review; personal accounts
   created after Nov 2023 additionally require a 12-tester/14-day closed
   test before production access.
4. Verify on a real phone: model download on Wi-Fi, dictation accuracy,
   RAM behavior on the target device tier.

## Phase 2 notes

- Backgrounded downloads: Android freezes the app process in the
  background, which pauses a first-run model download mid-flight. The
  resume flow recovers on next open, but a polished v2 should move the
  download to a foreground service or WorkManager so it survives
  backgrounding.
