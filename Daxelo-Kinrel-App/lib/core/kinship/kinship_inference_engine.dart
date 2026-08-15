// lib/core/kinship/kinship_inference_engine.dart
//
// DAXELO KINREL — Smart Kinship Inference Engine (v5.1)
//
// Automatically detects the most likely FUNDAMENTAL relationship between
// two family members using multiple signals:
//   1. Gender of both people
//   2. Birth year (age delta)
//   3. Existing family structure (what's missing?)
//   4. Direction of the "Relate to" action
//
// Returns a RANKED list of candidate relationships. The caller tries
// each one in order until validation passes — so the user NEVER sees
// an error or a picker. The first valid inference is created instantly.
//
// Why inference instead of a manual picker?
//   The user wants the system to "automatically detect, calculate, and
//   establish the appropriate kinship relationship between people
//   without requiring manual selection from a limited list." This engine
//   does exactly that — it uses genealogical heuristics to pick the
//   most likely fundamental edge, with a fallback chain so it never
//   fails.
//
// Storage convention:
//   from=A, to=B, key=X means "A's X is B" (e.g. A's father is B).
//   So if we infer that B is A's father, we store from=A, to=B, key=father.

import '../family/family_provider.dart' show Person, FamilyRelationship;

/// A candidate relationship inferred by the engine.
class InferredRelationship {
  const InferredRelationship({
    required this.key,
    required this.confidence,
    required this.reason,
  });

  /// The fundamental kinship key to store.
  /// One of: father, mother, parent, son, daughter, child,
  /// husband, wife, spouse, brother, sister, sibling.
  final String key;

  /// Confidence score 0.0 - 1.0 (higher = more likely).
  final double confidence;

  /// Human-readable reason for this inference.
  final String reason;
}

/// Smart Kinship Inference Engine.
///
/// Analyzes two people + their family context and returns a RANKED list
/// of candidate fundamental relationships. The caller tries each one
/// until validation passes.
class KinshipInferenceEngine {
  KinshipInferenceEngine._();

