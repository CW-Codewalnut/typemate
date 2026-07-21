import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

import '../platform_bridge.dart';

const _nativeChannel = MethodChannel('typemate/macos');

typedef NativeMethodInvoker =
    Future<T?> Function<T>(String method, [Object? arguments]);

/// Reports whether macOS trusts this process with the Accessibility
/// permission (required to post synthetic keyboard events). Abstracted so
/// tests can fake the answer.
abstract interface class MacAccessibility {
  bool get isProcessTrusted;
}

/// Types text into the focused field; abstracted so tests can capture the
/// typed text without posting real events.
abstract interface class MacTextTyper {
  Future<void> typeText(String text);
}

/// macOS implementation of the platform bridge.
///
/// Text lands in the focused field through CGEventPost keyboard events
/// carrying unicode payloads — the same effect as typing, and it needs the
/// Accessibility permission, which [isGlobalShortcutAvailable] reports
/// honestly. The listening/transcribing overlay and launch-at-login are
/// native (NSPanel, SMAppService) behind the `typemate/macos` method
/// channel; quit requests flow back over the same channel so resident
/// speech servers shut down before the process exits.
class MacOSPlatformBridge implements PlatformBridge, QuitRequestSource {
  MacOSPlatformBridge({
    NativeMethodInvoker? nativeMethodInvoker,
    this._textTyper,
    this._accessibility,
    String? executablePath,
  }) : _invokeNativeMethod = nativeMethodInvoker ?? _nativeChannel.invokeMethod,
       _executablePath = executablePath ?? Platform.resolvedExecutable {
    if (nativeMethodInvoker == null) {
      _nativeChannel.setMethodCallHandler(_handleNativeCall);
    }
  }

  final NativeMethodInvoker _invokeNativeMethod;
  final String _executablePath;

  /// Lazily bound on first use so constructing the bridge is safe on any
  /// host (tests, non-mac platforms) without CoreGraphics.
  MacTextTyper? _textTyper;
  MacAccessibility? _accessibility;

  Future<void> Function()? _onQuitRequested;

  @override
  set onQuitRequested(Future<void> Function()? handler) {
    _onQuitRequested = handler;
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'quitRequested') {
      await _onQuitRequested?.call();
    }
    return null;
  }

  @override
  Future<bool> isGlobalShortcutAvailable() async =>
      (_accessibility ??= FfiMacAccessibility()).isProcessTrusted;

  @override
  Future<void> showListeningOverlay() => _showOverlay('listening');

  @override
  Future<void> showTranscribingOverlay() => _showOverlay('transcribing');

  Future<void> _showOverlay(String state) async {
    try {
      await _invokeNativeMethod<void>('showOverlay', {'state': state});
    } on MissingPluginException {
      // Dev hosts without the native runner: dictation still works, only
      // the pill is missing.
    }
  }

  @override
  Future<void> hideListeningOverlay() async {
    try {
      await _invokeNativeMethod<void>('hideOverlay');
    } on MissingPluginException {
      // Ignored, as above.
    }
  }

  @override
  Future<void> insertTextIntoFocusedField(String text) async {
    if (!await isGlobalShortcutAvailable()) {
      throw StateError(
        'TypeMate needs the Accessibility permission to type into other '
        'apps. Enable TypeMate under System Settings > Privacy & Security '
        '> Accessibility, then try again.',
      );
    }
    await (_textTyper ??= CgEventMacTextTyper()).typeText(text);
  }

  @override
  Future<void> ensureLaunchAtStartup() async {
    // Only the installed app registers as a login item: transient binaries
    // (tests, flutter_tester, `flutter run` builds) must never end up in
    // the user's Login Items. The product name is "Type Mate", so the
    // executable path contains a space.
    final normalizedPath = _executablePath.toLowerCase().replaceAll(' ', '');
    if (!_executablePath.startsWith('/Applications/') ||
        !normalizedPath.endsWith('.app/contents/macos/typemate')) {
      return;
    }
    try {
      await _invokeNativeMethod<void>('ensureLaunchAtStartup');
    } on MissingPluginException {
      // Older runners without the native method: launch-at-login is a
      // nicety, not a dictation dependency.
    }
  }
}

typedef _AXIsProcessTrustedNative = Bool Function();
typedef _AXIsProcessTrusted = bool Function();

