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
//
// This file is wired up in step 6 of the spec. For steps 1–5 it
// returns null for every family — the tray still works (Petal rings
// for member Sparqs render normally), Moment Sparqs simply do not
// appear yet. This keeps the early commits runnable.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/family_sparq_tray_item.dart';

/// Stub provider that returns null for every family. Replaced with
/// the real implementation in step 6 (after the run screen + tray
/// wiring are merged).
final familyMomentSparqProvider =
    Provider.family<MomentSparq?, String>((ref, familyId) {
  return null;
});
