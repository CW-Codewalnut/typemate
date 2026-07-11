import 'dart:io';

import 'package:flutter/services.dart';

import 'platform_bridge.dart';

typedef PlatformProcessRunner =
    Future<PlatformProcessResult> Function(
      String executable,
      List<String> arguments,
    );

class PlatformProcessResult {
  const PlatformProcessResult({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

Future<PlatformProcessResult> runPlatformProcess(
  String executable,
  List<String> arguments,
) async {
  final result = await Process.run(executable, arguments);
  return PlatformProcessResult(
    exitCode: result.exitCode,
    stdout: '${result.stdout}',
    stderr: '${result.stderr}',
  );
}

class WindowsClipboardPastePlatformBridge implements PlatformBridge {
  const WindowsClipboardPastePlatformBridge({
    this.processRunner = runPlatformProcess,
  });

  final PlatformProcessRunner processRunner;

  @override
  Future<bool> isGlobalShortcutAvailable() async => true;

  @override
  Future<void> showListeningOverlay() async {}

  @override
  Future<void> hideListeningOverlay() async {}

  @override
  Future<void> insertTextIntoFocusedField(String text) async {
    await Clipboard.setData(ClipboardData(text: text));

    const script = r'''
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.SendKeys]::SendWait('^v')
''';
    final result = await processRunner('powershell.exe', const [
      '-NoProfile',
      '-STA',
      '-Command',
      script,
    ]);

    if (result.exitCode != 0) {
      throw StateError(
        'Unable to paste transcript into the focused field. ${result.stderr}',
      );
    }
  }
}
