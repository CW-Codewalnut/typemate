import 'dart:io';

import '../diagnostics/diagnostic_reporter.dart';
import 'language_aware_model_provisioner.dart';
import 'language_routing_stt_engine.dart';
import 'sherpa_parakeet_stt_engine.dart';
import 'speech_model_catalog.dart';
import 'stt_engine.dart';
import 'stt_model_provisioner.dart';
import 'whisper_cli_stt_engine.dart';
import 'whisper_server_stt_engine.dart';

export 'speech_model_catalog.dart';

typedef PathExists = bool Function(String path);

/// Appends the Windows executable suffix; Linux/macOS binaries have none.
String platformExecutablePath(String path, {bool? isWindows}) =>
    (isWindows ?? Platform.isWindows) ? '$path.exe' : path;

final bundledWhisperCliRelativePath = platformExecutablePath(
  'bin/whisper/whisper-cli',
);
final bundledWhisperServerRelativePath = platformExecutablePath(
  'bin/whisper/whisper-server',
);
const hindiServerPort = 43008;
const hinglishServerPort = 43009;
const _hindiDevanagariPrompt =
    'हिंदी भाषण को देवनागरी लिपि में ठीक-ठीक लिखें। '
    'अंग्रेज़ी में अनुवाद न करें।';

/// A language served by its own resident whisper.cpp HTTP server. Only the
/// selected language's server is kept loaded (RAM policy). Ports are fixed
/// per language so an orphaned server from an unclean exit is adopted
/// rather than duplicated.
class WhisperServerLanguage {
  const WhisperServerLanguage({
    required this.code,
    required this.modelFile,
    required this.port,
    this.cliLanguage,
    this.prompt,
  });

  final String code;

  /// The model's catalog entry: bundled installs carry it under `models/`,
  /// slim installs download it on demand.
  final SttModelFile modelFile;

  final int port;

  /// Whisper's language flag when it differs from [code] (e.g. Hinglish
  /// decodes as Hindi and romanizes on its own).
  final String? cliLanguage;
  final String? prompt;

  String get modelRelativePath => 'models/${modelFile.relativePath}';
}

