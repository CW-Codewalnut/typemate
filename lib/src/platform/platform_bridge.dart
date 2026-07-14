abstract interface class PlatformBridge {
  Future<bool> isGlobalShortcutAvailable();

  Future<void> showListeningOverlay();

  Future<void> hideListeningOverlay();

  Future<void> insertTextIntoFocusedField(String text);

  Future<void> ensureLaunchAtStartup();
}
