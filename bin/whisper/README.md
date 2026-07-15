# Bundled whisper CLI

TypeMate ships whisper.cpp v1.9.1 (OpenBLAS Windows x64 build) here:
`whisper-cli.exe` plus its `ggml*/whisper/libopenblas` DLLs. The app looks
for it at `bin/whisper/whisper-cli.exe`, first relative to the working
directory and then relative to the executable directory. Windows release
builds copy this folder (and `models/`) next to the executable.

The binaries are gitignored. Provision them together with the model:

```bash
dart run tool/fetch_whisper_runtime.dart
```

If the CLI is missing at runtime the app fails with a clear
`SttRuntimeException` — there is no silent fallback.

`TYPEMATE_WHISPER_CLI` overrides the bundled binary, for example to test a
different whisper.cpp build.
