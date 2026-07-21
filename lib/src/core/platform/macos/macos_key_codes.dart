/// Maps Windows virtual-key codes (the app's canonical shortcut encoding)
/// to macOS virtual key codes (`kVK_*`). Modifiers map to both their left
/// and right variants, matching GetAsyncKeyState's combined semantics on
/// Windows. The Win key maps to Command, Alt to Option.
List<int> macKeyCodesForVirtualKey(int virtualKey) {
  const shift = [0x38, 0x3C];
  const control = [0x3B, 0x3E];
  const option = [0x3A, 0x3D];
  const command = [0x37, 0x36];

  switch (virtualKey) {
    case 0x10:
      return shift;
    case 0x11:
      return control;
    case 0x12:
      return option;
    case 0x5B:
    case 0x5C:
      return command;
    case 0x20:
      return const [0x31]; // space
    case 0x0D:
      return const [0x24]; // return
    case 0x09:
      return const [0x30]; // tab
    case 0x1B:
      return const [0x35]; // escape
  }
  // F1..F20; F21-F24 have no macOS key codes.
  const functionKeyCodes = [
    0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, //
    0x67, 0x6F, 0x69, 0x6B, 0x71, 0x6A, 0x40, 0x4F, 0x50, 0x5A,
  ];
  if (virtualKey >= 0x70 && virtualKey < 0x70 + functionKeyCodes.length) {
    return [functionKeyCodes[virtualKey - 0x70]];
  }
  // 0-9 (kVK_ANSI_0..9 are not contiguous).
  const digitKeyCodes = [
    0x1D, 0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19, //
  ];
  if (virtualKey >= 0x30 && virtualKey <= 0x39) {
    return [digitKeyCodes[virtualKey - 0x30]];
  }
  // A-Z (kVK_ANSI_A..Z follow the ANSI layout, not alphabetical order).
  const letterKeyCodes = [
    0x00, 0x0B, 0x08, 0x02, 0x0E, 0x03, 0x05, 0x04, 0x22, 0x26, //
    0x28, 0x25, 0x2E, 0x2D, 0x1F, 0x23, 0x0C, 0x0F, 0x01, 0x11,
    0x20, 0x09, 0x0D, 0x07, 0x10, 0x06,
  ];
  if (virtualKey >= 0x41 && virtualKey <= 0x5A) {
    return [letterKeyCodes[virtualKey - 0x41]];
  }
  return const [];
}
