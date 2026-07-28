import 'dart:io';

/// Opens [path] in the OS file manager, creating it first so the window
/// never opens on an error. Used by Settings to show the log folder.
Future<void> revealDirectory(String path) async {
  final directory = Directory(path)..createSync(recursive: true);
  if (Platform.isWindows) {
    // Explorer wants backslashes; forward slashes open Documents instead.
    await Process.start('explorer', [directory.path.replaceAll('/', r'\')]);
  } else if (Platform.isMacOS) {
    await Process.start('open', [directory.path]);
  } else {
    await Process.start('xdg-open', [directory.path]);
  }
}
