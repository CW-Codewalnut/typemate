import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/app.dart';
import 'package:typemate/src/core/audio/system_default_microphone_discovery.dart';

void main() {
  test('prefers the bundled xdotool with its library directory', () {
    final resolved = resolveXdotool(
      environment: const {},
      pathExists: (path) => path == '/apps/typemate/bin/xdotool/xdotool',
      currentDirectoryPath: '/apps/typemate',
      executableDirectoryPath: '/apps/typemate/build',
    );

    expect(resolved.executable, '/apps/typemate/bin/xdotool/xdotool');
    expect(resolved.libraryDirectory, '/apps/typemate/bin/xdotool');
  });

  test('falls back to PATH xdotool without a library override', () {
    final resolved = resolveXdotool(
      environment: const {},
      pathExists: (_) => false,
      currentDirectoryPath: '/apps/typemate',
      executableDirectoryPath: '/apps/typemate/build',
    );

    expect(resolved.executable, 'xdotool');
    expect(resolved.libraryDirectory, isNull);
  });

  test('environment override wins for ffmpeg', () {
    final resolved = resolveFfmpegExecutable(
      environment: const {'TYPEMATE_FFMPEG': '/custom/ffmpeg'},
      pathExists: (_) => true,
      currentDirectoryPath: '/apps/typemate',
      executableDirectoryPath: '/apps/typemate/build',
    );

    expect(resolved, '/custom/ffmpeg');
  });

  test('bundled ffmpeg is found next to the app', () {
    final resolved = resolveFfmpegExecutable(
      environment: const {},
      pathExists: (path) => path == '/apps/typemate/bin/ffmpeg/ffmpeg',
      currentDirectoryPath: '/apps/typemate',
      executableDirectoryPath: '/apps/typemate/build',
      isWindows: false,
    );

    expect(resolved, '/apps/typemate/bin/ffmpeg/ffmpeg');
  });

  test(
    'system-default discovery offers exactly the alsa default device',
    () async {
      const discovery = SystemDefaultMicrophoneDiscovery();
      final devices = await discovery.listMicrophones();

      expect(devices, hasLength(1));
      expect(devices.single.name, 'System default microphone');
      expect(devices.single.alternativeName, 'default');
    },
  );
}
