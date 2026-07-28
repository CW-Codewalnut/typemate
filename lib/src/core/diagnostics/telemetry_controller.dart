import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'diagnostic_reporter.dart';

abstract interface class TelemetrySettingsStore {
  Future<TelemetrySettingsSnapshot> load();
  Future<void> save(TelemetrySettingsSnapshot snapshot);
}

class TelemetrySettingsSnapshot {
  const TelemetrySettingsSnapshot({this.errorReportingEnabled = true});

  /// Anonymous crash/error reporting. On by default and disclosed in
  /// Settings; the toggle there turns it off. Dictated text and audio are
  /// never part of a report regardless of this flag.
  final bool errorReportingEnabled;
}

class NoopTelemetrySettingsStore implements TelemetrySettingsStore {
  const NoopTelemetrySettingsStore();

  @override
  Future<TelemetrySettingsSnapshot> load() async =>
      const TelemetrySettingsSnapshot();

  @override
  Future<void> save(TelemetrySettingsSnapshot snapshot) async {}
}

class FileTelemetrySettingsStore implements TelemetrySettingsStore {
  const FileTelemetrySettingsStore({required this.file});

  final File file;

  @override
  Future<TelemetrySettingsSnapshot> load() async {
    if (!await file.exists()) {
      return const TelemetrySettingsSnapshot();
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded case Map<String, dynamic> values) {
      // A file written before the key existed reads as the on default.
      return TelemetrySettingsSnapshot(
        errorReportingEnabled: values['errorReportingEnabled'] != false,
      );
    }
    return const TelemetrySettingsSnapshot();
  }

  @override
  Future<void> save(TelemetrySettingsSnapshot snapshot) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({'errorReportingEnabled': snapshot.errorReportingEnabled}),
      flush: true,
    );
  }
}

typedef TelemetryStarter = Future<void> Function();
typedef TelemetryStopper = Future<void> Function();

/// Owns the error-reporting consent state and the telemetry backend's
/// lifecycle, and forwards failure reports only while reporting is on.
///
/// The Sentry-specific pieces (starter, stopper, sink) are injected so this
/// class — and everything that depends on it — stays testable without a
/// network backend. When [dsn] is empty (local/dev builds without
/// `--dart-define=TYPEMATE_SENTRY_DSN=...`), telemetry is unavailable: the
/// Settings toggle hides and reports go nowhere.
class TelemetryController extends ChangeNotifier implements TelemetrySink {
  TelemetryController({
    this.store = const NoopTelemetrySettingsStore(),
    this.dsn = '',
    TelemetrySink? telemetrySink,
    TelemetryStarter? startTelemetry,
    TelemetryStopper? stopTelemetry,
  }) : _sink = telemetrySink,
       _starter = startTelemetry,
       _stopper = stopTelemetry;

  final TelemetrySettingsStore store;
  final String dsn;
  final TelemetrySink? _sink;
  final TelemetryStarter? _starter;
  final TelemetryStopper? _stopper;

  bool _enabled = true;
  bool _running = false;

  bool get isAvailable => dsn.isNotEmpty && _sink != null && _starter != null;
  bool get enabled => _enabled;

  Future<void> load() async {
    try {
      _enabled = (await store.load()).errorReportingEnabled;
    } catch (_) {
      // An unreadable settings file keeps the default.
    }
    notifyListeners();
    await _applyEnabledState();
  }

  Future<void> setEnabled(bool enabled) async {
    if (_enabled == enabled) {
      return;
    }
    _enabled = enabled;
    notifyListeners();
    try {
      await store.save(
        TelemetrySettingsSnapshot(errorReportingEnabled: enabled),
      );
    } catch (_) {
      // Consent still applies for this run even if it could not persist.
    }
    await _applyEnabledState();
  }

  Future<void> _applyEnabledState() async {
    final starter = _starter;
    if (!isAvailable || starter == null) {
      return;
    }
    if (_enabled && !_running) {
      try {
        await starter();
        _running = true;
      } catch (_) {
        // A failed telemetry start must never affect the app.
      }
    } else if (!_enabled && _running) {
      _running = false;
      try {
        await _stopper?.call();
      } catch (_) {
        // Ditto for shutdown.
      }
    }
  }

  @override
  void reportFailure(String area, String kind, String message) {
    if (!_enabled || !_running) {
      return;
    }
    try {
      _sink?.reportFailure(area, kind, message);
    } catch (_) {
      // Telemetry must never break the flow it observes.
    }
  }
}
