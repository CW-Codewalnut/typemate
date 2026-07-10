import 'package:flutter/foundation.dart';

import '../audio/ffmpeg_microphone_discovery.dart';

class MicrophoneSettingsController extends ChangeNotifier {
  MicrophoneSettingsController({required this.discovery});

  final MicrophoneDiscovery discovery;

  List<MicrophoneDevice> _microphones = const [];
  MicrophoneDevice? _selectedMicrophone;
  bool _isLoading = false;
  String _statusMessage = 'Microphones not scanned yet.';

  List<MicrophoneDevice> get microphones => List.unmodifiable(_microphones);
  MicrophoneDevice? get selectedMicrophone => _selectedMicrophone;
  bool get isLoading => _isLoading;
  String get statusMessage => _statusMessage;

  Future<void> loadMicrophones() async {
    _isLoading = true;
    _statusMessage = 'Scanning microphones...';
    notifyListeners();

    try {
      final discovered = await discovery.listMicrophones();
      _microphones = discovered;
      _selectedMicrophone = _selectDefault(discovered);
      _statusMessage = switch (discovered.length) {
        0 => 'No microphones found.',
        1 => '1 microphone found.',
        final count => '$count microphones found.',
      };
    } catch (error) {
      _microphones = const [];
      _selectedMicrophone = null;
      _statusMessage = 'Unable to scan microphones.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void selectMicrophone(MicrophoneDevice microphone) {
    if (!_microphones.contains(microphone)) {
      return;
    }

    _selectedMicrophone = microphone;
    _statusMessage = 'Selected ${microphone.name}.';
    notifyListeners();
  }

  MicrophoneDevice? _selectDefault(List<MicrophoneDevice> discovered) {
    if (discovered.isEmpty) {
      return null;
    }

    final current = _selectedMicrophone;
    if (current != null && discovered.contains(current)) {
      return current;
    }

    return discovered.first;
  }
}
