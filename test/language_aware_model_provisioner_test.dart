import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/stt/language_aware_model_provisioner.dart';
import 'package:typemate/src/core/stt/stt_model_provisioner.dart';

SttModelProvisioner _provisioner(Directory directory, String fileName) =>
    SttModelProvisioner(
      modelDirectory: directory,
      files: [
        SttModelFile(
          url: 'https://example.invalid/$fileName',
          relativePath: fileName,
          expectedBytes: 3,
        ),
      ],
      downloader:
          (
            file,
            target, {
            required resumeFromBytes,
            required onProgress,
          }) async {
            target.writeAsBytesSync([1, 2, 3]);
            onProgress(3);
          },
    );

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('typemate-lang-prov-');
  });

  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  test('a language without an entry is ready with nothing to download', () {
    final coordinator = LanguageAwareModelProvisioner(
      provisionersByLanguageCode: {'hi': _provisioner(temp, 'hindi.bin')},
      languageCodeProvider: () => 'en',
    );

    expect(coordinator.active, isNull);
    expect(coordinator.isReady, isTrue);
    expect(coordinator.phase, SttModelProvisionPhase.ready);
    expect(coordinator.progress, 1);
    expect(coordinator.expectedTotalBytes, 0);
  });

  test('surfaces the selected language\'s provisioner state', () async {
    var language = 'hi';
    final hindi = _provisioner(temp, 'hindi.bin');
    final coordinator = LanguageAwareModelProvisioner(
      provisionersByLanguageCode: {'hi': hindi},
      languageCodeProvider: () => language,
    );

    await coordinator.refresh();
    expect(coordinator.isReady, isFalse);
    expect(coordinator.phase, SttModelProvisionPhase.downloadRequired);
    expect(coordinator.expectedTotalBytes, 3);

    await coordinator.download();
    expect(coordinator.isReady, isTrue);

    // Switching to a bundled language reports ready regardless.
    language = 'en';
    expect(coordinator.active, isNull);
    expect(coordinator.isReady, isTrue);
  });

  test('forwards child notifications and notifies on refresh', () async {
    var language = 'hi';
    final hindi = _provisioner(temp, 'hindi.bin');
    final coordinator = LanguageAwareModelProvisioner(
      provisionersByLanguageCode: {'hi': hindi},
      languageCodeProvider: () => language,
    );
    var notifications = 0;
    coordinator.addListener(() => notifications += 1);

    // The child's phase changes bubble up through the coordinator.
    await hindi.refresh();
    expect(notifications, greaterThan(0));

    // A refresh after a language change notifies even when the new
    // language has no provisioner (the UI must drop the download card).
    final before = notifications;
    language = 'en';
    await coordinator.refresh();
    expect(notifications, greaterThan(before));
  });

  test('languages sharing one provisioner notify once per change', () async {
    final shared = _provisioner(temp, 'parakeet.bin');
    final coordinator = LanguageAwareModelProvisioner(
      provisionersByLanguageCode: {'en': shared, 'de': shared, 'fr': shared},
      languageCodeProvider: () => 'en',
    );
    var notifications = 0;
    coordinator.addListener(() => notifications += 1);

    await shared.refresh();

    // refresh() emits checking + downloadRequired = 2 phase changes; a
    // listener registered per language code would triple that.
    expect(notifications, 2);
  });
}
