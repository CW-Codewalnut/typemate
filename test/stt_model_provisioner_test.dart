import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/stt/stt_model_provisioner.dart';

const _files = [
  SttModelFile(
    url: 'https://example.test/encoder.onnx',
    relativePath: 'encoder.onnx',
    expectedBytes: 10,
  ),
  SttModelFile(
    url: 'https://example.test/tokens.txt',
    relativePath: 'tokens.txt',
    expectedBytes: 10,
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

  test('a tampered completed file is detected and re-downloaded', () async {
    // A file at its final name but the wrong size (outside interference
    // with app storage — the validated rename can't produce this).
    File('${directory.path}/encoder.onnx').writeAsStringSync('0123');
    File('${directory.path}/tokens.txt').writeAsStringSync('0123456789');
    final downloaded = <String>[];
    final sut = provisioner(
      downloader:
          (
            file,
            target, {
            required resumeFromBytes,
            required onProgress,
          }) async {
            downloaded.add(file.relativePath);
            target.writeAsStringSync('0123456789');
          },
    );
    await sut.refresh();

    expect(
      sut.phase,
      SttModelProvisionPhase.downloadRequired,
      reason: 'Existence alone is not enough; the size must match.',
    );

    await sut.download();

    expect(sut.isReady, isTrue);
    expect(downloaded, ['encoder.onnx']);
    expect(
      File('${directory.path}/encoder.onnx').readAsStringSync(),
      '0123456789',
    );
  });

  test('reopening while a background download runs adopts it, not a new '
      'one', () async {
    var downloadCalls = 0;
    final sut = SttModelProvisioner(
      modelDirectory: directory,
      files: _files,
      // The download manager reports an in-flight download (app was
      // killed mid-download and reopened).
      hasActiveDownload: () async => true,
      downloader:
          (
            file,
            target, {
            required resumeFromBytes,
            required onProgress,
          }) async {
            downloadCalls += 1;
            target.writeAsStringSync('0123456789');
          },
    );

    await sut.refresh();

    // refresh() adopted the running download and drove it to completion
    // itself — the user never saw a Download button to double-tap.
    expect(sut.isReady, isTrue);
    expect(
      downloadCalls,
      _files.length,
      reason: 'Adopts by resuming the download, one pass per file.',
    );
  });

  test('a refresh during an active download leaves it untouched', () async {
    final gate = Completer<void>();
    final sut = provisioner(
      downloader:
          (
            file,
            target, {
            required resumeFromBytes,
            required onProgress,
          }) async {
            await gate.future;
            target.writeAsStringSync('0123456789');
          },
    );
    await sut.refresh();
    final downloading = sut.download();

    // Tab switches re-check the provisioner mid-download; that must not
    // hide the download behind the Download button again (which invited
    // a second concurrent download and a corrupted model).
    await sut.refresh();
    expect(sut.phase, SttModelProvisionPhase.downloading);

    await sut.download();
    expect(
      sut.phase,
      SttModelProvisionPhase.downloading,
      reason: 'A second download() while one runs is a no-op.',
    );

    gate.complete();
    await downloading;
    expect(sut.isReady, isTrue);
  });

  test('canceling from the notification returns to the Download button, '
      'not failed', () async {
    File('${directory.path}/encoder.onnx.part').writeAsStringSync('012');
    final sut = provisioner(
      downloader:
          (
            file,
            target, {
            required resumeFromBytes,
            required onProgress,
          }) async {
            // Mimics the package after the user taps Cancel on the
            // notification: a deliberate, terminal cancellation.
            throw const SttDownloadCanceled();
          },
    );
    await sut.refresh();

    await sut.download();

    expect(
      sut.phase,
      SttModelProvisionPhase.downloadRequired,
      reason: 'A user cancel is not a failure; offer Download again.',
    );
    expect(sut.errorMessage, isNull);
    expect(
      File('${directory.path}/encoder.onnx.part').existsSync(),
      isFalse,
      reason: 'Partial from the canceled attempt is discarded.',
    );

    // Tapping Download again after a cancel must actually download, not
    // silently do nothing.
    var secondAttempt = 0;
    final resumed = SttModelProvisioner(
      modelDirectory: directory,
      files: _files,
      downloader:
          (
            file,
            target, {
            required resumeFromBytes,
            required onProgress,
          }) async {
            secondAttempt += 1;
            target.writeAsStringSync('0123456789');
          },
    );
    await resumed.download();
    expect(resumed.isReady, isTrue);
    expect(secondAttempt, _files.length);
  });

  test('a checksum mismatch fails and discards the file', () async {
    // sha256 of the ten bytes '0123456789' that the fake writes.
    const rightHash =
        '84d89877f0d4041efb6bf91a16f0248f2fd573e6af05c19f96bedb9f882f7882';
    final files = [
      const SttModelFile(
        url: 'https://example.test/encoder.onnx',
        relativePath: 'encoder.onnx',
        expectedBytes: 10,
        expectedSha256: rightHash,
      ),
      const SttModelFile(
        url: 'https://example.test/tokens.txt',
        relativePath: 'tokens.txt',
        expectedBytes: 10,
        // Right size, wrong content hash: the corrupt-model case that
        // crashes the native loader if it ever gets through.
        expectedSha256: 'deadbeef',
      ),
    ];
    final sut = SttModelProvisioner(
      modelDirectory: directory,
      files: files,
      downloader:
          (
            file,
            target, {
            required resumeFromBytes,
            required onProgress,
          }) async {
            target.writeAsStringSync('0123456789');
          },
    );
    await sut.refresh();

    await sut.download();

    expect(sut.phase, SttModelProvisionPhase.failed);
    expect(
      File('${directory.path}/encoder.onnx').existsSync(),
      isTrue,
      reason: 'The file with the matching hash completed normally.',
    );
    expect(File('${directory.path}/tokens.txt').existsSync(), isFalse);
    expect(
      File('${directory.path}/tokens.txt.part').existsSync(),
      isFalse,
      reason: 'A hash-mismatched file is discarded entirely.',
    );
  });

  test('a wrong-sized download fails and discards the partial file', () async {
    final sut = provisioner(
      downloader:
          (
            file,
            target, {
            required resumeFromBytes,
            required onProgress,
          }) async {
            // The stream "ends" early: fewer bytes than the pinned
            // revision's exact size.
            target.writeAsStringSync('01234');
          },
    );
    await sut.refresh();

    await sut.download();

    expect(sut.phase, SttModelProvisionPhase.failed);
    expect(
      File('${directory.path}/encoder.onnx').existsSync(),
      isFalse,
      reason: 'A wrong-sized file must never be renamed to complete.',
    );
    expect(
      File('${directory.path}/encoder.onnx.part').existsSync(),
      isFalse,
      reason: 'The mismatched partial is discarded so retry starts clean.',
    );
  });
}
