# TypeMate listening overlay (X11)

A tiny always-on-top, borderless, non-focus-stealing pill shown while
dictating. `LinuxPlatformBridge` spawns it and writes `listening` /
`transcribing` / `hide` to its stdin. `override_redirect` keeps it above the
window manager without ever taking input focus, so the transcript still types
into the field the user had focused.

Dictation sounds (start chime, failure tone) are played by the app itself
(`lib/src/core/platform/dictation_sounds.dart`), not by this helper.

`tool/fetch_whisper_runtime.dart` compiles this source into
`bin/overlay/typemate-overlay` during the Linux build (needs gcc plus the
libX11/libXext dev headers), so the shipped overlay always matches the
source — there is no prebuilt binary to keep in sync. The manual build
command is:

    gcc typemate_overlay.c -o typemate-overlay -lX11 -lXext -lm
