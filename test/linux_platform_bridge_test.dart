import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/platform/linux_platform_bridge.dart';

void main() {
  test('types into the focused field through xdotool', () async {
    String? executable;
    List<String>? arguments;
    final bridge = LinuxPlatformBridge(
      processRunner: (exe, args) async {
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

  test('fails clearly when xdotool is missing', () async {
    final bridge = LinuxPlatformBridge(
      processRunner: (exe, args) async =>
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
      processRunner: (_, _) async => ProcessResult(1, 0, '', ''),
      environment: const {'DISPLAY': ':0'},
      executablePath: '/opt/typemate/typemate',
    );
    final withoutDisplay = LinuxPlatformBridge(
      processRunner: (_, _) async => ProcessResult(1, 0, '', ''),
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
      processRunner: (_, _) async => ProcessResult(1, 0, '', ''),
      environment: {'XDG_CONFIG_HOME': configHome.path},
      executablePath: '/opt/typemate/typemate',
    );
    await installed.ensureLaunchAtStartup();
    final entry = File('${configHome.path}/autostart/typemate.desktop');
    expect(entry.existsSync(), isTrue);
    expect(entry.readAsStringSync(), contains('Exec=/opt/typemate/typemate'));

    entry.deleteSync();
    final tester = LinuxPlatformBridge(
      processRunner: (_, _) async => ProcessResult(1, 0, '', ''),
      environment: {'XDG_CONFIG_HOME': configHome.path},
      executablePath: '/usr/lib/flutter_tester',
    );
    await tester.ensureLaunchAtStartup();
    expect(entry.existsSync(), isFalse);
  });
}
