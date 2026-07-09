// lib/features/pulse/providers/pulse_providers.dart
//
// DAXELO KINREL — Riverpod providers for Pulse + Pitru + Addictiveness
//
// All providers use AsyncNotifier (Riverpod 2.x pattern) for caching + invalidation.
// The familyId comes from the existing familyProvider (the user's current family).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/pulse_api_client.dart';
import '../data/pulse_models.dart';

// Re-export the API client provider for convenience
export '../data/pulse_api_client.dart' show pulseApiClientProvider;

// ═══════════════════════════════════════════════════════════════════════════
// PULSE — Daily Brief
// ═══════════════════════════════════════════════════════════════════════════

/// Today's brief. Auto-generates if not found (lazy generation before 7am cron).
final todayBriefProvider = FutureProvider<DailyBrief?>((ref) async {
  final client = ref.read(pulseApiClientProvider);
  try {
    var brief = await client.getTodayBrief();
    if (brief == null) {
      // Lazy generation — generate on first open of the day
      brief = await client.generateTodayBrief();
    }
    // Mark as viewed
    if (brief != null) {
      await client.markBriefViewed(brief.id);
    }
    return brief;
  } catch (e) {
    return null;
  }
});

/// Brief history (last 30 days).
final briefHistoryProvider = FutureProvider<List<DailyBrief>>((ref) async {
  final client = ref.read(pulseApiClientProvider);
  return client.getBriefHistory(days: 30, limit: 30);
});

// ═══════════════════════════════════════════════════════════════════════════
// PULSE — Weather + Streaks + Karma
// ═══════════════════════════════════════════════════════════════════════════

final weatherProvider = FutureProvider<List<RelationshipWeather>>((ref) async {
  final client = ref.read(pulseApiClientProvider);
  return client.getWeather();
});

final streaksProvider = FutureProvider<List<ConnectionStreak>>((ref) async {
  final client = ref.read(pulseApiClientProvider);
  return client.getStreaks();
});

final karmaProvider = FutureProvider<List<FamilyKarma>>((ref) async {
  final client = ref.read(pulseApiClientProvider);
  return client.getKarma();
});

// ═══════════════════════════════════════════════════════════════════════════
// PITRU — Ancestral Memories
// ═══════════════════════════════════════════════════════════════════════════

/// FamilyId provider — override this at the app root with the current family ID.
/// For now we use a placeholder that screens can override.
final currentFamilyIdProvider = StateProvider<String?>((ref) => null);

final memoriesProvider = FutureProvider.family<List<AncestralMemory>, String>((ref, familyId) async {
  final client = ref.read(pulseApiClientProvider);
  return client.listMemories(familyId, status: 'ready');
});

final memorialsProvider = FutureProvider.family<List<MemorialProfile>, String>((ref, familyId) async {
  final client = ref.read(pulseApiClientProvider);
  return client.listMemorials(familyId);
});

final memorialFeedProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, personId) async {
  final client = ref.read(pulseApiClientProvider);
  return client.getMemorialFeed(personId);
});

// ═══════════════════════════════════════════════════════════════════════════
// A-6 Festival Intelligence
// ═══════════════════════════════════════════════════════════════════════════

final upcomingFestivalsProvider = FutureProvider<List<Festival>>((ref) async {
  final client = ref.read(pulseApiClientProvider);
  return client.getUpcomingFestivals(days: 90);
});

final festivalsTodayProvider = FutureProvider<List<Festival>>((ref) async {
  final client = ref.read(pulseApiClientProvider);
  return client.getFestivalsToday();
});

// ═══════════════════════════════════════════════════════════════════════════
// A-1 Blessing Chain
// ═══════════════════════════════════════════════════════════════════════════

final blessingsForMeProvider = FutureProvider<List<BlessingChain>>((ref) async {
  final client = ref.read(pulseApiClientProvider);
  return client.getBlessingsForMe();
});

final familyBlessingsProvider = FutureProvider.family<List<BlessingChain>, String>((ref, familyId) async {
  final client = ref.read(pulseApiClientProvider);
  return client.listBlessings(familyId);
});

// ═══════════════════════════════════════════════════════════════════════════
// A-2 Time Capsule
// ═══════════════════════════════════════════════════════════════════════════

final capsulesForMeProvider = FutureProvider<List<TimeCapsule>>((ref) async {
  final client = ref.read(pulseApiClientProvider);
  return client.getTimeCapsulesForMe();
});

final familyCapsulesProvider = FutureProvider.family<List<TimeCapsule>, String>((ref, familyId) async {
  final client = ref.read(pulseApiClientProvider);
  return client.listTimeCapsules(familyId);
});

// ═══════════════════════════════════════════════════════════════════════════
// A-3 Family Quests
// ═══════════════════════════════════════════════════════════════════════════

final activeQuestsProvider = FutureProvider<List<FamilyQuest>>((ref) async {
  final client = ref.read(pulseApiClientProvider);
  return client.getActiveQuests();
});

final questHistoryProvider = FutureProvider<List<FamilyQuest>>((ref) async {
  final client = ref.read(pulseApiClientProvider);
  return client.getQuestHistory();
});

// ═══════════════════════════════════════════════════════════════════════════
// A-4 Silent Alarms
// ═══════════════════════════════════════════════════════════════════════════

final silentAlarmsProvider = FutureProvider<List<SilentAlarm>>((ref) async {
  final client = ref.read(pulseApiClientProvider);
  return client.getAlarms();
});

// ═══════════════════════════════════════════════════════════════════════════
// A-7 Family Chronicle
// ═══════════════════════════════════════════════════════════════════════════

final chronicleProvider = FutureProvider.family<FamilyChronicle?, String>((ref, familyId) async {
  final client = ref.read(pulseApiClientProvider);
  return client.getChronicle(familyId);
});
