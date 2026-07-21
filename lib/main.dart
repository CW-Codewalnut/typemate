import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_single_instance/flutter_single_instance.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'src/app.dart';
import 'src/models/app_identity.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // On macOS the app-scoped temporary directory does not exist until
  // something creates it, and flutter_single_instance treats the resulting
  // lock-file error as "another instance is running" — which would exit
  // every launch on a fresh install.
  if (Platform.isMacOS) {
    await (await getTemporaryDirectory()).create(recursive: true);
  }
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
  // The OS-visible window title (taskbar, alt-tab) derives from the same
  // constant as every in-app surface.
  await windowManager.setTitle(appDisplayName);
  runApp(const TypeMateApp());
}
