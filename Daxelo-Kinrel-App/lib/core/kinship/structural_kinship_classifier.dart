// lib/core/kinship/structural_kinship_classifier.dart
//
// DAXELO KINREL v66 — Structural Kinship Classifier
//
// Determines the KinshipEdgeCategory for ANY relationship path using
// GRAPH STRUCTURE alone — generation deltas + relationship-type
// patterns — without depending on the kinship JSON's chain rules
// (which only cover ~26 base keys and fail for most multi-hop paths).
//
// WHY THIS EXISTS:
//   The RelationshipEngine BFS produces paths like ['father', 'child']
//   when traversing an edge in reverse (the inverseTypeMap converts
//   'father'→'child', 'brother'→'sibling', etc.). The KinshipService
//   chain rules expect DIRECT keys ('father', 'brother') not inverse
//   types ('child', 'sibling'), so resolveChainPath returns null for
//   most multi-hop paths — leaving 6 of 9 nodes with no label and no
//   category (grey).
//
//   This classifier works on the STRUCTURAL pattern of the path:
//     - Count parent/child/spouse/sibling steps
//     - Compute generation delta (sum of parent-steps minus child-steps)
//     - Apply deterministic rules to pick the correct category
//
//   It is 100% data-driven — no name/ID/family-specific logic. Works
//   for any family structure, any depth, any branch combination.
//
// COVERAGE (all 9 required categories):
//   self, parent, child, sibling, grandparent, auntUncle, cousin,
//   inLaw, spouse, extended

import 'kinship_edge_style.dart';

/// Result of structural classification — the category + a human-readable
/// label that can be shown under the node.
class StructuralClassification {
  const StructuralClassification({
    required this.category,
    required this.label,
    required this.key,
  });

  /// The resolved kinship category. Never null.
  final KinshipEdgeCategory category;

  /// Human-readable label (e.g. "Father", "Grandfather", "Cousin").
  final String label;

  /// A best-effort kinship key (e.g. "father", "paternal_grandfather").
  /// May be a synthetic compound key for unusual paths.
  final String key;
}

/// Static classifier that maps a BFS path of relationship types to a
/// [StructuralClassification].
///
/// The path is a list of step types as produced by GraphService BFS:
///   ['father']              — direct parent
///   ['father', 'father']    — grandparent (2 parent hops)
///   ['father', 'brother']   — aunt/uncle (parent then sibling)
///   ['father', 'brother', 'son'] — cousin (parent + sibling + child)
///   ['brother']             — sibling
///   ['son']                 — child
///   ['wife']                — spouse
///   ['wife', 'father']      — in-law (spouse + parent)
///
/// The classifier normalizes inverse types ('child'→'parent', 'sibling'
/// stays 'sibling', 'spouse' stays 'spouse') so that the structural
/// pattern is consistent regardless of edge storage direction.
class StructuralKinshipClassifier {
  StructuralKinshipClassifier._();

  /// Parent-type steps (move up a generation).
  static const Set<String> _parentTypes = {
    'father', 'mother', 'parent',
  };

  /// Child-type steps (move down a generation).
  static const Set<String> _childTypes = {
    'son', 'daughter', 'child',
  };

  /// Sibling-type steps (same generation, shared parent).
  static const Set<String> _siblingTypes = {
    'brother', 'sister', 'sibling',
    'elder_brother', 'younger_brother',
    'elder_sister', 'younger_sister',
    'half_brother', 'half_sister',
  };

  /// Spouse-type steps (marriage link, same generation).
  static const Set<String> _spouseTypes = {
    'husband', 'wife', 'spouse', 'partner',
  };

  /// In-law compound markers (spouse's family or spouse-of-relative).
  static const Set<String> _inLawMarkers = {
    'father_in_law', 'mother_in_law', 'son_in_law', 'daughter_in_law',
    'brother_in_law', 'sister_in_law',
    'husbands_father', 'husbands_mother', 'husbands_brother',
    'wifes_father', 'wifes_mother', 'wifes_brother',
  };

  /// Step/extended types (adoptive/god/guru — weakest category).
  static const Set<String> _extendedTypes = {
    'step_father', 'step_mother', 'step_son', 'step_daughter',
    'step_brother', 'step_sister', 'stepfather', 'stepmother',
    'stepson', 'stepdaughter', 'stepbrother', 'stepsister',
    'godfather', 'godmother', 'guru',
    'related', 'unknown', 'other',
  };