/// Real Accessibility trust check via ApplicationServices. The native
/// runner prompts for the permission at launch; this only reads the
/// current answer.
class FfiMacAccessibility implements MacAccessibility {
  FfiMacAccessibility() {
    final applicationServices = DynamicLibrary.open(
      '/System/Library/Frameworks/ApplicationServices.framework/'
      'ApplicationServices',
    );
    _isProcessTrustedFunction = applicationServices
        .lookupFunction<_AXIsProcessTrustedNative, _AXIsProcessTrusted>(
          'AXIsProcessTrusted',
        );
  }

  late final _AXIsProcessTrusted _isProcessTrustedFunction;

  @override
  bool get isProcessTrusted => _isProcessTrustedFunction();
}

typedef _CGEventCreateKeyboardEventNative =
    Pointer<Void> Function(Pointer<Void>, Uint16, Bool);
typedef _CGEventCreateKeyboardEvent =
    Pointer<Void> Function(Pointer<Void>, int, bool);
typedef _CGEventKeyboardSetUnicodeStringNative =
    Void Function(Pointer<Void>, IntPtr, Pointer<Uint16>);
typedef _CGEventKeyboardSetUnicodeString =
    void Function(Pointer<Void>, int, Pointer<Uint16>);
typedef _CGEventSetFlagsNative = Void Function(Pointer<Void>, Uint64);
typedef _CGEventSetFlags = void Function(Pointer<Void>, int);
typedef _CGEventPostNative = Void Function(Uint32, Pointer<Void>);
typedef _CGEventPost = void Function(int, Pointer<Void>);
typedef _CFReleaseNative = Void Function(Pointer<Void>);
typedef _CFRelease = void Function(Pointer<Void>);

/// kCGHIDEventTap: post at the lowest level so the event reaches whatever
/// field has focus, exactly like hardware typing.
const _hidEventTap = 0;

/// Real typing via CGEventPost unicode keyboard events.
class CgEventMacTextTyper implements MacTextTyper {
  CgEventMacTextTyper() {
    final coreGraphics = DynamicLibrary.open(
      '/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics',
    );
    final coreFoundation = DynamicLibrary.open(
      '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation',
    );
    _createKeyboardEvent = coreGraphics
        .lookupFunction<
          _CGEventCreateKeyboardEventNative,
          _CGEventCreateKeyboardEvent
        >('CGEventCreateKeyboardEvent');
    _setUnicodeString = coreGraphics
        .lookupFunction<
          _CGEventKeyboardSetUnicodeStringNative,
          _CGEventKeyboardSetUnicodeString
        >('CGEventKeyboardSetUnicodeString');
    _setFlags = coreGraphics
        .lookupFunction<_CGEventSetFlagsNative, _CGEventSetFlags>(
          'CGEventSetFlags',
        );
    _post = coreGraphics.lookupFunction<_CGEventPostNative, _CGEventPost>(
      'CGEventPost',
    );
    _release = coreFoundation.lookupFunction<_CFReleaseNative, _CFRelease>(
      'CFRelease',
    );
  }

  late final _CGEventCreateKeyboardEvent _createKeyboardEvent;
  late final _CGEventKeyboardSetUnicodeString _setUnicodeString;
  late final _CGEventSetFlags _setFlags;
  late final _CGEventPost _post;
  late final _CFRelease _release;

  /// CGEventKeyboardSetUnicodeString drops anything beyond 20 UTF-16
  /// units, so longer transcripts go out as a chunk sequence.
  static const _maxUnitsPerEvent = 20;

  @override
  Future<void> typeText(String text) async {
    final units = text.codeUnits;
    for (var start = 0; start < units.length; start += _maxUnitsPerEvent) {
      final chunk = units.sublist(
        start,
        min(start + _maxUnitsPerEvent, units.length),
      );
      _postChunk(chunk, isKeyDown: true);
      _postChunk(chunk, isKeyDown: false);
      // Pace the chunks so receiving apps process them in order.
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
  }

  void _postChunk(List<int> codeUnits, {required bool isKeyDown}) {
    final buffer = calloc<Uint16>(codeUnits.length);
    try {
      for (var i = 0; i < codeUnits.length; i++) {
        buffer[i] = codeUnits[i];
      }
      final event = _createKeyboardEvent(nullptr, 0, isKeyDown);
      // Zero flags: lingering shortcut modifiers must not turn the typed
      // characters into app shortcuts.
      _setFlags(event, 0);
      _setUnicodeString(event, codeUnits.length, buffer);
      _post(_hidEventTap, event);
      _release(event);
    } finally {
      calloc.free(buffer);
    }
  }
}
