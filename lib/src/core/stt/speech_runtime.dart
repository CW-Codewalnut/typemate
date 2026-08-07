import 'dart:io';

import '../audio/audio_denoiser.dart';
import '../diagnostics/diagnostic_reporter.dart';
import 'language_aware_model_provisioner.dart';
import 'language_routing_stt_engine.dart';
import 'sherpa_parakeet_stt_engine.dart';
import 'speech_model_catalog.dart';
import 'stt_engine.dart';
import 'stt_model_provisioner.dart';
import 'whisper_cli_stt_engine.dart' show SttLanguageCodeProvider;
import 'whisper_ggml_stt_engine.dart';

export 'speech_model_catalog.dart';

typedef PathExists = bool Function(String path);

/// Appends the Windows executable suffix; Linux/macOS binaries have none.
String platformExecutablePath(String path, {bool? isWindows}) =>
    (isWindows ?? Platform.isWindows) ? '$path.exe' : path;

/// A language served by its own in-process whisper fine-tune. Only the
/// selected language's model is kept resident (RAM policy).
class WhisperLanguage {
  const WhisperLanguage({
    required this.code,
    required this.modelFile,
    this.cliLanguage,
    this.prompt,
  });

  final String code;

  /// The model's catalog entry: bundled installs carry it under `models/`,
  /// slim installs download it on demand.
  final SttModelFile modelFile;

  /// Whisper's language flag when it differs from [code] (e.g. Hinglish
  /// decodes as Hindi and romanizes on its own).
  final String? cliLanguage;
  final String? prompt;

  String get modelRelativePath => 'models/${modelFile.relativePath}';
}

const whisperLanguages = [
  // Vaani small fine-tune, noise-robust Devanagari output. No script
  // prompt: the fine-tune writes Devanagari natively, and on the
  // in-process path a prompt bleeds its own characters into the
  // transcript and slows decoding (corpus-verified).
  WhisperLanguage(code: 'hi', modelFile: vaaniHindiModelFile),
  // Oriserve Swift fine-tune, base-sized, romanized output; a script
  // prompt would fight it.
  WhisperLanguage(
    code: 'hinglish',
    modelFile: hinglishSwiftModelFile,
    cliLanguage: 'hi',
  ),
  // Vistaar (AI4Bharat) per-language fine-tunes, small-sized, quantized to
  // q5_0 by this repo (hosted on the models-v1 GitHub release).
  WhisperLanguage(code: 'ta', modelFile: vistaarTamilModelFile),
  // Telugu, Kannada, and Gujarati are intentionally absent: their Vistaar
  // checkpoints decode non-deterministically (thin logit margins flip
  // tokens into hallucinations run-to-run, at any quantization level and
  // even fp16), failing the "visible languages must work" bar. Marathi
  // validated cleanly but was cut for install size: its only checkpoint is
  // medium-sized (~514 MB, kept at R:/Models/whisper and on the models-v1
  // release for an easy re-add).
];
// Silero VAD trims hold-to-talk silence before decoding; without it whisper
// loops and repeats sentences while decoding the silent tail.
const bundledVadModelRelativePath = 'models/ggml-silero-v5.1.2.bin';

/// Threads for the in-process Parakeet recognizer — matches the
/// `--num-work-threads=4` the retired websocket server ran with, so
/// per-utterance latency stays at the benchmarked ~1s.
const desktopParakeetNumThreads = 4;

/// The speech stack: the routing engine over the in-process Parakeet
/// recognizer and the per-language in-process whisper fine-tunes, plus
/// the on-demand downloader for whichever models the install did not
/// bundle. [provisioner] is null when every model is bundled — nothing to
/// download. Desktop resolves bundled copies first; Android has no
/// bundled models, so everything downloads.
class SpeechRuntime {
  const SpeechRuntime({
    required this.engine,
    required this.denoiser,
    this.provisioner,
  });

  final SttEngine engine;

