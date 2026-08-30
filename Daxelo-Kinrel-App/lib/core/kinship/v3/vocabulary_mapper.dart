// lib/core/kinship/v3/vocabulary_mapper.dart
//
// DAXELO KINREL — Deterministic Kinship Engine v3.0
// Vocabulary Mapper
//
// Maps a KinshipSignature to a human-readable kinship term.
// The engine NEVER returns relationship names — it returns only
// KinshipSignature objects. This mapper does the final translation.
//
// Adding term #5,397 requires ONLY a new entry here. No engine changes.

import 'kinship_signature.dart';

class VocabularyMapper {
  VocabularyMapper._();

  /// Resolves a [KinshipSignature] to a human-readable kinship term.
  ///
  /// Fallback chain:
  /// 1. Exact match on pathPattern + gender + consanguinity
  /// 2. Try without seniority
  /// 3. Try with genderAnchor: 'neutral'
  /// 4. Generic term
  /// 5. Compose descriptive term
  static String resolve(KinshipSignature sig) {
    // Try exact match
    final exact = _lookup(sig);
    if (exact != null) return exact;

    // Try without seniority (ignore birth order)
    final noSeniority = KinshipSignature(
      generationDelta: sig.generationDelta,
      pathPattern: sig.pathPattern,
      side: sig.side,
      consanguinity: sig.consanguinity,
      genderAnchor: sig.genderAnchor,
      seniority: 'none',
      removal: sig.removal,
      doubleKinship: sig.doubleKinship,
    );
    final noSenior = _lookup(noSeniority);
    if (noSenior != null) return noSenior;

    // Try with neutral gender
    final neutral = KinshipSignature(
      generationDelta: sig.generationDelta,
      pathPattern: sig.pathPattern,
      side: sig.side,
      consanguinity: sig.consanguinity,
      genderAnchor: 'neutral',
      seniority: 'none',
      removal: sig.removal,
      doubleKinship: sig.doubleKinship,
    );
    final neutralMatch = _lookup(neutral);
    if (neutralMatch != null) return neutralMatch;

    // Fallback: compose descriptive term
    return _composeDescriptive(sig);
  }

