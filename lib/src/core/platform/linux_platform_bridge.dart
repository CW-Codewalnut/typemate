import 'dart:io';

import 'platform_bridge.dart';

typedef LinuxProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

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
  }) : _processRunner = processRunner ?? Process.run,
       _environment = environment ?? Platform.environment,
       _executablePath = executablePath ?? Platform.resolvedExecutable;

  final LinuxProcessRunner _processRunner;
  final Map<String, String> _environment;
  final String _executablePath;

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
    final ProcessResult result;
    try {
      result = await _processRunner('xdotool', [
        'type',
        '--clearmodifiers',
        '--delay',
        '2',
        '--',
        text,
      ]);
    } on ProcessException {
      throw const TextInsertionException(
        'xdotool is required to type into the focused field on Linux. '
        'Install it (e.g. sudo apt install xdotool) and try again.',
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
