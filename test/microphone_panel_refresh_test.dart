import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typemate/src/core/audio/microphone_discovery.dart';
import 'package:typemate/src/core/microphone_settings_controller.dart';
import 'package:typemate/src/features/settings/components/microphone_selection_panel.dart';

class _MutableDiscovery implements MicrophoneDiscovery {
  _MutableDiscovery(this.devices);

  List<MicrophoneDevice> devices;

  @override
  Future<List<MicrophoneDevice>> listMicrophones() async => devices;
}

const _brio = MicrophoneDevice(name: 'Microphone (Brio 100)');
const _headset = MicrophoneDevice(name: 'Headset (Tribit XSound Go)');

void main() {
  Future<MicrophoneSettingsController> pumpPanel(
    WidgetTester tester,
    _MutableDiscovery discovery,
  ) async {
    final controller = MicrophoneSettingsController(discovery: discovery);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MicrophoneSelectionPanel(controller: controller)),
      ),
    );
    await controller.loadMicrophones();
    await tester.pump();
    return controller;
  }

  testWidgets('the dropdown picks up a device plugged in while settings '
      'is open', (tester) async {
    final discovery = _MutableDiscovery([_brio]);
    final controller = await pumpPanel(tester, discovery);
    expect(find.text(_brio.name), findsOneWidget);
    expect(find.text(_headset.name), findsNothing);

    discovery.devices = [_brio, _headset];
    // Advance past the watch interval, then flush the async re-scan.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    await tester.tap(find.byType(DropdownButtonFormField<MicrophoneDevice>));
    await tester.pumpAndSettle();
    expect(find.text(_headset.name), findsOneWidget);

    await tester.tap(find.text(_headset.name).last);
    await tester.pumpAndSettle();
    expect(controller.selectedMicrophone, _headset);
  });

  testWidgets('unplugging the selected device updates the closed '
      'dropdown to the fallback', (tester) async {
    final discovery = _MutableDiscovery([_brio, _headset]);
    final controller = await pumpPanel(tester, discovery);
    controller.selectMicrophone(_headset);
    await tester.pump();
    expect(find.text(_headset.name), findsOneWidget);

    discovery.devices = [_brio];
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(find.text(_headset.name), findsNothing);
    expect(find.text(_brio.name), findsOneWidget);
    expect(controller.selectedMicrophone, _brio);
  });

  testWidgets('swapping the controller moves the device watch to the '
      'new one', (tester) async {
    final first = MicrophoneSettingsController(
      discovery: _MutableDiscovery([_brio]),
    );
    final second = MicrophoneSettingsController(
      discovery: _MutableDiscovery([_brio]),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MicrophoneSelectionPanel(controller: first)),
      ),
    );
    expect(first.isWatchingDevices, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MicrophoneSelectionPanel(controller: second)),
      ),
    );

    expect(first.isWatchingDevices, isFalse);
    expect(second.isWatchingDevices, isTrue);
  });

  testWidgets('losing every device swaps the dropdown for the status '
      'message', (tester) async {
    final discovery = _MutableDiscovery([_brio]);
    await pumpPanel(tester, discovery);
    expect(find.text(_brio.name), findsOneWidget);

    discovery.devices = const [];
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(
      find.byType(DropdownButtonFormField<MicrophoneDevice>),
      findsNothing,
    );
    expect(find.text('No microphones found.'), findsOneWidget);
  });
}
