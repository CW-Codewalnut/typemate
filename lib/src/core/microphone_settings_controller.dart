import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/audio/microphone_discovery.dart';
import 'microphone_settings_store.dart';

class MicrophoneSettingsController extends ChangeNotifier {
  MicrophoneSettingsController({
    required this.discovery,
    this.store = const NoopMicrophoneSettingsStore(),
  });

  final MicrophoneDiscovery discovery;
  final MicrophoneSettingsStore store;

  List<MicrophoneDevice> _microphones = const [];
  MicrophoneDevice? _selectedMicrophone;
  bool _isLoading = false;
  bool _hasError = false;
  String _statusMessage = 'Microphones not scanned yet.';
  Timer? _watchTimer;

  List<MicrophoneDevice> get microphones => List.unmodifiable(_microphones);
  MicrophoneDevice? get selectedMicrophone => _selectedMicrophone;
  bool get isLoading => _isLoading;
  bool get hasError => _hasError;
  String get statusMessage => _statusMessage;

  Future<void> loadMicrophones() async {
    _isLoading = true;
    _hasError = false;
    _statusMessage = 'Scanning microphones...';
    notifyListeners();

    try {
      final persistedName = await store.loadSelectedMicrophoneName();
      final discovered = await discovery.listMicrophones();
      _microphones = discovered;
      _selectedMicrophone = _selectDefault(
        discovered,
        preferredName: persistedName,
      );
      _hasError = false;
      _statusMessage = _statusForCount(discovered.length);
    } catch (error) {
      _microphones = const [];
      _selectedMicrophone = null;
      _hasError = true;
      _statusMessage =
          'Unable to scan microphones. Check the microphone and its permissions, then reopen Settings.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Re-scans on an interval while the microphone panel is visible so a
  /// device plugged in or removed shows up without reopening the app. The
  /// panel starts this on mount and stops it on dispose.
  void startWatchingDevices({Duration interval = const Duration(seconds: 2)}) {
    _watchTimer ??= Timer.periodic(interval, (_) => refreshDeviceList());
  }

  void stopWatchingDevices() {
    _watchTimer?.cancel();
    _watchTimer = null;
  }

  @override
  void dispose() {
    stopWatchingDevices();
    super.dispose();
  }

  /// One silent re-scan: updates state only when the device list actually
  /// changed, and never lets a transient scan failure wipe a working list.
  Future<void> refreshDeviceList() async {
    if (_isLoading) {
      return;
    }
    final List<MicrophoneDevice> discovered;
    try {
      discovered = await discovery.listMicrophones();
    } catch (_) {
      return;
    }
    if (listEquals(discovered, _microphones)) {
      return;
    }
    _microphones = discovered;
    _selectedMicrophone = _selectDefault(
      discovered,
      preferredName: _selectedMicrophone?.name,
    );
    _hasError = false;
    _statusMessage = _statusForCount(discovered.length);
    notifyListeners();
  }

  void selectMicrophone(MicrophoneDevice microphone) {
    if (!_microphones.contains(microphone)) {
      return;
    }

    _selectedMicrophone = microphone;
    _hasError = false;
    _statusMessage = 'Selected ${microphone.name}.';
    unawaited(store.saveSelectedMicrophoneName(microphone.name));
    notifyListeners();
  }

  static String _statusForCount(int count) => switch (count) {
    0 => 'No microphones found.',
    1 => '1 microphone found.',
    _ => '$count microphones found.',
  };

  MicrophoneDevice? _selectDefault(
    List<MicrophoneDevice> discovered, {
    String? preferredName,
  }) {
    if (discovered.isEmpty) {
      return null;
    }

    final preferred = preferredName?.trim();
    if (preferred != null && preferred.isNotEmpty) {
      for (final microphone in discovered) {
        if (microphone.name == preferred) {
          return microphone;
        }
      }
    }

    final current = _selectedMicrophone;
    if (current != null && discovered.contains(current)) {
      return current;
    }

    return discovered.first;
  }
}
