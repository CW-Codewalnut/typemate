import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:typemate/src/core/stt/stt_model_provisioner.dart';

/// The real desktop download stack, end to end: SttModelProvisioner
/// driving the background_downloader package's desktop backend against a
/// real hosted model file — the same path a slim install takes on first
/// use. Uses the smallest catalog-grade file (Silero VAD, ~0.9 MB) so the
/// test stays fast while still exercising real HTTP, the size gate, the
/// checksum gate, and the rename-to-complete.
///
/// Needs network access; run on a desktop device:
///   flutter test integration_test/desktop_model_download_test.dart -d windows
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('slim-install model download completes and verifies', (
    tester,
  ) async {
    // macOS CI runs e2e on flutter-tester (see ci.yml), which registers
    // no native plugins — the package's macOS download backend cannot
    // exist there. Windows/Linux/Android exercise the real backend.
    if (Platform.resolvedExecutable.contains('flutter_tester')) {
      markTestSkipped('real download backend unavailable on flutter-tester');
      return;
    }
    await FileDownloader().trackTasks();
    final directory = Directory.systemTemp.createTempSync('typemate-dl-e2e');
    addTearDown(() => directory.deleteSync(recursive: true));

    final provisioner = SttModelProvisioner(
      modelDirectory: directory,
      files: const [
        SttModelFile(
          url:
              'https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v5.1.2.bin',
          relativePath: 'ggml-silero-v5.1.2.bin',
          expectedBytes: 885098,
          expectedSha256:
              '29940d98d42b91fbd05ce489f3ecf7c72f0a42f027e4875919a28fb4c04ea2cf',
        ),
      ],
    );
    addTearDown(provisioner.dispose);

    await provisioner.refresh();
    expect(provisioner.phase, SttModelProvisionPhase.downloadRequired);

    await provisioner.download();

    expect(provisioner.phase, SttModelProvisionPhase.ready);
    expect(provisioner.isReady, isTrue);
    final downloaded = File('${directory.path}/ggml-silero-v5.1.2.bin');
    expect(downloaded.existsSync(), isTrue);
    expect(downloaded.lengthSync(), 885098);
  });
}
