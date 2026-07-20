import 'dart:io';

/// Finds an ALSA capture device that actually records on this machine.
///
/// `default` routes to PulseAudio/PipeWire on a normal desktop, but on
/// minimal setups (some VMs, headless boxes) it points at nothing and
/// ffmpeg fails with "No such device". The fallbacks capture the real
/// hardware card. The first spec that opens is cached for the session.
typedef AlsaProbeRunner =
    Future<int> Function(String executable, List<String> arguments);

const _candidateDevices = ['default', 'sysdefault', 'plughw:0', 'hw:0'];

String? _cachedDevice;

Future<String> resolveAlsaCaptureDevice(
  String ffmpegExecutable, {
  List<String> candidates = _candidateDevices,
  AlsaProbeRunner? probe,
  bool useCache = true,
}) async {
  if (useCache && _cachedDevice != null) {
    return _cachedDevice!;
  }
  final runner = probe ?? _defaultProbe;
  for (final device in candidates) {
    final exitCode = await runner(ffmpegExecutable, [
      '-hide_banner',
      '-f',
      'alsa',
      '-i',
      device,
      '-t',
      '0.2',
      '-f',
      'null',
      '-',
    ]);
    if (exitCode == 0) {
      _cachedDevice = device;
      return device;
    }
  }
  // Nothing probed clean; fall back to the most forgiving spec so the
  // recorder still attempts a capture rather than giving up.
  _cachedDevice = candidates.isEmpty ? 'default' : candidates.first;
  return _cachedDevice!;
}

/// Clears the session cache; for tests.
void resetAlsaCaptureDeviceCache() => _cachedDevice = null;

Future<int> _defaultProbe(String executable, List<String> arguments) async {
  try {
    final result = await Process.run(executable, arguments);
    return result.exitCode;
  } on ProcessException {
    return -1;
  }
}
