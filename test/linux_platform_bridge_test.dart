import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/platform/linux/linux_platform_bridge.dart';

class _FakeOverlaySink implements OverlaySink {
  _FakeOverlaySink(this.commands, {this.onClose});

  final List<String> commands;
  final void Function()? onClose;

  @override
  void send(String command) => commands.add(command);

  @override
  Future<void> close() async => onClose?.call();
}

void main() {
  test('X11 overlay draws capsule bars and plays the appearance chime', () {
    final source = File('linux/overlay/typemate_overlay.c').readAsStringSync();

    // Bars must have rounded capsule ends like the Windows RoundRect bars,
    // not sharp XFillRectangle corners.
    expect(
      source,
      contains('XFillArc(d, buffer, gc, bx, by, kBarWidth, kBarWidth'),
    );
    expect(
      source,
      isNot(contains('XFillRectangle(d, buffer, gc, bx, by, kBarWidth, h)')),
    );

    // The appearance chime: same generated WAV as Windows, ALSA loaded at
    // runtime so missing libasound degrades to silence, never a crash.
    expect(source, contains('#include "overlay_chime_wav.h"'));
    expect(source, contains('libasound.so.2'));
    expect(source, contains('play_chime();'));

    // Both platforms must embed the identical sound.
    final linuxHeader = File(
      'linux/overlay/overlay_chime_wav.h',
    ).readAsStringSync();
    final windowsHeader = File(
      'windows/runner/overlay_chime_wav.h',
    ).readAsStringSync();
    expect(linuxHeader, windowsHeader);
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

  test('drives the overlay through its lifecycle', () async {
    final commands = <String>[];
    var spawnCount = 0;
    var closed = false;
    final bridge = LinuxPlatformBridge(
      processRunner: (_, _, {environment}) async => ProcessResult(1, 0, '', ''),
      environment: const {'DISPLAY': ':0'},
      executablePath: '/opt/typemate/typemate',
      overlayExecutable: '/opt/typemate/bin/overlay/typemate-overlay',
      overlayStarter: () async {
        spawnCount++;
        return _FakeOverlaySink(commands, onClose: () => closed = true);
      },
    );

    // Showing spawns the helper (which maps its window on start); the
    // transcribing update is sent; hiding closes it.
    await bridge.showListeningOverlay();
    await bridge.showTranscribingOverlay();
    await bridge.hideListeningOverlay();

    expect(spawnCount, 1);
    expect(commands, ['transcribing']);
    expect(closed, isTrue);

    // The next dictation spawns a fresh helper.
    await bridge.showListeningOverlay();
    expect(spawnCount, 2);
  });

  test('overlay stays silent when no helper is configured', () async {
    var started = false;
    final bridge = LinuxPlatformBridge(
      processRunner: (_, _, {environment}) async => ProcessResult(1, 0, '', ''),
      environment: const {'DISPLAY': ':0'},
      executablePath: '/opt/typemate/typemate',
      overlayStarter: () async {
        started = true;
        return null;
      },
    );

    await bridge.showListeningOverlay();
    await bridge.showListeningOverlay();

    // A failed start is remembered so it is not retried on every dictation.
    expect(started, isTrue);
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
