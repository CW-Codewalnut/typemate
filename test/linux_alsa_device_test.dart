import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/audio/linux_alsa_device.dart';

void main() {
  setUp(resetAlsaCaptureDeviceCache);

  test('returns the first device that ffmpeg opens cleanly', () async {
    final tried = <String>[];
    final device = await resolveAlsaCaptureDevice(
      'ffmpeg',
      candidates: const ['default', 'sysdefault', 'plughw:0'],
      probe: (exe, args) async {
        final requested = args[args.indexOf('-i') + 1];
        tried.add(requested);
        // `default` fails (raw-ALSA VM), `sysdefault` opens.
        return requested == 'default' ? 1 : 0;
      },
    );

    expect(device, 'sysdefault');
    expect(tried, ['default', 'sysdefault']);
  });

  test('caches the resolved device for the session', () async {
    var probeCount = 0;
    Future<String> resolve() => resolveAlsaCaptureDevice(
      'ffmpeg',
      candidates: const ['plughw:0'],
      probe: (_, _) async {
        probeCount++;
        return 0;
      },
    );

    expect(await resolve(), 'plughw:0');
    expect(await resolve(), 'plughw:0');
    expect(probeCount, 1, reason: 'the probe runs once, then caches');
  });

  test('falls back to the first candidate when nothing opens', () async {
    final device = await resolveAlsaCaptureDevice(
      'ffmpeg',
      candidates: const ['default', 'sysdefault'],
      probe: (_, _) async => 1,
    );

    expect(device, 'default');
  });
}