  /// The in-process GTCRN noise-suppression step behind the Settings
  /// toggle; its tiny model is bundled on desktop and rides the Parakeet
  /// download elsewhere.
  final AudioDenoiser denoiser;

  final LanguageAwareModelProvisioner? provisioner;
}

/// Creates the production STT stack — every engine runs in-process, so no
/// binaries are required. Models resolve bundled-first (full install, dev
/// checkout); unbundled models download on demand into
/// `<dataDirectory>/models/`. The small always-needed files (Silero VAD)
/// ride a language's download when not bundled.
SpeechRuntime createSpeechRuntime({
  required String dataDirectoryPath,
  Map<String, String>? environment,
  PathExists? pathExists,
  SttLanguageCodeProvider? languageCodeProvider,
  DiagnosticReporter? diagnostics,
  String? currentDirectoryPath,
  String? executableDirectoryPath,
  int whisperThreads = 6,
}) {
  final values = environment ?? Platform.environment;
  final exists = pathExists ?? (path) => File(path).existsSync();
  final searchDirectories = [
    (currentDirectoryPath ?? Directory.current.path).replaceAll('\\', '/'),
    (executableDirectoryPath ?? File(Platform.resolvedExecutable).parent.path)
        .replaceAll('\\', '/'),
  ];

  String? findBundled(String relativePath) {
    for (final directory in searchDirectories) {
      final candidate = '$directory/$relativePath';
      if (exists(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  final downloadedModelsDirectory =
      '${dataDirectoryPath.replaceAll('\\', '/')}/models';
  final provisionersByLanguageCode = <String, SttModelProvisioner>{};

  // VAD rides a whisper language's download when not bundled.
  final bundledVad = findBundled(bundledVadModelRelativePath);
  final vadModel =
      bundledVad ??
      '$downloadedModelsDirectory/${sileroVadModelFile.relativePath}';
  final vadDownloads = bundledVad == null
      ? [sileroVadModelFile]
      : <SttModelFile>[];

  // Noise suppression: bundled GTCRN wins; otherwise the tiny model rides
  // whichever Parakeet download (English unified or multilingual v3) happens
  // first, so both directories are candidates. An env override points
  // anywhere.
  final envDenoiserModel = values['TYPEMATE_DENOISER_MODEL']?.trim() ?? '';
  final bundledGtcrn = findBundled('models/${gtcrnModelFile.relativePath}');
  final denoiser = SherpaGtcrnAudioDenoiser(
    modelPathCandidates: envDenoiserModel.isNotEmpty
        ? [envDenoiserModel]
        : bundledGtcrn != null
        ? [bundledGtcrn]
        : [
            '$downloadedModelsDirectory/$parakeetEnglishModelDirectoryName/'
                '${gtcrnModelFile.relativePath}',
            '$downloadedModelsDirectory/$parakeetModelDirectoryName/'
                '${gtcrnModelFile.relativePath}',
          ],
  );
  final gtcrnDownloads = bundledGtcrn == null && envDenoiserModel.isEmpty
      ? [gtcrnModelFile]
      : <SttModelFile>[];

  // An explicit model override applies to every language and bypasses the
  // per-language fine-tunes entirely (power-user escape hatch): the same
  // in-process engine, one model file, the selected language's flag.
  final envModelPath = values['TYPEMATE_WHISPER_MODEL']?.trim() ?? '';
  if (envModelPath.isNotEmpty) {
    final codeProvider = languageCodeProvider ?? (() => 'en');
    final overrideEngines = <String, SttEngine>{
      for (final option in const ['en', 'hi', 'hinglish', 'ta'])
        option: WhisperGgmlSttEngine(
          modelPath: envModelPath,
          language: option == 'hinglish' ? 'hi' : option,
          vadModelPath: vadModel,
          numThreads: whisperThreads,
          diagnostics: diagnostics,
        ),
    };
    return SpeechRuntime(
      engine: LanguageRoutingSttEngine(
        routes: overrideEngines,
        fallback: overrideEngines['en']!,
        languageCodeProvider: codeProvider,
      ),
      denoiser: denoiser,
    );
  }

  // Parakeet is all-or-nothing: the recognizer needs every file, so a
  // bundled copy only counts when the whole directory is present.
  String? findBundledParakeetDirectory(String relativePath) {
    for (final directory in searchDirectories) {
      final candidate = '$directory/$relativePath';
      if (sherpaParakeetModelFileNames.every(
        (name) => exists('$candidate/$name'),
      )) {
        return candidate;
      }
    }
    return null;
  }

  // English runs the dedicated parakeet-unified model (accent-robust,
  // corpus-verified); the other 24 Parakeet languages share the
  // multilingual v3. Each model provisions independently, so an
  // English-only user never downloads v3.
  SherpaParakeetSttEngine parakeetEngineFor({
    required String directoryName,
    required List<SttModelFile> modelFiles,
    required List<String> languageCodes,
  }) {
    final bundledDirectory = findBundledParakeetDirectory(
      'models/$directoryName',
    );
    final modelDirectory =
        bundledDirectory ?? '$downloadedModelsDirectory/$directoryName';
    if (bundledDirectory == null) {
      final provisioner = SttModelProvisioner(
        modelDirectory: Directory(modelDirectory),
        // The GTCRN denoiser model rides the Parakeet download when it is
        // not bundled (Android); it lands beside the Parakeet files.
        files: [...modelFiles, ...gtcrnDownloads],
      );
      for (final code in languageCodes) {
        provisionersByLanguageCode[code] = provisioner;
      }
    }
    return SherpaParakeetSttEngine(
      modelDirectoryPath: modelDirectory,
      numThreads: desktopParakeetNumThreads,
      diagnostics: diagnostics,
    );
  }

  final englishParakeet = parakeetEngineFor(
    directoryName: parakeetEnglishModelDirectoryName,
    modelFiles: parakeetEnglishModelFiles,
    languageCodes: const ['en'],
  );
  final multilingualParakeet = parakeetEngineFor(
    directoryName: parakeetModelDirectoryName,
    modelFiles: parakeetModelFiles,
    languageCodes: parakeetMultilingualLanguageCodes,
  );

  final whisperEnginesByCode = <String, WhisperGgmlSttEngine>{};
  for (final language in whisperLanguages) {
    final bundledModel = findBundled(language.modelRelativePath);
    final modelPath =
        bundledModel ??
        '$downloadedModelsDirectory/${language.modelFile.relativePath}';
    if (bundledModel == null) {
      provisionersByLanguageCode[language.code] = SttModelProvisioner(
        modelDirectory: Directory(downloadedModelsDirectory),
        // The VAD model rides the first whisper download when unbundled;
        // an already-present copy is skipped by the intactness check.
        files: [language.modelFile, ...vadDownloads],
      );
    }
    whisperEnginesByCode[language.code] = WhisperGgmlSttEngine(
      modelPath: modelPath,
      language: language.cliLanguage ?? language.code,
      vadModelPath: vadModel,
      prompt: language.prompt,
      numThreads: whisperThreads,
      diagnostics: diagnostics,
    );
  }

  final codeProvider = languageCodeProvider ?? (() => 'en');
  return SpeechRuntime(
    engine: LanguageRoutingSttEngine(
      routes: {
        'en': englishParakeet,
        for (final code in parakeetMultilingualLanguageCodes)
          code: multilingualParakeet,
        ...whisperEnginesByCode,
      },
      fallback: whisperEnginesByCode['hi']!,
      languageCodeProvider: codeProvider,
    ),
    denoiser: denoiser,
    provisioner: provisionersByLanguageCode.isEmpty
        ? null
        : LanguageAwareModelProvisioner(
            provisionersByLanguageCode: provisionersByLanguageCode,
            languageCodeProvider: codeProvider,
          ),
  );
}
