import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/app.dart';
import 'package:typemate/src/core/platform/macos/macos_platform_bridge.dart';

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

  test('reports the global shortcut as unavailable (no registrar yet)', () {
    final bridge = MacosPlatformBridge(
      nativeMethodInvoker: <T>(method, [arguments]) async => null,
    );

    expect(bridge.isGlobalShortcutAvailable(), completion(isFalse));
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

  test('native macOS overlay matches the Windows pill and plays the chime', () {
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
    expect(source, contains('xRadius: overlayHeight / 2'));
    // Never steals focus from the field being dictated into.
    expect(source, contains('.nonactivatingPanel'));
    expect(source, contains('orderFrontRegardless'));
    // The shared chime, once per appearance.
    expect(source, contains('overlayChimeWavBase64'));
    expect(source, contains('NSSound(data:'));
    expect(source, contains('let appearing = panel == nil'));

    final window = File(
      'macos/Runner/MainFlutterWindow.swift',
    ).readAsStringSync();
    expect(window, contains('typemate/macos'));
    expect(window, contains('showOverlay'));
    expect(window, contains('hideOverlay'));

    final chime = File('macos/Runner/OverlayChimeWav.swift').readAsStringSync();
    expect(chime, contains('overlayChimeWavBase64'));

    // The Xcode project must compile both new sources.
    final project = File(
      'macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    expect(project, contains('TypeMateOverlay.swift in Sources'));
    expect(project, contains('OverlayChimeWav.swift in Sources'));
  });
}
