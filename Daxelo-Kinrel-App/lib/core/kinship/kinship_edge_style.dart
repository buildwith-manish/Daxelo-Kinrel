// lib/core/kinship/kinship_edge_style.dart
//
// DAXELO KINREL — Kinrel Edge Color & Midpoint System
//
// Single source of truth for the 10-category edge styling system used by
// every graph painter in the app:
//   1. Self             — Teal    #0D9488  (node ring only, never on edges)
//   2. Parent / Child   — Blue    #3B82F6  (parent)  /  Pink #EC4899 (child)
//   3. Sibling          — Purple  #8B5CF6  (dashed arc above)
//   4. Spouse           — Orange  #F97316  edge + Pink heart #EC4899
//   5. Grandparent      — Indigo  #6366F1  (solid extended bezier)
//   6. Aunt / Uncle     — Cyan    #06B6D4  (dashed shallow S-curve)
//   7. Cousin           — Emerald #10B981  (wide arc bezier)
//   8. In-Law           — Amber   #F59E0B  (dashed straight/shallow)
//   9. Extended / Step  — Slate   #64748B  (dashed, alpha 0.45)
//  10. Indirect         — Gray    #8A7A72  (dashed, text label, NO dot)
//
// Each category resolves to:
//   - line color (with default alpha)
//   - line shape (solid / dashed / arc / wide-arc / shallow-S)
//   - dash pattern (when dashed)
//   - midpoint symbol (dot / heart / none)
//   - midpoint color (may differ from edge color — spouse's pink heart)
//
// The classifier handles ALL 5,359 Indian kinship compound keys via
// prefix patterns, with these rules (per the deep system spec):
//   • self / ego                                   → self
//   • husband / wife / spouse / partner (exact)    → spouse
//   • step* / half_* / god* / guru*                → extended
//   • contains "in_law"                            → in_law
//   • starts with husbands_ / wifes_ / spouses_    → in_law (spouse's family)
//   • father / mother / parent (exact)             → parent
//   • son / daughter / child (exact)               → child
//   • sons_wife / daughters_husband (and variants) → child (children's spouses)
//   • brother / sister / sibling + elder/younger/half (exact) → sibling
//   • starts with grand / paternal_grand / maternal_grand → grandparent
//   • uncle / aunt / nephew / niece (exact)        → aunt_uncle
//   • paternal_uncle / paternal_aunt / maternal_uncle / maternal_aunt → aunt_uncle
//   • fathers_brother / fathers_sister / mothers_brother / mothers_sister
//     (+ their spouses)                             → aunt_uncle
//   • brothers_son / brothers_daughter /
//     sisters_son  / sisters_daughter               → cousin (siblings' kids)
//   • cousin / cousin_brother / cousin_sister      → cousin
//   • fathers_(elder_|younger_)?(brothers|sisters)_(son|daughter)
//     / mothers_(brothers|sisters)_(son|daughter)   → sibling (parallel cousins)
//   • indirect_connection / indirect_*             → indirect
//   • fallback                                      → extended
//
// This file is pure Dart (+ Flutter Color). No widget imports, no painter
// imports. Painters and widgets DELEGATE to this classifier so the entire
// app shares one styling brain.

import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════
// EDGE CATEGORY ENUM
// ═══════════════════════════════════════════════════════════════════════

/// The 10 visual categories used by the Kinrel edge color & midpoint system.
///
/// Order matters for documentation but has no runtime meaning — the
/// classifier returns a category by name, not by index.
enum KinshipEdgeCategory {
  /// Self / ego node (teal ring on node, never on edges).
  self,

  /// Parent → ego or ego → child (solid vertical bezier).
  parent,

  /// Ego → child (solid vertical bezier, pink).
  child,

  /// Sibling + Indian parallel-cousin-equivalents (dashed arc above).
  sibling,

  /// Spouse / partner (dashed horizontal + pink heart at midpoint).
  spouse,

  /// Grandparent / grandchild (solid extended bezier).
  grandparent,

  /// Aunt / uncle (dashed shallow S-curve).
  auntUncle,

