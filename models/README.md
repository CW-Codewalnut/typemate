# Local whisper models

TypeMate bundles one validated model per supported language and routes by
the language selected in Settings (benchmarks from the target i5-11300H
laptop, ~13s clip):

- `ggml-distil-small.en.bin` (~321 MB) — English (distil-whisper), ~1.5s
  per clip; robust to Indian-English where tiny.en looped and misheard.
- `ggml-small-vaani-hindi-q6.bin` (~197 MB) — Hindi (Vaani small
  fine-tune, q6), ~2.8s per clip; more noise-robust than the tiny
  variant with near-turbo Hindi accuracy.
- `ggml-hindi2hinglish-apex-q5_1.bin` (~595 MB) — Hinglish (Oriserve Apex
  fine-tune) writes Hindi speech as romanized Hinglish; turbo-sized, so
  noticeably slower (~7s per clip).
- `ggml-silero-v5.1.2.bin` (~1 MB) — Silero VAD, always on; trims
  hold-to-talk silence so whisper does not loop and repeat sentences while
  decoding it.

The app resolves them first relative to the working directory and then
relative to the executable directory. Windows release builds copy this
folder (and `bin/whisper/`) next to the executable.

The binaries are not committed to git (they exceed practical git limits).
The Windows CMake build fetches anything missing automatically, so
`flutter build windows` and `flutter run -d windows` work on a fresh
clone. To provision manually:

```bash
dart run tool/fetch_whisper_runtime.dart
```

If a model is missing at runtime the app fails with a clear
`SttRuntimeException` — there is no silent fallback.

`TYPEMATE_WHISPER_MODEL` overrides the bundled models (it then applies to
every language), for example to point at `ggml-large-v3.bin` on
high-memory machines.
