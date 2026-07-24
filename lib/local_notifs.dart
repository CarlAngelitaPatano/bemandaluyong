import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

// ===========================================================================
// Daily reminder notification — a real lock-screen popup at 7:00 AM, even
// when the app is closed. Tapping it opens the app (where the live weather
// notification is waiting).
// ===========================================================================
class LocalNotifs {
  LocalNotifs._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// Initialize, ask permission (Android 13+), and schedule the 7 AM daily
  /// reminder. Safe to call on every app start (re-scheduling replaces the
  /// previous schedule; it does not duplicate).
  static Future<void> setup() async {
    try {
      // Timezone database — schedule in Manila time.
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Manila'));

      const androidInit =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      await _plugin.initialize(
        settings: const InitializationSettings(android: androidInit),
      );

      // Android 13+ runtime permission for notifications.
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();

      _ready = true;
      await _scheduleDaily();
    } catch (_) {
      // Notifications are a nice-to-have — never block the app over them.
    }
  }

  /// Next 7:00 AM (today if it's still before 7, otherwise tomorrow).
  static tz.TZDateTime _next7am() {
    final now = tz.TZDateTime.now(tz.local);
    var when =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, 7); // 7:00 AM
    if (when.isBefore(now)) when = when.add(const Duration(days: 1));
    return when;
  }

  static Future<void> _scheduleDaily() async {
    if (!_ready) return;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'daily_reminder',
        'Daily reminder',
        channelDescription:
            'A good-morning reminder with the day\'s weather and trail nudge.',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
    );
    await _plugin.zonedSchedule(
      id: 1001, // stable id — rescheduling replaces, never duplicates
      title: 'Good morning! ☀️',
      body: 'Check today\'s Mandaluyong weather and continue your Heritage Trail.',
      scheduledDate: _next7am(),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time, // repeat daily at 7 AM
    );
  }
}
