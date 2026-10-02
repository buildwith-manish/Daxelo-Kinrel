// lib/core/family/family_insights_service.dart
//
// ┌─────────────────────────────────────────────────────────────────────┐
// │  FAMILY INSIGHTS SERVICE — "Your family spans 3 generations"         │
// └─────────────────────────────────────────────────────────────────────┘
//
// WHY THIS EXISTS
// ───────────────
// Users build a family tree but never get a summary of what they've
// accomplished. Billion-dollar apps (Strava, Spotify Wrapped, Notion)
// surface "insights" that make the user feel their effort was
// worthwhile — and give them something shareable.
//
// This service computes aggregated stats from the FamilyDetail:
//   - Total members
//   - Number of generations (depth of the tree)
//   - Number of relationships mapped
//   - Gender distribution
//   - Age range (oldest to youngest, if DOBs are present)
//   - Number of couples (spouse relationships)
//   - Number of parent-child relationships
//
// The dashboard renders these as a beautiful, shareable card.
//
// PSYCHOLOGICAL PRINCIPLE: PROGRESS VISUALIZATION + SOCIAL CURRENCY
// ─────────────────────────────────────────────────────────────────────
//   • Progress Visualization: seeing "47 members, 3 generations" makes
//     the user's effort tangible. This drives continued engagement.
//   • Social Currency: sharing "My family spans 3 generations" on
//     WhatsApp makes the sharer look proud + drives app installs.
//
// PERFORMANCE
// ───────────
//   • Pure synchronous computation from in-memory lists — <1ms.
//   • No network calls, no Supabase queries.
//   • Gated behind premium (canViewInsights) — soft paywall.

import 'family_provider.dart';

/// Aggregated insights about a family, computed from FamilyDetail.
class FamilyInsights {
  const FamilyInsights({
    required this.familyName,
    required this.memberCount,
    required this.generationCount,
    required this.relationshipCount,
    required this.coupleCount,
    required this.parentChildCount,
    required this.oldestAge,
    required this.youngestAge,
    required this.genderSplit,
    required this.completenessPercent,
  });

  /// The family's display name.
  final String familyName;

  /// Total members in the family.
  final int memberCount;

  /// Number of generations (depth of the tree, 1 = flat).
  final int generationCount;

  /// Total relationships mapped.
  final int relationshipCount;

  /// Number of spouse/couple relationships.
  final int coupleCount;

  /// Number of parent-child relationships.
  final int parentChildCount;

  /// Age of the oldest member (null if no DOBs).
  final int? oldestAge;

  /// Age of the youngest member (null if no DOBs).
  final int? youngestAge;

  /// Gender distribution: { 'male': N, 'female': M, 'other': K }.
  final Map<String, int> genderSplit;

  /// Profile completeness (0-100). Based on: members with DOBs,
  /// avatars, and at least one relationship.
  final int completenessPercent;

  /// A short headline for the dashboard, e.g.:
  /// "3 generations · 47 members · 12 relationships"
  String get headline {
    final parts = <String>[];
    if (generationCount > 1) parts.add('$generationCount generations');
    parts.add('$memberCount ${memberCount == 1 ? 'member' : 'members'}');
    if (relationshipCount > 0) {
      parts.add('$relationshipCount ${relationshipCount == 1 ? 'relationship' : 'relationships'}');
    }
    return parts.join(' · ');
  }

  /// A pride-worthy summary line, e.g.:
  /// "Your family spans 3 generations — from 8 months to 87 years."
  String get prideSummary {
    if (oldestAge != null && youngestAge != null && oldestAge != youngestAge) {
      return 'Your family spans $generationCount ${generationCount == 1 ? 'generation' : 'generations'} '
          '— from $youngestAge ${youngestAge == 1 ? 'year' : 'years'} to $oldestAge years.';
    }
    return 'Your family has $memberCount ${memberCount == 1 ? 'member' : 'members'} '
        'across $generationCount ${generationCount == 1 ? 'generation' : 'generations'}.';
  }
}

/// Computes [FamilyInsights] from a [FamilyDetail].
class FamilyInsightsService {
  FamilyInsightsService._();

  /// Computes insights from the given FamilyDetail.
  ///
  /// Pure synchronous computation — safe to call in build().
  static FamilyInsights compute(FamilyDetail detail) {
    final members = detail.members;
    final relationships = detail.relationships;

    final memberCount = members.length;

    // ── Generation count: find the max generation index among members.
    int generationCount = 1;
    for (final m in members) {
      if ((m.generationIndex ?? 0) + 1 > generationCount) {
        generationCount = (m.generationIndex ?? 0) + 1;
      }
    }

    // ── Relationship counts by type.
    int coupleCount = 0;
    int parentChildCount = 0;
    for (final rel in relationships) {
      final key = rel.relationshipKey.toLowerCase();
      if (key.contains('spouse') ||
          key.contains('husband') ||
          key.contains('wife') ||
          key.contains('partner')) {
        coupleCount++;
      } else if (key.contains('father') ||
          key.contains('mother') ||
          key.contains('son') ||
          key.contains('daughter') ||
          key.contains('parent')) {
        parentChildCount++;
      }
    }

    // ── Age range (if DOBs present).
    int? oldestAge;
    int? youngestAge;
    final now = DateTime.now();
    for (final m in members) {
      final dobStr = m.dateOfBirth;
      if (dobStr == null || dobStr.isEmpty) continue;
      final dob = DateTime.tryParse(dobStr);
      if (dob == null) continue;
      final age = now.difference(dob).inDays ~/ 365;
      if (age < 0) continue; // future date — skip
      if (oldestAge == null || age > oldestAge) oldestAge = age;
      if (youngestAge == null || age < youngestAge) youngestAge = age;
    }

    // ── Gender split.
    final genderSplit = <String, int>{};
    for (final m in members) {
      final g = (m.gender ?? 'unknown').toLowerCase();
      genderSplit[g] = (genderSplit[g] ?? 0) + 1;
    }

    // ── Completeness: what % of members have a DOB + gender + at least
    // one relationship? This gives the user a "your tree is 78% complete"
    // progress bar — the Zeigarnik Effect pulls them to fill the gaps.
    int withDob = 0;
    int withGender = 0;
    for (final m in members) {
      if (m.dateOfBirth != null && m.dateOfBirth!.isNotEmpty) withDob++;
      if (m.gender != null && m.gender!.isNotEmpty) withGender++;
    }
    final withRel = relationships.isNotEmpty ? memberCount : 0;
    final completeness = memberCount == 0
        ? 0
        : (((withDob + withGender + withRel) / (memberCount * 3)) * 100).round();

    return FamilyInsights(
      familyName: detail.family.name,
      memberCount: memberCount,
      generationCount: generationCount,
      relationshipCount: relationships.length,
      coupleCount: coupleCount,
      parentChildCount: parentChildCount,
      oldestAge: oldestAge,
      youngestAge: youngestAge,
      genderSplit: genderSplit,
      completenessPercent: completeness.clamp(0, 100),
    );
  }
}