  /// Cousin (wide arc bezier).
  cousin,

  /// In-law (dashed straight or shallow).
  inLaw,

  /// Extended / step / ceremonial / god / guru (dashed, alpha 0.45).
  extended,

  /// Indirect connection through a blocked member (dashed gray, no dot).
  indirect,
}

// ═══════════════════════════════════════════════════════════════════════
// LINE SHAPE ENUM
// ═══════════════════════════════════════════════════════════════════════

/// Visual line shape used by painters to pick the right path geometry.
enum KinshipLineShape {
  /// Solid smooth S-curve (cubic bezier) — parent / child.
  solidBezier,

  /// Solid extended bezier with longer control-point spread — grandparent.
  solidExtendedBezier,

  /// Dashed curved arc that bows ABOVE the nodes — sibling.
  dashedArc,

  /// Dashed straight horizontal line — spouse / in-law.
  dashedStraight,

  /// Dashed shallow S-curve (less curve than sibling arc) — aunt/uncle.
  dashedShallowS,

  /// Wide-arc cubic bezier (control points pushed far apart) — cousin.
  /// Drawn solid by default; cousin edges can be long, so solid reads
  /// better than dashed at distance.
  wideArcBezier,

  /// Standard dashed line (default fallback) — extended / indirect.
  dashedDefault,
}

// ═══════════════════════════════════════════════════════════════════════
// MIDPOINT SYMBOL ENUM
// ═══════════════════════════════════════════════════════════════════════

/// What to draw at the t=0.5 point of an edge.
enum KinshipMidpointSymbol {
  /// No midpoint symbol (indirect connection — only a text label).
  none,

  /// Filled dot with glow halo, color = edge color.
  dot,

  /// Pink heart (spouse only) — color is ALWAYS pink #EC4899 regardless
  /// of the edge color.
  heart,
}

// ═══════════════════════════════════════════════════════════════════════
// EDGE STYLE VALUE OBJECT
// ═══════════════════════════════════════════════════════════════════════

/// Immutable description of how to paint a single edge.
class KinshipEdgeStyle {
  const KinshipEdgeStyle({
    required this.category,
    required this.color,
    required this.defaultAlpha,
    required this.lineShape,
    required this.dashPattern,
    required this.midpointSymbol,
    required this.midpointColor,
    required this.strokeWidth,
  });

  /// The category this style belongs to.
  final KinshipEdgeCategory category;

  /// Base color (full alpha). Painters multiply by [defaultAlpha] when
  /// the edge is not selected / hovered.
  final Color color;

  /// Default alpha (0..1) applied when the edge is not selected.
  final double defaultAlpha;

  /// Line geometry to draw.
  final KinshipLineShape lineShape;

  /// Dash pattern `[dash, gap]` in dp. Empty = solid.
  final List<double> dashPattern;

  /// What to draw at the midpoint.
  final KinshipMidpointSymbol midpointSymbol;

  /// Color of the midpoint symbol. For spouse this is PINK (#EC4899),
  /// for every other category it equals [color].
  final Color midpointColor;

  /// Stroke width in dp.
  final double strokeWidth;

  /// Whether this category should be drawn dashed.
  bool get isDashed =>
      lineShape == KinshipLineShape.dashedArc ||
      lineShape == KinshipLineShape.dashedStraight ||
      lineShape == KinshipLineShape.dashedShallowS ||
      lineShape == KinshipLineShape.dashedDefault;
}

// ═══════════════════════════════════════════════════════════════════════
// CATEGORY COLOR CONSTANTS
// ═══════════════════════════════════════════════════════════════════════

/// Centralized color palette for the 10 edge categories.
///
/// These match the user-facing brand spec exactly. Do NOT change without
/// updating the legend, the node ring colors in graph_node.dart, and the
/// brand_colors.dart node color constants.
class KinshipEdgeColors {
  KinshipEdgeColors._();

  /// Self — Teal #0D9488 (node ring only).
  static const Color self = Color(0xFF0D9488);

  /// Parent — Blue #3B82F6.
  static const Color parent = Color(0xFF3B82F6);

