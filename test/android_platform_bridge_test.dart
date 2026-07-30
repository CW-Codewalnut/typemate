import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/platform/android/android_platform_bridge.dart';

void main() {
  test('insertion copies the transcript to the clipboard', () async {
    ClipboardData? written;
    final bridge = AndroidPlatformBridge(
      clipboardWriter: (data) async => written = data,
    );

    await bridge.insertTextIntoFocusedField('hello from typemate');

    expect(written?.text, 'hello from typemate');
  });

  test('reports that no global shortcut exists', () async {
    final bridge = AndroidPlatformBridge(clipboardWriter: (_) async {});

    expect(await bridge.isGlobalShortcutAvailable(), isFalse);
  });

  test('overlay, notification, and startup calls are safe no-ops', () async {
    final bridge = AndroidPlatformBridge(clipboardWriter: (_) async {});

    await bridge.showListeningOverlay();
    await bridge.showTranscribingOverlay();
    await bridge.hideListeningOverlay();
    await bridge.showDictationFailureNotification('failed');
    await bridge.ensureLaunchAtStartup();
  });
}
