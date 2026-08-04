import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/platform/overlay/overlay_window.dart';
import 'package:typemate/src/core/platform/overlay/overlay_window_driver.dart';

class _FakeDriver extends OverlayWindowDriver {
  _FakeDriver({this.visibleAtLaunch = false});

  final bool visibleAtLaunch;
  final List<String> calls = [];

  @override
  bool get needsVisibleAtLaunch => visibleAtLaunch;

  @override
  void snapshotBefore() => calls.add('snapshot');

  @override
  bool adoptNewWindow() {
    calls.add('adopt');
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
  final List<(String, Object?)> invocations = [];

  @override
  Future<void> invokeMethod(String method, [dynamic arguments]) async {
    invocations.add((method, arguments));
  }
}

void main() {
  (OverlayWindow, _FakeDriver, _FakeHandle, List<bool>) build({
    bool visibleAtLaunch = false,
  }) {
    final driver = _FakeDriver(visibleAtLaunch: visibleAtLaunch);
    final handle = _FakeHandle();
    final hiddenFlags = <bool>[];
    final overlay = OverlayWindow(
      driver: driver,
      createWindow: ({required bool hiddenAtLaunch}) async {
        hiddenFlags.add(hiddenAtLaunch);
        return handle;
      },
    );
    return (overlay, driver, handle, hiddenFlags);
  }

  test('creates the window once and reuses it across shows', () async {
    final (overlay, driver, handle, hiddenFlags) = build();

    await overlay.showWorking('TypeMate is listening...');
    await overlay.showError('Something went wrong.');

    expect(hiddenFlags, [true], reason: 'one window, hidden at launch');
    expect(driver.calls.where((call) => call == 'snapshot'), hasLength(1));
    expect(driver.calls.where((call) => call == 'adopt'), hasLength(1));
    expect(handle.invocations, hasLength(2));
  });

  test('a driver that needs a visible launch gets one', () async {
    final (overlay, _, _, hiddenFlags) = build(visibleAtLaunch: true);

    await overlay.showWorking('TypeMate is listening...');

    expect(hiddenFlags, [false]);
  });

  test('variants carry the caller message and size their pill', () async {
    final (overlay, driver, handle, _) = build();

    await overlay.showWorking('Transcribing locally...');
    await overlay.showInfo('Please download the speech model first.');
    await overlay.showError("Couldn't capture your voice.");
    await overlay.hide();

    Map<String, dynamic> payload(int index) =>
        json.decode(handle.invocations[index].$2! as String)
            as Map<String, dynamic>;
    expect(payload(0), {
      'variant': 'working',
      'message': 'Transcribing locally...',
    });
    expect(payload(1), {
      'variant': 'info',
      'message': 'Please download the speech model first.',
    });
    expect(payload(2), {
      'variant': 'error',
      'message': "Couldn't capture your voice.",
    });
    // The bars pill is the native 210x58; text pills get the wide pill.
    expect(driver.calls.where((call) => call.startsWith('show:')), [
      'show:210x58',
      'show:360x92',
      'show:360x92',
    ]);
    expect(driver.calls.last, 'hide');
  });

  test(
    'a platform without a driver stays silent instead of throwing',
    () async {
      var created = 0;
      final overlay = OverlayWindow(
        driver: null,
        createWindow: ({required bool hiddenAtLaunch}) async {
          created++;
          return _FakeHandle();
        },
      );

      // Explicit null driver models an unsupported platform.
      expect(overlay.isAvailable, isFalse);
      await overlay.showWorking('TypeMate is listening...');
      await overlay.hide();
      expect(created, 0);
    },
  );
}
