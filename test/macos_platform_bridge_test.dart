import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/app.dart';
import 'package:typemate/src/core/platform/macos/macos_platform_bridge.dart';
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

  test('drives the native overlay panel through the macOS channel', () async {
    final calls = <({String method, Object? arguments})>[];
    final bridge = MacosPlatformBridge(
      nativeMethodInvoker: <T>(method, [arguments]) async {
        calls.add((method: method, arguments: arguments));
        return null;
      },
    );

    await bridge.showListeningOverlay();
    await bridge.showListeningOverlay();
    await bridge.showTranscribingOverlay();
    await bridge.hideListeningOverlay();
    await bridge.hideListeningOverlay();

    expect(calls.map((call) => call.method), [
      'showOverlay',
      'showOverlay',
      'hideOverlay',
    ]);
    expect(calls[0].arguments, {'state': 'listening'});
    expect(calls[1].arguments, {'state': 'transcribing'});
    expect(calls[2].arguments, isNull);
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

    // The fetch script must serve macOS its own runtime, never the Linux
    // binaries or Linux-only helper tools. (Sherpa needs no binaries on
    // any platform: everything sherpa runs in-process via the plugin.)
    final fetchScript = File(
      'tool/fetch_whisper_runtime.dart',
    ).readAsStringSync();
    expect(fetchScript, contains('whisper-v1.9.1-macos-universal.tar.gz'));
    expect(fetchScript, isNot(contains('sherpa-onnx-v1.13.4')));
    expect(fetchScript, contains('if (Platform.isLinux) {'));
  });

  test(
    'native macOS overlay matches the Windows pill, no sound of its own',
    () {
      final source = File(
        'macos/Runner/TypeMateOverlay.swift',
      ).readAsStringSync();

      // Same geometry and cadence as windows/runner/type_mate_overlay.cpp.
      expect(source, contains('overlayWidth: CGFloat = 210'));
      expect(source, contains('overlayHeight: CGFloat = 58'));
      expect(source, contains('let barCount = 7'));
      expect(source, contains('let barWidth = 5.0'));
      expect(source, contains('let gap = 6.0'));
      expect(source, contains('let maxHeight = 18.0'));
      expect(source, contains('* 0.55'));
      expect(source, contains('tickSeconds: TimeInterval = 0.07'));
      // Rounded capsule bars and pill.
      expect(source, contains('xRadius: barWidth / 2'));
      expect(source, contains('xRadius: bounds.height / 2'));
      // Never steals focus from the field being dictated into.
      expect(source, contains('.nonactivatingPanel'));
      expect(source, contains('orderFrontRegardless'));
      // Sounds moved to lib/src/core/platform/dictation_sounds.dart; the
      // overlay must not play audio of its own or the chime would double up.
      expect(source, isNot(contains('NSSound')));
      expect(source, isNot(contains('overlayChimeWavBase64')));

      final window = File(
        'macos/Runner/MainFlutterWindow.swift',
      ).readAsStringSync();
      expect(window, contains('typemate/macos'));
      expect(window, contains('showOverlay'));
      expect(window, contains('hideOverlay'));

      // The Xcode project must compile the overlay and must no longer
      // reference the retired chime source.
      final project = File(
        'macos/Runner.xcodeproj/project.pbxproj',
      ).readAsStringSync();
      expect(project, contains('TypeMateOverlay.swift in Sources'));
      expect(project, isNot(contains('OverlayChimeWav')));
    },
  );
}
