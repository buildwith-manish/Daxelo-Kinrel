/// Data class for app settings that benefit from local caching.
/// Stores key-value pairs for settings like language, theme preferences, etc.
class AppSettingsEntry {
  int? isarId;

  /// Setting key (unique)
  late String key;

  /// Setting value (stored as string, deserialize on read)
  late String value;

  /// When this setting was last updated
  late String updatedAt;

  /// Create or update a setting
  static AppSettingsEntry create({
    required String key,
    required String value,
  }) {
    return AppSettingsEntry()
      ..key = key
      ..value = value
      ..updatedAt = DateTime.now().toIso8601String();
  }
}
