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

    final overlayScriptFile = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}typemate-listening-overlay.ps1',
    );
    await overlayScriptFile.writeAsString(_overlayScript, flush: true);

    _overlayProcess = await overlayProcessStarter('powershell.exe', [
      '-NoLogo',
      '-NoProfile',
      '-STA',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      overlayScriptFile.path,
    ]);
  }

  @override
  Future<void> hideListeningOverlay() async {
    _overlayProcess?.kill();
    _overlayProcess = null;
  }

  @override
  Future<void> ensureLaunchAtStartup() async {
    final executablePath = Platform.resolvedExecutable;
    final escapedPath = executablePath.replaceAll("'", "''");
    final script =
        """
\$runPath = 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run'
\$value = '"$escapedPath"'
Set-ItemProperty -Path \$runPath -Name 'TypeMate' -Value \$value
\$shell = New-Object -ComObject WScript.Shell
\$startup = \$shell.SpecialFolders.Item('Startup')
\$shortcut = \$shell.CreateShortcut((Join-Path \$startup 'TypeMate.lnk'))
\$shortcut.TargetPath = '$escapedPath'
\$shortcut.WorkingDirectory = Split-Path '$escapedPath'
\$shortcut.Description = 'TypeMate background dictation'
\$shortcut.IconLocation = '$escapedPath,0'
\$shortcut.WindowStyle = 7
\$shortcut.Save()
\$enabled = [byte[]](0x02,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00)
\$approvedRunPath = 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\StartupApproved\\Run'
\$approvedStartupPath = 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\StartupApproved\\StartupFolder'
New-Item -Path \$approvedRunPath -Force | Out-Null
New-Item -Path \$approvedStartupPath -Force | Out-Null
New-ItemProperty -Path \$approvedRunPath -Name 'TypeMate' -PropertyType Binary -Value \$enabled -Force | Out-Null
New-ItemProperty -Path \$approvedStartupPath -Name 'TypeMate.lnk' -PropertyType Binary -Value \$enabled -Force | Out-Null
""";
    final result = await processRunner('powershell.exe', [
      '-NoProfile',
      '-Command',
      script,
    ]);

    if (result.exitCode != 0) {
      throw StateError(
        'Unable to register TypeMate for startup. ${result.stderr}',
      );
    }
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
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class TypeMateOverlayWindow {
  [DllImport("user32.dll")]
  public static extern bool SetWindowPos(
    IntPtr hWnd,
    IntPtr hWndInsertAfter,
    int X,
    int Y,
    int cx,
    int cy,
    uint uFlags);
}
"@
[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text = 'TypeMate'
$form.FormBorderStyle = 'None'
$form.StartPosition = 'Manual'
$form.TopMost = $true
$form.ShowInTaskbar = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(31, 34, 48)
$form.Width = 420
$form.Height = 104
$form.Opacity = 0.96

$screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Left = [int](($screen.Width - $form.Width) / 2)
$form.Top = [int]($screen.Top + 24)

$container = New-Object System.Windows.Forms.TableLayoutPanel
$container.Dock = 'Fill'
$container.ColumnCount = 1
$container.RowCount = 2
$container.Padding = New-Object System.Windows.Forms.Padding(20, 12, 20, 12)
$container.BackColor = $form.BackColor
$container.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 36))) | Out-Null
$container.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null

$label = New-Object System.Windows.Forms.Label
$label.Text = 'TypeMate is listening...'
$label.ForeColor = [System.Drawing.Color]::White
$label.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$label.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$label.Dock = 'Fill'
$container.Controls.Add($label, 0, 0)

$wavePanel = New-Object System.Windows.Forms.Panel
$wavePanel.Dock = 'Fill'
$wavePanel.BackColor = $form.BackColor
$container.Controls.Add($wavePanel, 0, 1)
$form.Controls.Add($container)

$script:bars = @()
$script:barCount = 13
$script:barWidth = 10
$script:gap = 10
$script:maxHeight = 34
$script:minHeight = 8
$totalWidth = ($script:barCount * $script:barWidth) + (($script:barCount - 1) * $script:gap)
$startX = [int](($form.Width - $totalWidth) / 2) - 20
for ($i = 0; $i -lt $script:barCount; $i++) {
  $bar = New-Object System.Windows.Forms.Panel
  $bar.Width = $script:barWidth
  $bar.Height = $script:minHeight
  $bar.Left = $startX + ($i * ($script:barWidth + $script:gap))
  $bar.Top = [int](($script:maxHeight - $bar.Height) / 2)
  $bar.BackColor = [System.Drawing.Color]::FromArgb(122, 139, 255)
  $wavePanel.Controls.Add($bar)
  $script:bars += $bar
}

$tick = 0
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 70
$timer.Add_Tick({
  $script:tick += 1
  for ($i = 0; $i -lt $script:bars.Count; $i++) {
    $phase = ($script:tick + ($i * 2)) * 0.55
    $height = [int]($script:minHeight + (([Math]::Sin($phase) + 1) / 2) * ($script:maxHeight - $script:minHeight))
    $script:bars[$i].Height = $height
    $script:bars[$i].Top = [int](($script:maxHeight - $height) / 2)
  }
})
$form.Add_Shown({
  $topMost = [IntPtr]::new(-1)
  $noSize = 0x0001
  $noMove = 0x0002
  $showWindow = 0x0040
  [TypeMateOverlayWindow]::SetWindowPos(
    $form.Handle,
    $topMost,
    0,
    0,
    0,
    0,
    $noSize -bor $noMove -bor $showWindow
  ) | Out-Null
  $timer.Start()
})
$form.Add_FormClosed({ $timer.Stop(); $timer.Dispose() })
[System.Windows.Forms.Application]::Run($form)
''';
