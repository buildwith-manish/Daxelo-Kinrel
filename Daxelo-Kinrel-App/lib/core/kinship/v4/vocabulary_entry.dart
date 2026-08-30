// lib/core/kinship/v4/vocabulary_entry.dart
//
// DAXELO-KINREL — v4.0 Vocabulary System (Phase 6)
//
// A scalable vocabulary layer that maps KinshipSignature → kinship term.
// Each entry specifies: signature fields, locale, region, gender, seniority,
// term, aliases, and notes.
//
// Adding term #5,397 or #50,001 requires ONLY a new VocabularyEntry.
// Zero engine changes. Zero signature changes.

import '../v3/kinship_signature.dart';

/// A single vocabulary entry mapping a signature to a kinship term.
class VocabularyEntry {
  const VocabularyEntry({
    required this.term,
    required this.locale,
    required this.pathPattern,
    required this.generationDelta,
    this.side,
    this.consanguinity,
    this.genderAnchor,
    this.seniority,
    this.intermediateSeniority,
    this.spouseSide,
    this.intermediateGender,
    this.removal,
    this.doubleKinship,
    this.aliases = const [],
    this.notes,
    this.region,
  });

  /// The human-readable kinship term (e.g. "Chacha", "Father", "Mama").
  final String term;

  /// ISO language code (e.g. 'en', 'hi', 'ta', 'te', 'kn', 'ml', 'bn', 'mr', 'gu', 'pa', 'ur').
  final String locale;

  /// Optional region within the language (e.g. 'north', 'south', 'east').
  final String? region;

  // ── Signature fields to match against ──
  final String pathPattern;
  final int generationDelta;
  final FamilySide? side;
  final Consanguinity? consanguinity;
  final String? genderAnchor;
  final String? seniority;
  final String? intermediateSeniority;
  final FamilySide? spouseSide;
  final String? intermediateGender;
  final int? removal;
  final bool? doubleKinship;

  /// Alternative spellings / colloquial variants.
  final List<String> aliases;

  /// Cultural notes about the term.
  final String? notes;

  /// Checks whether this entry matches the given signature fields.
  /// Null fields in the entry are treated as wildcards (match anything).
  bool matches({
    required String path,
    required int genDelta,
    required FamilySide famSide,
    required Consanguinity consang,
    required String gender,
    required String senior,
    required int remov,
    required bool isDouble,
    String? intSenior,
    FamilySide? sSide,
    String? intGender,
  }) {
    if (pathPattern != path) return false;
    if (generationDelta != genDelta) return false;
    if (side != null && side != famSide) return false;
    if (consanguinity != null && consanguinity != consang) return false;
    if (genderAnchor != null && genderAnchor != gender) return false;
    if (seniority != null && seniority != senior) return false;
    if (removal != null && removal != remov) return false;
    if (doubleKinship != null && doubleKinship != isDouble) return false;
    if (intermediateSeniority != null && intermediateSeniority != intSenior) return false;
    if (spouseSide != null && spouseSide != sSide) return false;
    if (intermediateGender != null && intermediateGender != intGender) return false;
    return true;
  }
}