  /// Child — Pink #EC4899.
  static const Color child = Color(0xFFEC4899);

  /// Sibling — Purple #8B5CF6.
  static const Color sibling = Color(0xFF8B5CF6);

  /// Spouse edge — Orange #F97316.
  static const Color spouseEdge = Color(0xFFF97316);

  /// Spouse heart — Pink #EC4899 (ALWAYS pink, never orange).
  static const Color spouseHeart = Color(0xFFEC4899);

  /// Grandparent — Indigo #6366F1.
  static const Color grandparent = Color(0xFF6366F1);

  /// Aunt / Uncle — Cyan #06B6D4.
  static const Color auntUncle = Color(0xFF06B6D4);

  /// Cousin — Emerald #10B981.
  static const Color cousin = Color(0xFF10B981);

  /// In-Law — Amber #F59E0B.
  static const Color inLaw = Color(0xFFF59E0B);

  /// Extended / Step — Slate #64748B.
  static const Color extended = Color(0xFF64748B);

  /// Indirect — Gray #8A7A72 (matches KinrelColors.textDim).
  static const Color indirect = Color(0xFF8A7A72);
}

// ═══════════════════════════════════════════════════════════════════════
// CLASSIFIER
// ═══════════════════════════════════════════════════════════════════════

/// Pure-string classifier that maps a relationship key (from the Indian
/// kinship database OR a legacy Latin key) to one of the 10 categories.
///
/// Rules ordered by priority (first match wins). All comparisons are
/// case-insensitive — caller may pass `"Father_In_Law"` or `"father_in_law"`.
class KinshipEdgeClassifier {
  KinshipEdgeClassifier._();

