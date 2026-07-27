import 'package:local_notifier/local_notifier.dart';

/// Seam over the OS notification plugin so bridge tests can capture what
/// would have been shown without a real toast popping up.
typedef DesktopNotificationSender =
    Future<void> Function(String title, String body);

/// Shows an OS notification through local_notifier. Works while the app is
/// hidden in the tray; on Windows the toast also lands in the Action
/// Center so it can be read again later.
Future<void> showDesktopNotification(String title, String body) async {
  await LocalNotification(title: title, body: body).show();
}
