import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/diagnostics/diagnostic_reporter.dart';
import 'package:typemate/src/core/diagnostics/telemetry_controller.dart';

void main() {
  group('TelemetryController', () {
    test('is unavailable without a DSN and forwards nothing', () async {
      final sink = _RecordingSink();
      var started = 0;
      final controller = TelemetryController(
        telemetrySink: sink,
        startTelemetry: () async => started++,
      );

      await controller.load();
      controller.reportFailure('stt', 'kind', 'message');

      expect(controller.isAvailable, isFalse);
      expect(started, 0);
      expect(sink.calls, isEmpty);
    });

    test('starts on load and forwards reports when enabled', () async {
      final sink = _RecordingSink();
      var started = 0;
      final controller = TelemetryController(
        dsn: 'https://x@example.ingest.sentry.io/1',
        telemetrySink: sink,
        startTelemetry: () async => started++,
      );

      await controller.load();
      controller.reportFailure('stt', 'kind', 'message');

      expect(controller.enabled, isTrue);
      expect(started, 1);
      expect(sink.calls, [('stt', 'kind', 'message')]);
    });

    test('respects a persisted opt-out: no start, no forwarding', () async {
      final sink = _RecordingSink();
      var started = 0;
      final controller = TelemetryController(
        store: _MemoryStore(
          const TelemetrySettingsSnapshot(errorReportingEnabled: false),
        ),
        dsn: 'https://x@example.ingest.sentry.io/1',
        telemetrySink: sink,
        startTelemetry: () async => started++,
      );

      await controller.load();
      controller.reportFailure('stt', 'kind', 'message');

      expect(controller.enabled, isFalse);
      expect(started, 0);
      expect(sink.calls, isEmpty);
    });

    test('the toggle stops, persists, and restarts reporting', () async {
      final sink = _RecordingSink();
      final store = _MemoryStore(const TelemetrySettingsSnapshot());
      var started = 0;
      var stopped = 0;
      final controller = TelemetryController(
        store: store,
        dsn: 'https://x@example.ingest.sentry.io/1',
        telemetrySink: sink,
        startTelemetry: () async => started++,
        stopTelemetry: () async => stopped++,
      );
      await controller.load();

      await controller.setEnabled(false);
      controller.reportFailure('stt', 'kind', 'dropped');

      expect(stopped, 1);
      expect(store.saved?.errorReportingEnabled, isFalse);
      expect(sink.calls, isEmpty);

      await controller.setEnabled(true);
      controller.reportFailure('stt', 'kind', 'forwarded');

      expect(started, 2);
      expect(store.saved?.errorReportingEnabled, isTrue);
      expect(sink.calls, [('stt', 'kind', 'forwarded')]);
    });

    test('opting out while a start is in flight still stops the '
        'backend', () async {
      final startGate = Completer<void>();
      var started = 0;
      var stopped = 0;
      final controller = TelemetryController(
        dsn: 'https://x@example.ingest.sentry.io/1',
        telemetrySink: _RecordingSink(),
        startTelemetry: () {
          started++;
          return startGate.future;
        },
        stopTelemetry: () async => stopped++,
      );

      final loading = controller.load();
      // Let load() get past the store read and into the pending start.
      await Future<void>.delayed(Duration.zero);
      expect(started, 1);

      final disabling = controller.setEnabled(false);
      startGate.complete();
      await loading;
      await disabling;

      expect(stopped, 1);
    });

    test('a failing telemetry start leaves the app unaffected', () async {
      final controller = TelemetryController(
        dsn: 'https://x@example.ingest.sentry.io/1',
        telemetrySink: _RecordingSink(),
        startTelemetry: () async => throw StateError('offline'),
      );

      await expectLater(controller.load(), completes);
      expect(() => controller.reportFailure('a', 'b', 'c'), returnsNormally);
    });
  });

  group('FileTelemetrySettingsStore', () {
    late Directory temp;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('typemate-telemetry');
    });

    tearDown(() {
      temp.deleteSync(recursive: true);
    });

    test('defaults to enabled when no file exists', () async {
      final store = FileTelemetrySettingsStore(
        file: File('${temp.path}/telemetry-settings.json'),
      );

      final snapshot = await store.load();

      expect(snapshot.errorReportingEnabled, isTrue);
    });

    test('round-trips the opt-out', () async {
      final file = File('${temp.path}/telemetry-settings.json');
      final store = FileTelemetrySettingsStore(file: file);

      await store.save(
        const TelemetrySettingsSnapshot(errorReportingEnabled: false),
      );

      expect((await store.load()).errorReportingEnabled, isFalse);
    });

    test('a settings file without the key reads as the on default', () async {
      final file = File('${temp.path}/telemetry-settings.json')
        ..writeAsStringSync('{"someOtherKey": 1}');
      final store = FileTelemetrySettingsStore(file: file);

      expect((await store.load()).errorReportingEnabled, isTrue);
    });
  });
}

class _RecordingSink implements TelemetrySink {
  final calls = <(String, String, String)>[];

  @override
  void reportFailure(String area, String kind, String message) {
    calls.add((area, kind, message));
  }
}

class _MemoryStore implements TelemetrySettingsStore {
  _MemoryStore(this._initial);

  final TelemetrySettingsSnapshot _initial;
  TelemetrySettingsSnapshot? saved;

  @override
  Future<TelemetrySettingsSnapshot> load() async => saved ?? _initial;

  @override
  Future<void> save(TelemetrySettingsSnapshot snapshot) async =>
      saved = snapshot;
}