const whisperServerLanguages = [
  // Vaani small fine-tune, noise-robust Devanagari output.
  WhisperServerLanguage(
    code: 'hi',
    modelFile: vaaniHindiModelFile,
    port: hindiServerPort,
    prompt: _hindiDevanagariPrompt,
  ),
  // Oriserve Swift fine-tune, base-sized, romanized output; a script
  // prompt would fight it.
  WhisperServerLanguage(
    code: 'hinglish',
    modelFile: hinglishSwiftModelFile,
    port: hinglishServerPort,
    cliLanguage: 'hi',
  ),
  // Vistaar (AI4Bharat) per-language fine-tunes, small-sized, quantized to
  // q5_0 by this repo (hosted on the models-v1 GitHub release).
  WhisperServerLanguage(
    code: 'ta',
    modelFile: vistaarTamilModelFile,
    port: 43011,
  ),
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
const bundledParakeetDirRelativePath = 'models/$parakeetModelDirectoryName';

/// Threads for the in-process Parakeet recognizer — matches the
/// `--num-work-threads=4` the retired websocket server ran with, so
/// per-utterance latency stays at the benchmarked ~1s.
const desktopParakeetNumThreads = 4;

/// The desktop speech stack: the routing engine over the in-process
/// Parakeet recognizer and the per-language whisper servers, plus the
/// on-demand downloader for whichever models the install did not bundle.
/// [provisioner] is null when every model is bundled (or an env override
/// bypasses the resident engines) — nothing to download.
class DesktopSpeechRuntime {
  const DesktopSpeechRuntime({required this.engine, this.provisioner});

  final SttEngine engine;
  final LanguageAwareModelProvisioner? provisioner;
}

/// Creates the production desktop STT stack. The whisper binaries and the
/// small VAD model are required: they ship with every install, and a
/// missing one is an installation defect that throws. The large speech
/// models may instead be downloaded on demand into
/// `<dataDirectory>/models/`; a bundled copy (full install, dev checkout)
/// always wins, and only unbundled models get a download entry.
DesktopSpeechRuntime createDesktopSpeechRuntime({
  required String dataDirectoryPath,
  Map<String, String>? environment,
  PathExists? pathExists,
  SttLanguageCodeProvider? languageCodeProvider,
  DiagnosticReporter? diagnostics,
  String? currentDirectoryPath,
  String? executableDirectoryPath,
}) {
  final values = environment ?? Platform.environment;
  final exists = pathExists ?? (path) => File(path).existsSync();
  final searchDirectories = [
    (currentDirectoryPath ?? Directory.current.path).replaceAll('\\', '/'),
    (executableDirectoryPath ?? File(Platform.resolvedExecutable).parent.path)
        .replaceAll('\\', '/'),
  ];

  String require(String relativePath, {String? environmentValue}) =>
      _resolveRuntimeFile(
        environmentValue: environmentValue,
        relativePath: relativePath,
        searchDirectories: searchDirectories,
        exists: exists,
      );

  String? findBundled(String relativePath) {
    for (final directory in searchDirectories) {
      final candidate = '$directory/$relativePath';
      if (exists(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  final whisperCli = require(
    bundledWhisperCliRelativePath,
    environmentValue: values['TYPEMATE_WHISPER_CLI'],
  );

  // An explicit model override applies to every language and bypasses the
  // resident engines entirely (power-user escape hatch).
  final envModelPath = values['TYPEMATE_WHISPER_MODEL']?.trim() ?? '';
  if (envModelPath.isNotEmpty) {
    return DesktopSpeechRuntime(
      engine: WhisperCliSttEngine(
        executable: whisperCli,
        modelPath: envModelPath,
        vadModelPath: require(bundledVadModelRelativePath),
        languageCodeProvider: languageCodeProvider,
      ),
    );
  }

  final whisperServer = require(bundledWhisperServerRelativePath);
  final vadModel = require(bundledVadModelRelativePath);
  final downloadedModelsDirectory =
      '${dataDirectoryPath.replaceAll('\\', '/')}/models';
  final provisionersByLanguageCode = <String, SttModelProvisioner>{};

  // Parakeet is all-or-nothing: the recognizer needs every file, so a
  // bundled copy only counts when the whole directory is present.
  String? bundledParakeetDirectory;
  for (final directory in searchDirectories) {
    final candidate = '$directory/$bundledParakeetDirRelativePath';
    if (sherpaParakeetModelFileNames.every(
      (name) => exists('$candidate/$name'),
    )) {
      bundledParakeetDirectory = candidate;
      break;
    }
  }
  final parakeetDirectory =
      bundledParakeetDirectory ??
      '$downloadedModelsDirectory/$parakeetModelDirectoryName';
  if (bundledParakeetDirectory == null) {
    final parakeetProvisioner = SttModelProvisioner(
      modelDirectory: Directory(parakeetDirectory),
      files: parakeetModelFiles,
      ensureNotificationPermission: _noNotificationPermissionNeeded,
    );
    for (final code in parakeetLanguageCodes) {
      provisionersByLanguageCode[code] = parakeetProvisioner;
    }
  }
  final parakeet = SherpaParakeetSttEngine(
    modelDirectoryPath: parakeetDirectory,
    numThreads: desktopParakeetNumThreads,
    diagnostics: diagnostics,
  );

  final whisperEnginesByCode = <String, WhisperServerSttEngine>{};
  for (final language in whisperServerLanguages) {
    final bundledModel = findBundled(language.modelRelativePath);
    final modelPath =
        bundledModel ??
        '$downloadedModelsDirectory/${language.modelFile.relativePath}';
    if (bundledModel == null) {
      provisionersByLanguageCode[language.code] = SttModelProvisioner(
        modelDirectory: Directory(downloadedModelsDirectory),
        files: [language.modelFile],
        ensureNotificationPermission: _noNotificationPermissionNeeded,
      );
    }
    whisperEnginesByCode[language.code] = WhisperServerSttEngine(
      serverExecutable: whisperServer,
      modelPath: modelPath,
      vadModelPath: vadModel,
      cliLanguage: language.cliLanguage ?? language.code,
      prompt: language.prompt,
      port: language.port,
      diagnostics: diagnostics,
    );
  }

  final codeProvider = languageCodeProvider ?? (() => 'en');
  return DesktopSpeechRuntime(
    engine: LanguageRoutingSttEngine(
      routes: {
        for (final code in parakeetLanguageCodes) code: parakeet,
        ...whisperEnginesByCode,
      },
      fallback: whisperEnginesByCode['hi']!,
      languageCodeProvider: codeProvider,
    ),
    provisioner: provisionersByLanguageCode.isEmpty
        ? null
        : LanguageAwareModelProvisioner(
            provisionersByLanguageCode: provisionersByLanguageCode,
            languageCodeProvider: codeProvider,
          ),
  );
}

/// Desktop downloads run in-process with no foreground-service
/// notification, so there is no permission to request.
Future<void> _noNotificationPermissionNeeded() async {}

String _resolveRuntimeFile({
  required String? environmentValue,
  required String relativePath,
  required List<String> searchDirectories,
  required PathExists exists,
}) {
  final override = environmentValue?.trim() ?? '';
  if (override.isNotEmpty) {
    return override;
  }

  final candidates = [
    for (final directory in searchDirectories) '$directory/$relativePath',
  ];
  for (final candidate in candidates) {
    if (exists(candidate)) {
      return candidate;
    }
  }

  throw SttRuntimeException(
    'TypeMate installation is broken: $relativePath was not found. '
    'Searched: ${candidates.join(', ')}. '
    'Reinstall the app or run: dart run tool/fetch_whisper_runtime.dart',
  );
}
