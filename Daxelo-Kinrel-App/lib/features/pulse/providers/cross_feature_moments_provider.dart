// lib/features/pulse/providers/cross_feature_moments_provider.dart
//
// DAXELO KINREL — Cross-feature Moment Surfacing
//
// Pulls "new memory unlocked", "grandma answered a quiz prompt", and
// "oral history clip recorded" events into the Family Pulse feed as
// first-class pulse items.
//
// This solves two problems:
// 1. Oral_history, memory_vault, and quiz results never feed back into
//    the Pulse feed — they're siloed features.
// 2. The Pulse feed has more content variety, giving users more reasons
//    to open the app daily.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';

class CrossFeatureMoment {
  final String id;
  final String type; // 'oral_history', 'memory_vault', 'quiz_result'
  final String title;
  final String? subtitle;
  final String? actorName;
  final DateTime createdAt;
  final String? deepLink;

  CrossFeatureMoment({
    required this.id,
    required this.type,
    required this.title,
    this.subtitle,
    this.actorName,
    required this.createdAt,
    this.deepLink,
  });

  String get emoji => switch (type) {
    'oral_history' => '🎙️',
    'memory_vault' => '📸',
    'quiz_result' => '🧠',
    _ => '✨',
  };
}

/// Fetches recent cross-feature moments for a family.
/// Pulls from Pitru memories (oral history), MemoryVault items, and
/// quiz game results, merges them by date, and returns the most recent N.
final crossFeatureMomentsProvider =
    FutureProvider.family<List<CrossFeatureMoment>, String>(
  (ref, familyId) async {
    final client = ref.read(supabaseProvider);
    if (client == null) return [];

    final moments = <CrossFeatureMoment>[];

    // 1. Oral history clips (from Pitru memories)
    try {
      final result = await client
          .from('PitruMemory')
          .select('id, title, transcription, createdAt, createdBy')
          .eq('familyId', familyId)
          .order('createdAt', ascending: false)
          .limit(5);
      for (final e in result) {
        moments.add(CrossFeatureMoment(
          id: e['id'] as String,
          type: 'oral_history',
          title: 'New oral history: ${e['title'] ?? 'Untitled'}',
          subtitle: _truncate(e['transcription'] as String?, 80),
          createdAt: DateTime.tryParse(e['createdAt'] as String? ?? '') ?? DateTime.now(),
          deepLink: '/memories?familyId=$familyId',
        ));
      }
    } catch (_) {}

    // 2. Memory vault items (photos with "On This Day")
    try {
      final result = await client
          .from('MemoryVaultItem')
          .select('id, title, caption, createdAt')
          .eq('familyId', familyId)
          .order('createdAt', ascending: false)
          .limit(5);
      for (final e in result) {
        moments.add(CrossFeatureMoment(
          id: e['id'] as String,
          type: 'memory_vault',
          title: 'New memory: ${e['title'] ?? 'Photo'}',
          subtitle: e['caption'] as String?,
          createdAt: DateTime.tryParse(e['createdAt'] as String? ?? '') ?? DateTime.now(),
          deepLink: '/memory-vault?familyId=$familyId',
        ));
      }
    } catch (_) {}

    // 3. Quiz game results
    try {
      final result = await client
          .from('GameSession')
          .select('id, gameType, score, createdAt, userId')
          .eq('familyId', familyId)
          .eq('status', 'completed')
          .order('createdAt', ascending: false)
          .limit(5);
      for (final e in result) {
        final gameType = e['gameType'] as String? ?? 'quiz';
        final score = e['score'] as int? ?? 0;
        moments.add(CrossFeatureMoment(
          id: e['id'] as String,
          type: 'quiz_result',
          title: 'Quiz completed: $gameType',
          subtitle: 'Score: $score',
          createdAt: DateTime.tryParse(e['createdAt'] as String? ?? '') ?? DateTime.now(),
          deepLink: '/games?familyId=$familyId',
        ));
      }
    } catch (_) {}

    // Sort by date descending and take top 8
    moments.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return moments.take(8).toList();
  },
);

String? _truncate(String? s, int n) {
  if (s == null) return null;
  return s.length > n ? '${s.substring(0, n)}...' : s;
}
