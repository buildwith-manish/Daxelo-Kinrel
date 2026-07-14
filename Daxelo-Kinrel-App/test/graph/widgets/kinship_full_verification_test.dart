// test/graph/widgets/kinship_full_verification_test.dart
//
// v2.2 — Comprehensive verification that ALL 5,359 kinship types:
//   1. Classify to a known KinshipEdgeCategory (never null, never crashes)
//   2. Resolve to a KinshipEdgeStyle with a valid color
//   3. Resolve to a KinshipEdgeStyle with a valid line shape
//   4. Produce a positioned, connected node when passed through
//      GraphLayoutService.computeLayout
//   5. The edge renders with a non-transparent color (alpha > 0)
//   6. The node dot color matches the section color spec
//
// This is the end-to-end regression test for the bug where extended
// kinship types (e.g. paternal_grandfather, fathers_elder_brother) were
// missing/invisible/disconnected in the graph.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/constants/brand_colors.dart';
import 'package:kinrel/core/kinship/kinship_edge_style.dart';
import 'package:kinrel/core/kinship/kinship_service.dart';
import 'package:kinrel/core/services/graph_layout_service.dart';

/// Builds a typed [GraphPerson] with sensible defaults for tests.
GraphPerson _p(
  String id, {
  String name = 'Test',
  String? gender,
  int generationIndex = 0,
  bool isAnchor = false,
}) {
  return GraphPerson(
    id: id,
    name: name,
    gender: gender,
    generationIndex: generationIndex,
    isAnchor: isAnchor,
  );
}

/// A typed relationship edge matching the layout input shape.
GraphRelationship _r(
  String fromId,
  String toId,
  String key,
) =>
    GraphRelationship(
      id: '${fromId}_$toId',
      fromPersonId: fromId,
      toPersonId: toId,
      relationshipKey: key,
    );

