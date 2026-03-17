import '../database/database.dart';
import '../services/reminder_scheduler.dart';
import 'package:drift/drift.dart';
class ReminderRepository {
  final AppDatabase database;
  
  ReminderRepository(this.database);
  
  Future<int> createReminderWithNotification({
    required int bookmarkId,
    required DateTime remindAt,
    required String bookmarkTitle,
    required String bookmarkUrl,
  }) async {
    final entry = RemindersCompanion.insert(
      bookmarkId: bookmarkId,
      remindAt: remindAt,
    );
    
    final reminderId = await database.into(database.reminders).insert(entry);
    
    await ReminderScheduler.scheduleReminder(
      reminderId: reminderId,
      bookmarkId: bookmarkId,
      title: bookmarkTitle,
      url:bookmarkUrl,
      remindAt: remindAt,
    );
    
    return reminderId;
  }
  Future<void> updateReminderTime({
  required int reminderId,
  required DateTime newRemindAt,
}) async {
  await (database.update(database.reminders)
        ..where((t) => t.id.equals(reminderId)))
      .write(RemindersCompanion(
        remindAt: Value(newRemindAt),
      ));
}
  Future<Reminder?> getReminderForBookmark(int bookmarkId) async {
    final query = database.select(database.reminders)
      ..where((t) => t.bookmarkId.equals(bookmarkId))
      ..where((t) => t.status.equals('pending'));
    
    final results = await query.get();
    return results.isEmpty ? null : results.first;
  }
  
  Future<int> deleteReminder(int id) async {
    return await (database.delete(database.reminders)
      ..where((t) => t.id.equals(id))).go();
  }
  
  Future<void> deleteReminderWithNotification(int id) async {
    await ReminderScheduler.cancelReminder(id);
    await deleteReminder(id);
  }
}
