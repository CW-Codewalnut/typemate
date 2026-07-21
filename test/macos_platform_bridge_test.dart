import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/platform/macos/macos_platform_bridge.dart';

class RecordingInvoker {
  final List<String> calls = [];

  Future<T?> call<T>(String method, [Object? arguments]) async {
    calls.add(arguments == null ? method : '$method $arguments');
    return null;
  }
}

class FakeMacAccessibility implements MacAccessibility {
  FakeMacAccessibility({required this.isProcessTrusted});

  @override
  final bool isProcessTrusted;
}

class RecordingMacTextTyper implements MacTextTyper {
  final List<String> typed = [];

  @override
  Future<void> typeText(String text) async {
    typed.add(text);
  }
}

void main() {
  test('shows and hides the native overlay through the channel', () async {
    final invoker = RecordingInvoker();
    final bridge = MacOSPlatformBridge(
      nativeMethodInvoker: invoker.call,
      accessibility: FakeMacAccessibility(isProcessTrusted: true),
      textTyper: RecordingMacTextTyper(),
    );

    await bridge.showListeningOverlay();
    await bridge.showTranscribingOverlay();
    await bridge.hideListeningOverlay();

    expect(invoker.calls, [
      'showOverlay {state: listening}',
      'showOverlay {state: transcribing}',
      'hideOverlay',
    ]);
  });

  test('types the transcript when the process is trusted', () async {
    final typer = RecordingMacTextTyper();
    final bridge = MacOSPlatformBridge(
      nativeMethodInvoker: RecordingInvoker().call,
      accessibility: FakeMacAccessibility(isProcessTrusted: true),
      textTyper: typer,
    );

    await bridge.insertTextIntoFocusedField('hello from typemate');

    expect(typer.typed, ['hello from typemate']);
  });

  test('refuses to type without the Accessibility permission and says how to '
      'fix it', () async {
    final typer = RecordingMacTextTyper();
    final bridge = MacOSPlatformBridge(
      nativeMethodInvoker: RecordingInvoker().call,
      accessibility: FakeMacAccessibility(isProcessTrusted: false),
      textTyper: typer,
    );

    expect(await bridge.isGlobalShortcutAvailable(), isFalse);
    await expectLater(
      bridge.insertTextIntoFocusedField('hello'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Accessibility'),
        ),
      ),
    );
    expect(typer.typed, isEmpty);
  });

  test('registers the installed app for launch at login', () async {
    final invoker = RecordingInvoker();
    final bridge = MacOSPlatformBridge(
      nativeMethodInvoker: invoker.call,
      accessibility: FakeMacAccessibility(isProcessTrusted: true),
      textTyper: RecordingMacTextTyper(),
      executablePath: '/Applications/Type Mate.app/Contents/MacOS/Type Mate',
    );

    await bridge.ensureLaunchAtStartup();

    expect(invoker.calls, ['ensureLaunchAtStartup']);
  });

  test('never registers transient binaries (tests, dev runs) for launch at '
      'login', () async {
    for (final path in [
      '/usr/local/bin/flutter_tester',
      '/Users/someone/typemate/build/macos/Build/Products/Debug/'
          'Type Mate.app/Contents/MacOS/Type Mate',
    ]) {
      final invoker = RecordingInvoker();
      final bridge = MacOSPlatformBridge(
        nativeMethodInvoker: invoker.call,
        accessibility: FakeMacAccessibility(isProcessTrusted: true),
        textTyper: RecordingMacTextTyper(),
        executablePath: path,
      );

      await bridge.ensureLaunchAtStartup();

      expect(invoker.calls, isEmpty, reason: path);
    }
  });
}
