import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_single_instance/flutter_single_instance.dart';
import 'package:window_manager/window_manager.dart';

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
  // Hide the native title bar on every desktop: WindowTitleBar draws one
  // Flutter bar (white, Windows-style) so the chrome is identical on all
  // OSes instead of following each window manager's theme.
  await windowManager.ensureInitialized();
  await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
  runApp(const DictationFlowApp());
}
