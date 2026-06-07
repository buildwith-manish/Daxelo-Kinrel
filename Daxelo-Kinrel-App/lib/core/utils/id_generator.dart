// lib/core/utils/id_generator.dart
//
// DAXELO KINREL — Shared ID Generator
//
// Generates CUID-like IDs for database inserts.
// Since we use Supabase client directly (not Prisma), we must generate IDs ourselves.
// Uses Random to avoid duplicate IDs when generating in a tight loop
// (DateTime.now().microsecond doesn't change between iterations).
//
// Previously duplicated in:
//   - core/family/family_provider.dart
//   - core/database/repositories/offline_family_repository.dart
//   - features/feed/providers/feed_provider.dart

import 'dart:math';

/// Generate a CUID-like ID for database inserts.
///
/// Returns a full-length ID without truncation to maximise entropy
/// and avoid collisions (previous feed version truncated to 25 chars).
String generateId() {
  final timestamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final random = Random();
  final rand = List.generate(
    16,
    (_) => random.nextInt(36),
  ).map((v) => v.toRadixString(36)).join();
  // Use full ID without truncation to maximise entropy and avoid collisions.
  return 'c$timestamp$rand';
}
