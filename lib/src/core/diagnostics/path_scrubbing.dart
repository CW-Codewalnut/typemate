/// Replaces the username segment of home-directory paths with a
/// placeholder. Telemetry messages may quote file paths (a missing model,
/// a server executable); the path shape is diagnostic, the username is
/// personal data and must never leave the machine.
///
/// The Windows pattern is deliberately GREEDIER than the Unix ones: it
/// stops only at a path separator or line break, not at whitespace,
/// because Windows usernames routinely contain spaces ("jane doe") and a
/// whitespace-bounded match would leak everything after the first space.
/// The cost: when a message continues after a bare user-directory path
/// ("... at C:\Users\jane, aborting"), the rest of that line segment is
/// scrubbed too. That trade errs toward privacy over diagnostic detail —
/// do not "fix" it by stopping at whitespace. Paths that continue past
/// the username (C:\Users\jane\AppData\...) keep their tail either way.
String scrubPersonalPaths(String text) => text
    .replaceAll(
      RegExp(r'[A-Za-z]:[\\/]Users[\\/][^\\/\r\n]+', caseSensitive: false),
      r'C:\Users\<user>',
    )
    .replaceAll(RegExp(r'/home/[^/\s]+'), '/home/<user>')
    .replaceAll(RegExp(r'/Users/[^/\s]+'), '/Users/<user>');
