import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/platform/overlay/overlay_window.dart';
import 'package:typemate/src/core/platform/windows/windows_platform_bridge.dart';

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
    'types transcript through the native channel without using the clipboard',
    () async {
      final nativeCalls = <({String method, Object? arguments})>[];
      final processCalls = <({String executable, List<String> arguments})>[];
      final bridge = WindowsPlatformBridge(
        nativeMethodInvoker: <T>(method, [arguments]) async {
          nativeCalls.add((method: method, arguments: arguments));
          return null;
        },
        processRunner: (executable, arguments) async {
          processCalls.add((executable: executable, arguments: arguments));
          return const PlatformProcessResult(exitCode: 0);
        },
      );

      await bridge.insertTextIntoFocusedField('नमस्ते TypeMate');

      expect(nativeCalls, hasLength(1));
      expect(nativeCalls.single.method, 'insertText');
      expect(nativeCalls.single.arguments, {'text': 'नमस्ते TypeMate'});
      expect(platformCalls, isEmpty, reason: 'clipboard must stay untouched');
      expect(processCalls, isEmpty);
    },
  );

  test('native runner injects keystrokes with SendInput unicode events', () {
    final source = File('windows/runner/flutter_window.cpp').readAsStringSync();

    expect(source, contains('insertText'));
    expect(source, contains('KEYEVENTF_UNICODE'));
    expect(source, contains('SendInput'));
    expect(source, contains('MultiByteToWideChar'));
  });

  test(
    'falls back to clipboard paste when the native channel is unavailable',
    () async {
      final processCalls = <({String executable, List<String> arguments})>[];
      final bridge = WindowsPlatformBridge(
        nativeMethodInvoker: <T>(method, [arguments]) async {
          throw MissingPluginException();
        },
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

  test('throws when the fallback paste command fails', () async {
    final bridge = WindowsPlatformBridge(
      nativeMethodInvoker: <T>(method, [arguments]) async {
        throw MissingPluginException();
      },
      processRunner: (_, _) async =>
          const PlatformProcessResult(exitCode: 1, stderr: 'paste failed'),
    );

    expect(
      () => bridge.insertTextIntoFocusedField('Hello TypeMate'),
      throwsA(isA<StateError>()),
    );
  });

  test('invokes onQuitRequested when the tray asks to quit', () async {
    final bridge = WindowsPlatformBridge(
      nativeMethodInvoker: <T>(method, [arguments]) async => null,
    );
    var quitRequests = 0;
    bridge.onQuitRequested = () async {
      quitRequests += 1;
    };

    const codec = StandardMethodCodec();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'typemate/windows',
          codec.encodeMethodCall(const MethodCall('quitRequested')),
          (_) {},
        );

    expect(quitRequests, 1);
  });

  test('native runner shows a tray icon and hides the window on close', () {
    final source = File('windows/runner/flutter_window.cpp').readAsStringSync();

    expect(source, contains('Shell_NotifyIcon(NIM_ADD'));
    expect(source, contains('Shell_NotifyIcon(NIM_DELETE'));
    expect(source, contains('L"Open Type Mate"'));
    expect(source, contains('L"Quit Type Mate"'));
    expect(source, contains('quitRequested'));
    expect(source, contains('case WM_CLOSE:'));
    expect(source, contains('SW_HIDE'));
  });

  test('overlay states map to the Flutter overlay window', () async {
    final overlay = FakeOverlayWindow();
    final bridge = WindowsPlatformBridge(
      nativeMethodInvoker: <T>(method, [arguments]) async => null,
      overlayWindow: overlay,
    );

    await bridge.showListeningOverlay();
    await bridge.showTranscribingOverlay();
    await bridge.showDictationInfoOverlay(
      'Please download the speech model first.',
    );
    await bridge.showDictationFailureOverlay(
      'Transcription took too long and was stopped.',
    );
    await bridge.hideListeningOverlay();

    expect(overlay.calls, [
      'working:TypeMate is listening...',
      'working:Transcribing locally...',
      'info:Please download the speech model first.',
      'error:Transcription took too long and was stopped.',
      'hide',
    ]);
  });

  test('the Windows runner no longer carries a native overlay', () {
    // The overlay is a second Flutter window now
    // (lib/src/core/platform/overlay/); the Win32 renderer is retired
    // and must not creep back into the runner.
    final window = File('windows/runner/flutter_window.cpp').readAsStringSync();
    expect(window, isNot(contains('overlay_')));
    expect(window, isNot(contains('showOverlay')));
    final cmake = File('windows/runner/CMakeLists.txt').readAsStringSync();
    expect(cmake, isNot(contains('type_mate_overlay.cpp')));
    expect(File('windows/runner/type_mate_overlay.cpp').existsSync(), isFalse);
  });

  test(
    'registers only the Startup shortcut and removes the legacy Run key value',
    () async {
      // Regression: a Run-key launch inherits C:\Windows\System32 as its
      // working directory, which broke dictation after login. Only the
      // Startup shortcut (which pins WorkingDirectory to the exe folder)
      // may register the app, and the Run value older builds wrote must
      // be cleaned up.
      final processCalls = <({String executable, List<String> arguments})>[];
      final bridge = WindowsPlatformBridge(
        processRunner: (executable, arguments) async {
          processCalls.add((executable: executable, arguments: arguments));
          return const PlatformProcessResult(exitCode: 0);
        },
        executablePath: r'C:\Apps\TypeMate\typemate.exe',
      );

      await bridge.ensureLaunchAtStartup();

      expect(processCalls, hasLength(1));
      expect(processCalls.single.executable, 'powershell.exe');
      final command = processCalls.single.arguments.join('\n');
      expect(
        command,
        contains(r'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'),
      );
      expect(command, contains('Remove-ItemProperty'));
      expect(command, isNot(contains('Set-ItemProperty')));
      expect(command, contains(r'C:\Apps\TypeMate\typemate.exe'));
      expect(command, contains('WScript.Shell'));
      expect(command, contains('SpecialFolders.Item(\'Startup\')'));
      expect(command, contains('TypeMate.lnk'));
      expect(command, contains(r"WorkingDirectory = Split-Path"));
      expect(command, contains('IconLocation'));
      expect(command, contains(r'StartupApproved\StartupFolder'));
      expect(command, contains(r'StartupApproved\Run'));
      expect(command, contains('New-ItemProperty'));
      expect(command, contains('PropertyType Binary'));
      expect(command, contains('Save()'));
    },
  );

  test('never registers a non-app executable for startup', () async {
    // Widget tests once wrote flutter_tester.exe into the user's Run key;
    // registration must be limited to the real typemate.exe.
    final processCalls = <({String executable, List<String> arguments})>[];
    final bridge = WindowsPlatformBridge(
      processRunner: (executable, arguments) async {
        processCalls.add((executable: executable, arguments: arguments));
        return const PlatformProcessResult(exitCode: 0);
      },
      executablePath:
          r'C:\Users\dev\flutter\bin\cache\artifacts\engine\flutter_tester.exe',
    );

    await bridge.ensureLaunchAtStartup();

    expect(processCalls, isEmpty);
  });

  test('throws when startup registration fails', () async {
    final bridge = WindowsPlatformBridge(
      executablePath: r'C:\Apps\TypeMate\typemate.exe',
      processRunner: (_, _) async =>
          const PlatformProcessResult(exitCode: 1, stderr: 'registry failed'),
    );

    expect(() => bridge.ensureLaunchAtStartup(), throwsA(isA<StateError>()));
  });
}

class FakeOverlayWindow extends OverlayWindow {
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
