import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Tracks whether the floating-mic accessibility service is on, and opens
/// the settings where the user turns it on (no app can flip it in code).
class FloatingMicController extends ChangeNotifier {
  FloatingMicController({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('typemate/floating_mic');

  final MethodChannel _channel;

  bool _isEnabled = false;

  bool get isEnabled => _isEnabled;

  bool get isSupported => Platform.isAndroid;

  /// Call on start and on app resume — the user toggles it in settings.
  Future<void> refresh() async {
    if (!isSupported) {
      return;
    }
    bool enabled;
    try {
      enabled = await _channel.invokeMethod<bool>('isEnabled') ?? false;
    } on PlatformException {
      enabled = false;
    } on MissingPluginException {
      enabled = false;
    }
    if (enabled != _isEnabled) {
      _isEnabled = enabled;
      notifyListeners();
    }
  }

  Future<void> openSettings() async {
    if (!isSupported) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('openSettings');
    } on PlatformException {
      // Best effort; the card stays for another try.
    } on MissingPluginException {
      // No channel (tests).
    }
  }
}
