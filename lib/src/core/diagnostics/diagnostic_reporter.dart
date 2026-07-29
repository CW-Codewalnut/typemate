import 'diagnostic_log.dart';

/// Receives failure reports for remote telemetry. Implemented by the
/// Sentry-backed sink in production and by fakes in tests.
abstract interface class TelemetrySink {
  /// [kind] is a stable machine-readable slug (e.g. 'transcribe-timeout')
  /// used for grouping; [message] carries the human-readable detail.
  void reportFailure(String area, String kind, String message);
}

/// Single diagnostics funnel handed to the dictation flow and the speech
/// engines: everything goes to the local [DiagnosticLog]; failures
/// additionally go to the optional [telemetrySink] (Sentry) when the user
/// has telemetry enabled.
class DiagnosticReporter {
  DiagnosticReporter({
    this.log = const DiagnosticLog.disabled(),
    this.telemetrySink,
  });

  final DiagnosticLog log;

  /// Where failure reports go besides the local log. In production this is
  /// the TelemetryController, which itself gates on consent and backend
  /// state — this reference never changes after construction.
  final TelemetrySink? telemetrySink;

  void info(String area, String message) => log.log(area, message);

  void failure(String area, String kind, String message) {
    log.log(area, '$kind: $message');
    try {
      telemetrySink?.reportFailure(area, kind, message);
    } catch (_) {
      // Telemetry must never break the flow it observes.
    }
  }
}
