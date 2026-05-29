import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_database.dart';
import 'isar_database.dart';

/// Provider for the singleton AppDatabase instance managed by IsarDatabase.
/// Uses the existing singleton instead of creating a new AppDatabase per read,
/// which would leak SQLite connections.
final databaseProvider = Provider<AppDatabase>((ref) {
  return IsarDatabase.instance;
  // Do NOT dispose here — IsarDatabase manages the singleton lifecycle.
});