  /// Infers the most likely fundamental relationships between
  /// [personA] (the source / anchor of the "Relate to" action) and
  /// [personB] (the target person being connected).
  ///
  /// [existingRelationships] — all current relationships in the family,
  /// used to detect what's missing (e.g. if A has no spouse, spouse
  /// is a higher-confidence inference).
  ///
  /// Returns a list sorted by confidence (highest first). The list
  /// always contains at least 4 candidates (one per fundamental type)
  /// so the fallback chain can always find a valid option.
  static List<InferredRelationship> infer({
    required Person personA,
    required Person personB,
    required List<FamilyRelationship> existingRelationships,
  }) {
    final candidates = <InferredRelationship>[];
    final now = DateTime.now().year;

    // ── Compute ages (if birth year available) ──
    final ageA = personA.birthYear != null ? now - personA.birthYear! : null;
    final ageB = personB.birthYear != null ? now - personB.birthYear! : null;
    final ageDiff = (ageA != null && ageB != null) ? (ageB - ageA) : null;

    final genderA = personA.gender?.toLowerCase();
    final genderB = personB.gender?.toLowerCase();

    // ── Check existing structure ──
    final aHasFather = existingRelationships.any((r) =>
        r.fromPersonId == personA.id &&
        (r.relationshipKey == 'father' ||
            r.relationshipKey == 'mother' ||
            r.relationshipKey == 'parent'));
    final aHasMother = existingRelationships.any((r) =>
        r.fromPersonId == personA.id && r.relationshipKey == 'mother');
    final aHasSpouse = existingRelationships.any((r) =>
        r.fromPersonId == personA.id &&
        (r.relationshipKey == 'spouse' ||
            r.relationshipKey == 'husband' ||
            r.relationshipKey == 'wife'));
    final aHasSibling = existingRelationships.any((r) =>
        r.fromPersonId == personA.id &&
        (r.relationshipKey == 'brother' ||
            r.relationshipKey == 'sister' ||
            r.relationshipKey == 'sibling'));

    // ── RULE 1: Age-based parent/child inference ──
    // If B is 15+ years older than A → likely B is A's parent
    if (ageDiff != null && ageDiff >= 15) {
      if (genderB == 'female') {
        candidates.add(InferredRelationship(
          key: 'mother',
          confidence: 0.85,
          reason: '${personB.name} is ${ageDiff} years older (mother)',
        ));
      } else if (genderB == 'male') {
        candidates.add(InferredRelationship(
          key: 'father',
          confidence: 0.85,
          reason: '${personB.name} is ${ageDiff} years older (father)',
        ));
      } else {
        candidates.add(InferredRelationship(
          key: 'parent',
          confidence: 0.75,
          reason: '${personB.name} is ${ageDiff} years older (parent)',
        ));
      }
    }

    // If B is 15+ years younger than A → likely B is A's child
    if (ageDiff != null && ageDiff <= -15) {
      if (genderB == 'female') {
        candidates.add(InferredRelationship(
          key: 'daughter',
          confidence: 0.85,
          reason: '${personB.name} is ${(-ageDiff)} years younger (daughter)',
        ));
      } else if (genderB == 'male') {
        candidates.add(InferredRelationship(
          key: 'son',
          confidence: 0.85,
          reason: '${personB.name} is ${(-ageDiff)} years younger (son)',
        ));
      } else {
        candidates.add(InferredRelationship(
          key: 'child',
          confidence: 0.75,
          reason: '${personB.name} is ${(-ageDiff)} years younger (child)',
        ));
      }
    }

    // ── RULE 2: Similar-age inference (sibling or spouse) ──
    if (ageDiff == null || (ageDiff.abs() < 15)) {
      final sameGender = genderA == genderB;

      if (!sameGender && !aHasSpouse) {
        // Opposite gender, similar age, A has no spouse → likely spouse
        if (genderB == 'female') {
          candidates.add(InferredRelationship(
            key: 'wife',
            confidence: 0.70,
            reason: 'Opposite gender, similar age, no existing spouse (wife)',
          ));
        } else if (genderB == 'male') {
          candidates.add(InferredRelationship(
            key: 'husband',
            confidence: 0.70,
            reason: 'Opposite gender, similar age, no existing spouse (husband)',
          ));
        } else {
          candidates.add(InferredRelationship(
            key: 'spouse',
            confidence: 0.60,
            reason: 'Opposite gender, similar age, no existing spouse',
          ));
        }
      }

      // Sibling inference (always add as a candidate)
      if (genderB == 'female') {
        candidates.add(InferredRelationship(
          key: 'sister',
          confidence: sameGender ? 0.65 : 0.45,
          reason: sameGender
              ? 'Same gender, similar age (sister)'
              : 'Similar age (sister)',
        ));
      } else if (genderB == 'male') {
        candidates.add(InferredRelationship(
          key: 'brother',
          confidence: sameGender ? 0.65 : 0.45,
          reason: sameGender
              ? 'Same gender, similar age (brother)'
              : 'Similar age (brother)',
        ));
      } else {
        candidates.add(InferredRelationship(
          key: 'sibling',
          confidence: 0.50,
          reason: 'Similar age (sibling)',
        ));
      }
    }

    // ── RULE 3: Fill in missing parent if no age info ──
    if (ageDiff == null && !aHasFather) {
      if (genderB == 'female' && !aHasMother) {
        candidates.add(InferredRelationship(
          key: 'mother',
          confidence: 0.40,
          reason: 'No mother assigned yet',
        ));
      } else if (genderB == 'male') {
        candidates.add(InferredRelationship(
          key: 'father',
          confidence: 0.40,
          reason: 'No father assigned yet',
        ));
      }
    }

    // ── FALLBACK: Ensure we have at least one candidate per fundamental type ──
    // This guarantees the caller can always find a valid option.
    final existingKeys = candidates.map((c) => c.key).toSet();

    // Add spouse as a fallback (if not already present)
    if (!existingKeys.contains('wife') &&
        !existingKeys.contains('husband') &&
        !existingKeys.contains('spouse')) {
      if (genderB == 'female') {
        candidates.add(InferredRelationship(
          key: 'wife',
          confidence: 0.30,
          reason: 'Fallback (wife)',
        ));
      } else if (genderB == 'male') {
        candidates.add(InferredRelationship(
          key: 'husband',
          confidence: 0.30,
          reason: 'Fallback (husband)',
        ));
      } else {
        candidates.add(InferredRelationship(
          key: 'spouse',
          confidence: 0.25,
          reason: 'Fallback (spouse)',
        ));
      }
    }

    // Add parent as a fallback
    if (!existingKeys.contains('father') &&
        !existingKeys.contains('mother') &&
        !existingKeys.contains('parent')) {
      if (genderB == 'female') {
        candidates.add(InferredRelationship(
          key: 'mother',
          confidence: 0.25,
          reason: 'Fallback (mother)',
        ));
      } else if (genderB == 'male') {
        candidates.add(InferredRelationship(
          key: 'father',
          confidence: 0.25,
          reason: 'Fallback (father)',
        ));
      } else {
        candidates.add(InferredRelationship(
          key: 'parent',
          confidence: 0.20,
          reason: 'Fallback (parent)',
        ));
      }
    }

    // Add child as a fallback
    if (!existingKeys.contains('son') &&
        !existingKeys.contains('daughter') &&
        !existingKeys.contains('child')) {
      if (genderB == 'female') {
        candidates.add(InferredRelationship(
          key: 'daughter',
          confidence: 0.25,
          reason: 'Fallback (daughter)',
        ));
      } else if (genderB == 'male') {
        candidates.add(InferredRelationship(
          key: 'son',
          confidence: 0.25,
          reason: 'Fallback (son)',
        ));
      } else {
        candidates.add(InferredRelationship(
          key: 'child',
          confidence: 0.20,
          reason: 'Fallback (child)',
        ));
      }
    }

    // Add sibling as a fallback
    if (!existingKeys.contains('brother') &&
        !existingKeys.contains('sister') &&
        !existingKeys.contains('sibling')) {
      if (genderB == 'female') {
        candidates.add(InferredRelationship(
          key: 'sister',
          confidence: 0.25,
          reason: 'Fallback (sister)',
        ));
      } else if (genderB == 'male') {
        candidates.add(InferredRelationship(
          key: 'brother',
          confidence: 0.25,
          reason: 'Fallback (brother)',
        ));
      } else {
        candidates.add(InferredRelationship(
          key: 'sibling',
          confidence: 0.20,
          reason: 'Fallback (sibling)',
        ));
      }
    }

    // ── Sort by confidence (highest first) ──
    candidates.sort((a, b) => b.confidence.compareTo(a.confidence));

    return candidates;
  }

  /// Returns a human-readable label for a kinship key.
  /// e.g. 'father' → 'Father', 'paternal_uncle' → 'Paternal Uncle'
  static String labelFor(String key) {
    return key.split('_').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');
  }
}
