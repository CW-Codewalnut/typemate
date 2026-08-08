import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/painting.dart';
import 'package:typemate/src/core/dictation_controller.dart';
import 'package:typemate/src/core/platform/overlay/overlay_window.dart';
import 'package:typemate/src/core/platform/overlay/overlay_window_driver.dart';

class _FakeDriver extends OverlayWindowDriver {
  _FakeDriver({this.visibleAtLaunch = false, this.adoptFailures = 0});

  final bool visibleAtLaunch;

  /// How many adopt attempts fail before one succeeds.
  int adoptFailures;
  final List<String> calls = [];

  @override
  bool get needsVisibleAtLaunch => visibleAtLaunch;

  @override
  void snapshotBefore() => calls.add('snapshot');

  @override
  bool adoptNewWindow() {
    calls.add('adopt');
    if (adoptFailures > 0) {
      adoptFailures--;
      return false;
    }
    return true;
  }

  @override
  bool show({required int width, required int height}) {
    calls.add('show:${width}x$height');
    return true;
  }

  @override
  void hide() => calls.add('hide');

  @override
  String focusEvidence() => 'fake';

  @override
  bool get overlayStoleFocus => false;
}

class _FakeHandle implements OverlayWindowHandle {
  _FakeHandle({this.failInvocations = false, this.alive = true});

  final List<(String, Object?)> invocations = [];

  /// Simulates the overlay engine not answering: either it has not
  /// registered its handler yet (transient) or the window is gone (fatal).
  final bool failInvocations;
  bool alive;
  int aliveChecks = 0;

  @override
  Future<void> invokeMethod(String method, [dynamic arguments]) async {
    invocations.add((method, arguments));
    if (failInvocations) {
      throw StateError('overlay engine not listening');
    }
  }

  @override
  Future<bool> isAlive() async {
    aliveChecks += 1;
    return alive;
  }
}

