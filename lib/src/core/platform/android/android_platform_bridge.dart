import 'package:flutter/services.dart';

import '../platform_bridge.dart';

typedef ClipboardWriter = Future<void> Function(ClipboardData data);

/// Android dictation happens inside the app: there is no system-wide
/// overlay, no global shortcut, and no focused field in another app to
/// type into (that needs the Phase 2 keyboard/IME). The bridge therefore
/// maps the desktop contract onto mobile equivalents: the dictation
/// screen replaces the overlay, failures surface in-app, and "insertion"
/// copies the transcript to the clipboard so it can be pasted anywhere.
class AndroidPlatformBridge implements PlatformBridge {
  AndroidPlatformBridge({ClipboardWriter? clipboardWriter})
    : _clipboardWriter = clipboardWriter ?? Clipboard.setData;

  final ClipboardWriter _clipboardWriter;

  @override
  Future<bool> isGlobalShortcutAvailable() async => false;

  @override
  Future<void> showListeningOverlay() async {}

  @override
  Future<void> showTranscribingOverlay() async {}

  @override
  Future<void> hideListeningOverlay() async {}

  @override
  Future<void> showDictationFailureNotification(String message) async {
    // The user is looking at the dictation screen, which shows the same
    // failure through the controller's error state.
  }

  @override
  Future<void> insertTextIntoFocusedField(String text) =>
      _clipboardWriter(ClipboardData(text: text));

  @override
  Future<void> ensureLaunchAtStartup() async {
    // Android has no user-facing launch-at-startup concept for apps.
  }
}