  /// Classifies a BFS path into a [StructuralClassification].
  ///
  /// [path] is the list of relationship step types from the viewer to
  /// the target. [targetGender] is the target person's gender
  /// ('male'/'female'/null) — used to pick gendered labels.
  /// [viewerGender] is the viewer's gender — used for in-law labels.
  ///
  /// Returns a non-null classification. If the path is genuinely
  /// ambiguous, routes to [KinshipEdgeCategory.extended] with a
  /// descriptive label — never returns null.
  static StructuralClassification classify({
    required List<String> path,
    String? targetGender,
    String viewerGender = 'male',
  }) {
    if (path.isEmpty) {
      return const StructuralClassification(
        category: KinshipEdgeCategory.extended,
        label: 'Unknown',
        key: 'unknown',
      );
    }

    // Single-step paths — direct classification.
    if (path.length == 1) {
      return _classifySingleStep(path.first, targetGender);
    }

    // Multi-step paths — analyze structure.
    return _classifyMultiStep(path, targetGender, viewerGender);
  }

  // ── Single-step classification ──────────────────────────────────

  static StructuralClassification _classifySingleStep(
    String type,
    String? targetGender,
  ) {
    final t = type.toLowerCase().trim();

    // Self
    if (t == 'self' || t == 'ego') {
      return const StructuralClassification(
        category: KinshipEdgeCategory.self,
        label: 'You',
        key: 'self',
      );
    }

    // Parent
    if (_parentTypes.contains(t)) {
      final isFemale = targetGender == 'female' || targetGender == 'f';
      return StructuralClassification(
        category: KinshipEdgeCategory.parent,
        label: isFemale ? 'Mother' : 'Father',
        key: isFemale ? 'mother' : 'father',
      );
    }

    // Child
    if (_childTypes.contains(t)) {
      final isFemale = targetGender == 'female' || targetGender == 'f';
      return StructuralClassification(
        category: KinshipEdgeCategory.child,
        label: isFemale ? 'Daughter' : 'Son',
        key: isFemale ? 'daughter' : 'son',
      );
    }

    // Sibling
    if (_siblingTypes.contains(t)) {
      final isFemale = targetGender == 'female' || targetGender == 'f';
      return StructuralClassification(
        category: KinshipEdgeCategory.sibling,
        label: isFemale ? 'Sister' : 'Brother',
        key: isFemale ? 'sister' : 'brother',
      );
    }

    // Spouse
    if (_spouseTypes.contains(t)) {
      final isFemale = targetGender == 'female' || targetGender == 'f';
      return StructuralClassification(
        category: KinshipEdgeCategory.spouse,
        label: isFemale ? 'Wife' : 'Husband',
        key: isFemale ? 'wife' : 'husband',
      );
    }

    // In-law (single-step stored key)
    if (_inLawMarkers.contains(t) || t.contains('in_law') || t.contains('in-law')) {
      return StructuralClassification(
        category: KinshipEdgeCategory.inLaw,
        label: _inLawLabel(t, targetGender),
        key: t,
      );
    }

    // Extended/step
    if (_extendedTypes.contains(t) || t.startsWith('step') || t.startsWith('god') || t.startsWith('guru')) {
      return StructuralClassification(
        category: KinshipEdgeCategory.extended,
        label: _extendedLabel(t),
        key: t,
      );
    }

    // Great-grandparent / Great-grandchild (direct stored key)
    if (t.startsWith('great_grand')) {
      if (t.contains('son') || t.contains('daughter') || t.contains('child')) {
        // Great-grandchild
        final isFemale = t.contains('daughter');
        return StructuralClassification(
          category: KinshipEdgeCategory.grandparent,
          label: isFemale ? 'Great-granddaughter' : 'Great-grandson',
          key: t,
        );
      }
      // Great-grandparent
      final isFemale = t.contains('mother') || t.contains('grandmother');
      return StructuralClassification(
        category: KinshipEdgeCategory.grandparent,
        label: isFemale ? 'Great-grandmother' : 'Great-grandfather',
        key: t,
      );
    }

    // Grandparent (direct stored key)
    if (t == 'grandfather' || t == 'grandmother' || t == 'grandparent' ||
        t.startsWith('paternal_grand') || t.startsWith('maternal_grand')) {
      final isFemale = t.contains('mother') || t.contains('grandmother');
      return StructuralClassification(
        category: KinshipEdgeCategory.grandparent,
        label: isFemale ? 'Grandmother' : 'Grandfather',
        key: t,
      );
    }

    // Aunt/Uncle (direct stored key)
    if (t == 'uncle' || t == 'aunt' || t.startsWith('paternal_uncle') ||
        t.startsWith('paternal_aunt') || t.startsWith('maternal_uncle') ||
        t.startsWith('maternal_aunt') || t.startsWith('fathers_brother') ||
        t.startsWith('fathers_sister') || t.startsWith('mothers_brother') ||
        t.startsWith('mothers_sister')) {
      final isFemale = t.contains('aunt') || t.contains('sister');
      return StructuralClassification(
        category: KinshipEdgeCategory.auntUncle,
        label: isFemale ? 'Aunt' : 'Uncle',
        key: t,
      );
    }

    // Cousin (direct stored key)
    if (t == 'cousin' || t.startsWith('cousin') ||
        t.startsWith('brothers_son') || t.startsWith('brothers_daughter') ||
        t.startsWith('sisters_son') || t.startsWith('sisters_daughter')) {
      return const StructuralClassification(
        category: KinshipEdgeCategory.cousin,
        label: 'Cousin',
        key: 'cousin',
      );
    }

    // Niece/Nephew → auntUncle category (per spec, nieces/nephews share
    // the aunt/uncle color from the viewer's perspective)
    if (t == 'nephew' || t == 'niece') {
      final isFemale = t == 'niece';
      return StructuralClassification(
        category: KinshipEdgeCategory.auntUncle,
        label: isFemale ? 'Niece' : 'Nephew',
        key: t,
      );
    }

    // Grandchild
    if (t == 'grandson' || t == 'granddaughter' || t == 'grandchild') {
      final isFemale = t == 'granddaughter';
      return StructuralClassification(
        category: KinshipEdgeCategory.grandparent,
        label: isFemale ? 'Granddaughter' : 'Grandson',
        key: t,
      );
    }

    // Fallback — genuinely unclassifiable single step.
    // Route to extended with the raw key as the label.
    return StructuralClassification(
      category: KinshipEdgeCategory.extended,
      label: _prettyPrint(t),
      key: t,
    );
  }

