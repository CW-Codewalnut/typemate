// The overlay window's UI (sub engine): a faithful clone of the native
// pill design, colours and metrics in a ThemeExtension, message always
// supplied by the caller.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';

import '../core/platform/overlay/overlay_variant.dart';

/// Semantic overlay colours and metrics as a proper [ThemeExtension]:
/// widgets never carry raw colour values, they read the themed role.
@immutable
class OverlayTheme extends ThemeExtension<OverlayTheme> {
  const OverlayTheme({
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
  const OverlayTheme.native()
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
  OverlayTheme copyWith({
    Color? pillBackground,
    Color? errorBackground,
    Color? foreground,
    Color? barColor,
    double? barMinHeight,
    double? barMaxHeight,
    double? barWidth,
    double? barGap,
  }) {
    return OverlayTheme(
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
  OverlayTheme lerp(ThemeExtension<OverlayTheme>? other, double t) {
    if (other is! OverlayTheme) {
      return this;
    }
    return OverlayTheme(
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

/// The cross-engine channel the overlay listens on. Fixed name (one
/// overlay per app): unidirectional, so the overlay engine registers as
/// the single handler and the main engine invokes without needing the
/// window id.
const overlayWindowChannelName = 'typemate/overlay';

class OverlayWindowApp extends StatefulWidget {
  const OverlayWindowApp({
    this.initialVariant = OverlayVariant.working,
    this.initialMessage = '',
    this.connectChannel = true,
    super.key,
  });

  final OverlayVariant initialVariant;
  final String initialMessage;

  /// Widget tests render the pill without a second engine; false skips
  /// the cross-engine channel registration.
  final bool connectChannel;

  @override
  State<OverlayWindowApp> createState() => _OverlayWindowAppState();
}

class _OverlayWindowAppState extends State<OverlayWindowApp> {
  late OverlayVariant _variant = widget.initialVariant;
  late String _message = widget.initialMessage;
  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    if (!widget.connectChannel) {
      return;
    }
    const WindowMethodChannel(
      overlayWindowChannelName,
      mode: ChannelMode.unidirectional,
    ).setMethodCallHandler((call) async {
      if (call.method == 'setState') {
        final data = json.decode(call.arguments as String);
        setState(() {
          _hidden = data['hidden'] as bool? ?? false;
          if (data['variant'] != null) {
            _variant =
                OverlayVariant.values.asNameMap()[data['variant']] ??
                OverlayVariant.working;
          }
          if (data['message'] != null) {
            _message = data['message'] as String;
          }
        });
      }
      return null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // A hidden overlay renders nothing at all, which also unmounts the
    // bars and stops their animation timer - the native window is
    // invisible anyway, so ticking would only burn cycles.
    if (_hidden) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: SizedBox.shrink(),
      );
    }
    final isTextPill = _variant != OverlayVariant.working;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        extensions: const [OverlayTheme.native()],
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontSize: 12.5, color: Colors.white),
        ),
      ),
      // Material ancestor: without it Text falls back to the yellow
      // double-underline error style.
      home: Builder(
        builder: (context) {
          final overlayTheme = Theme.of(context).extension<OverlayTheme>()!;
          final textStyle = Theme.of(
            context,
          ).textTheme.bodyMedium!.copyWith(color: overlayTheme.foreground);
          // Severity-coded: red only for real failures, the primary
          // pill colour for guidance.
          final pillColor = _variant == OverlayVariant.error
              ? overlayTheme.errorBackground
              : overlayTheme.pillBackground;
          final barsPill = Column(
            children: [
              const SizedBox(height: 7),
              SizedBox(
                height: 22,
                child: Center(child: Text(_message, style: textStyle)),
              ),
              const Expanded(child: _Bars()),
            ],
          );
          // No Center inside the pill: Center expands to its incoming
          // constraints, which inflated the capsule to the full overlay
          // window instead of hugging the message.
          final textPill = Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Text(
              _message,
              textAlign: TextAlign.center,
              style: textStyle,
            ),
          );
          if (Platform.isLinux) {
            // The X11 shape cuts the rounded corners, so the pill paints
            // edge to edge - a chroma margin would show as a border. The
            // window is the capsule here, so the message centres in it.
            return Material(
              color: pillColor,
              child: isTextPill ? Center(child: textPill) : barsPill,
            );
          }
          // macOS composits true per-pixel alpha (window is non-opaque
          // with a clear background), so paint nothing around the pill;
          // Windows paints the chroma key that the layered window drops.
          final backdrop = Platform.isMacOS ? Colors.transparent : kChromaKey;
          return Material(
            color: backdrop,
            child: Center(
              child: isTextPill
                  ? Container(
                      constraints: const BoxConstraints(maxWidth: 340),
                      decoration: BoxDecoration(
                        color: pillColor,
                        borderRadius: BorderRadius.circular(29),
                      ),
                      child: textPill,
                    )
                  : Container(
                      width: 210,
                      height: 58,
                      decoration: BoxDecoration(
                        color: overlayTheme.pillBackground,
                        borderRadius: BorderRadius.circular(29),
                      ),
                      child: barsPill,
                    ),
            ),
          );
        },
      ),
    );
  }
}

/// The animated level bars, matching the native cadence: tick every
/// 70 ms; bar i maps sin((tick + i*2) * 0.55) into the themed height
/// range.
class _Bars extends StatefulWidget {
  const _Bars();

  @override
  State<_Bars> createState() => _BarsState();
}

class _BarsState extends State<_Bars> {
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
    final overlayTheme = Theme.of(context).extension<OverlayTheme>()!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 7; i++) ...[
          if (i > 0) SizedBox(width: overlayTheme.barGap),
          _bar(i, overlayTheme),
        ],
      ],
    );
  }

  Widget _bar(int index, OverlayTheme overlayTheme) {
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
