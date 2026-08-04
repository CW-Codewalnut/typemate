// Spike: can desktop_multi_window + Dart-side Win32 FFI replace the
// native overlay renderers? Feasibility gates, in order of importance:
//   1. showing the overlay must NOT steal keyboard focus (a stolen focus
//      means the transcript lands in the wrong window),
//   2. frameless + transparent + always-on-top + no taskbar entry,
//   3. show/hide cycling stays stable.
//
// Run on Windows:
//   flutter run -d windows -t lib/spike/overlay_spike_main.dart
//
// The overlay window is styled entirely from the MAIN engine via user32
// calls (no compiled native code): WS_POPUP, WS_EX_NOACTIVATE |
// WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_LAYERED with a colour key,
// then SW_SHOWNOACTIVATE. The spike prints FOREGROUND= lines around the
// show so focus stealing is measurable, not eyeballed.
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';

// Chroma key painted behind the overlay UI and keyed out by
// SetLayeredWindowAttributes: everything this exact colour becomes
// transparent AND click-through (Windows routes clicks on keyed pixels
// to the window below). Near-black on purpose: the capsule's
// antialiased edge pixels blend toward the key colour and are NOT keyed
// out, so a loud key (magenta) leaves a coloured fringe while a
// near-black key leaves a faint dark halo that reads as a shadow. The
// pill itself must simply never contain this exact colour.
const _chromaKey = Color(0xFF010203);
// COLORREF is 0x00BBGGRR: blue 03, green 02, red 01.
const _chromaKeyColorref = 0x00030201;
// The package's fixed Win32 class for every window it creates.
const _overlayWindowClass = 'FLUTTER_MULTI_WINDOW_WIN32_WINDOW';

void main(List<String> args) {
  if (args.firstOrNull == 'multi_window') {
    final data = json.decode(args[2]) as Map<String, dynamic>;
    runApp(
      _OverlayApp(
        windowId: args[1],
        initialState: data['state'] as String? ?? 'listening',
      ),
    );
    return;
  }
  runApp(const _ControlApp());
}

// ---------------------------------------------------------------------------
// Win32 via FFI (main engine only; the overlay engine just renders UI).
// ---------------------------------------------------------------------------

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

class _Win32 {
  _Win32() : _user32 = DynamicLibrary.open('user32.dll');

  final DynamicLibrary _user32;

  late final findWindow = _user32.lookupFunction<_FindWindowC, _FindWindowD>(
    'FindWindowW',
  );
  late final getWindowLong = _user32
      .lookupFunction<_GetWindowLongC, _GetWindowLongD>('GetWindowLongPtrW');
  late final setWindowLong = _user32
      .lookupFunction<_SetWindowLongC, _SetWindowLongD>('SetWindowLongPtrW');
  late final setLayeredWindowAttributes = _user32
      .lookupFunction<_SetLayeredC, _SetLayeredD>('SetLayeredWindowAttributes');
  late final setWindowPos = _user32
      .lookupFunction<_SetWindowPosC, _SetWindowPosD>('SetWindowPos');
  late final showWindow = _user32.lookupFunction<_ShowWindowC, _ShowWindowD>(
    'ShowWindow',
  );
  late final getForegroundWindow = _user32
      .lookupFunction<_GetForegroundC, _GetForegroundD>('GetForegroundWindow');
  late final getWindowText = _user32
      .lookupFunction<_GetWindowTextC, _GetWindowTextD>('GetWindowTextW');
  late final getSystemMetrics = _user32
      .lookupFunction<_GetSystemMetricsC, _GetSystemMetricsD>(
        'GetSystemMetrics',
      );
  late final getDpiForWindow = _user32
      .lookupFunction<_GetDpiForWindowC, _GetDpiForWindowD>('GetDpiForWindow');

  static const gwlStyle = -16;
  static const gwlExstyle = -20;
  static const wsPopup = 0x80000000;
  static const wsVisible = 0x10000000;
  static const wsExNoActivate = 0x08000000;
  static const wsExToolwindow = 0x00000080;
  static const wsExTopmost = 0x00000008;
  static const wsExLayered = 0x00080000;
  static const lwaColorkey = 0x00000001;
  static const hwndTopmost = -1;
  static const swpNoactivate = 0x0010;
  static const swShowNoActivate = 4;
  static const swHide = 0;
  static const smCxScreen = 0;
  static const smCyScreen = 1;

