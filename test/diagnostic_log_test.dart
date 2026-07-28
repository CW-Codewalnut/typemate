import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/diagnostics/diagnostic_log.dart';
import 'package:typemate/src/core/diagnostics/diagnostic_reporter.dart';

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('typemate-log');
  });

  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  group('DiagnosticLog', () {
    test('appends timestamped, area-tagged entries', () {
      final file = File('${temp.path}/logs/typemate.log');
      final log = DiagnosticLog(
        file: file,
        clock: () => DateTime(2026, 7, 28, 16, 14, 3),
      );

      log.log('app', 'starting');
      log.log('dictation', 'transcribe-timeout: took 20s');

      final lines = file.readAsLinesSync();
      expect(lines, hasLength(2));
      expect(lines[0], '2026-07-28T16:14:03.000 [app] starting');
      expect(
        lines[1],
        '2026-07-28T16:14:03.000 [dictation] transcribe-timeout: took 20s',
      );
    });

    test('indents continuation lines so stderr tails stay attached', () {
      final file = File('${temp.path}/typemate.log');
      final log = DiagnosticLog(file: file);

      log.log('stt', 'server failed; stderr tail:\nline one\r\nline two\n');

      final content = file.readAsStringSync();
      expect(content, contains('server failed; stderr tail:\n'));
      expect(content, contains('\n    line one\n'));
      expect(content, contains('\n    line two\n'));
    });

    test('rotates to a .1 file instead of growing forever', () {
      final file = File('${temp.path}/typemate.log');
      final log = DiagnosticLog(file: file, maxSizeBytes: 10);

      log.log('app', 'first entry, longer than ten bytes');
      log.log('app', 'second entry');

      final rotated = File('${file.path}.1');
      expect(rotated.existsSync(), isTrue);
      expect(rotated.readAsStringSync(), contains('first entry'));
      expect(file.readAsStringSync(), contains('second entry'));
      expect(file.readAsStringSync(), isNot(contains('first entry')));
    });

    test('a disabled log writes nothing and exposes no directory', () {
      const log = DiagnosticLog.disabled();

      log.log('app', 'goes nowhere');

      expect(log.isEnabled, isFalse);
      expect(log.directoryPath, isNull);
    });

    test('swallows write failures instead of breaking the caller', () {
      // The "parent directory" is a file, so every write must fail.
      final blocker = File('${temp.path}/blocker')..writeAsStringSync('x');
      final log = DiagnosticLog(file: File('${blocker.path}/typemate.log'));

      expect(() => log.log('app', 'never lands'), returnsNormally);
    });
  });

  group('DiagnosticTailBuffer', () {
    test('keeps only the last maxLength characters', () {
      final buffer = DiagnosticTailBuffer(maxLength: 8);

      buffer.add('abcdefgh');
      buffer.add('ijkl');

      expect(buffer.tail, 'efghijkl');
    });

    test('reports emptiness after whitespace-only input', () {
      final buffer = DiagnosticTailBuffer();

      buffer.add('  \n ');

      expect(buffer.isEmpty, isTrue);
    });
  });

  group('DiagnosticReporter', () {
    test('info goes only to the local log, failures also to telemetry', () {
      final file = File('${temp.path}/typemate.log');
      final sink = _RecordingSink();
      final reporter = DiagnosticReporter(
        log: DiagnosticLog(file: file),
        telemetrySink: sink,
      );

      reporter.info('app', 'startup detail');
      reporter.failure('stt', 'server-start-timeout', 'no connection in 60s');

      final content = file.readAsStringSync();
      expect(content, contains('[app] startup detail'));
      expect(content, contains('[stt] server-start-timeout: no connection'));
      expect(sink.calls, [
        ('stt', 'server-start-timeout', 'no connection in 60s'),
      ]);
    });

    test('a throwing telemetry sink never breaks the caller', () {
      final reporter = DiagnosticReporter(telemetrySink: _ThrowingSink());

      expect(() => reporter.failure('a', 'b', 'c'), returnsNormally);
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

class _ThrowingSink implements TelemetrySink {
  @override
  void reportFailure(String area, String kind, String message) {
    throw StateError('sink offline');
  }
}
