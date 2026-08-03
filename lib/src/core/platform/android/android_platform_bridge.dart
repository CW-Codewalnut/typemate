import '../platform_bridge.dart';

/// The in-app dictation bridge on Android. In-app dictation is a quick
/// capture: the transcript is saved to History (by the controller) and
/// nothing else — it does not touch the clipboard or type anywhere. The
/// floating mic (accessibility overlay) is the surface that inserts text
/// straight into another app's focused field.
class AndroidPlatformBridge implements PlatformBridge {
  @override
  Future<bool> isGlobalShortcutAvailable() async => false;

  @override
  Future<void> showListeningOverlay() async {}

  @override
  Future<void> showTranscribingOverlay() async {}

  @override
  Future<void> hideListeningOverlay() async {}

  @override
  Future<void> showDictationFailureOverlay(String message) async {
    // In-app dictation shows the failure on the mic tile; the floating
    // mic's native bubble carries its own error state.
  }

  @override
  Future<void> insertTextIntoFocusedField(String text) async {
    // In-app dictation lands in History only; there is no focused field
    // to type into and the clipboard is left untouched.
  }

  @override
  Future<void> ensureLaunchAtStartup() async {
    // Android has no user-facing launch-at-startup concept for apps.
  }
}
