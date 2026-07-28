import 'dart:io';

class MicrophoneDevice {
  const MicrophoneDevice({required this.name, this.alternativeName});

  final String name;
  final String? alternativeName;

  /// Value equality so a re-scan (which builds fresh instances) recognizes
  /// devices that are still present, keeping the user's selection stable.
  @override
  bool operator ==(Object other) =>
      other is MicrophoneDevice &&
      other.name == name &&
      other.alternativeName == alternativeName;

  @override
  int get hashCode => Object.hash(name, alternativeName);
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
