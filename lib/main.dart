import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'src/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The app UI is light; keep the native title bar light too instead of
  // following the system dark theme. Linux is excluded because its title
  // bars are drawn by the desktop's window manager from the system theme.
  if (!Platform.isLinux) {
    await windowManager.ensureInitialized();
    await windowManager.setBrightness(Brightness.light);
  }
  runApp(const DictationFlowApp());
}
