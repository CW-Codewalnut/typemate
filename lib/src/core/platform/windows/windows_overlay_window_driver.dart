// Win32 overlay driver: user32 via FFI from the main engine restyles
// the desktop_multi_window window into a non-activating, click-through,
// topmost, colour-keyed layered popup shown with SW_SHOWNOACTIVATE.
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../overlay/overlay_window_driver.dart';
import '../overlay/overlay_variant.dart';

/// The package's fixed Win32 class for every window it creates.
const _overlayWindowClass = 'FLUTTER_MULTI_WINDOW_WIN32_WINDOW';

typedef _FindWindowC = IntPtr Function(Pointer<Utf16>, Pointer<Utf16>);
typedef _FindWindowD = int Function(Pointer<Utf16>, Pointer<Utf16>);
typedef _GetWindowLongC = IntPtr Function(IntPtr, Int32);
typedef _GetWindowLongD = int Function(int, int);
typedef _SetWindowLongC = IntPtr Function(IntPtr, Int32, IntPtr);
typedef _SetWindowLongD = int Function(int, int, int);
typedef _SetLayeredC = Int32 Function(IntPtr, Uint32, Uint8, Uint32);
typedef _SetLayeredD = int Function(int, int, int, int);
typedef _SetWindowPosC =
    Int32 Function(IntPtr, IntPtr, Int32, Int32, Int32, Int32, Uint32);
typedef _SetWindowPosD = int Function(int, int, int, int, int, int, int);
typedef _ShowWindowC = Int32 Function(IntPtr, Int32);
typedef _ShowWindowD = int Function(int, int);
typedef _GetForegroundC = IntPtr Function();
typedef _GetForegroundD = int Function();
typedef _GetWindowTextC = Int32 Function(IntPtr, Pointer<Utf16>, Int32);
typedef _GetWindowTextD = int Function(int, Pointer<Utf16>, int);
typedef _GetSystemMetricsC = Int32 Function(Int32);
typedef _GetSystemMetricsD = int Function(int);
typedef _GetDpiForWindowC = Uint32 Function(IntPtr);
typedef _GetDpiForWindowD = int Function(int);
typedef _GetWindowThreadProcessIdC = Uint32 Function(IntPtr, Pointer<Uint32>);
typedef _GetWindowThreadProcessIdD = int Function(int, Pointer<Uint32>);
typedef _GetCurrentProcessIdC = Uint32 Function();
typedef _GetCurrentProcessIdD = int Function();

class WindowsOverlayWindowDriver extends OverlayWindowDriver {
  WindowsOverlayWindowDriver()
    : _user32 = DynamicLibrary.open('user32.dll'),
      _kernel32 = DynamicLibrary.open('kernel32.dll');

  final DynamicLibrary _user32;
  final DynamicLibrary _kernel32;

  late final _findWindow = _user32.lookupFunction<_FindWindowC, _FindWindowD>(
    'FindWindowW',
  );
  late final _getWindowLong = _user32
      .lookupFunction<_GetWindowLongC, _GetWindowLongD>('GetWindowLongPtrW');
  late final _setWindowLong = _user32
      .lookupFunction<_SetWindowLongC, _SetWindowLongD>('SetWindowLongPtrW');
  late final _setLayeredWindowAttributes = _user32
      .lookupFunction<_SetLayeredC, _SetLayeredD>('SetLayeredWindowAttributes');
  late final _setWindowPos = _user32
      .lookupFunction<_SetWindowPosC, _SetWindowPosD>('SetWindowPos');
  late final _showWindow = _user32.lookupFunction<_ShowWindowC, _ShowWindowD>(
    'ShowWindow',
  );
  late final _getForegroundWindow = _user32
      .lookupFunction<_GetForegroundC, _GetForegroundD>('GetForegroundWindow');
  late final _getWindowText = _user32
      .lookupFunction<_GetWindowTextC, _GetWindowTextD>('GetWindowTextW');
  late final _getSystemMetrics = _user32
      .lookupFunction<_GetSystemMetricsC, _GetSystemMetricsD>(
        'GetSystemMetrics',
      );
  late final _getDpiForWindow = _user32
      .lookupFunction<_GetDpiForWindowC, _GetDpiForWindowD>('GetDpiForWindow');
  late final _getWindowThreadProcessId = _user32
      .lookupFunction<_GetWindowThreadProcessIdC, _GetWindowThreadProcessIdD>(
        'GetWindowThreadProcessId',
      );
  late final _getCurrentProcessId = _kernel32
      .lookupFunction<_GetCurrentProcessIdC, _GetCurrentProcessIdD>(
        'GetCurrentProcessId',
      );

