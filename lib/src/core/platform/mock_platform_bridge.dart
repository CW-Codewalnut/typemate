import 'platform_bridge.dart';

class MockPlatformBridge implements PlatformBridge {
  String lastInsertedText = '';
  bool overlayVisible = false;
  String overlayMessage = '';
  int transcribingOverlayCount = 0;
  bool launchAtStartupEnsured = false;

  @override
  Future<bool> isGlobalShortcutAvailable() async => true;

  @override
  Future<void> showListeningOverlay() async {
    overlayVisible = true;
    overlayMessage = 'TypeMate is listening...';
  }

  @override
  Future<void> showTranscribingOverlay() async {
    overlayVisible = true;
    overlayMessage = 'Transcribing locally...';
    transcribingOverlayCount += 1;
  }

  @override
  Future<void> hideListeningOverlay() async {
    overlayVisible = false;
    overlayMessage = '';
  }

  String lastFailureNotification = '';

  @override
  Future<void> showDictationFailureNotification(String message) async {
    lastFailureNotification = message;
  }

  @override
  Future<void> insertTextIntoFocusedField(String text) async {
    lastInsertedText = text;
  }

  @override
  Future<void> ensureLaunchAtStartup() async {
    launchAtStartupEnsured = true;
  }
}
