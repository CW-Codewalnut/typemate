import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/platform/windows_clipboard_paste_platform_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> platformCalls;

  setUp(() {
    platformCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          platformCalls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test(
    'copies transcript to clipboard and sends Ctrl+V through PowerShell',
    () async {
      final processCalls = <({String executable, List<String> arguments})>[];
      final bridge = WindowsClipboardPastePlatformBridge(
        processRunner: (executable, arguments) async {
          processCalls.add((executable: executable, arguments: arguments));
          return const PlatformProcessResult(exitCode: 0);
        },
      );

      await bridge.insertTextIntoFocusedField('Hello TypeMate');

      expect(platformCalls, hasLength(1));
      expect(platformCalls.single.method, 'Clipboard.setData');
      expect(platformCalls.single.arguments, {'text': 'Hello TypeMate'});
      expect(processCalls, hasLength(1));
      expect(processCalls.single.executable, 'powershell.exe');
      expect(processCalls.single.arguments, contains('-STA'));
      expect(processCalls.single.arguments.join(' '), contains('SendKeys'));
      expect(processCalls.single.arguments.join(' '), contains('^v'));
    },
  );

  test('throws when paste command fails', () async {
    final bridge = WindowsClipboardPastePlatformBridge(
      processRunner: (_, _) async =>
          const PlatformProcessResult(exitCode: 1, stderr: 'paste failed'),
    );

    expect(
      () => bridge.insertTextIntoFocusedField('Hello TypeMate'),
      throwsA(isA<StateError>()),
    );
  });

  test('shows one overlay process and kills it on hide', () async {
    final started = <({String executable, List<String> arguments})>[];
    final overlayProcess = FakeOverlayProcess();
    final bridge = WindowsClipboardPastePlatformBridge(
      overlayProcessStarter: (executable, arguments) async {
        started.add((executable: executable, arguments: arguments));
        return overlayProcess;
      },
    );

    await bridge.showListeningOverlay();
    await bridge.showListeningOverlay();
    await bridge.hideListeningOverlay();

    expect(started, hasLength(1));
    expect(started.single.executable, 'powershell.exe');
    expect(started.single.arguments, contains('-WindowStyle'));
    expect(
      started.single.arguments.join(' '),
      contains('TypeMate is listening'),
    );
    expect(overlayProcess.killCount, 1);
  });
}

class FakeOverlayProcess implements OverlayProcess {
  int killCount = 0;

  @override
  void kill() {
    killCount += 1;
  }
}
