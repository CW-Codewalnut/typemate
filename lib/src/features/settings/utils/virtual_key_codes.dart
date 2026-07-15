import 'package:flutter/services.dart';

int? virtualKeyCodeForLogicalKey(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.control ||
      key == LogicalKeyboardKey.controlLeft ||
      key == LogicalKeyboardKey.controlRight) {
    return 0x11;
  }
  if (key == LogicalKeyboardKey.shift ||
      key == LogicalKeyboardKey.shiftLeft ||
      key == LogicalKeyboardKey.shiftRight) {
    return 0x10;
  }
  if (key == LogicalKeyboardKey.alt ||
      key == LogicalKeyboardKey.altLeft ||
      key == LogicalKeyboardKey.altRight) {
    return 0x12;
  }
  if (key == LogicalKeyboardKey.meta ||
      key == LogicalKeyboardKey.metaLeft ||
      key == LogicalKeyboardKey.metaRight) {
    return 0x5B;
  }
  if (key == LogicalKeyboardKey.space) return 0x20;
  if (key == LogicalKeyboardKey.enter) return 0x0D;
  if (key == LogicalKeyboardKey.tab) return 0x09;
  if (key == LogicalKeyboardKey.escape) return 0x1B;
  if (key == LogicalKeyboardKey.backspace) return 0x08;
  if (key == LogicalKeyboardKey.delete) return 0x2E;
  if (key == LogicalKeyboardKey.arrowLeft) return 0x25;
  if (key == LogicalKeyboardKey.arrowUp) return 0x26;
  if (key == LogicalKeyboardKey.arrowRight) return 0x27;
  if (key == LogicalKeyboardKey.arrowDown) return 0x28;

  final keyLabel = key.keyLabel.toUpperCase();
  if (keyLabel.length == 1) {
    final codeUnit = keyLabel.codeUnitAt(0);
    if ((codeUnit >= 0x30 && codeUnit <= 0x39) ||
        (codeUnit >= 0x41 && codeUnit <= 0x5A)) {
      return codeUnit;
    }
  }

  if (key == LogicalKeyboardKey.f1) return 0x70;
  if (key == LogicalKeyboardKey.f2) return 0x71;
  if (key == LogicalKeyboardKey.f3) return 0x72;
  if (key == LogicalKeyboardKey.f4) return 0x73;
  if (key == LogicalKeyboardKey.f5) return 0x74;
  if (key == LogicalKeyboardKey.f6) return 0x75;
  if (key == LogicalKeyboardKey.f7) return 0x76;
  if (key == LogicalKeyboardKey.f8) return 0x77;
  if (key == LogicalKeyboardKey.f9) return 0x78;
  if (key == LogicalKeyboardKey.f10) return 0x79;
  if (key == LogicalKeyboardKey.f11) return 0x7A;
  if (key == LogicalKeyboardKey.f12) return 0x7B;
  return null;
}
