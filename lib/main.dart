import 'dart:io';

import 'package:flutter/material.dart';
// Re-exports window_manager, which the title-bar brightness call uses.
import 'package:flutter_single_instance/flutter_single_instance.dart';

import 'src/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // One TypeMate only: a second launch would fight over the global
  // shortcut and the resident speech servers. Hand focus to the running
  // instance and bow out.
  if (!await FlutterSingleInstance().isFirstInstance()) {
    await FlutterSingleInstance().focus();
    exit(0);
  }
  // When a second launch pings us, surface the existing window — including
  // un-hiding it from the tray, which a bare focus() cannot do.
  FlutterSingleInstance.onFocus = (_) async {
    await windowManager.show();
    await windowManager.focus();
  };
  // The app UI is light; keep the native title bar light too instead of
  // following the system dark theme. Linux is excluded because its title
  // bars are drawn by the desktop's window manager from the system theme.
  if (!Platform.isLinux) {
    await windowManager.ensureInitialized();
    await windowManager.setBrightness(Brightness.light);
  }
  runApp(const DictationFlowApp());
}