  /// Classify a relationship key.
  static KinshipEdgeCategory classify(String relationshipKey) {
    if (relationshipKey.isEmpty) return KinshipEdgeCategory.extended;
    final k = relationshipKey.toLowerCase().trim();

    // 0. Server-computed category strings (snake_case).
    // ─────────────────────────────────────────────────────────────────
    // When the server pre-computes a kinship category and stores it on
    // the person (PersonData.kinshipCategory), that string flows through
    // to the classifier instead of a raw kinship key. family_graph.dart
    // stores it as GraphPersonData.relationshipKey, which GraphNode
    // passes to RelationshipColors.borderColorFor() → styleFor() →
    // classify().
    //
    // Recognize these category strings explicitly so node ring colors
    // resolve correctly even when no direct edge exists from the anchor
    // to the person. Without this block, "aunt_uncle" (the snake_case
    // category string for aunts/uncles) falls through to the extended
    // fallback and aunts/uncles get slate gray instead of cyan.
    //
    // We accept snake_case, hyphenated, and unseparated variants for
    // defensive matching against any future server-side format change.
    switch (k) {
      case 'self':
      case 'ego':
        return KinshipEdgeCategory.self;
      case 'parent':
        return KinshipEdgeCategory.parent;
      case 'spouse':
        return KinshipEdgeCategory.spouse;
      case 'sibling':
        return KinshipEdgeCategory.sibling;
      case 'child':
        return KinshipEdgeCategory.child;
      case 'grandparent':
      case 'grandchild':
        return KinshipEdgeCategory.grandparent;
      case 'aunt_uncle':
      case 'aunt-uncle':
      case 'auntuncle':
        return KinshipEdgeCategory.auntUncle;
      case 'cousin':
        return KinshipEdgeCategory.cousin;
      case 'in_law':
      case 'in-law':
      case 'inlaw':
        return KinshipEdgeCategory.inLaw;
      case 'extended':
        return KinshipEdgeCategory.extended;
      case 'indirect':
        return KinshipEdgeCategory.indirect;
    }

    // 1. Indirect (blocked-member path) — synthetic prefix added by the
    //    graph repository for paths that go through a blocked member.
    if (k == 'indirect_connection' || k.startsWith('indirect_')) {
      return KinshipEdgeCategory.indirect;
    }

    // 2. Self / ego (never appears on edges, but keep for completeness).
    //    (Plain "self"/"ego" already handled by the category block above.)
    if (k == 'self' || k == 'ego') {
      return KinshipEdgeCategory.self;
    }

    // 3. Spouse — exact match only. A compound like "husbands_father"
    //    is an in-law, not a spouse.
    if (k == 'husband' || k == 'wife' || k == 'spouse' || k == 'partner') {
      return KinshipEdgeCategory.spouse;
    }

    // 4. Extended — step / god / guru / half_parent. Use prefix so
    //    compound forms like "step_father_son" also map here.
    //    NOTE: half_brother / half_sister are SIBLINGS (per spec §3),
    //    not extended — they fall through to the sibling block below.
    if (k.startsWith('step') ||
        k.startsWith('god') ||
        k.startsWith('guru') ||
        k == 'guru' ||
        k == 'half_father' ||
        k == 'half_mother') {
      return KinshipEdgeCategory.extended;
    }

    // 5. In-law — explicit "_in_law" suffix or spouse's family compound.
    //    (Plain "in_law" already handled by the category block above.)
    if (k.contains('in_law') ||
        k.contains('in-law') ||
        k.startsWith('husbands_') ||
        k.startsWith('wifes_') ||
        k.startsWith('wives_') ||
        k.startsWith('spouses_')) {
      return KinshipEdgeCategory.inLaw;
    }

    // 6. Grandparent / grandchild — exact or compound starting with
    //    grand / paternal_grand / maternal_grand.
    if (k == 'grandfather' ||
        k == 'grandmother' ||
        k == 'grandson' ||
        k == 'granddaughter' ||
        k == 'grandparent' ||
        k.startsWith('grand') ||
        k.startsWith('paternal_grand') ||
        k.startsWith('maternal_grand')) {
      return KinshipEdgeCategory.grandparent;
    }

    // 7. Parent — exact only. Compound forms like "fathers_brother" are
    //    aunt/uncle, not parent.
    if (k == 'father' || k == 'mother' || k == 'parent') {
      return KinshipEdgeCategory.parent;
    }

    // 8. Child — exact + children's spouses ("sons_wife", "daughters_husband").
    if (k == 'son' || k == 'daughter' || k == 'child') {
      return KinshipEdgeCategory.child;
    }
    if (k == 'sons_wife' ||
        k == 'sons_husband' ||
        k == 'daughters_husband' ||
        k == 'daughters_wife' ||
        k == 'sons_partner' ||
        k == 'daughters_partner') {
      return KinshipEdgeCategory.child;
    }

    // 9. Sibling — exact + elder/younger/half modifiers.
    if (k == 'brother' ||
        k == 'sister' ||
        k == 'sibling' ||
        k == 'elder_brother' ||
        k == 'elder_sister' ||
        k == 'younger_brother' ||
        k == 'younger_sister' ||
        k == 'half_brother' ||
        k == 'half_sister') {
      return KinshipEdgeCategory.sibling;
    }

    // 10. Aunt/Uncle — exact + paternal/maternal variants + parent's
    //     siblings and their spouses (but NOT their children — those are
    //     parallel cousins = sibling).
    if (k == 'uncle' ||
        k == 'aunt' ||
        k == 'nephew' ||
        k == 'niece' ||
        k == 'paternal_uncle' ||
        k == 'paternal_aunt' ||
        k == 'maternal_uncle' ||
        k == 'maternal_aunt') {
      return KinshipEdgeCategory.auntUncle;
    }
    // Parent's siblings themselves + their spouses:
    //   fathers_elder_brother, fathers_younger_brother, fathers_sister,
    //   mothers_brother, mothers_sister,
    //   fathers_elder_brothers_wife, fathers_sisters_husband, etc.
    if (_parentSiblingPattern.hasMatch(k)) {
      return KinshipEdgeCategory.auntUncle;
    }

    // 11. Cousin — exact + sibling's children.
    if (k == 'cousin' ||
        k == 'cousin_brother' ||
        k == 'cousin_sister' ||
        k == 'parallel_cousin' ||
        k == 'cross_cousin') {
      return KinshipEdgeCategory.cousin;
    }
    // Sibling's children = niece/nephew-equivalent (cousin color per spec).
    if (k == 'brothers_son' ||
        k == 'brothers_daughter' ||
        k == 'sisters_son' ||
        k == 'sisters_daughter') {
      return KinshipEdgeCategory.cousin;
    }

    // 12. Sibling (parallel cousin) — parent's sibling's child.
    //     Pattern: fathers_(elder_|younger_)?brothers_(son|daughter)
    //              fathers_(elder_|younger_)?sisters_(son|daughter)
    //              mothers_brothers_(son|daughter)
    //              mothers_sisters_(son|daughter)
    //     Also singular variants: fathers_brother_son, etc.
    //     These are "same-generation parallel cousins" treated as
    //     siblings in Indian kinship.
    if (_parentSiblingChildPattern.hasMatch(k)) {
      return KinshipEdgeCategory.sibling;
    }

    // 13. Cousin (extended) — deeper compound that ends in _son/_daughter
    //     and traces through any combination of parents'/grandparents'
    //     siblings. Treat as cousin if not already matched.
    if (_cousinCompoundPattern.hasMatch(k)) {
      return KinshipEdgeCategory.cousin;
    }

    // 14. Synthetic fallback used by family_graph.dart when there are 2+
    //     persons but no real relationships in the DB.
    if (k == 'related' || k == 'unknown' || k == 'other') {
      return KinshipEdgeCategory.extended;
    }

    // 15. Fallback — every other compound key (5,000+ Indian kinship
    //     compounds that don't match a more specific rule).
    return KinshipEdgeCategory.extended;
  }

