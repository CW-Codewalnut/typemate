import 'dart:io';

import 'package:flutter/services.dart';

import '../desktop_notification_sender.dart';
import '../platform_bridge.dart';

const _nativeChannel = MethodChannel('typemate/macos');

typedef MacosProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

typedef MacosNativeMethodInvoker =
    Future<T?> Function<T>(String method, [Object? arguments]);

/// macOS adapter: the native overlay panel is driven over the
/// `typemate/macos` method channel; text lands in the focused field via
/// clipboard + a synthesized Cmd+V (System Events, which requires the
/// user to grant Accessibility permission); launch-at-login registers a
/// System Events login item for the installed .app bundle. The global
/// hold shortcut is served by MacosPollingHoldShortcutRegistrar (Input
/// Monitoring permission, prompted at registration).
class MacosPlatformBridge implements PlatformBridge {
  MacosPlatformBridge({
    MacosNativeMethodInvoker? nativeMethodInvoker,
    this.processRunner = Process.run,
    DesktopNotificationSender? notificationSender,
    String? executablePath,
  }) : nativeMethodInvoker = nativeMethodInvoker ?? _nativeChannel.invokeMethod,
       notificationSender = notificationSender ?? showDesktopNotification,
       _executablePath = executablePath ?? Platform.resolvedExecutable;

  final MacosNativeMethodInvoker nativeMethodInvoker;
  final MacosProcessRunner processRunner;
  final DesktopNotificationSender notificationSender;
  final String _executablePath;

  String? _overlayState;

  @override
  Future<bool> isGlobalShortcutAvailable() async => true;

  @override
  Future<void> showListeningOverlay() => _showOverlay('listening');

  @override
  Future<void> showTranscribingOverlay() => _showOverlay('transcribing');

  Future<void> _showOverlay(String state) async {
    if (_overlayState == state) {
      return;
    }
    _overlayState = state;
    await nativeMethodInvoker<void>('showOverlay', {'state': state});
  }

  @override
  Future<void> hideListeningOverlay() async {
    if (_overlayState == null) {
      return;
    }
    _overlayState = null;
    await nativeMethodInvoker<void>('hideOverlay');
  }

  @override
  Future<void> showDictationFailureNotification(String message) async {
    try {
      await notificationSender('Dictation failed', message);
    } on MissingPluginException {
      // Runners without the notification plugin skip the toast; the
      // in-app history banner still carries the reason.
    }
  }

  @override
  Future<void> insertTextIntoFocusedField(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    final result = await processRunner('osascript', [
      '-e',
      'tell application "System Events" to keystroke "v" using command down',
    ]);
    if (result.exitCode != 0) {
      throw StateError(
        'Unable to paste into the focused field. Grant TypeMate the '
        'Accessibility permission (System Settings > Privacy & Security > '
        'Accessibility), then try again. ${result.stderr}',
      );
    }
  }

  @override
  Future<void> ensureLaunchAtStartup() async {
    // Only the installed bundle may self-register; dev binaries (flutter
    // run, flutter_tester) must never end up in the user's login items.
    const marker = '.app/Contents/MacOS/';
    final markerIndex = _executablePath.indexOf(marker);
    if (markerIndex < 0) {
      return;
    }
    final bundlePath = _executablePath.substring(0, markerIndex + 4);
    final result = await processRunner('osascript', [
      '-e',
      'tell application "System Events" to if not (exists login item '
          '"TypeMate") then make login item at end with properties '
          '{path:"$bundlePath", hidden:false}',
    ]);
    if (result.exitCode != 0) {
      throw StateError(
        'Unable to register TypeMate as a login item. ${result.stderr}',
      );
    }
  }
}
