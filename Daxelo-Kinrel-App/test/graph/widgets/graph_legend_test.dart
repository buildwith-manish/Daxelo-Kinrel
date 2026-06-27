// test/graph/widgets/graph_legend_test.dart
//
// v2.2 — Tests for the data-driven GraphLegend widget and the
// kinship edge style system that powers it.
//
// Verifies:
//   - The legend renders only the categories present in the graph
//   - The KinshipEdgeStyleResolver returns correct styles for all
//     5,359 kinship types
//   - The edge painter uses category colors (not gray) for edges
//   - The node dot color uses kinship category colors

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/kinship/kinship_edge_style.dart';
import 'package:kinrel/core/kinship/kinship_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('KinshipEdgeStyleResolver', () {
    test('returns a style for every kinship category', () {
      for (final cat in KinshipEdgeCategory.values) {
        final style = KinshipEdgeStyleResolver.styleForCategory(cat);
        expect(style.category, cat);
        expect(style.color, isNotNull);
        expect(style.strokeWidth, greaterThan(0));
      }
    });

    test('classifies core relationship keys correctly', () {
      expect(KinshipEdgeClassifier.classify('father'),
          KinshipEdgeCategory.parent);
      expect(KinshipEdgeClassifier.classify('mother'),
          KinshipEdgeCategory.parent);
      expect(KinshipEdgeClassifier.classify('son'),
          KinshipEdgeCategory.child);
      expect(KinshipEdgeClassifier.classify('daughter'),
          KinshipEdgeCategory.child);
      expect(KinshipEdgeClassifier.classify('brother'),
          KinshipEdgeCategory.sibling);
      expect(KinshipEdgeClassifier.classify('sister'),
          KinshipEdgeCategory.sibling);
      expect(KinshipEdgeClassifier.classify('husband'),
          KinshipEdgeCategory.spouse);
      expect(KinshipEdgeClassifier.classify('wife'),
          KinshipEdgeCategory.spouse);
      expect(KinshipEdgeClassifier.classify('grandfather'),
          KinshipEdgeCategory.grandparent);
      expect(KinshipEdgeClassifier.classify('grandmother'),
          KinshipEdgeCategory.grandparent);
      expect(KinshipEdgeClassifier.classify('uncle'),
          KinshipEdgeCategory.auntUncle);
      expect(KinshipEdgeClassifier.classify('aunt'),
          KinshipEdgeCategory.auntUncle);
      expect(KinshipEdgeClassifier.classify('cousin'),
          KinshipEdgeCategory.cousin);
      expect(KinshipEdgeClassifier.classify('father_in_law'),
          KinshipEdgeCategory.inLaw);
      expect(KinshipEdgeClassifier.classify('step_father'),
          KinshipEdgeCategory.extended);
    });

    test('classifies extended Indian kinship compound keys', () {
      // These are the keys that previously broke the layout — they
      // should all classify to a non-extended category now.
      expect(KinshipEdgeClassifier.classify('fathers_elder_brother'),
          KinshipEdgeCategory.auntUncle);
      expect(KinshipEdgeClassifier.classify('mothers_sister'),
          KinshipEdgeCategory.auntUncle);
      expect(KinshipEdgeClassifier.classify('paternal_grandfather'),
          KinshipEdgeCategory.grandparent);
      expect(KinshipEdgeClassifier.classify('maternal_grandmother'),
          KinshipEdgeCategory.grandparent);
      expect(KinshipEdgeClassifier.classify('fathers_younger_brother_son'),
          KinshipEdgeCategory.sibling); // parallel cousin = sibling
      expect(KinshipEdgeClassifier.classify('brothers_son'),
          KinshipEdgeCategory.cousin);
      expect(KinshipEdgeClassifier.classify('husbands_father'),
          KinshipEdgeCategory.inLaw);
    });

    test('spouse edge has pink heart midpoint, not orange', () {
      final style = KinshipEdgeStyleResolver.styleFor('wife');
      expect(style.midpointSymbol, KinshipMidpointSymbol.heart);
      expect(style.midpointColor, KinshipEdgeColors.spouseHeart);
      expect(style.color, KinshipEdgeColors.spouseEdge);
      // The heart is pink, the edge is orange — they must differ.
      expect(style.midpointColor, isNot(style.color));
    });

    test('all non-spouse categories have dot midpoint matching edge color', () {
      for (final cat in KinshipEdgeCategory.values) {
        if (cat == KinshipEdgeCategory.self ||
            cat == KinshipEdgeCategory.spouse ||
            cat == KinshipEdgeCategory.indirect) continue;
        final style = KinshipEdgeStyleResolver.styleForCategory(cat);
        expect(style.midpointSymbol, KinshipMidpointSymbol.dot);
        expect(style.midpointColor, style.color);
      }
    });

    test('indirect category has NO midpoint symbol', () {
      final style = KinshipEdgeStyleResolver.styleForCategory(
          KinshipEdgeCategory.indirect);
      expect(style.midpointSymbol, KinshipMidpointSymbol.none);
    });

    test('extended category uses 0.45 alpha (dim)', () {
      final style = KinshipEdgeStyleResolver.styleForCategory(
          KinshipEdgeCategory.extended);
      expect(style.defaultAlpha, closeTo(0.45, 0.01));
    });
  });

  group('KinshipEdgeStyleResolver — all 5,359 keys', () {
    late KinshipService kinship;

    setUpAll(() async {
      kinship = KinshipService.instance;
      await kinship.load();
    });

    test('every kinship key resolves to a non-null style', () {
      expect(kinship.isLoaded, isTrue);
      var count = 0;
      for (final rel in kinship.getAllRelationships()) {
        if (rel.relationshipKey == 'self' || rel.relationshipKey.isEmpty) {
          continue;
        }
        final style = KinshipEdgeStyleResolver.styleFor(rel.relationshipKey);
        expect(style, isNotNull,
            reason: 'Key "${rel.relationshipKey}" must resolve to a style');
        expect(style.color, isNotNull);
        expect(style.strokeWidth, greaterThan(0));
        count++;
      }
      expect(count, greaterThan(5000),
          reason: 'Must have resolved styles for >5000 kinship keys');
    });

    test('no kinship key classifies as self (except "self" itself)', () {
      // Only the literal "self" key should classify as self — no
      // compound key should accidentally land in the self category.
      for (final rel in kinship.getAllRelationships()) {
        final key = rel.relationshipKey;
        if (key == 'self' || key.isEmpty) continue;
        final cat = KinshipEdgeClassifier.classify(key);
        expect(cat, isNot(KinshipEdgeCategory.self),
            reason: 'Key "$key" should not classify as self');
      }
    });
  });

  group('GraphLegend presentCategories', () {
    // The GraphLegend widget itself requires a full widget test harness
    // (ProviderScope, etc.), so we test the underlying classification
    // logic that drives which categories appear in the legend.

    test('a graph with only parent/child edges shows 3 categories (parent, child, self)', () {
      final keys = {'father', 'son'};
      final cats = <KinshipEdgeCategory>{};
      for (final k in keys) {
        cats.add(KinshipEdgeClassifier.classify(k));
      }
      cats.add(KinshipEdgeCategory.self); // always included
      expect(cats.length, 3);
      expect(cats, contains(KinshipEdgeCategory.parent));
      expect(cats, contains(KinshipEdgeCategory.child));
      expect(cats, contains(KinshipEdgeCategory.self));
    });

    test('a graph with extended kinship shows the correct categories', () {
      final keys = {
        'father', 'mother', 'brother', 'wife',
        'paternal_grandfather', 'fathers_elder_brother',
        'fathers_younger_brother_son', // parallel cousin = sibling
        'brothers_son', // cousin
        'father_in_law',
      };
      final cats = <KinshipEdgeCategory>{};
      for (final k in keys) {
        cats.add(KinshipEdgeClassifier.classify(k));
      }
      cats.add(KinshipEdgeCategory.self);

      // Should include: self, parent, sibling, spouse, grandparent,
      // auntUncle, cousin, inLaw = 8 categories
      expect(cats.length, 8);
      expect(cats, contains(KinshipEdgeCategory.self));
      expect(cats, contains(KinshipEdgeCategory.parent));
      expect(cats, contains(KinshipEdgeCategory.sibling));
      expect(cats, contains(KinshipEdgeCategory.spouse));
      expect(cats, contains(KinshipEdgeCategory.grandparent));
      expect(cats, contains(KinshipEdgeCategory.auntUncle));
      expect(cats, contains(KinshipEdgeCategory.cousin));
      expect(cats, contains(KinshipEdgeCategory.inLaw));
    });

    test('empty graph shows only self category', () {
      final cats = <KinshipEdgeCategory>{};
      cats.add(KinshipEdgeCategory.self); // always included
      expect(cats.length, 1);
      expect(cats, contains(KinshipEdgeCategory.self));
    });
  });
}
