abstract interface class PlatformBridge {
  Future<bool> isGlobalShortcutAvailable();

  Future<void> showListeningOverlay();

  Future<void> showTranscribingOverlay();

  Future<void> hideListeningOverlay();

  /// Transient system toast with the failure reason, shown at the same
  /// screen position as the dictation overlay so it is visible in whatever
  /// app the user was dictating into. Auto-hides on its own; no OS
  /// notification is involved.
  Future<void> showDictationFailureOverlay(String message);

  Future<void> insertTextIntoFocusedField(String text);

  Future<void> ensureLaunchAtStartup();
}

/// Bridges that can receive a quit request from the platform (e.g. the
/// Windows tray menu). The app answers by shutting resident services down
/// and exiting the process.
abstract interface class QuitRequestSource {
  set onQuitRequested(Future<void> Function()? handler);
}
