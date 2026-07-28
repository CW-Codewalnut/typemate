import 'dart:async';

import 'package:sentry_flutter/sentry_flutter.dart';

import 'diagnostic_reporter.dart';
import 'path_scrubbing.dart';

/// Starts the Sentry SDK for anonymous error reports and release-health
/// sessions (active users per version/OS). Dictation stays local: no PII,
/// no screenshots, no tracing — errors and session counts only.
Future<void> startSentryTelemetry(String dsn) => SentryFlutter.init((options) {
  options.dsn = dsn;
  options.sendDefaultPii = false;
  options.attachScreenshot = false;
  options.enableAutoSessionTracking = true;
  options.beforeSend = scrubSentryEvent;
});

Future<void> stopSentryTelemetry() => Sentry.close();

/// Last line of defense before an event leaves the machine: usernames in
/// quoted paths are replaced in the message and every exception value.
/// Reports authored by [SentryTelemetrySink] are pre-scrubbed; this also
/// covers crash events captured by the SDK itself.
FutureOr<SentryEvent?> scrubSentryEvent(SentryEvent event, Hint hint) {
  final message = event.message;
  return event.copyWith(
    serverName: null,
    message: message == null
        ? null
        : SentryMessage(
            scrubPersonalPaths(message.formatted),
            template: message.template,
            params: message.params,
          ),
    exceptions: event.exceptions
        ?.map(
          (exception) => exception.copyWith(
            value: exception.value == null
                ? null
                : scrubPersonalPaths(exception.value!),
          ),
        )
        .toList(),
  );
}

/// Forwards failure reports to Sentry, grouped by (area, kind) so each
/// failure mode is one issue with a counter instead of a noise stream.
class SentryTelemetrySink implements TelemetrySink {
  const SentryTelemetrySink();

  @override
  void reportFailure(String area, String kind, String message) {
    unawaited(
      Sentry.captureMessage(
        '$area/$kind: ${scrubPersonalPaths(message)}',
        level: SentryLevel.error,
        withScope: (scope) {
          scope.fingerprint = [area, kind];
          scope.setTag('area', area);
          scope.setTag('kind', kind);
        },
      ),
    );
  }
}
