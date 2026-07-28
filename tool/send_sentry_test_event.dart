// Sends one test event to the Sentry project so the DSN, network path,
// and dashboard can be verified without building or running the app.
//
// Usage: dart run tool/send_sentry_test_event.dart <dsn>
import 'dart:io';

import 'package:sentry/sentry.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/send_sentry_test_event.dart <dsn>');
    exit(64);
  }
  await Sentry.init((options) {
    options.dsn = args.first;
    options.release = 'typemate-dsn-verification';
  });
  final id = await Sentry.captureMessage(
    'TypeMate telemetry verification event',
    level: SentryLevel.info,
  );
  // close() flushes the queue; without it the process can exit first.
  await Sentry.close();
  stdout.writeln('sent event $id');
}