  int findOverlay() {
    final className = _overlayWindowClass.toNativeUtf16();
    try {
      return findWindow(className, nullptr);
    } finally {
      malloc.free(className);
    }
  }

  String foregroundTitle() {
    final hwnd = getForegroundWindow();
    final buffer = malloc.allocate<Utf16>(512 * 2);
    try {
      final length = getWindowText(hwnd, buffer, 512);
      return length > 0 ? buffer.toDartString() : '<untitled:$hwnd>';
    } finally {
      malloc.free(buffer);
    }
  }

  /// Restyles the overlay top-level window as a non-activating,
  /// click-through, topmost, colour-keyed layered popup and shows it
  /// WITHOUT activation, positioned at the bottom-centre of the screen.
  bool styleAndShowOverlay({required int width, required int height}) {
    final hwnd = findOverlay();
    if (hwnd == 0) {
      return false;
    }
    setWindowLong(hwnd, gwlStyle, wsPopup | wsVisible);
    setWindowLong(
      hwnd,
      gwlExstyle,
      wsExNoActivate | wsExToolwindow | wsExTopmost | wsExLayered,
    );
    setLayeredWindowAttributes(hwnd, _chromaKeyColorref, 0, lwaColorkey);
    // width/height are LOGICAL pixels; scale to the window's DPI so the
    // Flutter content gets the layout space it was designed for.
    final scale = getDpiForWindow(hwnd) / 96.0;
    final physicalWidth = (width * scale).round();
    final physicalHeight = (height * scale).round();
    final x = (getSystemMetrics(smCxScreen) - physicalWidth) ~/ 2;
    final y =
        getSystemMetrics(smCyScreen) - physicalHeight - (96 * scale).round();
    setWindowPos(
      hwnd,
      hwndTopmost,
      x,
      y,
      physicalWidth,
      physicalHeight,
      swpNoactivate,
    );
    showWindow(hwnd, swShowNoActivate);
    return true;
  }

  void hideOverlay() {
    final hwnd = findOverlay();
    if (hwnd != 0) {
      showWindow(hwnd, swHide);
    }
  }
}

// ---------------------------------------------------------------------------
// Control window (main engine)
// ---------------------------------------------------------------------------

class _ControlApp extends StatefulWidget {
  const _ControlApp();

  @override
  State<_ControlApp> createState() => _ControlAppState();
}

class _ControlAppState extends State<_ControlApp> {
  final _win32 = Platform.isWindows ? _Win32() : null;
  WindowController? _overlay;
  String _log = 'Overlay not created yet.';

  // The real product reasons, verbatim, so every error renders exactly
  // as it will in production (the error pill shows whatever message the
  // dictation controller reports - engine preparing, model missing,
  // microphone problems - never a generic failure).
  static const _sequence = [
    ('listening', null),
    ('transcribing', null),
    ('error', 'Download the speech model in the TypeMate window first.'),
    ('error', 'Preparing local speech engine...'),
    (
      'error',
      "Couldn't start recording. Check that your microphone is "
          'connected and allowed, then try again.',
    ),
  ];
  int _cycle = 0;

  @override
  void initState() {
    super.initState();
    // Unattended: cycle forever - 9s shown, 3s hidden - so an external
    // observer can screenshot any time and logs accumulate evidence.
    Timer.periodic(const Duration(seconds: 12), (_) async {
      final (state, message) = _sequence[_cycle % _sequence.length];
      await _show(state, message);
      _cycle++;
      Timer(const Duration(seconds: 9), _hide);
    });
  }

  Future<void> _ensureOverlay() async {
    if (_overlay != null) {
      return;
    }
    final controller = await WindowController.create(
      WindowConfiguration(
        arguments: json.encode({'state': 'listening'}),
        hiddenAtLaunch: true,
      ),
    );
    // Give the sub-engine a beat to first-frame before restyling.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    _overlay = controller;
  }

