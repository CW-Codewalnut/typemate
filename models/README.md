# Local whisper models

TypeMate bundles one validated model per supported language and routes by
the language selected in Settings (benchmarks from the target i5-11300H
laptop, ~13s clip):

- `parakeet-tdt-0.6b-v3-int8/` (~640 MB) — English plus 24 European
  languages (NVIDIA Parakeet TDT 0.6B v3, int8 ONNX, automatic language
  detection). Served by a resident sherpa-onnx server that loads it once
  at app start; roughly a second per short clip with the best accuracy of
  every model benchmarked, including Indian-English.
- `ggml-small-vaani-hindi-q6.bin` (~197 MB) — Hindi (Vaani small
  fine-tune, q6), ~2.8s per clip; more noise-robust than the tiny
  variant with near-turbo Hindi accuracy.
- `ggml-hindi2hinglish-swift.bin` (~141 MB) — Hinglish (Oriserve Swift
  fine-tune, base-sized) writes Hindi speech as romanized Hinglish at
  ~1.2s per clip. Our own GGML conversion (no public one exists), hosted
  on this repo's GitHub releases.
- `ggml-vistaar-tamil-small-q5_0.bin` (~167 MB) — Tamil (AI4Bharat
  Vistaar small fine-tune, quantized to q5_0 by this repo, hosted on the
  `models-v1` GitHub release), ~2s per clip and stable across repeated
  requests.
- `ggml-indicwhisper-marathi-medium-q5_0.bin` (~514 MB) — Marathi
  (IndicWhisper medium fine-tune; no small checkpoint exists), same
  conversion and hosting, ~5.5s per clip and word-perfect.
- Telugu, Kannada, and Gujarati were evaluated and dropped: their
  Vistaar checkpoints decode non-deterministically (identical requests
  flip between correct output and hallucinations at every quantization
  level, including fp16) on the benchmark corpus.
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