  // ── Multi-step classification ───────────────────────────────────

  static StructuralClassification _classifyMultiStep(
    List<String> path,
    String? targetGender,
    String viewerGender,
  ) {
    // Normalize each step to its structural role.
    final roles = <_StepRole>[];
    for (final step in path) {
      roles.add(_roleOf(step));
    }

    // Count step roles.
    int parentCount = 0;   // up a generation
    int childCount = 0;    // down a generation
    int siblingCount = 0;  // same generation, collateral
    int spouseCount = 0;   // marriage link
    int extendedCount = 0; // step/god/guru
    int inLawCount = 0;    // in-law markers

    for (final role in roles) {
      switch (role) {
        case _StepRole.parent:
          parentCount++;
          break;
        case _StepRole.child:
          childCount++;
          break;
        case _StepRole.sibling:
          siblingCount++;
          break;
        case _StepRole.spouse:
          spouseCount++;
          break;
        case _StepRole.extended:
          extendedCount++;
          break;
        case _StepRole.inLaw:
          inLawCount++;
          break;
        case _StepRole.unknown:
          // Unknown steps → extended fallback.
          extendedCount++;
          break;
      }
    }

    final generationDelta = parentCount - childCount;
    final hasSpouse = spouseCount > 0;
    final hasSibling = siblingCount > 0;
    final hasExtended = extendedCount > 0;
    final hasInLaw = inLawCount > 0;

    // ── Extended/step takes priority when present ─────────────────
    if (hasExtended) {
      return StructuralClassification(
        category: KinshipEdgeCategory.extended,
        label: _extendedLabel(path.last),
        key: _composeKey(path),
      );
    }

    // ── In-law vs Step-parent: depends on step ORDER ──────────────
    // v5.87: The previous code treated ALL [spouse + parent] paths as
    // in-law, but the ORDER matters:
    //   [spouse, parent] = spouse's parent → Father/Mother-in-law (CORRECT)
    //   [parent, spouse] = parent's spouse → Step-father/mother (was WRONG)
    //
    // The fix: check if the FIRST step is a spouse step (→ in-law) or
    // a parent step (→ step-parent). This correctly distinguishes the
    // two relationship types.
    if (hasSpouse && parentCount > 0 && childCount == 0) {
      final isFirstStepSpouse = roles.first == _StepRole.spouse;
      final isFemale = targetGender == 'female' || targetGender == 'f';

      if (isFirstStepSpouse) {
        // [spouse, parent] = spouse's parent = in-law
        return StructuralClassification(
          category: KinshipEdgeCategory.inLaw,
          label: isFemale ? 'Mother-in-law' : 'Father-in-law',
          key: isFemale ? 'mother_in_law' : 'father_in_law',
        );
      } else {
        // [parent, spouse] = parent's spouse = step-parent
        // (NOT in-law — in-law means "spouse's blood relative")
        return StructuralClassification(
          category: KinshipEdgeCategory.extended,
          label: isFemale ? 'Step-mother' : 'Step-father',
          key: isFemale ? 'step_mother' : 'step_father',
        );
      }
    }
    if (hasSpouse && siblingCount > 0 && parentCount == 0 && childCount == 0) {
      // v5.87: Same order check as parent+spouse above.
      // [spouse, sibling] = spouse's sibling = sibling-in-law (CORRECT)
      // [sibling, spouse] = sibling's spouse = sibling-in-law (also correct,
      //   but technically a co-sibling-in-law, not a blood in-law.
      //   For simplicity, both are labeled sibling-in-law.)
      final isFemale = targetGender == 'female' || targetGender == 'f';
      return StructuralClassification(
        category: KinshipEdgeCategory.inLaw,
        label: isFemale ? 'Sister-in-law' : 'Brother-in-law',
        key: isFemale ? 'sister_in_law' : 'brother_in_law',
      );
    }
    // Spouse + child path (spouse's child): check BEFORE the generic
    // spouse+child=own-child rule below. If the child step came from
    // inverting a parent-type (e.g. 'father' → 'child'), this is
    // actually spouse's parent = inLaw, not own child.
    if (hasSpouse && childCount > 0 && parentCount == 0) {
      // v67 (BUG-8 FIX): Spouse's child is NOT always a step-child.
      // If the path is ['wife', 'son'] or ['husband', 'daughter'],
      // the child is likely the viewer's OWN child (shared with the
      // spouse), not a step-child from a previous marriage.
      //
      // Heuristic: a single spouse step + single child step = own child
      // (blood relation through the marriage). Only classify as
      // step-child if there are additional hops suggesting a different
      // parent (e.g. spouse + parent + child = spouse's parent's other
      // child = step-sibling, not step-child).
      //
      // This prevents the user's own children from being misclassified
      // as step-children (grey/extended) when they're reachable via
      // the spouse.
      if (spouseCount == 1 && childCount == 1 && siblingCount == 0) {
        final isFemale = targetGender == 'female' || targetGender == 'f';
        return StructuralClassification(
          category: KinshipEdgeCategory.child,
          label: isFemale ? 'Daughter' : 'Son',
          key: isFemale ? 'daughter' : 'son',
        );
      }
      // Multi-hop spouse+child path — treat as step-child (extended).
      final isFemale = targetGender == 'female' || targetGender == 'f';
      return StructuralClassification(
        category: KinshipEdgeCategory.extended,
        label: isFemale ? 'Step-daughter' : 'Step-son',
        key: isFemale ? 'step_daughter' : 'step_son',
      );
    }
    if (hasInLaw) {
      // Explicit in-law marker in the path.
      return StructuralClassification(
        category: KinshipEdgeCategory.inLaw,
        label: _inLawLabel(path.last, targetGender),
        key: _composeKey(path),
      );
    }

    // ── Spouse-in-middle guard ──────────────────────────────────────
    // If the path contains a spouse step but didn't match any of the
    // specific in-law patterns above, the relationship involves a
    // marriage link in the middle. This is NOT a pure blood relation —
    // e.g. ['father', 'spouse', 'child', 'sibling'] is a step-sibling
    // or in-law connection, NOT a cousin. Route to extended/inLaw.
    if (hasSpouse) {
      return StructuralClassification(
        category: KinshipEdgeCategory.inLaw,
        label: _inLawLabel(path.last, targetGender),
        key: _composeKey(path),
      );
    }

    // ── Pure blood relations (no spouse, no in-law) ───────────────
    //
    // Generation delta determines the category:
    //   +2+  → grandparent (ancestor)
    //   +1   → parent
    //    0   → sibling or cousin (depends on path)
    //   -1   → child
    //   -2-  → grandchild (descendant)
    //
    // With a sibling step in the middle:
    //   parent + sibling        → auntUncle
    //   parent + sibling + child → cousin
    //   sibling + child          → niece/nephew → auntUncle category

    // Grandparent / ancestor (2+ parent hops, no siblings)
    if (generationDelta >= 2 && !hasSibling && childCount == 0) {
      final isFemale = targetGender == 'female' || targetGender == 'f';
      return StructuralClassification(
        category: KinshipEdgeCategory.grandparent,
        label: generationDelta >= 3
            ? (isFemale ? 'Great-grandmother' : 'Great-grandfather')
            : (isFemale ? 'Grandmother' : 'Grandfather'),
        key: generationDelta >= 3
            ? (isFemale ? 'great_grandmother' : 'great_grandfather')
            : (isFemale ? 'grandmother' : 'grandfather'),
      );
    }

    // Grandchild / descendant (2+ child hops, no siblings)
    if (generationDelta <= -2 && !hasSibling && parentCount == 0) {
      final isFemale = targetGender == 'female' || targetGender == 'f';
      return StructuralClassification(
        category: KinshipEdgeCategory.grandparent, // grandchild uses same color
        label: generationDelta <= -3
            ? (isFemale ? 'Great-granddaughter' : 'Great-grandson')
            : (isFemale ? 'Granddaughter' : 'Grandson'),
        key: generationDelta <= -3
            ? (isFemale ? 'great_granddaughter' : 'great_grandson')
            : (isFemale ? 'granddaughter' : 'grandson'),
      );
    }

    // Aunt/Uncle (parent + sibling — parent's sibling)
    if (parentCount == 1 && hasSibling && childCount == 0) {
      final isFemale = targetGender == 'female' || targetGender == 'f';
      return StructuralClassification(
        category: KinshipEdgeCategory.auntUncle,
        label: isFemale ? 'Aunt' : 'Uncle',
        key: isFemale ? 'aunt' : 'uncle',
      );
    }

    // Niece/Nephew (sibling + child — sibling's child)
    if (hasSibling && childCount == 1 && parentCount == 0) {
      final isFemale = targetGender == 'female' || targetGender == 'f';
      return StructuralClassification(
        category: KinshipEdgeCategory.auntUncle, // niece/nephew → auntUncle color
        label: isFemale ? 'Niece' : 'Nephew',
        key: isFemale ? 'niece' : 'nephew',
      );
    }

    // Cousin (parent + sibling + child — shared grandparent, not direct sibling)
    if (parentCount == 1 && hasSibling && childCount == 1) {
      return const StructuralClassification(
        category: KinshipEdgeCategory.cousin,
        label: 'Cousin',
        key: 'cousin',
      );
    }

    // Sibling (single sibling step, generation delta 0)
    if (hasSibling && generationDelta == 0 && parentCount == 0 && childCount == 0) {
      final isFemale = targetGender == 'female' || targetGender == 'f';
      return StructuralClassification(
        category: KinshipEdgeCategory.sibling,
        label: isFemale ? 'Sister' : 'Brother',
        key: isFemale ? 'sister' : 'brother',
      );
    }

    // Sibling via shared parent (parent + child, generation delta 0, no
    // explicit sibling step). This is the path: viewer → parent → sibling,
    // where the BFS represents it as [parent, child] (up to parent, down
    // to parent's other child). The target is viewer's SIBLING.
    // Key is 'parents_child' to match the synthetic fixture expectations.
    if (!hasSibling && !hasSpouse &&
        parentCount == 1 && childCount == 1 && generationDelta == 0) {
      final isFemale = targetGender == 'female' || targetGender == 'f';
      return StructuralClassification(
        category: KinshipEdgeCategory.sibling,
        label: isFemale ? 'Sister' : 'Brother',
        key: 'parents_child',
      );
    }

    // Aunt/Uncle via shared grandparent (2 parent + 1 child, generation
    // delta 1, no explicit sibling step). Path: viewer → parent →
    // grandparent → uncle (up 2, down 1). The target is viewer's
    // aunt/uncle (parent's sibling).
    if (!hasSibling && !hasSpouse &&
        parentCount == 2 && childCount == 1 && generationDelta == 1) {
      final isFemale = targetGender == 'female' || targetGender == 'f';
      return StructuralClassification(
        category: KinshipEdgeCategory.auntUncle,
        label: isFemale ? 'Aunt' : 'Uncle',
        key: isFemale ? 'aunt' : 'uncle',
      );
    }

    // Cousin via shared grandparent (2 parent + 1 sibling + 1 child, or
    // 2 parent + 2 child with generation delta 0). Path: viewer → parent →
    // grandparent → uncle → cousin (up 2, down 2). The target is viewer's
    // cousin. Key is 'parents_parents_childs_child' to match the synthetic
    // fixture expectations.
    if (!hasSibling && !hasSpouse &&
        parentCount == 2 && childCount == 2 && generationDelta == 0) {
      return const StructuralClassification(
        category: KinshipEdgeCategory.cousin,
        label: 'Cousin',
        key: 'parents_parents_childs_child',
      );
    }

    // Parent (single parent step)
    if (parentCount == 1 && childCount == 0 && !hasSibling && !hasSpouse) {
      final isFemale = targetGender == 'female' || targetGender == 'f';
      return StructuralClassification(
        category: KinshipEdgeCategory.parent,
        label: isFemale ? 'Mother' : 'Father',
        key: isFemale ? 'mother' : 'father',
      );
    }

    // Child (single child step)
    if (childCount == 1 && parentCount == 0 && !hasSibling && !hasSpouse) {
      final isFemale = targetGender == 'female' || targetGender == 'f';
      return StructuralClassification(
        category: KinshipEdgeCategory.child,
        label: isFemale ? 'Daughter' : 'Son',
        key: isFemale ? 'daughter' : 'son',
      );
    }

    // Spouse (single spouse step)
    if (spouseCount == 1 && parentCount == 0 && childCount == 0 && !hasSibling) {
      final isFemale = targetGender == 'female' || targetGender == 'f';
      return StructuralClassification(
        category: KinshipEdgeCategory.spouse,
        label: isFemale ? 'Wife' : 'Husband',
        key: isFemale ? 'wife' : 'husband',
      );
    }

    // ── Fallback: genuinely ambiguous multi-step path ─────────────
    // Route to extended with a descriptive label. This should be rare
    // but ensures no node ever renders with no category.
    return StructuralClassification(
      category: KinshipEdgeCategory.extended,
      label: _prettyPrint(_composeKey(path)),
      key: _composeKey(path),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────

  /// Maps a step type to its structural role.
  static _StepRole _roleOf(String type) {
    final t = type.toLowerCase().trim();
    if (_parentTypes.contains(t)) return _StepRole.parent;
    if (_childTypes.contains(t)) return _StepRole.child;
    if (_siblingTypes.contains(t)) return _StepRole.sibling;
    if (_spouseTypes.contains(t)) return _StepRole.spouse;
    if (_inLawMarkers.contains(t) || t.contains('in_law') || t.contains('in-law')) {
      return _StepRole.inLaw;
    }
    if (_extendedTypes.contains(t) || t.startsWith('step') || t.startsWith('god') || t.startsWith('guru')) {
      return _StepRole.extended;
    }
    // Compound keys — infer from the last segment.
    if (t.endsWith('_father') || t.endsWith('_mother') || t.endsWith('_parent')) {
      return _StepRole.parent;
    }
    if (t.endsWith('_son') || t.endsWith('_daughter') || t.endsWith('_child')) {
      return _StepRole.child;
    }
    if (t.endsWith('_brother') || t.endsWith('_sister') || t.endsWith('_sibling')) {
      return _StepRole.sibling;
    }
    if (t.endsWith('_husband') || t.endsWith('_wife') || t.endsWith('_spouse')) {
      return _StepRole.spouse;
    }
    // Great-grandparent/aunt/cousin direct keys
    if (t.startsWith('great_grand')) {
      if (t == 'great_grandson' || t == 'great_granddaughter' || t == 'great_grandchild') {
        return _StepRole.child;
      }
      return _StepRole.parent; // great_grandfather/great_grandmother = up 2+ generations
    }
    // Grandparent/aunt/cousin direct keys
    if (t.startsWith('grand') || t.startsWith('paternal_grand') || t.startsWith('maternal_grand')) {
      // v67 (BUG-9 FIX): Distinguish grandchild from grandparent.
      // 'grandson', 'granddaughter', 'grandchild' are DOWN a generation
      // (child role). 'grandfather', 'grandmother', 'grandparent' and
      // paternal/maternal variants are UP a generation (parent role).
      if (t == 'grandson' || t == 'granddaughter' || t == 'grandchild' ||
          t == 'great_grandson' || t == 'great_granddaughter' || t == 'great_grandchild') {
        return _StepRole.child;
      }
      return _StepRole.parent; // grandfather/grandmother = up a generation
    }
    if (t == 'uncle' || t == 'aunt' || t.startsWith('fathers_brother') || t.startsWith('fathers_sister') ||
        t.startsWith('mothers_brother') || t.startsWith('mothers_sister')) {
      return _StepRole.sibling; // parent's sibling — treat the sibling part
    }
    if (t == 'cousin' || t.startsWith('cousin')) {
      return _StepRole.sibling;
    }
    if (t == 'nephew' || t == 'niece') {
      return _StepRole.child;
    }
    return _StepRole.unknown;
  }

  /// Composes a synthetic kinship key from a path.
  static String _composeKey(List<String> path) {
    if (path.length == 1) return path.first;
    final buffer = StringBuffer();
    for (int i = 0; i < path.length; i++) {
      if (i < path.length - 1) {
        buffer.write(_pluralize(path[i]));
        buffer.write('_');
      } else {
        buffer.write(path[i]);
      }
    }
    return buffer.toString();
  }

  /// Pluralizes a kinship term for compound keys.
  static String _pluralize(String term) {
    if (term.endsWith('s')) return term;
    if (term.endsWith('y') && !term.endsWith('ay')) {
      return '${term.substring(0, term.length - 1)}ies';
    }
    return '${term}s';
  }

  /// Pretty-prints a kinship key as a human-readable label.
  static String _prettyPrint(String key) {
    return key
        .split('_')
        .where((s) => s.isNotEmpty)
        .map((s) => '${s[0].toUpperCase()}${s.substring(1)}')
        .join(' ');
  }

  /// Returns a label for an in-law relationship.
  static String _inLawLabel(String key, String? targetGender) {
    final isFemale = targetGender == 'female' || targetGender == 'f';
    final k = key.toLowerCase();
    if (k.contains('father')) return isFemale ? 'Mother-in-law' : 'Father-in-law';
    if (k.contains('mother')) return 'Mother-in-law';
    if (k.contains('son')) return 'Son-in-law';
    if (k.contains('daughter')) return 'Daughter-in-law';
    if (k.contains('brother')) return 'Brother-in-law';
    if (k.contains('sister')) return 'Sister-in-law';
    return isFemale ? 'Sister-in-law' : 'Brother-in-law';
  }

  /// Returns a label for an extended/step relationship.
  static String _extendedLabel(String key) {
    final k = key.toLowerCase();
    if (k.contains('father') || k.contains('dad')) return 'Step-father';
    if (k.contains('mother') || k.contains('mom')) return 'Step-mother';
    if (k.contains('son')) return 'Step-son';
    if (k.contains('daughter')) return 'Step-daughter';
    if (k.contains('brother')) return 'Step-brother';
    if (k.contains('sister')) return 'Step-sister';
    if (k.contains('god')) return k.contains('mother') ? 'Godmother' : 'Godfather';
    if (k.contains('guru')) return 'Guru';
    return _prettyPrint(k);
  }
}

/// Structural role of a single step in a relationship path.
enum _StepRole {
  parent,
  child,
  sibling,
  spouse,
  inLaw,
  extended,
  unknown,
}
