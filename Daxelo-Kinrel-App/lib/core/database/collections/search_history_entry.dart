import 'package:isar/isar.dart';

part 'search_history_entry.g.dart';

/// Isar collection for search history entries.
/// Replaces the Hive-based search history with a more robust Isar collection.
@Collection()
class SearchHistoryEntry {
  Id isarId = Isar.autoIncrement;

  /// The search query text
  @Index()
  late String query;

  /// When this search was performed
  late String searchedAt;

  /// Type of search filter used
  late String filterType;

  /// Number of results found
  late int resultCount;

  /// Create a new search history entry
  static SearchHistoryEntry create({
    required String query,
    String filterType = 'all',
    int resultCount = 0,
  }) {
    return SearchHistoryEntry()
      ..query = query
      ..searchedAt = DateTime.now().toIso8601String()
      ..filterType = filterType
      ..resultCount = resultCount;
  }
}
