import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart' as record_pkg;
import 'package:typemate/src/core/audio/ffmpeg_microphone_discovery.dart';
import 'package:typemate/src/core/audio/record_package_audio.dart';

class FakeRecordBackend implements RecordBackend {
  FakeRecordBackend({this.devices = const [], this.stopPath});

  final List<record_pkg.InputDevice> devices;
  final String? stopPath;

  record_pkg.RecordConfig? startedConfig;
  String? startedPath;
  bool stopped = false;
  bool disposed = false;

  @override
  Future<List<record_pkg.InputDevice>> listInputDevices() async => devices;

  @override
  Future<void> start(
    record_pkg.RecordConfig config, {
    required String path,
  }) async {
    startedConfig = config;
    startedPath = path;
  }

  @override
  Future<String?> stop() async {
    stopped = true;
    return stopPath ?? startedPath;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

void main() {
  test('discovery maps plugin devices to microphone devices', () async {
    final backend = FakeRecordBackend(
      devices: const [
        record_pkg.InputDevice(id: '{0.0.1.00000000}.{abc}', label: 'Brio 100'),
        record_pkg.InputDevice(id: '{0.0.1.00000000}.{def}', label: 'Headset'),
      ],
    );
    final discovery = RecordPackageMicrophoneDiscovery(
      backendFactory: () => backend,
    );

    final devices = await discovery.listMicrophones();

    expect(devices, hasLength(2));
    expect(devices[0].name, 'Brio 100');
    expect(devices[0].alternativeName, '{0.0.1.00000000}.{abc}');
    expect(backend.disposed, isTrue);
  });

  test('recorder captures 16kHz mono wav from the selected device', () async {
    final directory = Directory.systemTemp.createTempSync('typemate-rec-pkg');
    addTearDown(() => directory.deleteSync(recursive: true));
    final backend = FakeRecordBackend();
    final recorder = RecordPackageAudioRecorder(
      microphone: const MicrophoneDevice(
        name: 'Brio 100',
        alternativeName: '{device-id}',
      ),
      outputDirectory: directory,
      backendFactory: () => backend,
      clock: () => DateTime(2026, 7, 17, 10, 30),
    );

    await recorder.start();

    final config = backend.startedConfig!;
    expect(config.encoder, record_pkg.AudioEncoder.wav);
    expect(config.sampleRate, 16000);
    expect(config.numChannels, 1);
    expect(config.device?.id, '{device-id}');
    expect(backend.startedPath, endsWith('typemate-20260717-103000.wav'));

    final recording = await recorder.stop();
    expect(backend.stopped, isTrue);
    expect(backend.disposed, isTrue);
    expect(recording.path, backend.startedPath);
  });

  test('stop without start returns an empty recording', () async {
    final recorder = RecordPackageAudioRecorder(
      microphone: const MicrophoneDevice(name: 'Brio 100'),
      outputDirectory: Directory.systemTemp,
      backendFactory: FakeRecordBackend.new,
    );

    final recording = await recorder.stop();
    expect(recording.path, isEmpty);
    expect(recording.duration, Duration.zero);
  });

  test('factory builds a recorder for the selected microphone', () async {
    final backend = FakeRecordBackend();
    final directory = Directory.systemTemp.createTempSync('typemate-rec-fac');
    addTearDown(() => directory.deleteSync(recursive: true));
    final factory = RecordPackageAudioRecorderFactory(
      outputDirectory: directory,
      backendFactory: () => backend,
    );

    final recorder = factory.create(
      const MicrophoneDevice(name: 'Brio 100', alternativeName: '{id}'),
    );
    await recorder.start();

    expect(backend.startedConfig?.device?.id, '{id}');
  });
}