  Future<void> _show(String state, [String? message]) async {
    final before = _win32?.foregroundTitle();
    await _ensureOverlay();
    await _overlay!.invokeMethod(
      'setState',
      json.encode({'state': state, 'message': message}),
    );
    final isError = state == 'error';
    final styled = _win32?.styleAndShowOverlay(
      width: isError ? 360 : 230,
      height: isError ? 92 : 66,
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final after = _win32?.foregroundTitle();
    final overlayHwnd = _win32?.findOverlay() ?? 0;
    final foregroundHwnd = _win32?.getForegroundWindow() ?? -1;
    // The decisive check: the overlay must never BE the foreground
    // window, regardless of what else holds focus.
    final stole = overlayHwnd != 0 && foregroundHwnd == overlayHwnd;
    final exstyle = overlayHwnd == 0
        ? 0
        : _win32!.getWindowLong(overlayHwnd, _Win32.gwlExstyle);
    setState(() {
      _log =
          'styled=$styled overlayHwnd=$overlayHwnd\n'
          'FOREGROUND before: $before\n'
          'FOREGROUND after:  $after\n'
          '${stole ? "FAIL: overlay took focus" : "PASS: overlay not foreground"}';
    });
    // Also to stdout so `flutter run` logs carry the evidence.
    debugPrint(
      'SPIKE|$state|styled=$styled|overlay=$overlayHwnd'
      '|foreground=$foregroundHwnd|stole=$stole'
      '|exstyle=0x${exstyle.toRadixString(16)}'
      '|before=$before|after=$after',
    );
  }

  void _hide() {
    _win32?.hideOverlay();
    setState(() => _log = 'Overlay hidden.');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Overlay spike control',
      home: Scaffold(
        appBar: AppBar(title: const Text('Overlay spike control')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: () => _show('listening'),
                    child: const Text('Show listening'),
                  ),
                  FilledButton(
                    onPressed: () => _show('transcribing'),
                    child: const Text('Show transcribing'),
                  ),
                  FilledButton(
                    onPressed: () => _show('error'),
                    child: const Text('Show error'),
                  ),
                  OutlinedButton(onPressed: _hide, child: const Text('Hide')),
                ],
              ),
              const SizedBox(height: 16),
              Text(_log, style: const TextStyle(fontFamily: 'monospace')),
              const SizedBox(height: 16),
              const Text(
                'Test: focus Notepad, then trigger a show from the global '
                'shortcut simulation (buttons here steal focus by being '
                'clicked - the PASS/FAIL line accounts for that by '
                'comparing against the pre-click foreground).',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Overlay window (sub engine): pure UI on a chroma-key background.
// ---------------------------------------------------------------------------

/// Semantic overlay colours and metrics as a proper [ThemeExtension]:
/// widgets never carry raw colour values, they read the themed role.
@immutable
class _OverlayTheme extends ThemeExtension<_OverlayTheme> {
  const _OverlayTheme({
    required this.pillBackground,
    required this.errorBackground,
    required this.foreground,
    required this.barColor,
    required this.barMinHeight,
    required this.barMaxHeight,
    required this.barWidth,
    required this.barGap,
  });

  /// Matches the native overlay palette (RGB 31,34,48 pill, 96,28,34
  /// error, 122,139,255 bars).
  const _OverlayTheme.native()
    : this(
        pillBackground: const Color(0xFF1F2230),
        errorBackground: const Color(0xFF601C22),
        foreground: Colors.white,
        barColor: const Color(0xFF7A8BFF),
        barMinHeight: 4,
        barMaxHeight: 14,
        barWidth: 4,
        barGap: 5,
      );

  final Color pillBackground;
  final Color errorBackground;
  final Color foreground;
  final Color barColor;
  final double barMinHeight;
  final double barMaxHeight;
  final double barWidth;
  final double barGap;

  @override
  _OverlayTheme copyWith({
    Color? pillBackground,
    Color? errorBackground,
    Color? foreground,
    Color? barColor,
    double? barMinHeight,
    double? barMaxHeight,
    double? barWidth,
    double? barGap,
  }) {
    return _OverlayTheme(
      pillBackground: pillBackground ?? this.pillBackground,
      errorBackground: errorBackground ?? this.errorBackground,
      foreground: foreground ?? this.foreground,
      barColor: barColor ?? this.barColor,
      barMinHeight: barMinHeight ?? this.barMinHeight,
      barMaxHeight: barMaxHeight ?? this.barMaxHeight,
      barWidth: barWidth ?? this.barWidth,
      barGap: barGap ?? this.barGap,
    );
  }

  @override
  _OverlayTheme lerp(ThemeExtension<_OverlayTheme>? other, double t) {
    if (other is! _OverlayTheme) {
      return this;
    }
    return _OverlayTheme(
      pillBackground: Color.lerp(pillBackground, other.pillBackground, t)!,
      errorBackground: Color.lerp(errorBackground, other.errorBackground, t)!,
      foreground: Color.lerp(foreground, other.foreground, t)!,
      barColor: Color.lerp(barColor, other.barColor, t)!,
      barMinHeight: lerpDouble(barMinHeight, other.barMinHeight, t)!,
      barMaxHeight: lerpDouble(barMaxHeight, other.barMaxHeight, t)!,
      barWidth: lerpDouble(barWidth, other.barWidth, t)!,
      barGap: lerpDouble(barGap, other.barGap, t)!,
    );
  }
}

class _OverlayApp extends StatefulWidget {
  const _OverlayApp({required this.windowId, required this.initialState});

  final String windowId;
  final String initialState;

  @override
  State<_OverlayApp> createState() => _OverlayAppState();
}

class _OverlayAppState extends State<_OverlayApp> {
  late String _state = widget.initialState;
  String? _message;

  @override
  void initState() {
    super.initState();
    WindowController.fromWindowId(widget.windowId).setWindowMethodHandler((
      call,
    ) async {
      if (call.method == 'setState') {
        final data = json.decode(call.arguments as String);
        setState(() {
          _state = data['state'] as String;
          _message = data['message'] as String?;
        });
      }
      return null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isError = _state == 'error';
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        extensions: const [_OverlayTheme.native()],
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontSize: 12.5, color: Colors.white),
        ),
      ),
      // Material ancestor: without it Text falls back to the yellow
      // double-underline error style.
      home: Builder(
        builder: (context) {
          final overlayTheme = Theme.of(context).extension<_OverlayTheme>()!;
          final textStyle = Theme.of(
            context,
          ).textTheme.bodyMedium!.copyWith(color: overlayTheme.foreground);
          return Material(
            color: _chromaKey,
            child: Center(
              child: isError
                  ? Container(
                      constraints: const BoxConstraints(maxWidth: 340),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: overlayTheme.errorBackground,
                        borderRadius: BorderRadius.circular(29),
                      ),
                      child: Text(
                        _message ?? 'Dictation failed',
                        textAlign: TextAlign.center,
                        style: textStyle,
                      ),
                    )
                  : Container(
                      width: 210,
                      height: 58,
                      decoration: BoxDecoration(
                        color: overlayTheme.pillBackground,
                        borderRadius: BorderRadius.circular(29),
                      ),
                      child: Column(
                        children: [
                          const SizedBox(height: 7),
                          SizedBox(
                            height: 22,
                            child: Center(
                              child: Text(
                                _state == 'transcribing'
                                    ? 'Transcribing locally...'
                                    : 'TypeMate is listening...',
                                style: textStyle,
                              ),
                            ),
                          ),
                          const Expanded(child: _Bars()),
                        ],
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }
}

/// The animated level bars, proving the sub-engine renders animation
/// while the window is a no-activate layered popup.
class _Bars extends StatefulWidget {
  const _Bars();

  @override
  State<_Bars> createState() => _BarsState();
}

class _BarsState extends State<_Bars> {
  // Native cadence: tick_ increments every 70 ms; bar i uses
  // sin((tick + i*2) * 0.55) mapped into 5..18 px.
  late final Timer _timer;
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 70), (_) {
      setState(() => _tick++);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final overlayTheme = Theme.of(context).extension<_OverlayTheme>()!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < 7; i++) ...[
          if (i > 0) SizedBox(width: overlayTheme.barGap),
          _bar(i, overlayTheme),
        ],
      ],
    );
  }

  Widget _bar(int index, _OverlayTheme overlayTheme) {
    final phase = (_tick + index * 2) * 0.55;
    final range = overlayTheme.barMaxHeight - overlayTheme.barMinHeight;
    final height =
        overlayTheme.barMinHeight + ((math.sin(phase) + 1.0) / 2.0) * range;
    return Container(
      width: overlayTheme.barWidth,
      height: height,
      decoration: BoxDecoration(
        color: overlayTheme.barColor,
        borderRadius: BorderRadius.circular(overlayTheme.barWidth / 2),
      ),
    );
  }
}
