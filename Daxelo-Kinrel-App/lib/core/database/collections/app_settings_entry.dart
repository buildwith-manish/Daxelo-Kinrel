import 'package:isar/isar.dart';

part 'app_settings_entry.g.dart';

/// Isar collection for app settings that benefit from local caching.
/// Stores key-value pairs for settings like language, theme preferences, etc.
@Collection()
class AppSettingsEntry {
  Id isarId = Isar.autoIncrement;

  /// Setting key (unique)
  @Index(unique: true, replace: true)
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
