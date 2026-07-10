import 'platform_bridge.dart';

class MockPlatformBridge implements PlatformBridge {
  String lastInsertedText = '';
  bool overlayVisible = false;

  @override
  Future<bool> isGlobalShortcutAvailable() async => true;

  @override
  Future<void> showListeningOverlay() async {
    overlayVisible = true;
  }

  @override
  Future<void> hideListeningOverlay() async {
    overlayVisible = false;
  }

  @override
  Future<void> insertTextIntoFocusedField(String text) async {
    lastInsertedText = text;
  }
}
