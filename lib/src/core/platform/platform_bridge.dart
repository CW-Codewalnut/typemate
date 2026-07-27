abstract interface class PlatformBridge {
  Future<bool> isGlobalShortcutAvailable();

  Future<void> showListeningOverlay();

  Future<void> showTranscribingOverlay();

  Future<void> hideListeningOverlay();

  /// Posts an OS notification with the failure reason. It persists
  /// (Windows: Action Center), so the user can read it again later; the
  /// history page banner and failed entry carry the reason in-app.
  Future<void> showDictationFailureNotification(String message);

  Future<void> insertTextIntoFocusedField(String text);

  Future<void> ensureLaunchAtStartup();
}

/// Bridges that can receive a quit request from the platform (e.g. the
/// Windows tray menu). The app answers by shutting resident services down
/// and exiting the process.
abstract interface class QuitRequestSource {
  set onQuitRequested(Future<void> Function()? handler);
}
