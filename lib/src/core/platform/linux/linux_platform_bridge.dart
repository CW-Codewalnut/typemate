import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../models/app_identity.dart';
import '../desktop_notification_sender.dart';
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

/// Starts the long-lived overlay helper; abstracted so tests can capture
/// the commands written to it.
abstract interface class OverlaySink {
  void send(String command);
  Future<void> close();
}

typedef OverlayStarter = Future<OverlaySink?> Function();

/// Linux (X11) implementation of the platform bridge.
///
/// Text lands in the focused field through `xdotool type`, which synthesizes
/// key events at the X server — the same effect as typing. Wayland blocks
/// synthetic input by design, so dictation requires an X11 session (or
/// XWayland focus); [isGlobalShortcutAvailable] reports that honestly.
///
/// The listening/transcribing overlay is a small bundled X11 helper
/// ([overlayExecutable]) driven over stdin; it is override-redirect so it
/// never steals focus from the field being typed into.
class LinuxPlatformBridge implements PlatformBridge {
  LinuxPlatformBridge({
    LinuxProcessRunner? processRunner,
    Map<String, String>? environment,
    String? executablePath,
    this.xdotoolExecutable = 'xdotool',
    this.xdotoolLibraryDirectory,
    this.overlayExecutable = '',
    OverlayStarter? overlayStarter,
    DesktopNotificationSender? notificationSender,
  }) : _processRunner = processRunner ?? _runProcess,
       _environment = environment ?? Platform.environment,
       _executablePath = executablePath ?? Platform.resolvedExecutable,
       notificationSender = notificationSender ?? showDesktopNotification,
       // ignore: prefer_initializing_formals
       _overlayStarter = overlayStarter;

  final LinuxProcessRunner _processRunner;
  final Map<String, String> _environment;
  final String _executablePath;
  final DesktopNotificationSender notificationSender;

  /// Bundled xdotool ships with a private libxdo; its directory goes on
  /// LD_LIBRARY_PATH so no system install is needed.
  final String xdotoolExecutable;
  final String? xdotoolLibraryDirectory;

  /// The bundled overlay helper; empty disables the overlay (falls back to
  /// the in-app status only).
  final String overlayExecutable;
  final OverlayStarter? _overlayStarter;
  OverlaySink? _overlay;
  bool _overlayFailed = false;

  /// Spawns one overlay per dictation. The helper maps its window as soon
  /// as it starts, so being spawned IS the "show" — no reliance on the
  /// first stdin command arriving (parent-side write buffering could delay
  /// it). Later state changes ([showTranscribingOverlay]) are best-effort
  /// stdin updates; [hideListeningOverlay] closes the helper.
  Future<void> _ensureOverlay() async {
    if (_overlayFailed || _overlay != null) {
      return;
    }
    if (overlayExecutable.isEmpty && _overlayStarter == null) {
      return;
    }
    final overlay = await (_overlayStarter ?? _startOverlayProcess)();
    if (overlay == null) {
      _overlayFailed = true;
      return;
    }
    _overlay = overlay;
  }

  Future<OverlaySink?> _startOverlayProcess() async {
    try {
      final process = await Process.start(overlayExecutable, const []);
      unawaited(process.stdout.drain<void>());
      unawaited(process.stderr.drain<void>());
      return _ProcessOverlaySink(process);
    } on ProcessException {
      return null;
    }
  }

  @override
  Future<bool> isGlobalShortcutAvailable() async {
    return (_environment['DISPLAY'] ?? '').trim().isNotEmpty;
  }

  @override
  Future<void> showListeningOverlay() => _ensureOverlay();

  @override
  Future<void> showTranscribingOverlay() async {
    await _ensureOverlay();
    _overlay?.send('transcribing');
  }

  @override
  Future<void> hideListeningOverlay() async {
    final overlay = _overlay;
    _overlay = null;
    await overlay?.close();
  }

  @override
  Future<void> showDictationFailureNotification(String message) async {
    try {
      await notificationSender('Dictation failed', message);
    } catch (_) {
      // Notifications are best effort (headless sessions have no daemon);
      // the in-app history banner still carries the reason.
    }
  }

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
    // The bundle ships the app icon at data/app_icon.png next to the binary.
    final bundleDirectory = _executablePath.substring(
      0,
      _executablePath.lastIndexOf('/'),
    );
    await entry.writeAsString('''
[Desktop Entry]
Type=Application
Name=$appDisplayName
Comment=Local hold-to-dictate speech typing
Exec=$_executablePath
Icon=$bundleDirectory/data/app_icon.png
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

class _ProcessOverlaySink implements OverlaySink {
  _ProcessOverlaySink(this._process);

  final Process _process;

  @override
  void send(String command) {
    try {
      // add() + flush pushes the bytes straight down the pipe; writeln's
      // buffering can otherwise leave the helper waiting.
      _process.stdin.add(utf8.encode('$command\n'));
      unawaited(_process.stdin.flush());
    } catch (_) {
      // The helper may have exited; ignored.
    }
  }

  @override
  Future<void> close() async {
    try {
      await _process.stdin.close();
    } catch (_) {}
    _process.kill();
  }
}
