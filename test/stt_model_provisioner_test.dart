import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/stt/stt_model_provisioner.dart';

const _files = [
  SttModelFile(
    url: 'https://example.test/encoder.onnx',
    relativePath: 'encoder.onnx',
  ),
  SttModelFile(
    url: 'https://example.test/tokens.txt',
    relativePath: 'tokens.txt',
  ),
];

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('typemate-model');
  });

  tearDown(() => directory.deleteSync(recursive: true));

  SttModelProvisioner provisioner({SttModelFileDownloader? downloader}) =>
      SttModelProvisioner(
        modelDirectory: directory,
        files: _files,
        expectedTotalBytes: 20,
        downloader:
            downloader ??
            (
              file,
              target, {
              required resumeFromBytes,
              required onProgress,
            }) async {
              target.writeAsStringSync('0123456789');
              onProgress(10);
            },
      );

  test('refresh reports downloadRequired when files are missing', () async {
    final sut = provisioner();

    await sut.refresh();

    expect(sut.phase, SttModelProvisionPhase.downloadRequired);
    expect(sut.isReady, isFalse);
  });

  test('refresh reports ready when every file exists', () async {
    for (final file in _files) {
      File('${directory.path}/${file.relativePath}')
        ..createSync(recursive: true)
        ..writeAsStringSync('0123456789');
    }
    final sut = provisioner();

    await sut.refresh();

    expect(sut.isReady, isTrue);
  });

  test('download fetches every file and lands ready', () async {
    final sut = provisioner();
    await sut.refresh();

    await sut.download();

    expect(sut.isReady, isTrue);
    expect(sut.progress, 1);
    for (final file in _files) {
      expect(
        File('${directory.path}/${file.relativePath}').existsSync(),
        isTrue,
      );
      expect(
        File('${directory.path}/${file.relativePath}.part').existsSync(),
        isFalse,
        reason: 'completed downloads leave no partial file behind',
      );
    }
  });

  test(
    'a failed download reports failure and keeps the partial file',
    () async {
      var calls = 0;
      final sut = provisioner(
        downloader:
            (
              file,
              target, {
              required resumeFromBytes,
              required onProgress,
            }) async {
              calls += 1;
              if (calls == 2) {
                target.writeAsStringSync('01234');
                throw const SocketException('connection reset');
              }
              target.writeAsStringSync('0123456789');
            },
      );
      await sut.refresh();

      await sut.download();

      expect(sut.phase, SttModelProvisionPhase.failed);
      expect(sut.errorMessage, isNotNull);
      expect(File('${directory.path}/encoder.onnx').existsSync(), isTrue);
      expect(File('${directory.path}/tokens.txt.part').existsSync(), isTrue);
    },
  );

  test('retry skips finished files and resumes the partial one', () async {
    File('${directory.path}/encoder.onnx').writeAsStringSync('0123456789');
    File('${directory.path}/tokens.txt.part').writeAsStringSync('01234');
    final resumeOffsets = <String, int>{};
    final sut = provisioner(
      downloader:
          (
            file,
            target, {
            required resumeFromBytes,
            required onProgress,
          }) async {
            resumeOffsets[file.relativePath] = resumeFromBytes;
            target.writeAsStringSync(
              '56789',
              mode: resumeFromBytes > 0 ? FileMode.append : FileMode.write,
            );
          },
    );
    await sut.refresh();

    await sut.download();

    expect(sut.isReady, isTrue);
    expect(resumeOffsets.keys, ['tokens.txt']);
    expect(resumeOffsets['tokens.txt'], 5);
    expect(
      File('${directory.path}/tokens.txt').readAsStringSync(),
      '0123456789',
    );
  });
}
