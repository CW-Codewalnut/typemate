import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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

  test('failure notification goes through the desktop notifier', () async {
    final sent = <({String title, String body})>[];
    final bridge = WindowsPlatformBridge(
      nativeMethodInvoker: <T>(method, [arguments]) async => null,
      notificationSender: (title, body) async {
        sent.add((title: title, body: body));
      },
    );

    await bridge.showDictationFailureNotification(
      'Transcription took too long and was stopped.',
    );

    expect(sent.single.title, 'Dictation failed');
    expect(sent.single.body, 'Transcription took too long and was stopped.');
  });

  test('shows native overlay through Windows method channel', () async {
    final calls = <({String method, Object? arguments})>[];
    final bridge = WindowsPlatformBridge(
      nativeMethodInvoker: <T>(method, [arguments]) async {
        calls.add((method: method, arguments: arguments));
        return null;
      },
    );

    await bridge.showListeningOverlay();
    await bridge.showListeningOverlay();
    await bridge.showTranscribingOverlay();
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

  test(
    'falls back to PowerShell overlay when native channel is unavailable',
    () async {
      final started = <({String executable, List<String> arguments})>[];
      final overlayProcess = FakeOverlayProcess();
      final bridge = WindowsPlatformBridge(
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
      expect(started.single.arguments, contains('-File'));
      expect(started.single.arguments.last, 'listening');
      final scriptPath =
          started.single.arguments[started.single.arguments.length - 2];
      expect(scriptPath, endsWith('typemate-listening-overlay.ps1'));
      final script = File(scriptPath).readAsStringSync();
      expect(script, contains('TypeMate is listening'));
      expect(script, contains('Transcribing locally'));
      expect(script, contains(r"param([string]$State"));
      expect(script, contains('Application]::Run'));
      expect(script, contains('System.Windows.Forms.Timer'));
      expect(script, contains(r'$form.Width = 210'));
      expect(script, contains(r'$form.Height = 58'));
      expect(
        script,
        contains(r'$form.Top = [int]($screen.Bottom - $form.Height - 28)'),
      );
      expect(script, contains(r'$script:barCount = 7'));
      expect(script, contains(r'$script:barWidth = 5'));
      expect(script, contains(r'$script:maxHeight = 18'));
      expect(script, contains('System.Drawing.Drawing2D.GraphicsPath'));
      expect(script, contains('Set-CapsuleControlRegion'));
      expect(script, contains(r'Set-CapsuleControlRegion $bar'));
      expect(script, contains('[Math]::Sin'));
      expect(script, contains('SetWindowPos'));
      expect(overlayProcess.killCount, 1);
    },
  );
  test('shows transcribing overlay as a native overlay state', () async {
    final started = <({String executable, List<String> arguments})>[];
    final listeningProcess = FakeOverlayProcess();
    final transcribingProcess = FakeOverlayProcess();
    final bridge = WindowsPlatformBridge(
      overlayProcessStarter: (executable, arguments) async {
        started.add((executable: executable, arguments: arguments));
        return started.length == 1 ? listeningProcess : transcribingProcess;
      },
    );

    await bridge.showListeningOverlay();
    await bridge.showTranscribingOverlay();

    expect(started, hasLength(2));
    expect(started.first.arguments.last, 'listening');
    expect(started.last.arguments.last, 'transcribing');
    expect(listeningProcess.killCount, 1);
    expect(transcribingProcess.killCount, 0);
  });

  test('native overlay plays the chime once per appearance', () {
    final source = File(
      'windows/runner/type_mate_overlay.cpp',
    ).readAsStringSync();

    expect(source, contains('#include "overlay_chime_wav.h"'));
    expect(source, contains('const bool appearing = hwnd_ == nullptr;'));
    expect(source, contains('PlaySound'));
    expect(source, contains('SND_MEMORY | SND_ASYNC | SND_NODEFAULT'));

    final cmake = File('windows/runner/CMakeLists.txt').readAsStringSync();
    expect(cmake, contains('winmm.lib'));

    final header = File(
      'windows/runner/overlay_chime_wav.h',
    ).readAsStringSync();
    expect(header, contains('kOverlayChimeWav[]'));
    expect(header, contains('kOverlayChimeRate'));
  });

  test('native Windows overlay is bottom anchored, compact, and rounded', () {
    final source = File(
      'windows/runner/type_mate_overlay.cpp',
    ).readAsStringSync();

    expect(source, contains('constexpr int kOverlayWidth = 210;'));
    expect(source, contains('constexpr int kOverlayHeight = 58;'));
    expect(source, contains('work_area.bottom - kOverlayHeight - 28'));
    expect(source, contains('CreateRoundRectRgn'));
    expect(source, contains('constexpr int bar_count = 7;'));
    expect(source, contains('constexpr int bar_width = 5;'));
    expect(source, contains('constexpr int max_height = 18;'));
    expect(source, contains('RoundRect(hdc, left, top'));
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

class FakeOverlayProcess implements OverlayProcess {
  int killCount = 0;

  @override
  void kill() {
    killCount += 1;
  }
}