  /// Matches parent's-sibling (the uncle/aunt themselves) + their spouses.
  /// Examples: fathers_elder_brother, fathers_sisters_husband,
  ///           mothers_younger_brother, mothers_brothers_wife.
  static final RegExp _parentSiblingPattern = RegExp(
    r'^(?:fathers|mothers)_(?:elder_|younger_)?(?:brothers?|sisters?)(?:_wife|_husband|s_wife|s_husband)?$',
  );

  /// Matches parent's-sibling's-child (parallel cousin = sibling in
  /// Indian kinship).
  /// Examples: fathers_elder_brothers_son, fathers_brother_daughter,
  ///           mothers_brothers_son, mothers_sisters_daughter.
  static final RegExp _parentSiblingChildPattern = RegExp(
    r'^(?:fathers|mothers)_(?:elder_|younger_)?(?:brothers?|sisters?)_(?:son|daughter|sons|daughters)$',
  );

  /// Loose cousin compound — any key that traces through grandparent /
  /// parent / sibling chains and ends in _son or _daughter. Used as a
  /// late-stage catch for cousin-like compounds not matched above.
  static final RegExp _cousinCompoundPattern = RegExp(
    r'^(?:grand|fathers|mothers|brothers|sisters|paternal|maternal).*_(?:son|daughter)$',
  );
}

// ═══════════════════════════════════════════════════════════════════════
// STYLE RESOLVER
// ═══════════════════════════════════════════════════════════════════════

/// Maps a [KinshipEdgeCategory] to its full [KinshipEdgeStyle].
///
/// Painters call [KinshipEdgeStyleResolver.styleFor] to get the complete
/// style for an edge in one shot — no per-painter color constants, no
/// per-painter dash pattern tables.
class KinshipEdgeStyleResolver {
  KinshipEdgeStyleResolver._();

  /// Resolve the style for a relationship key.
  static KinshipEdgeStyle styleFor(String relationshipKey) {
    final category = KinshipEdgeClassifier.classify(relationshipKey);
    return styleForCategory(category);
  }