void main() {
  (OverlayWindow, _FakeDriver, _FakeHandle, List<String>) build({
    bool visibleAtLaunch = false,
    int adoptFailures = 0,
    Duration autoHide = const Duration(milliseconds: 4500),
  }) {
    final driver = _FakeDriver(
      visibleAtLaunch: visibleAtLaunch,
      adoptFailures: adoptFailures,
    );
    final handle = _FakeHandle();
    final creations = <String>[];
    final overlay = OverlayWindow(
      driver: driver,
      textPillAutoHideAfter: autoHide,
      createWindow:
          ({required bool hiddenAtLaunch, required String arguments}) async {
            creations.add('hidden=$hiddenAtLaunch args=$arguments');
            return handle;
          },
    );
    return (overlay, driver, handle, creations);
  }

  Map<String, dynamic> payload(_FakeHandle handle, int index) =>
      json.decode(handle.invocations[index].$2! as String)
          as Map<String, dynamic>;

  test('creates the window once and reuses it across shows', () async {
    final (overlay, driver, handle, creations) = build();

    await overlay.showWorking('TypeMate is listening...');
    await overlay.showError('Something went wrong.');

    expect(creations, hasLength(1), reason: 'one window for the app life');
    expect(creations.single, startsWith('hidden=true'));
    expect(driver.calls.where((call) => call == 'snapshot'), hasLength(1));
    expect(driver.calls.where((call) => call == 'adopt'), hasLength(1));
  });

  test('the first show rides the creation arguments', () async {
    final (overlay, _, _, creations) = build();

    await overlay.showInfo('Please download the speech model first.');

    // Even if the sub-engine misses the first setState, its creation
    // args already carry the right pill.
    expect(creations.single, contains('"variant":"info"'));
    expect(
      creations.single,
      contains('Please download the speech model first.'),
    );
  });

  test('a driver that needs a visible launch gets one', () async {
    final (overlay, _, _, creations) = build(visibleAtLaunch: true);

    await overlay.showWorking('TypeMate is listening...');

    expect(creations.single, startsWith('hidden=false'));
  });

  test('adoption retries until the native window exists', () async {
    final (overlay, driver, _, _) = build(adoptFailures: 3);

    await overlay.showWorking('TypeMate is listening...');

    expect(driver.calls.where((call) => call == 'adopt'), hasLength(4));
    expect(driver.calls.last, startsWith('show:'));
  });

  test('variants carry the caller message and size their pill', () async {
    final (overlay, driver, handle, _) = build();

    await overlay.showWorking('Transcribing locally...');
    await overlay.showInfo('Please download the speech model first.');
    await overlay.showError("Couldn't capture your voice.");

    expect(payload(handle, 0), {
      'variant': 'working',
      'message': 'Transcribing locally...',
      'hidden': false,
    });
    expect(payload(handle, 1)['variant'], 'info');
    expect(payload(handle, 2)['variant'], 'error');
    // The bars pill is the native 210x58; text pills are the wide pill,
    // sized to their own message rather than a fixed height — a short one
    // must not reserve room for four lines.
    const info = 'Please download the speech model first.';
    const error = "Couldn't capture your voice.";
    expect(driver.calls.where((call) => call.startsWith('show:')), [
      'show:210x58',
      'show:360x${OverlayWindow.textPillHeightFor(info)}',
      'show:360x${OverlayWindow.textPillHeightFor(error)}',
    ]);
  });

  test('hide pauses the pill before hiding the native window', () async {
    final (overlay, driver, handle, _) = build();

    await overlay.showWorking('TypeMate is listening...');
    await overlay.hide();

    expect(payload(handle, 1), {'hidden': true});
    expect(driver.calls.last, 'hide');
  });

  test('info and error pills auto-hide; working never does', () {
    fakeAsync((async) {
      final (overlay, driver, _, _) = build(
        autoHide: const Duration(milliseconds: 4500),
      );

      overlay.showError('Something went wrong.');
      async.flushMicrotasks();
      expect(driver.calls, isNot(contains('hide')));

      async.elapse(const Duration(milliseconds: 4600));
      expect(
        driver.calls,
        contains('hide'),
        reason: 'the native overlays all auto-hid their toasts at 4.5s',
      );

      driver.calls.clear();
      overlay.showWorking('TypeMate is listening...');
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 30));
      expect(
        driver.calls,
        isNot(contains('hide')),
        reason: 'the working pill lives for the whole dictation',
      );
    });
  });

  test('a new show cancels the pending auto-hide', () {
    fakeAsync((async) {
      final (overlay, driver, _, _) = build();

      overlay.showError('Something went wrong.');
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 3000));
      overlay.showWorking('TypeMate is listening...');
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 3000));

      expect(
        driver.calls,
        isNot(contains('hide')),
        reason: 'the working pill must not be killed by a stale timer',
      );
    });
  });

  test('preload creates the window off the dictation path', () async {
    final (overlay, driver, _, creations) = build();

    overlay.preload();
    await Future<void>.delayed(Duration.zero);

    expect(creations, hasLength(1));
    expect(driver.calls, isNot(contains(startsWith('show:'))));

    // The first dictation reuses the preloaded window instantly.
    await overlay.showWorking('TypeMate is listening...');
    expect(creations, hasLength(1));
  });

  test(
    'a failed window creation never reaches the caller and retries',
    () async {
      final driver = _FakeDriver();
      final handle = _FakeHandle();
      var attempts = 0;
      final overlay = OverlayWindow(
        driver: driver,
        createWindow:
            ({required bool hiddenAtLaunch, required String arguments}) async {
              attempts++;
              if (attempts == 1) {
                throw StateError('channel not ready');
              }
              return handle;
            },
      );

      // The first show swallows the failure - dictation must proceed.
      await overlay.showWorking('TypeMate is listening...');
      expect(attempts, 1);
      expect(driver.calls, isNot(contains(startsWith('show:'))));

      // The failure is not memoized: the next show retries and succeeds.
      await overlay.showWorking('TypeMate is listening...');
      expect(attempts, 2);
      expect(driver.calls, contains('show:210x58'));
    },
  );

  test(
    'a platform without a driver stays silent instead of throwing',
    () async {
      var created = 0;
      final overlay = OverlayWindow(
        driver: null,
        createWindow:
            ({required bool hiddenAtLaunch, required String arguments}) async {
              created++;
              return _FakeHandle();
            },
      );

      // Explicit null driver models an unsupported platform.
      expect(overlay.isAvailable, isFalse);
      overlay.preload();
      await overlay.showWorking('TypeMate is listening...');
      await overlay.hide();
      expect(created, 0);
    },
  );

  test('the text pill window fits the longest real failure messages', () {
    // These two used to measure 92.0 against a hard-coded 92 window: four
    // lines plus padding, exactly full, nothing to spare. One more line of
    // copy, a longer translation, or a larger text scale would overflow
    // and render as a pill filling the window — the very look the capsule
    // fix removed.
    const longest = [
      DictationController.insertionFailedMessage,
      DictationController.failedToStartRecordingMessage,
      DictationController.failedToFinishRecordingMessage,
      DictationController.transcriptionFailedMessage,
      DictationController.transcriptionTimeoutMessage,
    ];

    for (final message in longest) {
      final height = OverlayWindow.textPillHeightFor(message);
      final painter = TextPainter(
        text: TextSpan(text: message, style: const TextStyle(fontSize: 12.5)),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 304);

      expect(
        height,
        greaterThan(painter.height + 20),
        reason: 'no headroom for: $message',
      );
      painter.dispose();
    }
  });

  test('the text pill window grows with the message', () {
    final short = OverlayWindow.textPillHeightFor('Short.');
    final long = OverlayWindow.textPillHeightFor(
      DictationController.insertionFailedMessage,
    );

    expect(short, lessThan(long));
    // A one-liner must not render as a slab, which is what a fixed height
    // would do on Linux where the window itself is the capsule.
    expect(short, lessThan(60));
  });

  test('a not-listening engine does not orphan a live window', () async {
    // desktop_multi_window cannot close a window, so rebuilding on a
    // transient channel error would strand the old window and its engine
    // forever. The rebuild is gated on the window actually being gone.
    final driver = _FakeDriver();
    final handle = _FakeHandle(failInvocations: true, alive: true);
    var creations = 0;
    final overlay = OverlayWindow(
      driver: driver,
      createWindow: ({required hiddenAtLaunch, required arguments}) async {
        creations += 1;
        return handle;
      },
    );

    await overlay.showInfo('first');
    await overlay.showInfo('second');

    expect(handle.aliveChecks, 2, reason: 'each failure must be classified');
    expect(creations, 1, reason: 'a live window must be reused, not orphaned');
  });

  test('a dead window is rebuilt on the next show', () async {
    final driver = _FakeDriver();
    final handle = _FakeHandle(failInvocations: true, alive: false);
    var creations = 0;
    final overlay = OverlayWindow(
      driver: driver,
      createWindow: ({required hiddenAtLaunch, required arguments}) async {
        creations += 1;
        return handle;
      },
    );

    await overlay.showInfo('first');
    await overlay.showInfo('second');

    expect(creations, 2, reason: 'a window confirmed gone must be rebuilt');
  });
}
