import 'dart:io';

import '../platform_bridge.dart';

typedef LinuxProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      Map<String, String>? environment,
    });

Future<ProcessResult> _runProcess(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
}) => Process.run(executable, arguments, environment: environment);

/// Linux (X11) implementation of the platform bridge.
///
/// Text lands in the focused field through `xdotool type`, which synthesizes
/// key events at the X server — the same effect as typing. Wayland blocks
/// synthetic input by design, so dictation requires an X11 session (or
/// XWayland focus); [isGlobalShortcutAvailable] reports that honestly.
///
/// Overlays are not implemented on Linux yet; the in-app status and history
/// still reflect every dictation.
class LinuxPlatformBridge implements PlatformBridge {
  LinuxPlatformBridge({
    LinuxProcessRunner? processRunner,
    Map<String, String>? environment,
    String? executablePath,
    this.xdotoolExecutable = 'xdotool',
    this.xdotoolLibraryDirectory,
  }) : _processRunner = processRunner ?? _runProcess,
       _environment = environment ?? Platform.environment,
       _executablePath = executablePath ?? Platform.resolvedExecutable;

  final LinuxProcessRunner _processRunner;
  final Map<String, String> _environment;
  final String _executablePath;

  /// Bundled xdotool ships with a private libxdo; its directory goes on
  /// LD_LIBRARY_PATH so no system install is needed.
  final String xdotoolExecutable;
  final String? xdotoolLibraryDirectory;

  @override
  Future<bool> isGlobalShortcutAvailable() async {
    return (_environment['DISPLAY'] ?? '').trim().isNotEmpty;
  }

  @override
  Future<void> showListeningOverlay() async {}

  @override
  Future<void> showTranscribingOverlay() async {}

  @override
  Future<void> hideListeningOverlay() async {}

  @override
  Future<void> insertTextIntoFocusedField(String text) async {
    final libraryDirectory = xdotoolLibraryDirectory;
    final ProcessResult result;
    try {
      result = await _processRunner(
        xdotoolExecutable,
        ['type', '--clearmodifiers', '--delay', '2', '--', text],
        environment: libraryDirectory == null
            ? null
            : {
                ..._environment,
                'LD_LIBRARY_PATH': [
                  libraryDirectory,
                  ?_environment['LD_LIBRARY_PATH'],
                ].join(':'),
              },
      );
    } on ProcessException {
      throw const TextInsertionException(
        'The bundled xdotool could not be launched, so the transcript '
        'could not be typed. Reinstall TypeMate and try again.',
      );
    }
    if (result.exitCode != 0) {
      throw TextInsertionException(
        'xdotool failed (exit ${result.exitCode}): ${result.stderr}'.trim(),
      );
    }
  }

  @override
  Future<void> ensureLaunchAtStartup() async {
    // Never register transient binaries (tests, flutter_tester, dev runs
    // from odd paths) as startup apps.
    if (!_executablePath.toLowerCase().endsWith('/typemate')) {
      return;
    }
    final configHome =
        _environment['XDG_CONFIG_HOME']?.trim().isNotEmpty == true
        ? _environment['XDG_CONFIG_HOME']!.trim()
        : '${_environment['HOME'] ?? ''}/.config';
    if (configHome == '/.config') {
      return;
    }
    final entry = File('$configHome/autostart/typemate.desktop');
    await entry.parent.create(recursive: true);
    await entry.writeAsString('''
[Desktop Entry]
Type=Application
Name=Type Mate
Comment=Local hold-to-dictate speech typing
Exec=$_executablePath
X-GNOME-Autostart-enabled=true
''');
  }
}

class TextInsertionException implements Exception {
  const TextInsertionException(this.message);

  final String message;

  @override
  String toString() => 'TextInsertionException: $message';
}
