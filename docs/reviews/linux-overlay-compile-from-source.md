# Review guide: compile the Linux overlay from source

**Branch:** `fix/linux-overlay-compile-from-source`
**Type:** bug fix + build change (Linux only). No product/Dart app-code changes.

## The bug this fixes

TypeMate v1.3.0 shipped a Linux-only defect: **the dictation start chime
plays twice.**

Why: v1.3.0 moved all dictation sounds into the app itself
(`lib/src/core/platform/dictation_sounds.dart`, plays the WAV assets via
`pw-play`/`paplay`/`aplay`). But the Linux **overlay helper**
(`linux/overlay/typemate_overlay.c`, the small always-on-top "listening"
pill) historically played the same chime itself via ALSA. The source was
updated to remove that chime, **but the binary the build actually ships
was not rebuilt from that source** — it was downloaded as a prebuilt
artifact from the `models-v1` GitHub release, and that hosted binary still
contained the ALSA chime code. So at dictation start the app played the
chime AND the overlay played the chime → two beeps.

Evidence (hosted binary vs source-built binary):

```
hosted typemate-overlay:   30856 bytes, strings shows libasound.so.2 + snd_pcm_*
source-built (this branch): 21448 bytes, zero libasound references
```

## Root cause, stated plainly

A **prebuilt binary hosted on a GitHub release drifted from its source**.
Fetching a prebuilt artifact means the binary and the source can disagree,
and nothing catches it. This is the second time this exact class of bug
has bitten the overlay.

## The fix

Stop shipping a prebuilt overlay binary. **Compile it from the in-repo
source during the build**, so the shipped overlay is always exactly what
`linux/overlay/typemate_overlay.c` says.

`tool/fetch_whisper_runtime.dart` already runs during every Linux build
(invoked by `linux/CMakeLists.txt`) to fetch runtime tools. The overlay's
`_fetchToolArchive(...)` call is replaced with a new `_compileLinuxOverlay`
that runs:

```
gcc linux/overlay/typemate_overlay.c -o bin/overlay/typemate-overlay -lX11 -lXext -lm
```

Because this runs in the same place for **both CI and local builds**, both
now build the overlay identically. There is no longer any hosted overlay
binary to keep in sync.

## Files changed (4)

| File | Change |
|------|--------|
| `tool/fetch_whisper_runtime.dart` | Replace overlay download with `_compileLinuxOverlay`; update the runtime-revision comment |
| `.github/workflows/release.yml` | Add `libx11-dev libxext-dev` to the Linux builder's apt install (to compile the overlay) |
| `.github/workflows/ci.yml` | Same apt addition for the Linux test job |
| `linux/overlay/README.md` | Document that the overlay is compiled during the build, not fetched |

## Design choices worth a reviewer's attention

- **Recompile when the source is newer than the output** (not plain
  skip-if-exists). A machine that already has an older or stale-prebuilt
  binary — every box that built before this change — picks up the current
  source instead of silently keeping the old chime-playing binary, and
  later edits to `typemate_overlay.c` always rebuild. Fresh checkouts stamp
  the source "now", so a restored CI cache also recompiles. (Addresses the
  original review's #1 and #2.)
- **Compile failure is fatal in CI, non-fatal on dev boxes.** When
  `CI=true` (GitHub Actions), a missing toolchain or failed compile sets a
  non-zero exit code, so `linux/CMakeLists.txt`'s `FATAL_ERROR` fails the
  build — a release can never silently ship overlay-less. On a developer
  box (no `CI` env) it warns and continues, because the overlay is optional
  and the app falls back to its in-window status (`resolveBundledTool`).
  (Addresses the original review's #3.)
- **Cache key includes the overlay source.** Both Linux cache keys hash
  `linux/overlay/typemate_overlay.c` alongside the fetch script, so editing
  the overlay busts the Actions cache — redundant with the mtime check, but
  explicit.
- **The hosted `typemate-overlay-linux-x64.tar.gz` on `models-v1` is now
  unused.** It can be left as-is (harmless) or deleted later; no code
  references it.
- Windows/macOS are untouched — the overlay is Linux-only; those platforms
  draw their overlay natively in the runner.

## How it was verified

- WSL (Ubuntu) clean build: removed `bin/overlay/typemate-overlay`, ran
  `dart run tool/fetch_whisper_runtime.dart` → it compiled the overlay
  (`compiling=linux/overlay/typemate_overlay.c`), producing a **21448-byte
  binary with 0 `libasound` references** (chime-less).
- The app's own sound path (`dictation_sounds.dart`) is unchanged; this
  branch only stops the *overlay* from playing a second chime.

## Not in scope

- The already-published v1.3.0 artifacts are not retroactively fixed; this
  lands in the next release.
- No change to what sounds play or how the app plays them.
