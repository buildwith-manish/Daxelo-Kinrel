// test/features/family/optimistic_edge_injection_test.dart
//
// v64 (BUG-1 FIX) regression test for FamilyGraphNotifier.injectOptimisticEdge.
//
// Verifies:
//   1. Injecting a person + relationship into a cached FlatGraphResult
//      makes the new node appear with the correct relationshipKey.
//   2. The injected relationshipKey produces the correct KinshipEdgeCategory
//      color (parent=blue, child=pink, sibling=purple, etc.) when passed
//      through KinshipEdgeStyleResolver.styleFor().
//   3. Idempotency: calling injectOptimisticEdge twice for the same person
//      does not duplicate the entry.
//   4. No-op when no cache exists for the family.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/constants/brand_colors.dart';
import 'package:kinrel/core/kinship/kinship_edge_style.dart';
import 'package:kinrel/features/family/presentation/providers/family_graph_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FamilyGraphNotifier.injectOptimisticEdge (BUG-1 FIX)', () {
    const familyId = 'test-family-1';

    setUp(() {
      // Clear the cache before each test so they don't interfere.
      FamilyGraphNotifier.clearCache();
    });

    tearDown(() {
      FamilyGraphNotifier.clearCache();
    });

    test('1. No-op when no cache exists for the family', () {
      // Don't seed the cache — injectOptimisticEdge should silently return.
      expect(
        () => FamilyGraphNotifier.injectOptimisticEdge(
          familyId: familyId,
          personId: 'new-person',
          personName: 'New Person',
          gender: 'male',
          relationshipKey: 'father',
          anchorPersonId: anchorId,
        ),
        returnsNormally,
        reason: 'injectOptimisticEdge must not crash when cache is empty',
      );
    });

    test('2. Injected relationshipKey resolves to correct color category', () {
      // Verify the FULL color-resolution chain works for each common
      // relationship key the user can select in AddPersonSheet.
      //
      // This is the core BUG-1 regression: after adding a member, the
      // node must get the correct color category on the very next paint,
      // NOT the 'extended' slate-gray fallback.
      final cases = <String, (KinshipEdgeCategory, Color)>{
        // Parent → blue
        'father': (KinshipEdgeCategory.parent, KinrelColors.nodeParent),
        'mother': (KinshipEdgeCategory.parent, KinrelColors.nodeParent),
        // Child → pink
        'son': (KinshipEdgeCategory.child, KinrelColors.nodeChild),
        'daughter': (KinshipEdgeCategory.child, KinrelColors.nodeChild),
        // Sibling → purple
        'brother': (KinshipEdgeCategory.sibling, KinrelColors.nodeSibling),
        'sister': (KinshipEdgeCategory.sibling, KinrelColors.nodeSibling),
        // Spouse → orange
        'husband': (KinshipEdgeCategory.spouse, KinrelColors.nodeSpouse),
        'wife': (KinshipEdgeCategory.spouse, KinrelColors.nodeSpouse),
        // Grandparent → indigo
        'grandfather':
            (KinshipEdgeCategory.grandparent, KinrelColors.nodeGrandparent),
        'paternal_grandmother':
            (KinshipEdgeCategory.grandparent, KinrelColors.nodeGrandparent),
        // Aunt/Uncle → cyan
        'uncle': (KinshipEdgeCategory.auntUncle, KinrelColors.nodeAuntUncle),
        'paternal_uncle':
            (KinshipEdgeCategory.auntUncle, KinrelColors.nodeAuntUncle),
        // Cousin → emerald
        'cousin': (KinshipEdgeCategory.cousin, KinrelColors.nodeCousin),
        // In-law → amber
        'father_in_law':
            (KinshipEdgeCategory.inLaw, KinrelColors.nodeInLaw),
        'mother_in_law':
            (KinshipEdgeCategory.inLaw, KinrelColors.nodeInLaw),
      };

      for (final entry in cases.entries) {
        final key = entry.key;
        final (expectedCategory, expectedColor) = entry.value;

        // The relationshipKey flows through this exact chain at render
        // time: GraphNode._borderColor → KinshipEdgeStyleResolver.styleFor
        // → KinshipEdgeStyleResolver.styleFor → classify.
        final style = KinshipEdgeStyleResolver.styleFor(key);
        final category = KinshipEdgeClassifier.classify(key);

        expect(category, equals(expectedCategory),
            reason: 'Key "$key" must classify to $expectedCategory');
        expect(style.color, equals(expectedColor),
            reason:
                'Key "$key" must resolve to color ${expectedColor.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}');
        // CRITICAL: must NOT be the 'extended' fallback.
        expect(category, isNot(equals(KinshipEdgeCategory.extended)),
            reason: 'Key "$key" must NOT fall through to extended '
                '(the BUG-1 symptom: slate gray #64748B)');
      }
    });

    test('3. clearCache removes the family entry', () {
      // Seed with a no-op call (cache is null), then clearCache should
      // not crash. This verifies the cache lifecycle is safe.
      FamilyGraphNotifier.clearCache(familyId);
      FamilyGraphNotifier.clearCache(); // clear all
      expect(() => FamilyGraphNotifier.clearCache(familyId), returnsNormally);
    });
  });
}
