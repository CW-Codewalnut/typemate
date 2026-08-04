import 'dart:io';

import 'package:flutter/services.dart';

import '../overlay/overlay_window.dart';
import '../platform_bridge.dart';

const _nativeChannel = MethodChannel('typemate/windows');

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

typedef NativeMethodInvoker =
    Future<T?> Function<T>(String method, [Object? arguments]);

class WindowsPlatformBridge
    implements PlatformBridge, InfoOverlaySource, QuitRequestSource {
  WindowsPlatformBridge({
    this.processRunner = runPlatformProcess,
    NativeMethodInvoker? nativeMethodInvoker,
    String? executablePath,
    OverlayWindow? overlayWindow,
  }) : nativeMethodInvoker = nativeMethodInvoker ?? _nativeChannel.invokeMethod,
       _executablePath = executablePath ?? Platform.resolvedExecutable,
       _overlay = overlayWindow ?? OverlayWindow.forPlatform() {
    _nativeChannel.setMethodCallHandler(_handleNativeCall);
    // Off the dictation critical path: the first showListening must
    // never wait on second-engine bring-up while the user speaks.
    _overlay.preload();
  }

  final PlatformProcessRunner processRunner;
  final NativeMethodInvoker nativeMethodInvoker;
  final String _executablePath;

  /// The Flutter-rendered overlay window (second engine), which replaced
  /// the native Win32 overlay renderer.
  final OverlayWindow _overlay;

  Future<void> Function()? _onQuitRequested;

  @override
  set onQuitRequested(Future<void> Function()? handler) {
    _onQuitRequested = handler;
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'quitRequested') {
      await _onQuitRequested?.call();
    }
    return null;
  }

  @override
  Future<bool> isGlobalShortcutAvailable() async => true;

  @override
  Future<void> showListeningOverlay() async {
    await _overlay.showWorking('TypeMate is listening...');
  }

  @override
  Future<void> showTranscribingOverlay() async {
    await _overlay.showWorking('Transcribing locally...');
  }

  @override
  Future<void> showDictationFailureOverlay(String message) async {
    await _overlay.showError(message);
  }

  @override
  Future<void> showDictationInfoOverlay(String message) async {
    await _overlay.showInfo(message);
  }

  @override
  Future<void> hideListeningOverlay() async {
    await _overlay.hide();
  }

  @override
  Future<void> ensureLaunchAtStartup() async {
    final executablePath = _executablePath;
    // Never register the Flutter test harness (or anything that is not the
    // real app) for startup: widget tests once wrote flutter_tester.exe
    // into the user's Run key.
    if (!executablePath.toLowerCase().endsWith('typemate.exe')) {
      return;
    }
    final escapedPath = executablePath.replaceAll("'", "''");
    // Startup registration uses only the Startup-folder shortcut, which
    // pins WorkingDirectory to the exe folder. A Run-key launch inherits
    // C:\Windows\System32 as its working directory, which broke dictation
    // after login; older builds wrote that value, so remove it here.
    final script =
        """
\$runPath = 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run'
\$approvedRunPath = 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\StartupApproved\\Run'
Remove-ItemProperty -Path \$runPath -Name 'TypeMate' -ErrorAction SilentlyContinue
Remove-ItemProperty -Path \$approvedRunPath -Name 'TypeMate' -ErrorAction SilentlyContinue
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
\$approvedStartupPath = 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\StartupApproved\\StartupFolder'
New-Item -Path \$approvedStartupPath -Force | Out-Null
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
    try {
      // Primary path: the native runner types the text into the focused
      // field with SendInput unicode events. The clipboard stays untouched.
      await nativeMethodInvoker<void>('insertText', {'text': text});
      return;
    } on MissingPluginException {
      // Development fallback for older Windows runners before the native
      // method channel is available: clipboard + Ctrl+V.
    }

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
