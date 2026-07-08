// lib/features/aura/data/archetype_strings.dart
//
// AURA — Archetype display strings (Phase 11.2).
//
// Source of truth for the 6 archetype names + 2-line poetic descriptions.
// Mirrors the backend `ARCHETYPES` table in
// server/src/aura/archetype-classifier.service.ts.
//
// The descriptions live in code (not in .arb) because:
//   1. They are 8-language poetic copy — localizing via .arb would inflate
//      the l10n bundle with 6×8×2 = 96 strings that the rest of the app
//      doesn't use.
//   2. They are tightly coupled to the archetype enum: any change to the
//      archetype set requires a code change here anyway.
//
// Per the implementation guide deviation #6: only `app_en.arb` is hand-
// edited for the rest of the AURA UI (nav label, empty/loading/error states).
// The 30 non-English .arb files remain on the English fallback until a
// follow-up translation pass.

import 'aura_model.dart';

/// Display strings for one archetype.
class ArchetypeStrings {
  const ArchetypeStrings({
    required this.name,
    required this.description,
  });

  /// Short display name (e.g. "The Banyan").
  final String name;

  /// Two-line poetic description. Newline separates the two lines so
  /// the widget can render them with a paragraph break.
  final String description;
}

/// Lookup the display strings for an archetype.
///
/// Always returns a non-null value — falls back to [ArchetypeType.lotus]
/// for any unknown key (matches the backend's getDefinition fallback).
ArchetypeStrings archetypeStrings(ArchetypeType type) {
  switch (type) {
    case ArchetypeType.banyan:
      return const ArchetypeStrings(
        name: 'The Banyan',
        description:
            'One or two roots hold the entire family in their shade.\n'
            'Strength passes through you, generation to generation.',
      );
    case ArchetypeType.riverDelta:
      return const ArchetypeStrings(
        name: 'The River Delta',
        description:
            'Your family flows outward, branching into the world.\n'
            'Each branch carries the same river — born from the same source.',
      );
    case ArchetypeType.confluence:
      return const ArchetypeStrings(
        name: 'The Confluence',
        description:
            "Many rivers have joined at your family's heart.\n"
            'You are richer for every stream that chose to merge.',
      );
    case ArchetypeType.spine:
      return const ArchetypeStrings(
        name: 'The Spine',
        description:
            'Yours is a family of deep roots and tall lineage.\n'
            'Every generation stands on the shoulders of the last.',
      );
    case ArchetypeType.lotus:
      return const ArchetypeStrings(
        name: 'The Lotus',
        description:
            'A strong center holds, while new petals are still unfolding.\n'
            'Your family is becoming — not yet complete, and more beautiful for it.',
      );
    case ArchetypeType.forest:
      return const ArchetypeStrings(
        name: 'The Forest',
        description:
            'Many trees, each strong in their own right.\n'
            'Your family needs no single center — you are strongest together.',
      );
  }
}

/// Lookup the localized name for a role glyph (root/anchor/bridge/...).
/// Returns the English label; non-English translations are a follow-up.
String roleLabel(String roleKey) {
  switch (roleKey) {
    case 'root':
      return 'Root';
    case 'anchor':
      return 'Anchor';
    case 'bridge':
      return 'Bridge';
    case 'weaver':
      return 'Weaver';
    case 'leaf':
      return 'Leaf';
    case 'twin_node':
      return 'Twin';
    default:
      return 'Leaf';
  }
}