  /// Direct lookup in the vocabulary table.
  static String? _lookup(KinshipSignature sig) {
    // ── Direct ancestors (generationDelta < 0, pattern starts with UP_PARENT) ──
    if (sig.pathPattern == 'UP_PARENT' && sig.generationDelta == -1) {
      if (sig.consanguinity == Consanguinity.adoptive) {
        return sig.genderAnchor == 'female' ? 'Adoptive Mother' : 'Adoptive Father';
      }
      if (sig.consanguinity == Consanguinity.step) {
        return sig.genderAnchor == 'female' ? 'Step Mother' : 'Step Father';
      }
      return sig.genderAnchor == 'female' ? 'Mother' : 'Father';
    }

    if (sig.pathPattern == 'UP_PARENT_UP_PARENT' && sig.generationDelta == -2) {
      if (sig.side == FamilySide.paternal) {
        return sig.genderAnchor == 'female' ? 'Grandmother (Paternal)' : 'Grandfather (Paternal)';
      }
      return sig.genderAnchor == 'female' ? 'Grandmother (Maternal)' : 'Grandfather (Maternal)';
    }

    if (sig.pathPattern == 'UP_PARENT_UP_PARENT_UP_PARENT' && sig.generationDelta == -3) {
      return sig.genderAnchor == 'female' ? 'Great Grandmother' : 'Great Grandfather';
    }

    // ── Direct descendants (generationDelta > 0, pattern with DOWN_CHILD) ──
    if (sig.pathPattern == 'DOWN_CHILD' && sig.generationDelta == 1) {
      return sig.genderAnchor == 'female' ? 'Daughter' : 'Son';
    }

    if (sig.pathPattern == 'DOWN_CHILD_DOWN_CHILD' && sig.generationDelta == 2) {
      return sig.genderAnchor == 'female' ? 'Granddaughter' : 'Grandson';
    }

    if (sig.pathPattern == 'DOWN_CHILD_DOWN_CHILD_DOWN_CHILD' && sig.generationDelta == 3) {
      return sig.genderAnchor == 'female' ? 'Great Granddaughter' : 'Great Grandson';
    }

    // ── Siblings (generationDelta == 0, pattern UP_PARENT_DOWN_CHILD) ──
    if (sig.pathPattern == 'UP_PARENT_DOWN_CHILD' && sig.generationDelta == 0) {
      final genderLabel = sig.genderAnchor == 'female' ? 'Sister' : 'Brother';
      switch (sig.consanguinity) {
        case Consanguinity.blood:
          if (sig.seniority == 'elder') return 'Elder $genderLabel';
          if (sig.seniority == 'younger') return 'Younger $genderLabel';
          return genderLabel;
        case Consanguinity.half:
          return 'Half $genderLabel';
        case Consanguinity.step:
          return 'Step $genderLabel';
        case Consanguinity.adoptive:
          return 'Adoptive $genderLabel';
        case Consanguinity.inLaw:
          return genderLabel; // shouldn't happen for siblings
      }
    }

    // ── Uncle/Aunt (generationDelta == -1, pattern UP_PARENT_DOWN_CHILD
    //    but through grandparent — pattern is UP_PARENT_UP_PARENT_DOWN_CHILD) ──
    if (sig.pathPattern == 'UP_PARENT_UP_PARENT_DOWN_CHILD' && sig.generationDelta == -1) {
      if (sig.side == FamilySide.paternal) {
        return sig.genderAnchor == 'female' ? 'Aunt (Paternal)' : 'Uncle (Paternal)';
      }
      return sig.genderAnchor == 'female' ? 'Aunt (Maternal)' : 'Uncle (Maternal)';
    }

    // Great uncle/aunt
    if (sig.pathPattern == 'UP_PARENT_UP_PARENT_UP_PARENT_DOWN_CHILD' && sig.generationDelta == -2) {
      return sig.genderAnchor == 'female' ? 'Great Aunt' : 'Great Uncle';
    }

    // ── Nephew/Niece (generationDelta == 1, pattern UP_PARENT_DOWN_CHILD_DOWN_CHILD) ──
    if (sig.pathPattern == 'UP_PARENT_DOWN_CHILD_DOWN_CHILD' && sig.generationDelta == 1) {
      return sig.genderAnchor == 'female' ? 'Niece' : 'Nephew';
    }

    // ── Cousins (generationDelta == 0, complex pattern) ──
    if (sig.pathPattern == 'UP_PARENT_UP_PARENT_DOWN_CHILD_DOWN_CHILD' && sig.generationDelta == 0) {
      if (sig.doubleKinship) return 'Double Cousin';
      return 'Cousin';
    }

    // First cousin once removed
    if (sig.pathPattern == 'UP_PARENT_UP_PARENT_DOWN_CHILD_DOWN_CHILD_DOWN_CHILD' ||
        sig.pathPattern == 'UP_PARENT_UP_PARENT_UP_PARENT_DOWN_CHILD_DOWN_CHILD') {
      if (sig.removal == 1) return 'Cousin (Once Removed)';
      if (sig.removal == 2) return 'Cousin (Twice Removed)';
      return 'Cousin';
    }

    // Second cousin
    if (sig.pathPattern == 'UP_PARENT_UP_PARENT_UP_PARENT_DOWN_CHILD_DOWN_CHILD_DOWN_CHILD' &&
        sig.generationDelta == 0) {
      return 'Second Cousin';
    }

    // ── In-laws (pattern starts with SPOUSE) ──
    if (sig.pathPattern == 'SPOUSE_UP_PARENT' && sig.generationDelta == -1) {
      return sig.genderAnchor == 'female' ? 'Mother-in-Law' : 'Father-in-Law';
    }

    if (sig.pathPattern == 'SPOUSE_UP_PARENT_UP_PARENT' && sig.generationDelta == -2) {
      return sig.genderAnchor == 'female' ? 'Grandmother-in-Law' : 'Grandfather-in-Law';
    }

    if (sig.pathPattern == 'SPOUSE_UP_PARENT_DOWN_CHILD' && sig.generationDelta == 0) {
      return sig.genderAnchor == 'female' ? 'Sister-in-Law' : 'Brother-in-Law';
    }

    if (sig.pathPattern == 'SPOUSE_DOWN_CHILD' && sig.generationDelta == 1) {
      return sig.genderAnchor == 'female' ? 'Daughter-in-Law' : 'Son-in-Law';
    }

    // ── Spouse ──
    if (sig.pathPattern == 'SPOUSE' && sig.generationDelta == 0) {
      return sig.genderAnchor == 'female' ? 'Wife' : 'Husband';
    }

    return null; // No match — caller will try fallbacks
  }

  /// Composes a descriptive term as a last resort.
  static String _composeDescriptive(KinshipSignature sig) {
    final parts = <String>[];

    if (sig.consanguinity == Consanguinity.half) parts.add('Half');
    if (sig.consanguinity == Consanguinity.step) parts.add('Step');
    if (sig.consanguinity == Consanguinity.adoptive) parts.add('Adoptive');
    if (sig.consanguinity == Consanguinity.inLaw) parts.add('In-Law');

    if (sig.generationDelta < -2) parts.add('Great');
    if (sig.generationDelta == -2) parts.add('Grand');
    if (sig.generationDelta < 0) {
      parts.add(sig.genderAnchor == 'female' ? 'Mother' : 'Father');
    } else if (sig.generationDelta > 2) {
      parts.add('Great');
      parts.add(sig.genderAnchor == 'female' ? 'Granddaughter' : 'Grandson');
    } else if (sig.generationDelta == 2) {
      parts.add(sig.genderAnchor == 'female' ? 'Granddaughter' : 'Grandson');
    } else if (sig.generationDelta == 1) {
      parts.add(sig.genderAnchor == 'female' ? 'Daughter' : 'Son');
    } else {
      parts.add(sig.genderAnchor == 'female' ? 'Relative' : 'Relative');
    }

    return parts.join(' ');
  }
}
