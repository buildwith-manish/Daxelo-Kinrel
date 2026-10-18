// lib/features/sparq_tray/providers/moment_sparq_provider.dart
//
// DAXELO KINREL — Moment Sparq provider (client-generated cards).
//
// A Moment Sparq is a CLIENT-GENERATED card, not stored on the server,
// not counted in viewer counts, and shown as the first item in a
// family's run. Sources, in priority order:
//   1. birthday today (or within 3 days)
//   2. anniversary today
//   3. festival today
//   4. "on this day" memory
//
// Show at most ONE Moment Sparq per family per day (highest priority
// wins). Shown only for the viewer's own families, only once the
// occasion data for that family is loaded.
//
// Seen state is LOCAL: persisted via `shared_preferences` with key
// `sparq_moment_seen_{momentId}_{yyyyMMdd}`. A seen Moment Sparq
// becomes an outline gold petal and disappears the next day.

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/family/family_provider.dart'
    show familyListProvider;
import '../../occasions/providers/occasion_reminders_provider.dart'
    show OccasionItem, OccasionType, familyOccasionsProvider;
import '../data/family_sparq_tray_item.dart';

/// Key prefix for the local seen-state of Moment Sparqs in
/// SharedPreferences.
const _kSeenKeyPrefix = 'sparq_moment_seen_';

/// The viewer's own families (just the IDs — used to gate which
/// families get a Moment Sparq).
final _viewerFamilyIdsProvider = Provider<Set<String>>((ref) {
  final families = ref.watch(familyListProvider).valueOrNull ?? [];
  return {for (final f in families) f.id};
});

/// The Moment Sparq for a family for today, or null when none applies.
///
/// Priority order:
///   1. birthday today (or within 3 days) — highest
///   2. anniversary today
///   3. festival today (TODO step 7 — no live festival-today provider
///      yet; the festival_cards module only generates templates on
///      demand. Skipped for now, falls through to the next source.)
///   4. "on this day" memory (TODO step 7 — the crossFeatureMoments
///      provider surfaces ORAL_HISTORY / MEMORY_VAULT / QUIZ_RESULT
///      events, none of which are "on this day". The "on this day"
///      surface lives in the Memory Vault feature. Skipped for now.)
///
/// Show at most ONE per family per day. The viewer's own families
/// only. Local-only — never counted as a viewed Sparq on the server.
final familyMomentSparqProvider =
    Provider.family<MomentSparq?, String>((ref, familyId) {
  // Only the viewer's own families.
  final viewerFamilyIds = ref.watch(_viewerFamilyIdsProvider);
  if (!viewerFamilyIds.contains(familyId)) return null;

  // Watch the family-scoped occasions (already-loaded members drive
  // this). Returns an empty list when the family detail hasn't
  // loaded yet — that satisfies the "only once occasion data is
  // loaded" gate.
  final occasions = ref.watch(familyOccasionsProvider(familyId));
  if (occasions.isEmpty) return null;

  // Priority 1: birthday today or within 3 days.
  for (final occ in occasions) {
    if (occ.type == OccasionType.birthday && occ.daysUntil <= 3) {
      final moment = MomentSparq(
        id: 'birthday_${occ.personId}',
        familyId: familyId,
        headline: _birthdayHeadline(occ),
        relationLine: '', // relation line resolved in the run screen
        eventType: MomentEventType.birthday,
        date: occ.nextOccurrence,
        subtitle: occ.photoUrl,
      );
      return moment;
    }
  }

  // Priority 2: anniversary today.
  for (final occ in occasions) {
    if (occ.type == OccasionType.anniversary && occ.daysUntil == 0) {
      final moment = MomentSparq(
        id: 'anniversary_${occ.personId}',
        familyId: familyId,
        headline: _anniversaryHeadline(occ),
        relationLine: '',
        eventType: MomentEventType.anniversary,
        date: occ.nextOccurrence,
        subtitle: occ.photoUrl,
      );
      return moment;
    }
  }

  // Priority 3 (festival today) + Priority 4 (on-this-day memory)
  // are stubbed — see file header. The provider still returns null
  // for these today; the tray ring renders empty kolam dots, which
  // is the correct "no Moment" state per spec.

  return null;
});

String _birthdayHeadline(OccasionItem occ) {
  // "Dadi turns 78 today" — compute the age from the next occurrence
  // (we'd need the dob from the Person row; the OccasionItem only
  // has nextOccurrence. Approximate using year diff against today).
  // If we can't compute an age, fall back to "{name}'s birthday".
  final now = DateTime.now();
  final years =
      now.year - occ.nextOccurrence.year; // crude — see Person.dateOfBirth.
  if (years > 0 && years < 130) {
    return '${occ.name} turns $years today';
  }
  return "${occ.name}'s birthday today";
}

String _anniversaryHeadline(OccasionItem occ) {
  return "${occ.name}'s anniversary today";
}

/// Mark a Moment Sparq as seen locally. Persists with key
/// `sparq_moment_seen_{momentId}_{yyyyMMdd}` so a Moment becomes
/// unseen again the next day.
Future<void> markMomentSparqSeen(MomentSparq moment) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_kSeenKeyPrefix${moment.seenKeySuffix}', true);
  } catch (e) {
    debugPrint('markMomentSparqSeen failed: $e');
  }
}

/// Whether a Moment Sparq has been marked seen locally for today.
/// Reads the same `sparq_moment_seen_{momentId}_{yyyyMMdd}` key.
Future<bool> isMomentSparqSeen(MomentSparq moment) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_kSeenKeyPrefix${moment.seenKeySuffix}') ?? false;
  } catch (e) {
    debugPrint('isMomentSparqSeen failed: $e');
    return false;
  }
}

/// Sync version for use inside Riverpod builders — returns false if
/// the prefs haven't been read yet (the build doesn't block).
/// Replaced by [isMomentSparqSeenStream] in a future step if needed.
bool isMomentSparqSeenSync(MomentSparq moment, SharedPreferences? prefs) {
  if (prefs == null) return false;
  return prefs.getBool('$_kSeenKeyPrefix${moment.seenKeySuffix}') ?? false;
}
