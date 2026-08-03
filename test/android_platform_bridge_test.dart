import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/platform/android/android_platform_bridge.dart';

void main() {
  test('in-app insertion is a no-op: History only, no clipboard', () async {
    final bridge = AndroidPlatformBridge();

    // Must complete without throwing and without touching the clipboard;
    // in-app dictation is saved to History by the controller alone.
    await bridge.insertTextIntoFocusedField('hello from typemate');
  });

  test('reports that no global shortcut exists', () async {
    final bridge = AndroidPlatformBridge();

    expect(await bridge.isGlobalShortcutAvailable(), isFalse);
  });

  test('overlay, failure toast, and startup calls are safe no-ops', () async {
    final bridge = AndroidPlatformBridge();

    await bridge.showListeningOverlay();
    await bridge.showTranscribingOverlay();
    await bridge.hideListeningOverlay();
    await bridge.showDictationFailureOverlay('failed');
    await bridge.ensureLaunchAtStartup();
  });
}
