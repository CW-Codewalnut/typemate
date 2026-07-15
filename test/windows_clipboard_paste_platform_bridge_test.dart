import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/platform/windows_clipboard_paste_platform_bridge.dart';

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

  test('shows native overlay through Windows method channel', () async {
    final calls = <({String method, Object? arguments})>[];
    final bridge = WindowsClipboardPastePlatformBridge(
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
    final bridge = WindowsClipboardPastePlatformBridge(
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
    'registers TypeMate in the Run key and Startup folder shortcut',
    () async {
      final processCalls = <({String executable, List<String> arguments})>[];
      final bridge = WindowsClipboardPastePlatformBridge(
        processRunner: (executable, arguments) async {
          processCalls.add((executable: executable, arguments: arguments));
          return const PlatformProcessResult(exitCode: 0);
        },
      );

      await bridge.ensureLaunchAtStartup();

      expect(processCalls, hasLength(1));
      expect(processCalls.single.executable, 'powershell.exe');
      final command = processCalls.single.arguments.join('\n');
      expect(
        command,
        contains(r'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'),
      );
      expect(command, contains('TypeMate'));
      expect(command, contains('Set-ItemProperty'));
      expect(command, contains('WScript.Shell'));
      expect(command, contains('SpecialFolders.Item(\'Startup\')'));
      expect(command, contains('TypeMate.lnk'));
      expect(command, contains('IconLocation'));
      expect(command, contains('StartupApproved'));
      expect(command, contains('New-ItemProperty'));
      expect(command, contains('PropertyType Binary'));
      expect(command, contains('Save()'));
    },
  );

  test('throws when startup registration fails', () async {
    final bridge = WindowsClipboardPastePlatformBridge(
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
