import 'dart:io';

class MicrophoneDevice {
  const MicrophoneDevice({required this.name, this.alternativeName});

  final String name;
  final String? alternativeName;
}

class DiscoveryProcessResult {
  const DiscoveryProcessResult({required this.exitCode, required this.output});

  final int exitCode;
  final String output;
}

abstract interface class DiscoveryProcessRunner {
  Future<DiscoveryProcessResult> run(String executable, List<String> arguments);
}

abstract interface class MicrophoneDiscovery {
  Future<List<MicrophoneDevice>> listMicrophones();
}

class FfmpegMicrophoneDiscovery implements MicrophoneDiscovery {
  const FfmpegMicrophoneDiscovery({
    this.executable = 'ffmpeg',
    this.processRunner = const DartDiscoveryProcessRunner(),
  });

  final String executable;
  final DiscoveryProcessRunner processRunner;

  @override
  Future<List<MicrophoneDevice>> listMicrophones() async {
    final result = await processRunner.run(executable, [
      '-hide_banner',
      '-list_devices',
      'true',
      '-f',
      'dshow',
      '-i',
      'dummy',
    ]);

    return parseDirectShowDevices(result.output);
  }

  static List<MicrophoneDevice> parseDirectShowDevices(String output) {
    final devices = <MicrophoneDevice>[];
    String? pendingAudioDevice;

    for (final line in output.split(RegExp(r'\r?\n'))) {
      final deviceMatch = RegExp(r'"(.+)" \((audio|video)\)').firstMatch(line);
      if (deviceMatch != null) {
        if (deviceMatch.group(2) == 'audio') {
          pendingAudioDevice = deviceMatch.group(1);
        } else {
          pendingAudioDevice = null;
        }
        continue;
      }

      final alternativeNameMatch = RegExp(
        r'Alternative name "(.+)"',
      ).firstMatch(line);
      if (alternativeNameMatch != null && pendingAudioDevice != null) {
        devices.add(
          MicrophoneDevice(
            name: pendingAudioDevice,
            alternativeName: alternativeNameMatch.group(1),
          ),
        );
        pendingAudioDevice = null;
      }
    }

    if (pendingAudioDevice != null) {
      devices.add(MicrophoneDevice(name: pendingAudioDevice));
    }

    return devices;
  }
}

class DartDiscoveryProcessRunner implements DiscoveryProcessRunner {
  const DartDiscoveryProcessRunner();

  @override
  Future<DiscoveryProcessResult> run(
    String executable,
    List<String> arguments,
  ) async {
    final result = await Process.run(executable, arguments);
    return DiscoveryProcessResult(
      exitCode: result.exitCode,
      output: '${result.stdout}${result.stderr}',
    );
  }
}
