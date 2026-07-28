import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/diagnostics/path_scrubbing.dart';

void main() {
  test('replaces the username in Windows home paths', () {
    expect(
      scrubPersonalPaths(
        r'model not found at C:\Users\ranjan.bhagat\AppData\Local\TypeMate\models\x.bin',
      ),
      r'model not found at C:\Users\<user>\AppData\Local\TypeMate\models\x.bin',
    );
  });

  test('handles forward-slash Windows paths and other drive letters', () {
    expect(
      scrubPersonalPaths('searched D:/Users/jane/app/bin/whisper-cli.exe'),
      r'searched C:\Users\<user>/app/bin/whisper-cli.exe',
    );
  });

  test('replaces the username in Linux and macOS home paths', () {
    expect(
      scrubPersonalPaths(
        'could not spawn /home/jane/.local/share/TypeMate/bin/x',
      ),
      'could not spawn /home/<user>/.local/share/TypeMate/bin/x',
    );
    expect(
      scrubPersonalPaths('missing /Users/jane/Library/TypeMate/models'),
      'missing /Users/<user>/Library/TypeMate/models',
    );
  });

  test('leaves path-free messages untouched', () {
    const message = 'transcription timed out after 20s (clip 5000ms)';
    expect(scrubPersonalPaths(message), message);
  });
}