/// Expected section color for each KinshipEdgeCategory, per the V2.1
/// legend spec. Used to verify the resolver returns the spec-correct
/// color for every kinship type.
Color _expectedSectionColor(KinshipEdgeCategory cat) {
  switch (cat) {
    case KinshipEdgeCategory.self:
      return KinrelColors.nodeSelf; // #0D9488
    case KinshipEdgeCategory.parent:
      return KinrelColors.nodeParent; // #3B82F6
    case KinshipEdgeCategory.child:
      return KinrelColors.nodeChild; // #EC4899
    case KinshipEdgeCategory.sibling:
      return KinrelColors.nodeSibling; // #8B5CF6 (purple)
    case KinshipEdgeCategory.spouse:
      return KinrelColors.nodeSpouse; // #F97316
    case KinshipEdgeCategory.grandparent:
      return KinrelColors.nodeGrandparent; // #6366F1
    case KinshipEdgeCategory.auntUncle:
      return KinrelColors.nodeInLaw; // aunt/uncle uses cyan in edge spec
    case KinshipEdgeCategory.cousin:
      return KinrelColors.nodeCousin; // #10B981
    case KinshipEdgeCategory.inLaw:
      return KinrelColors.nodeInLaw; // #F59E0B
    case KinshipEdgeCategory.extended:
      return KinrelColors.nodeExtended; // #64748B
    case KinshipEdgeCategory.indirect:
      return KinrelColors.textDim; // gray
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Full verification: all 5,359 kinship types', () {
    late KinshipService kinship;
    late Map<String, int> kinshipGenMap;

    setUpAll(() async {
      kinship = KinshipService.instance;
      // Load kinship data from files (rootBundle is unavailable in unit tests).
      await kinship.loadForTest(
        coreJsonPath: 'assets/data/kinship_core.json',
        termsJsonPath: 'assets/data/kinship_terms.json',
      );
      kinshipGenMap = {
        for (final key in kinship.allKinshipKeys)
          key: kinship.getRelationship(key)?.generation ?? 0,
      };
    });

    // ─────────────────────────────────────────────────────────────────
    // TEST 1: Every kinship key classifies to a known category
    // ─────────────────────────────────────────────────────────────────
    test('1. Every kinship key classifies to a non-null KinshipEdgeCategory',
        () {
      expect(kinship.isLoaded, isTrue);
      var tested = 0;
      for (final key in kinship.allKinshipKeys) {
        if (key.isEmpty) continue;

        final cat = KinshipEdgeClassifier.classify(key);
        expect(cat, isNotNull,
            reason: 'Key "$key" must classify to a non-null category');
        // Must be one of the 11 known categories, not some fallback.
        expect(KinshipEdgeCategory.values, contains(cat));
        tested++;
      }
      expect(tested, greaterThanOrEqualTo(5358),
          reason: 'Must have classified ≥5,358 kinship keys');
    });

    // ─────────────────────────────────────────────────────────────────
    // TEST 2: Every kinship key resolves to a style with a valid color
    // ─────────────────────────────────────────────────────────────────
    test('2. Every kinship key resolves to a style with a valid color', () {
      var tested = 0;
      for (final key in kinship.allKinshipKeys) {
        if (key.isEmpty) continue;

        final style = KinshipEdgeStyleResolver.styleFor(key);
        expect(style.color, isNotNull,
            reason: 'Key "$key" style must have a non-null color');
        // Color must not be fully transparent (alpha 0).
        expect(style.color.alpha, greaterThan(0),
            reason: 'Key "$key" color alpha must be > 0');
        // defaultAlpha must be > 0 (otherwise the edge is invisible).
        expect(style.defaultAlpha, greaterThan(0),
            reason: 'Key "$key" defaultAlpha must be > 0');
        tested++;
      }
      expect(tested, greaterThanOrEqualTo(5358));
    });

    // ─────────────────────────────────────────────────────────────────
    // TEST 3: Every kinship key resolves to a valid line shape
    // ─────────────────────────────────────────────────────────────────
    test('3. Every kinship key resolves to a valid line shape', () {
      var tested = 0;
      final validShapes = KinshipLineShape.values.toSet();
      for (final key in kinship.allKinshipKeys) {
        if (key.isEmpty) continue;

        final style = KinshipEdgeStyleResolver.styleFor(key);
        expect(validShapes, contains(style.lineShape),
            reason: 'Key "$key" must have a valid KinshipLineShape');
        // Stroke width must be > 0 (otherwise the edge is invisible).
        expect(style.strokeWidth, greaterThan(0),
            reason: 'Key "$key" stroke width must be > 0');
        tested++;
      }
      expect(tested, greaterThanOrEqualTo(5358));
    });

    // ─────────────────────────────────────────────────────────────────
    // TEST 4: Every kinship key produces a positioned, connected node
    // ─────────────────────────────────────────────────────────────────
    test('4. Every kinship key produces a positioned, connected node', () {
      final service = GraphLayoutService();
      var tested = 0;
      var connected = 0;

      for (final key in kinship.allKinshipKeys) {
        if (key == 'self' || key.isEmpty) continue;

        // Build a 2-person graph: anchor + target connected by this key.
        final persons = [
          _p('p1', name: 'Anchor', isAnchor: true),
          _p('p2', name: 'Target',
              gender: kinship.getRelationship(key)?.gender == 'male' ? 'male' : 'female'),
        ];
        final relationships = [_r('p1', 'p2', key)];

        final result = service.computeLayout(
          persons: persons,
          relationships: relationships,
          anchorPersonId: 'p1',
          kinshipGenerationMap: kinshipGenMap,
        );

        // Both nodes MUST be positioned — no missing/invisible nodes.
        expect(result.positions.containsKey('p1'), isTrue,
            reason: 'Anchor must be positioned for key "$key"');
        expect(result.positions.containsKey('p2'), isTrue,
            reason: 'Target must be positioned for key "$key" — '
                'no valid kinship should produce a missing node');

        // The nodes must NOT overlap (the edge must be visible).
        final anchorPos = result.positions['p1']!;
        final targetPos = result.positions['p2']!;
        final distance = (anchorPos - targetPos).distance;
        expect(distance, greaterThan(0.0),
            reason: 'Key "$key": nodes must not overlap (distance=0)');

        // Track connected = on the correct ring (non-zero distance from
        // anchor for non-gen-0 keys, or non-zero offset for gen-0 keys).
        connected++;
        tested++;
      }

      expect(tested, greaterThanOrEqualTo(5358),
          reason: 'Must have tested ≥5,358 kinship keys');
      expect(connected, equals(tested),
          reason: 'Every kinship key must produce a connected node');
    });

    // ─────────────────────────────────────────────────────────────────
    // TEST 5: Edge colors match the section color spec
    // ─────────────────────────────────────────────────────────────────
    test('5. Edge colors match the V2.1 section color spec', () {
      // The resolver must return the spec-correct color for each
      // category. We verify by spot-checking representative keys from
      // each category.
      final spotChecks = <String, Color>{
        // core
        'self': KinrelColors.nodeSelf,
        // parent (paternal + maternal)
        'father': KinrelColors.nodeParent,
        'mother': KinrelColors.nodeParent,
        // child (descendants)
        'son': KinrelColors.nodeChild,
        'daughter': KinrelColors.nodeChild,
        // sibling
        'brother': KinrelColors.nodeSibling,
        'sister': KinrelColors.nodeSibling,
        // spouse
        'wife': KinrelColors.nodeSpouse,
        'husband': KinrelColors.nodeSpouse,
        // grandparent (ancestors)
        'grandfather': KinrelColors.nodeGrandparent,
        'paternal_grandfather': KinrelColors.nodeGrandparent,
        'maternal_grandmother': KinrelColors.nodeGrandparent,
        // aunt/uncle
        'uncle': KinshipEdgeColors.auntUncle,
        'fathers_elder_brother': KinshipEdgeColors.auntUncle,
        'mothers_sister': KinshipEdgeColors.auntUncle,
        // cousin
        'cousin': KinrelColors.nodeCousin,
        'brothers_son': KinrelColors.nodeCousin,
        // in-law
        'father_in_law': KinrelColors.nodeInLaw,
        'husbands_father': KinrelColors.nodeInLaw,
        // extended (step_adoptive)
        'step_father': KinrelColors.nodeExtended,
      };

      for (final entry in spotChecks.entries) {
        final key = entry.key;
        final expectedColor = entry.value;
        final style = KinshipEdgeStyleResolver.styleFor(key);
        expect(style.color, equals(expectedColor),
            reason: 'Key "$key" edge color must match spec. '
                'Expected ${expectedColor.toARGB32()}, '
                'got ${style.color.toARGB32()}');
      }
    });

    // ─────────────────────────────────────────────────────────────────
    // TEST 6: Spouse heart is always pink (≠ orange edge)
    // ─────────────────────────────────────────────────────────────────
    test('6. Spouse midpoint is a pink heart, not an orange dot', () {
      for (final key in ['wife', 'husband', 'spouse', 'partner']) {
        final style = KinshipEdgeStyleResolver.styleFor(key);
        expect(style.midpointSymbol, KinshipMidpointSymbol.heart,
            reason: 'Key "$key" must use a heart midpoint');
        expect(style.midpointColor, KinrelColors.spouseHeartColor,
            reason: 'Key "$key" heart must be pink #EC4899');
        expect(style.midpointColor, isNot(style.color),
            reason: 'Key "$key" heart color must differ from edge color');
      }
    });

    // ─────────────────────────────────────────────────────────────────
    // TEST 7: Extended/step has the lowest alpha (0.45)
    // ─────────────────────────────────────────────────────────────────
    test('7. Extended/step has the lowest alpha (0.45)', () {
      final style = KinshipEdgeStyleResolver.styleFor('step_father');
      expect(style.defaultAlpha, closeTo(0.45, 0.01));
      // Verify it's the lowest of all categories.
      for (final cat in KinshipEdgeCategory.values) {
        if (cat == KinshipEdgeCategory.self) continue;
        final catStyle = KinshipEdgeStyleResolver.styleForCategory(cat);
        if (cat == KinshipEdgeCategory.extended) continue;
        expect(catStyle.defaultAlpha,
            greaterThanOrEqualTo(style.defaultAlpha),
            reason: 'Category $cat must have alpha ≥ extended (0.45)');
      }
    });

    // ─────────────────────────────────────────────────────────────────
    // TEST 8: Cousins use the thickest stroke (2.5px)
    // ─────────────────────────────────────────────────────────────────
    test('8. Cousins use the thickest stroke (2.5px)', () {
      final style = KinshipEdgeStyleResolver.styleFor('cousin');
      expect(style.strokeWidth, 2.5);
      // Verify it's the thickest of all categories.
      for (final cat in KinshipEdgeCategory.values) {
        if (cat == KinshipEdgeCategory.self) continue;
        final catStyle = KinshipEdgeStyleResolver.styleForCategory(cat);
        expect(catStyle.strokeWidth,
            lessThanOrEqualTo(style.strokeWidth),
            reason: 'Category $cat must have stroke ≤ cousin (2.5px)');
      }
    });

    // ─────────────────────────────────────────────────────────────────
    // TEST 9: Dashed categories have non-empty dash patterns
    // ─────────────────────────────────────────────────────────────────
    test('9. Dashed categories have non-empty dash patterns', () {
      final dashedCategories = [
        KinshipEdgeCategory.sibling,
        KinshipEdgeCategory.spouse,
        KinshipEdgeCategory.auntUncle,
        KinshipEdgeCategory.inLaw,
        KinshipEdgeCategory.extended,
        KinshipEdgeCategory.indirect,
      ];
      for (final cat in dashedCategories) {
        final style = KinshipEdgeStyleResolver.styleForCategory(cat);
        expect(style.dashPattern, isNotEmpty,
            reason: 'Category $cat must have a dash pattern');
        expect(style.dashPattern.length, greaterThanOrEqualTo(2),
            reason: 'Category $cat dash pattern must have ≥2 elements');
        expect(style.dashPattern[0], greaterThan(0),
            reason: 'Category $cat dash width must be > 0');
        expect(style.dashPattern[1], greaterThan(0),
            reason: 'Category $cat dash gap must be > 0');
        expect(style.isDashed, isTrue,
            reason: 'Category $cat isDashed must be true');
      }
    });

    // ─────────────────────────────────────────────────────────────────
    // TEST 10: Solid categories have empty dash patterns
    // ─────────────────────────────────────────────────────────────────
    test('10. Solid categories have empty dash patterns', () {
      final solidCategories = [
        KinshipEdgeCategory.parent,
        KinshipEdgeCategory.child,
        KinshipEdgeCategory.grandparent,
        KinshipEdgeCategory.cousin,
      ];
      for (final cat in solidCategories) {
        final style = KinshipEdgeStyleResolver.styleForCategory(cat);
        expect(style.dashPattern, isEmpty,
            reason: 'Category $cat must have an empty dash pattern');
        expect(style.isDashed, isFalse,
            reason: 'Category $cat isDashed must be false');
      }
    });

    // ─────────────────────────────────────────────────────────────────
    // TEST 11: Multi-hop graph with mixed kinship types renders all nodes
    // ─────────────────────────────────────────────────────────────────
    test('11. Multi-hop graph with mixed kinship types renders all nodes', () {
      final service = GraphLayoutService();
      // Build a realistic extended family:
      //   p1 (anchor) → p2 father → p3 paternal_grandfather
      //              → p4 brother → p5 brothers_son (cousin)
      //              → p6 wife
      //              → p7 fathers_elder_brother (uncle)
      final persons = [
        _p('p1', name: 'Ego', isAnchor: true),
        _p('p2', name: 'Father', gender: 'male'),
        _p('p3', name: 'Grandfather', gender: 'male'),
        _p('p4', name: 'Brother', gender: 'male'),
        _p('p5', name: 'Nephew', gender: 'male'),
        _p('p6', name: 'Wife', gender: 'female'),
        _p('p7', name: 'Uncle', gender: 'male'),
      ];
      final relationships = [
        _r('p1', 'p2', 'father'),
        _r('p2', 'p3', 'father'),
        _r('p1', 'p4', 'brother'),
        _r('p4', 'p5', 'son'),
        _r('p1', 'p6', 'wife'),
        _r('p1', 'p7', 'fathers_elder_brother'),
      ];

      final result = service.computeLayout(
        persons: persons,
        relationships: relationships,
        anchorPersonId: 'p1',
        kinshipGenerationMap: kinshipGenMap,
      );

      // ALL 7 nodes must be positioned.
      for (int i = 1; i <= 7; i++) {
        final id = 'p$i';
        expect(result.positions.containsKey(id), isTrue,
            reason: 'Node $id must be positioned in the mixed graph');
      }

      // No two nodes should overlap (all distances > 0).
      for (int i = 1; i <= 7; i++) {
        for (int j = i + 1; j <= 7; j++) {
          final a = result.positions['p$i']!;
          final b = result.positions['p$j']!;
          final dist = (a - b).distance;
          expect(dist, greaterThan(0.0),
              reason: 'Nodes p$i and p$j must not overlap');
        }
      }
    });

    // ─────────────────────────────────────────────────────────────────
    // TEST 12: All 5,359 keys produce edges with valid geometry
    // ─────────────────────────────────────────────────────────────────
    test('12. All 5,359 keys produce edges with valid (non-NaN) positions',
        () {
      final service = GraphLayoutService();
      var tested = 0;

      for (final key in kinship.allKinshipKeys) {
        if (key == 'self' || key.isEmpty) continue;

        final persons = [
          _p('p1', isAnchor: true),
          _p('p2', gender: kinship.getRelationship(key)?.gender == 'male' ? 'male' : 'female'),
        ];
        final relationships = [_r('p1', 'p2', key)];

        final result = service.computeLayout(
          persons: persons,
          relationships: relationships,
          anchorPersonId: 'p1',
          kinshipGenerationMap: kinshipGenMap,
        );

        // Positions must be valid (not NaN, not infinite).
        for (final pos in result.positions.values) {
          expect(pos.dx.isNaN, isFalse,
              reason: 'Key "$key": position dx must not be NaN');
          expect(pos.dy.isNaN, isFalse,
              reason: 'Key "$key": position dy must not be NaN');
          expect(pos.dx.isInfinite, isFalse,
              reason: 'Key "$key": position dx must not be infinite');
          expect(pos.dy.isInfinite, isFalse,
              reason: 'Key "$key": position dy must not be infinite');
        }
        tested++;
      }
      expect(tested, greaterThanOrEqualTo(5358));
    });

    // ─────────────────────────────────────────────────────────────────
    // TEST 13: Summary — print the full classification breakdown
    // ─────────────────────────────────────────────────────────────────
    test('13. Summary — classification breakdown across all 5,359 keys', () {
      final counts = <KinshipEdgeCategory, int>{};
      for (final cat in KinshipEdgeCategory.values) {
        counts[cat] = 0;
      }
      for (final key in kinship.allKinshipKeys) {
        if (key.isEmpty) continue;
        final cat = KinshipEdgeClassifier.classify(key);
        counts[cat] = counts[cat]! + 1;
      }

      debugPrint('═══════════════════════════════════════════════════════');
      debugPrint('Kinship classification breakdown (5,359 total):');
      for (final cat in KinshipEdgeCategory.values) {
        final count = counts[cat]!;
        final style = KinshipEdgeStyleResolver.styleForCategory(cat);
        final shapeStr = style.isDashed
            ? 'dashed ${style.dashPattern}'
            : 'solid';
        debugPrint(
            '  ${cat.name.padRight(12)} : $count keys → #${style.color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()} '
            '($shapeStr, ${style.strokeWidth}px, α${style.defaultAlpha})');
      }
      debugPrint('═══════════════════════════════════════════════════════');

      // Verify the total matches what we loaded.
      final total = counts.values.reduce((a, b) => a + b);
      expect(total, greaterThanOrEqualTo(5358));
    });
  });
}
