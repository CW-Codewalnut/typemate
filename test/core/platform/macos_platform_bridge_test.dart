import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/app.dart';
import 'package:typemate/src/core/platform/macos/macos_platform_bridge.dart';
import 'package:typemate/src/core/platform/overlay/overlay_window.dart';
import 'package:typemate/src/core/platform/macos/macos_polling_hold_shortcut_registrar.dart';

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

  test('createDefaultPlatformBridge returns the macOS bridge on macOS', () {
    final bridge = createDefaultPlatformBridge(
      isWindows: false,
      isLinux: false,
      isMacOS: true,
    );

    expect(bridge, isA<MacosPlatformBridge>());
  });

  test('reports the global shortcut as available (polling registrar)', () {
    final bridge = MacosPlatformBridge(
      nativeMethodInvoker: <T>(method, [arguments]) async => null,
    );

    expect(bridge.isGlobalShortcutAvailable(), completion(isTrue));
  });

  test('overlay states map to the Flutter overlay window', () async {
    final overlay = _FakeOverlayWindow();
    final bridge = MacosPlatformBridge(
      nativeMethodInvoker: <T>(method, [arguments]) async => null,
      overlayWindow: overlay,
    );

    await bridge.showListeningOverlay();
    await bridge.showTranscribingOverlay();
    await bridge.showDictationInfoOverlay('Preparing local speech engine...');
    await bridge.showDictationFailureOverlay('Something went wrong.');
    await bridge.hideListeningOverlay();

    expect(overlay.calls, [
      'working:TypeMate is listening...',
      'working:Transcribing locally...',
      'info:Preparing local speech engine...',
      'error:Something went wrong.',
      'hide',
    ]);
  });

  test('pastes the transcript with clipboard + synthesized Cmd+V', () async {
    final processCalls = <({String executable, List<String> arguments})>[];
    final bridge = MacosPlatformBridge(
      nativeMethodInvoker: <T>(method, [arguments]) async => null,
      processRunner: (executable, arguments) async {
        processCalls.add((executable: executable, arguments: arguments));
        return ProcessResult(1, 0, '', '');
      },
    );

    await bridge.insertTextIntoFocusedField('नमस्ते TypeMate');

    expect(platformCalls, hasLength(1));
    expect(platformCalls.single.method, 'Clipboard.setData');
    expect(platformCalls.single.arguments, {'text': 'नमस्ते TypeMate'});
    expect(processCalls, hasLength(1));
    expect(processCalls.single.executable, 'osascript');
    expect(
      processCalls.single.arguments.join(' '),
      contains('keystroke "v" using command down'),
    );
  });

  test('surfaces the Accessibility permission when pasting fails', () {
    final bridge = MacosPlatformBridge(
      nativeMethodInvoker: <T>(method, [arguments]) async => null,
      processRunner: (_, _) async => ProcessResult(1, 1, '', 'not authorized'),
    );

    expect(
      () => bridge.insertTextIntoFocusedField('Hello'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Accessibility'),
        ),
      ),
    );
  });

  test('registers the installed bundle as a login item', () async {
    final processCalls = <({String executable, List<String> arguments})>[];
    final bridge = MacosPlatformBridge(
      nativeMethodInvoker: <T>(method, [arguments]) async => null,
      processRunner: (executable, arguments) async {
        processCalls.add((executable: executable, arguments: arguments));
        return ProcessResult(1, 0, '', '');
      },
      executablePath: '/Applications/TypeMate.app/Contents/MacOS/typemate',
    );

    await bridge.ensureLaunchAtStartup();

    expect(processCalls, hasLength(1));
    expect(processCalls.single.executable, 'osascript');
    final script = processCalls.single.arguments.join(' ');
    expect(script, contains('login item'));
    expect(script, contains('/Applications/TypeMate.app'));
    expect(script, isNot(contains('MacOS/typemate"')));
  });

  test('never registers a non-bundle executable for startup', () async {
    final processCalls = <({String executable, List<String> arguments})>[];
    final bridge = MacosPlatformBridge(
      nativeMethodInvoker: <T>(method, [arguments]) async => null,
      processRunner: (executable, arguments) async {
        processCalls.add((executable: executable, arguments: arguments));
        return ProcessResult(1, 0, '', '');
      },
      executablePath: '/Users/dev/flutter/bin/cache/flutter_tester',
    );

    await bridge.ensureLaunchAtStartup();

    expect(processCalls, isEmpty);
  });

  test('createDefaultHoldShortcutRegistrar polls keys on macOS', () {
    final registrar = createDefaultHoldShortcutRegistrar(
      isWindows: false,
      isLinux: false,
      isMacOS: true,
    );

    expect(registrar, isA<MacosPollingHoldShortcutRegistrar>());
  });

  test('macOS app config permits dictation (no sandbox, usage strings)', () {
    // The sandbox would block spawning the bundled STT servers, key
    // polling, and System Events; TypeMate is a direct download on every
    // platform.
    for (final entitlements in [
      'macos/Runner/DebugProfile.entitlements',
      'macos/Runner/Release.entitlements',
    ]) {
      final content = File(entitlements).readAsStringSync();
      expect(
        RegExp(
          r'<key>com\.apple\.security\.app-sandbox</key>\s*<false/>',
        ).hasMatch(content),
        isTrue,
        reason: '$entitlements must disable the sandbox',
      );
    }

    final infoPlist = File('macos/Runner/Info.plist').readAsStringSync();
    expect(infoPlist, contains('NSMicrophoneUsageDescription'));
    expect(infoPlist, contains('NSAppleEventsUsageDescription'));

    // The fetch script serves models only — every speech engine runs
    // in-process via plugins, so no speech binaries are fetched for any
    // platform; only Linux gets its capture/typing helper tools.
    final fetchScript = File(
      'tool/fetch_whisper_runtime.dart',
    ).readAsStringSync();
    expect(fetchScript, isNot(contains('whisper-blas-bin')));
    expect(fetchScript, isNot(contains('sherpa-onnx-v1.13.4')));
    expect(fetchScript, contains('if (Platform.isLinux) {'));
  });

  test('the native macOS overlay panel is retired', () {
    // The overlay is the shared Flutter overlay window now
    // (lib/src/core/platform/overlay/); the Swift panel is gone and the
    // runner channel no longer carries overlay methods.
    expect(File('macos/Runner/TypeMateOverlay.swift').existsSync(), isFalse);
    final window = File(
      'macos/Runner/MainFlutterWindow.swift',
    ).readAsStringSync();
    expect(window, isNot(contains('showOverlay')));
    expect(window, isNot(contains('TypeMateOverlay')));
    final project = File(
      'macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    expect(project, isNot(contains('TypeMateOverlay')));
  });
}

class _FakeOverlayWindow extends OverlayWindow {
  final List<String> calls = [];

  @override
  Future<void> showWorking(String label) async {
    calls.add('working:$label');
  }

  @override
  Future<void> showInfo(String message) async {
    calls.add('info:$message');
  }

  @override
  Future<void> showError(String message) async {
    calls.add('error:$message');
  }

  @override
  Future<void> hide() async {
    calls.add('hide');
  }
}
