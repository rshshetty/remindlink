import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:flutter/foundation.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  static void Function(int reminderId, String title, String url)?
      onRemindLater;

  static const _openLinkChannel =
      MethodChannel('com.remindlink.app/open_link');

  static Future<void> initialize() async {
    if (_initialized) return;

    tz.initializeTimeZones();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings =
        InitializationSettings(android: androidSettings);

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
      onDidReceiveBackgroundNotificationResponse: _onBackgroundTapped,
    );

    _initialized = true;
  }

  static Future<bool> requestPermission() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  static Future<NotificationAppLaunchDetails?> getLaunchDetails() async {
    return await _notifications.getNotificationAppLaunchDetails();
  }

  static Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
  }) async {
    final utcTime = scheduledTime.toUtc();
    final tzScheduledTime = tz.TZDateTime.utc(
      utcTime.year,
      utcTime.month,
      utcTime.day,
      utcTime.hour,
      utcTime.minute,
    );

    if (tzScheduledTime.isBefore(tz.TZDateTime.now(tz.UTC))) {
      debugPrint('Warning: Attempted to schedule notification in the past.');
      return;
    }

    await _notifications.zonedSchedule(
      id,
      title,
      body,
      tzScheduledTime,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'reminders',
          'Bookmark Reminders',
          channelDescription: 'Notifications for bookmark reminders',
          importance: Importance.high,
          priority: Priority.high,
          actions: [
            AndroidNotificationAction(
              'open_link',
              'Open Link',
              showsUserInterface: false,
              cancelNotification: true,
            ),
            AndroidNotificationAction(
              'remind_later',
              'Remind Later',
              showsUserInterface: true,
              cancelNotification: true,
            ),
          ],
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );

    debugPrint('Notification scheduled for: $tzScheduledTime');
  }

  static Future<void> cancelNotification(int id) async {
    await _notifications.cancel(id);
  }

  static Future<void> _openUrlTransparent(String url) async {
    try {
      await _openLinkChannel.invokeMethod('openUrl', {'url': url});
    } catch (e) {
      debugPrint('Failed to open URL via channel: $e');
    }
  }

  static void _onNotificationTapped(NotificationResponse response) {
    _parseAndHandle(response);
  }

  static Future<void> _parseAndHandle(
      NotificationResponse response) async {
    final payload = response.payload;
    if (payload == null) return;

    final parts  = payload.split('|');
    final remId  = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
    final title  = parts.length > 1 ? parts[1] : '';
    final url    = parts.length > 2 ? parts[2] : payload;

    if (response.actionId == 'open_link') {
      // Open via transparent activity — no visible app UI
      await _openUrlTransparent(url);
    } else if (response.actionId == 'remind_later') {
      // Notify main.dart to show picker
      onRemindLater?.call(remId, title, url);
    } else {
      // Tapped notification body — open URL
      await _openUrlTransparent(url);
    }
  }
}

@pragma('vm:entry-point')
void _onBackgroundTapped(NotificationResponse response) async {
  final payload = response.payload;
  if (payload == null) return;

  if (response.actionId == 'open_link' ||
      response.actionId == null) {
    final parts = payload.split('|');
    final url   = parts.length > 2 ? parts[2] : payload;
    try {
      const channel = MethodChannel('com.remindlink.app/open_link');
      await channel.invokeMethod('openUrl', {'url': url});
    } catch (e) {
      debugPrint('Background open URL failed: $e');
    }
  }
}