  /// Resolve the style for a known category.
  static KinshipEdgeStyle styleForCategory(KinshipEdgeCategory category) {
    switch (category) {
      case KinshipEdgeCategory.self:
        return const KinshipEdgeStyle(
          category: KinshipEdgeCategory.self,
          color: KinshipEdgeColors.self,
          defaultAlpha: 1.0,
          lineShape: KinshipLineShape.dashedDefault,
          dashPattern: [4.0, 4.0],
          midpointSymbol: KinshipMidpointSymbol.dot,
          midpointColor: KinshipEdgeColors.self,
          strokeWidth: 2.0,
        );

      case KinshipEdgeCategory.parent:
        return const KinshipEdgeStyle(
          category: KinshipEdgeCategory.parent,
          color: KinshipEdgeColors.parent,
          defaultAlpha: 0.85,
          lineShape: KinshipLineShape.solidBezier,
          dashPattern: [],
          midpointSymbol: KinshipMidpointSymbol.dot,
          midpointColor: KinshipEdgeColors.parent,
          strokeWidth: 2.0,
        );

      case KinshipEdgeCategory.child:
        return const KinshipEdgeStyle(
          category: KinshipEdgeCategory.child,
          color: KinshipEdgeColors.child,
          defaultAlpha: 0.85,
          lineShape: KinshipLineShape.solidBezier,
          dashPattern: [],
          midpointSymbol: KinshipMidpointSymbol.dot,
          midpointColor: KinshipEdgeColors.child,
          strokeWidth: 2.0,
        );

      case KinshipEdgeCategory.sibling:
        return const KinshipEdgeStyle(
          category: KinshipEdgeCategory.sibling,
          color: KinshipEdgeColors.sibling,
          defaultAlpha: 0.75,
          lineShape: KinshipLineShape.dashedArc,
          dashPattern: [6.0, 4.0],
          midpointSymbol: KinshipMidpointSymbol.dot,
          midpointColor: KinshipEdgeColors.sibling,
          strokeWidth: 2.0,
        );

      case KinshipEdgeCategory.spouse:
        return const KinshipEdgeStyle(
          category: KinshipEdgeCategory.spouse,
          color: KinshipEdgeColors.spouseEdge,
          defaultAlpha: 0.85,
          lineShape: KinshipLineShape.dashedStraight,
          dashPattern: [6.0, 4.0],
          midpointSymbol: KinshipMidpointSymbol.heart,
          // PINK heart on ORANGE edge — the only category where the
          // midpoint color differs from the edge color. This contrast
          // makes the heart pop visually.
          midpointColor: KinshipEdgeColors.spouseHeart,
          strokeWidth: 2.0,
        );

      case KinshipEdgeCategory.grandparent:
        return const KinshipEdgeStyle(
          category: KinshipEdgeCategory.grandparent,
          color: KinshipEdgeColors.grandparent,
          defaultAlpha: 0.75,
          lineShape: KinshipLineShape.solidExtendedBezier,
          dashPattern: [],
          midpointSymbol: KinshipMidpointSymbol.dot,
          midpointColor: KinshipEdgeColors.grandparent,
          strokeWidth: 2.0,
        );

      case KinshipEdgeCategory.auntUncle:
        return const KinshipEdgeStyle(
          category: KinshipEdgeCategory.auntUncle,
          color: KinshipEdgeColors.auntUncle,
          defaultAlpha: 0.7,
          lineShape: KinshipLineShape.dashedShallowS,
          dashPattern: [5.0, 4.0],
          midpointSymbol: KinshipMidpointSymbol.dot,
          midpointColor: KinshipEdgeColors.auntUncle,
          strokeWidth: 2.0,
        );

      case KinshipEdgeCategory.cousin:
        return const KinshipEdgeStyle(
          category: KinshipEdgeCategory.cousin,
          color: KinshipEdgeColors.cousin,
          defaultAlpha: 0.7,
          lineShape: KinshipLineShape.wideArcBezier,
          dashPattern: [],
          midpointSymbol: KinshipMidpointSymbol.dot,
          midpointColor: KinshipEdgeColors.cousin,
          // v2.2 spec: cousins use the thickest stroke (2.5px) — the
          // only category wider than the default 2.0px, reflecting the
          // wideArcBezier designation.
          strokeWidth: 2.5,
        );

      case KinshipEdgeCategory.inLaw:
        return const KinshipEdgeStyle(
          category: KinshipEdgeCategory.inLaw,
          color: KinshipEdgeColors.inLaw,
          defaultAlpha: 0.7,
          lineShape: KinshipLineShape.dashedStraight,
          dashPattern: [5.0, 4.0],
          midpointSymbol: KinshipMidpointSymbol.dot,
          midpointColor: KinshipEdgeColors.inLaw,
          strokeWidth: 2.0,
        );

      case KinshipEdgeCategory.extended:
        return const KinshipEdgeStyle(
          category: KinshipEdgeCategory.extended,
          color: KinshipEdgeColors.extended,
          // 0.45 alpha per spec — extended connections stay dim so the
          // core bloodline edges remain visually dominant.
          defaultAlpha: 0.45,
          lineShape: KinshipLineShape.dashedDefault,
          dashPattern: [4.0, 4.0],
          midpointSymbol: KinshipMidpointSymbol.dot,
          midpointColor: KinshipEdgeColors.extended,
          // v2.2 spec: step_adoptive uses the thinnest stroke (1.5px) —
          // the lowest visual priority of all 8 sections.
          strokeWidth: 1.5,
        );

      case KinshipEdgeCategory.indirect:
        return const KinshipEdgeStyle(
          category: KinshipEdgeCategory.indirect,
          color: KinshipEdgeColors.indirect,
          defaultAlpha: 0.5,
          lineShape: KinshipLineShape.dashedDefault,
          dashPattern: [4.0, 4.0],
          // NO dot — the absence of the dot itself signals "incomplete
          // information" per the spec. Only a text label is drawn.
          midpointSymbol: KinshipMidpointSymbol.none,
          midpointColor: KinshipEdgeColors.indirect,
          strokeWidth: 1.5,
        );
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SPOUSE KEY SET (legacy compat for graph_canvas_widget.dart)
// ═══════════════════════════════════════════════════════════════════════

/// Relationship keys that represent spouse/partner connections.
///
/// Provided as a Set for O(1) lookup by widgets that need to special-case
/// the spouse midpoint (heart) without going through the full classifier.
const Set<String> kinshipSpouseKeys = <String>{
  'husband',
  'wife',
  'spouse',
  'partner',
};

// ═══════════════════════════════════════════════════════════════════════
// ANTI-TREE-SHAKE REGISTRY
// ═══════════════════════════════════════════════════════════════════════

/// Forces dart2js to retain all color constants and the resolver methods.
///
/// dart2js aggressively tree-shakes `const` fields and static methods that
/// it determines are never read at runtime. In rare cases (especially with
/// complex delegation chains like classifier → resolver → style → color),
/// dart2js incorrectly determines that the color constants are unreachable
/// and strips them from the build — causing edges to render with wrong
/// colors or no colors.
///
/// This registry is a list of all 10 category colors, referenced from a
/// top-level `final` variable (which dart2js cannot tree-shake). Calling
/// [kinshipEdgeColorRegistry] from anywhere in the app forces all 10
/// colors to be retained in the build.
final List<Color> kinshipEdgeColorRegistry = <Color>[
  KinshipEdgeColors.self,
  KinshipEdgeColors.parent,
  KinshipEdgeColors.child,
  KinshipEdgeColors.sibling,
  KinshipEdgeColors.spouseEdge,
  KinshipEdgeColors.spouseHeart,
  KinshipEdgeColors.grandparent,
  KinshipEdgeColors.auntUncle,
  KinshipEdgeColors.cousin,
  KinshipEdgeColors.inLaw,
  KinshipEdgeColors.extended,
  KinshipEdgeColors.indirect,
];

/// Forces dart2js to retain the resolver methods by calling each one.
/// Returns the number of styles resolved (always 11).
int kinshipEdgeStyleRegistryCheck() {
  int count = 0;
  for (final cat in KinshipEdgeCategory.values) {
    final style = KinshipEdgeStyleResolver.styleForCategory(cat);
    // Access every field to prevent field-level tree-shaking.
    style.color;
    style.defaultAlpha;
    style.lineShape;
    style.dashPattern;
    style.midpointSymbol;
    style.midpointColor;
    style.strokeWidth;
    count++;
  }
  // Access the registry to prevent the list from being tree-shook.
  kinshipEdgeColorRegistry.length;
  return count;
}

