# TypeMate listening overlay (X11)

A tiny always-on-top, borderless, non-focus-stealing pill shown while
dictating. `LinuxPlatformBridge` spawns it and writes `listening` /
`transcribing` / `hide` to its stdin. `override_redirect` keeps it above the
window manager without ever taking input focus, so the transcript still types
into the field the user had focused.

Build (links libX11/libXext, present on every X11 desktop):

    gcc typemate_overlay.c -o typemate-overlay -lX11 -lXext -lm

Dictation sounds (start chime, failure tone) are played by the app itself
(`lib/src/core/platform/dictation_sounds.dart`), not by this helper.

The compiled binary is hosted on the `models-v1` release
(`typemate-overlay-linux-x64.tar.gz`) and fetched into `bin/overlay/` by
`tool/fetch_whisper_runtime.dart`.
