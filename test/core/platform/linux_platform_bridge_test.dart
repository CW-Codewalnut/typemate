import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/platform/linux/linux_platform_bridge.dart';
import 'package:typemate/src/core/platform/overlay/overlay_window.dart';

class _FakeOverlayWindow extends OverlayWindow {
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

void main() {
  test('the native X11 overlay helper is retired', () {
    // The overlay is a second Flutter window now
    // (lib/src/core/platform/overlay/); the C helper is gone and the
    // fetch script must not compile or ship it.
    expect(File('linux/overlay/typemate_overlay.c').existsSync(), isFalse);
    final fetchScript = File(
      'tool/fetch_whisper_runtime.dart',
    ).readAsStringSync();
    expect(fetchScript, isNot(contains('typemate_overlay')));
    expect(fetchScript, isNot(contains('bin/overlay')));
  });

  test('types into the focused field through xdotool', () async {
    String? executable;
    List<String>? arguments;
    final bridge = LinuxPlatformBridge(
      processRunner: (exe, args, {environment}) async {
        executable = exe;
        arguments = args;
        return ProcessResult(1, 0, '', '');
      },
      environment: const {'DISPLAY': ':0'},
      executablePath: '/opt/typemate/typemate',
    );

    await bridge.insertTextIntoFocusedField('नमस्ते world');

    expect(executable, 'xdotool');
    expect(arguments, [
      'type',
      '--clearmodifiers',
      '--delay',
      '2',
      '--',
      'नमस्ते world',
    ]);
  });

  test('bundled xdotool runs with its library directory on the path', () async {
    String? executable;
    Map<String, String>? spawnedEnvironment;
    final bridge = LinuxPlatformBridge(
      processRunner: (exe, args, {environment}) async {
        executable = exe;
        spawnedEnvironment = environment;
        return ProcessResult(1, 0, '', '');
      },
      environment: const {'DISPLAY': ':0', 'LD_LIBRARY_PATH': '/existing'},
      executablePath: '/opt/typemate/typemate',
      xdotoolExecutable: '/opt/typemate/bin/xdotool/xdotool',
      xdotoolLibraryDirectory: '/opt/typemate/bin/xdotool',
    );

    await bridge.insertTextIntoFocusedField('hello');

    expect(executable, '/opt/typemate/bin/xdotool/xdotool');
    expect(
      spawnedEnvironment?['LD_LIBRARY_PATH'],
      '/opt/typemate/bin/xdotool:/existing',
    );
  });

  test('overlay states map to the Flutter overlay window', () async {
    final overlay = _FakeOverlayWindow();
    final bridge = LinuxPlatformBridge(
      processRunner: (_, _, {environment}) async => ProcessResult(1, 0, '', ''),
      environment: const {'DISPLAY': ':0'},
      executablePath: '/opt/typemate/typemate',
      overlayWindow: overlay,
    );

    await bridge.showListeningOverlay();
    await bridge.showTranscribingOverlay();
    await bridge.showDictationInfoOverlay('Preparing local speech engine...');
    await bridge.showDictationFailureOverlay('Something went wrong.');
    await bridge.hideListeningOverlay();

    expect(overlay.calls, [
      'working:TypeMate is listening...',
      'working:Transcribing locally...',
      'info:Preparing local speech engine...',
      'error:Something went wrong.',
      'hide',
    ]);
  });

  test('fails clearly when xdotool is missing', () async {
    final bridge = LinuxPlatformBridge(
      processRunner: (exe, args, {environment}) async =>
          throw ProcessException(exe, args, 'not found', 2),
      environment: const {'DISPLAY': ':0'},
      executablePath: '/opt/typemate/typemate',
    );

    expect(
      () => bridge.insertTextIntoFocusedField('hello'),
      throwsA(isA<TextInsertionException>()),
    );
  });

  test('global shortcut availability follows the X display', () async {
    final withDisplay = LinuxPlatformBridge(
      processRunner: (_, _, {environment}) async => ProcessResult(1, 0, '', ''),
      environment: const {'DISPLAY': ':0'},
      executablePath: '/opt/typemate/typemate',
    );
    final withoutDisplay = LinuxPlatformBridge(
      processRunner: (_, _, {environment}) async => ProcessResult(1, 0, '', ''),
      environment: const {},
      executablePath: '/opt/typemate/typemate',
    );

    expect(await withDisplay.isGlobalShortcutAvailable(), isTrue);
    expect(await withoutDisplay.isGlobalShortcutAvailable(), isFalse);
  });

  test('registers an autostart entry only for the installed binary', () async {
    final configHome = Directory.systemTemp.createTempSync('typemate-xdg');
    addTearDown(() => configHome.deleteSync(recursive: true));

    final installed = LinuxPlatformBridge(
      processRunner: (_, _, {environment}) async => ProcessResult(1, 0, '', ''),
      environment: {'XDG_CONFIG_HOME': configHome.path},
      executablePath: '/opt/typemate/typemate',
    );
    await installed.ensureLaunchAtStartup();
    final entry = File('${configHome.path}/autostart/typemate.desktop');
    expect(entry.existsSync(), isTrue);
    final content = entry.readAsStringSync();
    expect(content, contains('Exec=/opt/typemate/typemate'));
    expect(content, contains('Icon=/opt/typemate/data/app_icon.png'));

    entry.deleteSync();
    final tester = LinuxPlatformBridge(
      processRunner: (_, _, {environment}) async => ProcessResult(1, 0, '', ''),
      environment: {'XDG_CONFIG_HOME': configHome.path},
      executablePath: '/usr/lib/flutter_tester',
    );
    await tester.ensureLaunchAtStartup();
    expect(entry.existsSync(), isFalse);
  });
}
