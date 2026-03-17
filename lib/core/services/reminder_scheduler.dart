import 'package:workmanager/workmanager.dart';
import 'notification_service.dart';

class ReminderScheduler {
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    await Workmanager().initialize(
      callbackDispatcher,
    );
    _initialized = true;
  }

  static Future<void> scheduleReminder({
    required int reminderId,
    required int bookmarkId,
    required String title,
    required String url,
    required DateTime remindAt,
  }) async {
    final delay = remindAt.difference(DateTime.now());
    if (delay.isNegative) {
      throw Exception('Cannot schedule reminder in the past');
    }

    await NotificationService.scheduleNotification(
      id: reminderId,
      title: title,
      body: 'Tap to open your bookmark',
      scheduledTime: remindAt,
      payload: '$reminderId|$title|$url',
    );
  }

  static Future<void> cancelReminder(int reminderId) async {
    await NotificationService.cancelNotification(reminderId);
  }
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    return Future.value(true);
  });
}