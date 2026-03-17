import 'package:drift/drift.dart';
import '../database/database.dart';
import '../utils/url_parser.dart';

class BookmarkRepository {
  final AppDatabase database;
  BookmarkRepository(this.database);

  Future<int> saveBookmark({
    required String url,
    String? title,
    String? platform,
  }) async {
    final detectedPlatform = platform ?? UrlParser.detectPlatform(url);
    final finalTitle = title ?? UrlParser.extractTitle(url);
    final entry = BookmarksCompanion.insert(
      url: url,
      title: finalTitle,
      platform: detectedPlatform,
    );
    return await database.into(database.bookmarks).insert(entry);
  }

  Future<List<Bookmark>> getAllBookmarks() async {
    final query = database.select(database.bookmarks);
    query.orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return await query.get();
  }

  Future<int> deleteBookmark(int id) async {
    return await (database.delete(database.bookmarks)
          ..where((t) => t.id.equals(id)))
        .go();
  }

  Future<void> updateBookmark({
    required int id,
    required String title,
    required String platform,
  }) async {
    await (database.update(database.bookmarks)
          ..where((t) => t.id.equals(id)))
        .write(BookmarksCompanion(
      title: Value(title),
      platform: Value(platform),
    ));
  }
}