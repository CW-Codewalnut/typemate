/// Replaces the username segment of home-directory paths with a
/// placeholder. Telemetry messages may quote file paths (a missing model,
/// a server executable); the path shape is diagnostic, the username is
/// personal data and must never leave the machine.
String scrubPersonalPaths(String text) => text
    .replaceAll(
      RegExp(r'[A-Za-z]:[\\/]Users[\\/][^\\/\r\n]+', caseSensitive: false),
      r'C:\Users\<user>',
    )
    .replaceAll(RegExp(r'/home/[^/\s]+'), '/home/<user>')
    .replaceAll(RegExp(r'/Users/[^/\s]+'), '/Users/<user>');