  static const _gwlStyle = -16;
  static const _gwlExstyle = -20;
  static const _wsPopup = 0x80000000;
  static const _wsVisible = 0x10000000;
  static const _wsExNoActivate = 0x08000000;
  static const _wsExToolwindow = 0x00000080;
  static const _wsExTopmost = 0x00000008;
  static const _wsExLayered = 0x00080000;
  static const _lwaColorkey = 0x00000001;
  static const _hwndTopmost = -1;
  static const _swpNoactivate = 0x0010;
  static const _swShowNoActivate = 4;
  static const _swHide = 0;
  static const _smCxScreen = 0;
  static const _smCyScreen = 1;

  int _findOverlay() {
    final className = _overlayWindowClass.toNativeUtf16();
    try {
      return _findWindow(className, nullptr);
    } finally {
      malloc.free(className);
    }
  }

  @override
  bool show({required int width, required int height}) {
    final hwnd = _findOverlay();
    if (hwnd == 0) {
      return false;
    }
    _setWindowLong(hwnd, _gwlStyle, _wsPopup | _wsVisible);
    _setWindowLong(
      hwnd,
      _gwlExstyle,
      _wsExNoActivate | _wsExToolwindow | _wsExTopmost | _wsExLayered,
    );
    _setLayeredWindowAttributes(hwnd, kChromaKeyColorref, 0, _lwaColorkey);
    // width/height are LOGICAL pixels; scale to the window's DPI so the
    // Flutter content gets the layout space it was designed for.
    final scale = _getDpiForWindow(hwnd) / 96.0;
    final physicalWidth = (width * scale).round();
    final physicalHeight = (height * scale).round();
    final x = (_getSystemMetrics(_smCxScreen) - physicalWidth) ~/ 2;
    final y =
        _getSystemMetrics(_smCyScreen) - physicalHeight - (96 * scale).round();
    _setWindowPos(
      hwnd,
      _hwndTopmost,
      x,
      y,
      physicalWidth,
      physicalHeight,
      _swpNoactivate,
    );
    _showWindow(hwnd, _swShowNoActivate);
    return true;
  }

  @override
  void hide() {
    final hwnd = _findOverlay();
    if (hwnd != 0) {
      _showWindow(hwnd, _swHide);
    }
  }

  @override
  String focusEvidence() {
    final hwnd = _getForegroundWindow();
    final buffer = malloc.allocate<Utf16>(512 * 2);
    try {
      final length = _getWindowText(hwnd, buffer, 512);
      final title = length > 0 ? buffer.toDartString() : '<untitled>';
      return '0x${hwnd.toRadixString(16)}:$title';
    } finally {
      malloc.free(buffer);
    }
  }

  @override
  bool get overlayStoleFocus {
    final overlay = _findOverlay();
    return overlay != 0 && _getForegroundWindow() == overlay;
  }

  @override
  bool get foregroundIsSelf {
    final foreground = _getForegroundWindow();
    if (foreground == 0) {
      return false;
    }
    final processId = malloc<Uint32>();
    try {
      _getWindowThreadProcessId(foreground, processId);
      return processId.value == _getCurrentProcessId();
    } finally {
      malloc.free(processId);
    }
  }

  @override
  String styleEvidence() {
    final overlay = _findOverlay();
    if (overlay == 0) {
      return 'exstyle=none';
    }
    final exstyle = _getWindowLong(overlay, _gwlExstyle);
    return 'exstyle=0x${exstyle.toRadixString(16)}';
  }
}
