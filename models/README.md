# Local whisper models

TypeMate bundles Whisper `large-v3-turbo` (q5_0 quantized, ~574 MB) as its
default speech-to-text model. The app looks for it at
`models/ggml-large-v3-turbo-q5_0.bin`, first relative to the working
directory and then relative to the executable directory. Windows release
builds copy this folder (and `bin/whisper/`) next to the executable.

The binary is not committed to git (GitHub rejects files over 100 MB).
Provision it together with the whisper CLI:

```bash
dart run tool/fetch_whisper_runtime.dart
```

If the model is missing at runtime the app fails with a clear
`SttRuntimeException` — there is no silent fallback.

`TYPEMATE_WHISPER_MODEL` still overrides the bundled model, for example to
point at `ggml-large-v3.bin` on high-memory machines.
