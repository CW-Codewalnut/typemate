import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:typemate/src/core/diagnostics/sentry_telemetry.dart';

void main() {
  test('scrubSentryEvent cleans the message, exception values, and '
      'server name', () async {
    final event = SentryEvent(
      serverName: 'RANJANS-LAPTOP',
      message: SentryMessage(
        r'model not found at C:\Users\jane\AppData\Local\TypeMate\m.bin',
      ),
      exceptions: [
        SentryException(
          type: 'FileSystemException',
          value: 'Cannot open file /home/jane/.config/TypeMate/history.json',
        ),
      ],
    );

    final scrubbed = (await scrubSentryEvent(event, Hint()))!;

    expect(
      scrubbed.message?.formatted,
      r'model not found at C:\Users\<user>\AppData\Local\TypeMate\m.bin',
    );
    expect(
      scrubbed.exceptions?.single.value,
      'Cannot open file /home/<user>/.config/TypeMate/history.json',
    );
    expect(scrubbed.serverName, '<device>');
  });

  test('scrubSentryEvent tolerates events without message or '
      'exceptions', () async {
    final scrubbed = await scrubSentryEvent(SentryEvent(), Hint());

    expect(scrubbed, isNotNull);
    expect(scrubbed!.message, isNull);
    expect(scrubbed.exceptions, anyOf(isNull, isEmpty));
  });
}
