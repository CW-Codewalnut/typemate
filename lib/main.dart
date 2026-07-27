import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_single_instance/flutter_single_instance.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:window_manager/window_manager.dart';

import 'src/app.dart';
import 'src/models/app_identity.dart';

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
  // OS notifications for dictation failures: they must reach the user even
  // while the app sits in the tray. Windows toasts require a Start Menu
  // shortcut with the app's identity, which setup ensures.
  await localNotifier.setup(
    appName: appDisplayName,
    shortcutPolicy: ShortcutPolicy.requireCreate,
  );
  await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
  // The OS-visible window title (taskbar, alt-tab) derives from the same
  // constant as every in-app surface.
  await windowManager.setTitle(appDisplayName);
  runApp(const TypeMateApp());
}
