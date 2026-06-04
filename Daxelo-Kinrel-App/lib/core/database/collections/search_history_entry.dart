/// Data class for search history entries.
class SearchHistoryEntry {
  int? isarId;

  /// The search query text
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
