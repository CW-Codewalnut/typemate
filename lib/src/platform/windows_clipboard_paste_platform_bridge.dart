import 'dart:io';

import 'package:flutter/services.dart';

import 'platform_bridge.dart';

typedef PlatformProcessRunner =
    Future<PlatformProcessResult> Function(
      String executable,
      List<String> arguments,
    );

typedef OverlayProcessStarter =
    Future<OverlayProcess> Function(String executable, List<String> arguments);

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

abstract interface class OverlayProcess {
  void kill();
}

class StartedOverlayProcess implements OverlayProcess {
  StartedOverlayProcess(this.process);

  final Process process;

  @override
  void kill() {
    process.kill();
  }
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

Future<OverlayProcess> startOverlayProcess(
  String executable,
  List<String> arguments,
) async {
  final process = await Process.start(
    executable,
    arguments,
    mode: ProcessStartMode.detachedWithStdio,
  );
  return StartedOverlayProcess(process);
}

class WindowsClipboardPastePlatformBridge implements PlatformBridge {
  WindowsClipboardPastePlatformBridge({
    this.processRunner = runPlatformProcess,
    this.overlayProcessStarter = startOverlayProcess,
  });

  final PlatformProcessRunner processRunner;
  final OverlayProcessStarter overlayProcessStarter;

  OverlayProcess? _overlayProcess;

  @override
  Future<bool> isGlobalShortcutAvailable() async => true;

  @override
  Future<void> showListeningOverlay() async {
    if (_overlayProcess != null) {
      return;
    }

    _overlayProcess = await overlayProcessStarter('powershell.exe', const [
      '-NoProfile',
      '-STA',
      '-WindowStyle',
      'Hidden',
      '-Command',
      _overlayScript,
    ]);
  }

  @override
  Future<void> hideListeningOverlay() async {
    _overlayProcess?.kill();
    _overlayProcess = null;
  }

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

const _overlayScript = r'''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$form = New-Object System.Windows.Forms.Form
$form.Text = 'TypeMate'
$form.FormBorderStyle = 'None'
$form.StartPosition = 'Manual'
$form.TopMost = $true
$form.ShowInTaskbar = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(35, 38, 55)
$form.Width = 360
$form.Height = 86
$screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Left = [int](($screen.Width - $form.Width) / 2)
$form.Top = [int]($screen.Top + 24)
$label = New-Object System.Windows.Forms.Label
$label.Text = 'TypeMate is listening...'
$label.ForeColor = [System.Drawing.Color]::White
$label.Font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
$label.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$label.Dock = 'Fill'
$form.Controls.Add($label)
[void]$form.ShowDialog()
''';
