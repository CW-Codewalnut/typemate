import 'dart:io';

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
    expect(started.single.arguments, contains('-File'));
    final scriptPath = started.single.arguments.last;
    expect(scriptPath, endsWith('typemate-listening-overlay.ps1'));
    final script = File(scriptPath).readAsStringSync();
    expect(script, contains('TypeMate is listening'));
    expect(script, contains('Application]::Run'));
    expect(script, contains('System.Windows.Forms.Timer'));
    expect(script, contains(r'$script:barCount = 13'));
    expect(script, contains('[Math]::Sin'));
    expect(script, contains('SetWindowPos'));
    expect(overlayProcess.killCount, 1);
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
