// lib/core/kinship/v3/canonical_id.dart
//
// DAXELO KINREL — Deterministic Kinship Engine v3.0
// Canonical Relationship ID Layer
//
// Maps all user-facing kinship terms, colloquial names, and regional
// variants to a single Canonical ID before entering the engine.
// This makes localization trivial and prevents duplicate storage.

/// The canonical relationship IDs. Only these map to fundamental
/// stored edges. Everything else is DERIVED.
enum CanonicalId {
  parent,           // → stored as 'parent'
  spouse,           // → stored as 'spouse'
  adoptiveParent,   // → stored as 'adoptive_parent'
  stepParent,       // → stored as 'step_parent'
  derived,          // NOT stored — derived at runtime (grandfather, uncle, etc.)
}

/// Maps a user-input kinship term to its CanonicalId.
/// Handles English + common Indian language variants.
class CanonicalIdMapper {
  CanonicalIdMapper._();

  /// Map of lowercase term → CanonicalId.
  /// Covers English, Hindi, Tamil, Telugu, Bengali, Marathi, etc.
  static const Map<String, CanonicalId> _termMap = {
    // ── Parent (father/mather variants) ──
    'father': CanonicalId.parent,
    'dad': CanonicalId.parent,
    'daddy': CanonicalId.parent,
    'papa': CanonicalId.parent,
    'appa': CanonicalId.parent,       // Tamil/Telugu
    'baba': CanonicalId.parent,       // Hindi/Marathi
    'abba': CanonicalId.parent,       // Urdu
    'nana': CanonicalId.parent,       // maternal grandfather (Hindi) — stored as parent of parent
    'dada': CanonicalId.parent,       // paternal grandfather (Hindi) — stored as parent of parent
    'mother': CanonicalId.parent,
    'mom': CanonicalId.parent,
    'mommy': CanonicalId.parent,
    'mummy': CanonicalId.parent,
    'amma': CanonicalId.parent,       // Tamil/Telugu/Kannada
    'maa': CanonicalId.parent,        // Hindi/Bengali
    'ummi': CanonicalId.parent,       // Urdu
    'parent': CanonicalId.parent,

    // ── Child (inverse of parent — user says "son/daughter") ──
    'son': CanonicalId.parent,        // inverse direction
    'daughter': CanonicalId.parent,  // inverse direction
    'beta': CanonicalId.parent,       // Hindi
    'beti': CanonicalId.parent,       // Hindi
    'putra': CanonicalId.parent,      // Sanskrit
    'putri': CanonicalId.parent,      // Sanskrit
    'child': CanonicalId.parent,

    // ── Spouse ──
    'husband': CanonicalId.spouse,
    'wife': CanonicalId.spouse,
    'spouse': CanonicalId.spouse,
    'pati': CanonicalId.spouse,       // Hindi
    'patni': CanonicalId.spouse,      // Hindi
    'miya': CanonicalId.spouse,       // Urdu
    'biwi': CanonicalId.spouse,       // Urdu

    // ── Adoptive parent ──
    'adoptive_father': CanonicalId.adoptiveParent,
    'adoptive_mother': CanonicalId.adoptiveParent,
    'adoptive_parent': CanonicalId.adoptiveParent,
    'adopted_father': CanonicalId.adoptiveParent,
    'adopted_mother': CanonicalId.adoptiveParent,

    // ── Step parent ──
    'step_father': CanonicalId.stepParent,
    'step_mother': CanonicalId.stepParent,
    'stepfather': CanonicalId.stepParent,
    'stepmother': CanonicalId.stepParent,
    'step_parent': CanonicalId.stepParent,

    // ── Derived (NOT stored — computed at runtime) ──
    'grandfather': CanonicalId.derived,
    'grandmother': CanonicalId.derived,
    'grandparent': CanonicalId.derived,
    'great_grandfather': CanonicalId.derived,
    'great_grandmother': CanonicalId.derived,
    'uncle': CanonicalId.derived,
    'aunt': CanonicalId.derived,
    'nephew': CanonicalId.derived,
    'niece': CanonicalId.derived,
    'cousin': CanonicalId.derived,
    'brother': CanonicalId.derived,
    'sister': CanonicalId.derived,
    'sibling': CanonicalId.derived,
    'elder_brother': CanonicalId.derived,
    'elder_sister': CanonicalId.derived,
    'younger_brother': CanonicalId.derived,
    'younger_sister': CanonicalId.derived,
    'half_brother': CanonicalId.derived,
    'half_sister': CanonicalId.derived,
    'step_brother': CanonicalId.derived,
    'step_sister': CanonicalId.derived,
    'father_in_law': CanonicalId.derived,
    'mother_in_law': CanonicalId.derived,
    'brother_in_law': CanonicalId.derived,
    'sister_in_law': CanonicalId.derived,
    'son_in_law': CanonicalId.derived,
    'daughter_in_law': CanonicalId.derived,
    'grandson': CanonicalId.derived,
    'granddaughter': CanonicalId.derived,
    'great_grandson': CanonicalId.derived,
    'great_granddaughter': CanonicalId.derived,
    'great_uncle': CanonicalId.derived,
    'great_aunt': CanonicalId.derived,
    'grandchild': CanonicalId.derived,
    'great_grandchild': CanonicalId.derived,

    // Indian compound kinship terms — all derived
    'chacha': CanonicalId.derived,
    'chachi': CanonicalId.derived,
    'mama': CanonicalId.derived,
    'mami': CanonicalId.derived,
    'kaka': CanonicalId.derived,
    'kaki': CanonicalId.derived,
    'bua': CanonicalId.derived,
    'phupha': CanonicalId.derived,
    'phuphi': CanonicalId.derived,
    'tau': CanonicalId.derived,
    'tai': CanonicalId.derived,
    'bhaiya': CanonicalId.derived,
    'bhabhi': CanonicalId.derived,
    'devar': CanonicalId.derived,
    'devrani': CanonicalId.derived,
    'jeth': CanonicalId.derived,
    'jethani': CanonicalId.derived,
    'nand': CanonicalId.derived,
    'nanad': CanonicalId.derived,
    'jija': CanonicalId.derived,
    'saas': CanonicalId.derived,
    'sasur': CanonicalId.derived,
    'damad': CanonicalId.derived,
    'bahu': CanonicalId.derived,
    'bhatija': CanonicalId.derived,
    'bhatiji': CanonicalId.derived,
    'bhanja': CanonicalId.derived,
    'bhanji': CanonicalId.derived,
  };

  /// Normalizes a user-input term to a CanonicalId.
  /// Returns [CanonicalId.derived] if the term is not recognized
  /// (meaning it's not a fundamental edge — the system should ask
  /// the user for the fundamental edge instead).
  static CanonicalId normalize(String input) {
    final normalized = input
        .toLowerCase()
        .trim()
        .replaceAll(' ', '_')
        .replaceAll('-', '_');
    return _termMap[normalized] ?? CanonicalId.derived;
  }

  /// Returns the fundamental edge type string to store in the database
  /// for a given CanonicalId. Returns null for derived.
  static String? toFundamentalEdge(CanonicalId id) {
    switch (id) {
      case CanonicalId.parent:
        return 'parent';
      case CanonicalId.spouse:
        return 'spouse';
      case CanonicalId.adoptiveParent:
        return 'adoptive_parent';
      case CanonicalId.stepParent:
        return 'step_parent';
      case CanonicalId.derived:
        return null;
    }
  }
}
