import 'dart:io';

import 'package:flutter/services.dart';

import '../overlay/overlay_window.dart';
import '../platform_bridge.dart';

const _nativeChannel = MethodChannel('typemate/macos');

typedef MacosProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

typedef MacosNativeMethodInvoker =
    Future<T?> Function<T>(String method, [Object? arguments]);

/// macOS adapter: the dictation overlay is the shared Flutter overlay
/// window (ObjC-runtime FFI driver - verified in CI to build, still
/// pending a real-hardware pass); text lands in the focused field via
/// clipboard + a synthesized Cmd+V (System Events, which requires the
/// user to grant Accessibility permission); launch-at-login registers a
/// System Events login item for the installed .app bundle. The global
/// hold shortcut is served by MacosPollingHoldShortcutRegistrar (Input
/// Monitoring permission, prompted at registration).
class MacosPlatformBridge implements PlatformBridge, InfoOverlaySource {
  MacosPlatformBridge({
    MacosNativeMethodInvoker? nativeMethodInvoker,
    this.processRunner = Process.run,
    String? executablePath,
    OverlayWindow? overlayWindow,
  }) : nativeMethodInvoker = nativeMethodInvoker ?? _nativeChannel.invokeMethod,
       _executablePath = executablePath ?? Platform.resolvedExecutable,
       _overlay = overlayWindow ?? OverlayWindow.forPlatform() {
    // Off the dictation critical path: the first showListening must
    // never wait on second-engine bring-up while the user speaks.
    _overlay.preload();
  }

  final MacosNativeMethodInvoker nativeMethodInvoker;
  final MacosProcessRunner processRunner;
  final String _executablePath;

  /// The Flutter-rendered overlay window (second engine), which
  /// replaced the native Swift overlay panel.
  final OverlayWindow _overlay;

  @override
  Future<bool> isGlobalShortcutAvailable() async => true;

  @override
  Future<void> showListeningOverlay() async {
    await _overlay.showWorking('TypeMate is listening...');
  }

  @override
  Future<void> showTranscribingOverlay() async {
    await _overlay.showWorking('Transcribing locally...');
  }

  @override
  Future<void> hideListeningOverlay() async {
    await _overlay.hide();
  }

  @override
  Future<void> showDictationInfoOverlay(String message) async {
    await _overlay.showInfo(message);
  }

  @override
  Future<void> showDictationFailureOverlay(String message) async {
    await _overlay.showError(message);
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
