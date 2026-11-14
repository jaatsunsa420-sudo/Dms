import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'local_db.dart';

class NotificationService {
  static final _notifications = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    await _notifications.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    await scheduleDaily8PMReminder();
  }

  static Future<void> scheduleDaily8PMReminder() async {
    await _notifications.cancel(800);
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, 20, 0);
    if (scheduled.isBefore(now)) scheduled = scheduled.add(const Duration(days: 1));
    final todayStr = now.toIso8601String().substring(0, 10);
    final db = await LocalDatabase.instance.database;
    final trips = await db.query('trips', where: 'trip_date = ?', whereArgs: [todayStr]);
    final hol = await db.query('attendance_logs', where: "log_date = ? AND status = 'Holiday'", whereArgs: [todayStr]);
    if (trips.isNotEmpty || hol.isNotEmpty) {
      scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, 20, 0).add(const Duration(days: 1));
    }
    await _notifications.zonedSchedule(
      800,
      'Trip Entry Reminder / ट्रिप रिमाइंडर',
      'आज की कोई Trip दर्ज नहीं हुई है। कृपया Trip या Holiday दर्ज करें।',
      scheduled,
      const NotificationDetails(android: AndroidNotificationDetails('daily_trip_reminder', 'Daily 8 PM Reminder', importance: Importance.high, priority: Priority.high)),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  static Future<void> cancelTodayReminder() async => await scheduleDaily8PMReminder();
}
