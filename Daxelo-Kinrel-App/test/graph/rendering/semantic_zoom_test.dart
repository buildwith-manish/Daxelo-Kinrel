// test/graph/rendering/semantic_zoom_test.dart
//
// Phase 3 — Semantic Zoom Presentation Tiers tests.
//
// Tests:
//   1. tier selection (NEAR/MEDIUM/FAR at correct zoom ranges)
//   2. threshold transitions (enter/leave boundaries)
//   3. hysteresis (no flicker when zoom oscillates near threshold)
//   4. focused-node tier override (discoverable at FAR)
//   5. selected-node override (discoverable at FAR)
//   6. dot LOD remains reachable
//   7. far tier excludes premium shadows
//   8. path remains discoverable

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/rendering/semantic_zoom.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 3 — Tier selection', () {
    test('TEST 1: NEAR tier at zoom >= 1.0 (initial, no hysteresis)', () {
      expect(computeSemanticTier(1.0), SemanticTier.near);
      expect(computeSemanticTier(1.5), SemanticTier.near);
      expect(computeSemanticTier(2.5), SemanticTier.near);
    });

    test('TEST 1: MEDIUM tier at 0.72 <= zoom < 1.0', () {
      expect(computeSemanticTier(0.72), SemanticTier.medium);
      expect(computeSemanticTier(0.8), SemanticTier.medium);
      expect(computeSemanticTier(0.99), SemanticTier.medium);
    });

    test('TEST 1: FAR tier at zoom < 0.65', () {
      expect(computeSemanticTier(0.64), SemanticTier.far);
      expect(computeSemanticTier(0.3), SemanticTier.far);
      expect(computeSemanticTier(0.1), SemanticTier.far);
    });
  });

  group('Phase 3 — Threshold transitions', () {
    test('TEST 2: NEAR → MEDIUM transition at nearLeave (0.92)', () {
      // Start at NEAR (zoom=1.0)
      var tier = computeSemanticTier(1.0);
      expect(tier, SemanticTier.near);

      // Zoom out to just above nearLeave → still NEAR
      tier = computeSemanticTier(0.93, currentTier: tier);
      expect(tier, SemanticTier.near);

      // Zoom out past nearLeave → MEDIUM
      tier = computeSemanticTier(0.91, currentTier: tier);
      expect(tier, SemanticTier.medium);
    });

    test('TEST 2: MEDIUM → NEAR transition at nearEnter (1.0)', () {
      // Start at MEDIUM (zoom=0.8)
      var tier = computeSemanticTier(0.8);
      expect(tier, SemanticTier.medium);

      // Zoom in to just below nearEnter → still MEDIUM
      tier = computeSemanticTier(0.99, currentTier: tier);
      expect(tier, SemanticTier.medium);

      // Zoom in past nearEnter → NEAR
      tier = computeSemanticTier(1.01, currentTier: tier);
      expect(tier, SemanticTier.near);
    });

    test('TEST 2: MEDIUM → FAR transition at mediumLeave (0.65)', () {
      var tier = computeSemanticTier(0.8);
      expect(tier, SemanticTier.medium);

      tier = computeSemanticTier(0.66, currentTier: tier);
      expect(tier, SemanticTier.medium);

      tier = computeSemanticTier(0.64, currentTier: tier);
      expect(tier, SemanticTier.far);
    });

    test('TEST 2: FAR → MEDIUM transition at mediumEnter (0.72)', () {
      var tier = computeSemanticTier(0.5);
      expect(tier, SemanticTier.far);

      tier = computeSemanticTier(0.71, currentTier: tier);
      expect(tier, SemanticTier.far);

      tier = computeSemanticTier(0.73, currentTier: tier);
      expect(tier, SemanticTier.medium);
    });
  });

  group('Phase 3 — Hysteresis (no flicker)', () {
    test('TEST 3: zoom oscillating around nearEnter does NOT flap', () {
      // Start at MEDIUM (zoom=0.95)
      var tier = computeSemanticTier(0.95);
      expect(tier, SemanticTier.medium);

      // Zoom up to 1.0 → NEAR
      tier = computeSemanticTier(1.0, currentTier: tier);
      expect(tier, SemanticTier.near);

      // Zoom back down to 0.95 → still NEAR (hysteresis: nearLeave=0.92)
      tier = computeSemanticTier(0.95, currentTier: tier);
      expect(tier, SemanticTier.near,
          reason: 'Hysteresis: should stay NEAR until zoom < 0.92');

      // Zoom down past nearLeave → MEDIUM
      tier = computeSemanticTier(0.91, currentTier: tier);
      expect(tier, SemanticTier.medium);

      // Zoom back up to 0.95 → still MEDIUM (hysteresis: nearEnter=1.0)
      tier = computeSemanticTier(0.95, currentTier: tier);
      expect(tier, SemanticTier.medium,
          reason: 'Hysteresis: should stay MEDIUM until zoom >= 1.0');
    });

    test('TEST 3: zoom oscillating around mediumEnter does NOT flap', () {
      var tier = computeSemanticTier(0.6);
      expect(tier, SemanticTier.far);

      // Zoom up past mediumEnter → MEDIUM
      tier = computeSemanticTier(0.73, currentTier: tier);
      expect(tier, SemanticTier.medium);

      // Zoom back down to 0.68 → still MEDIUM (hysteresis: mediumLeave=0.65)
      tier = computeSemanticTier(0.68, currentTier: tier);
      expect(tier, SemanticTier.medium);

      // Zoom down past mediumLeave → FAR
      tier = computeSemanticTier(0.64, currentTier: tier);
      expect(tier, SemanticTier.far);
    });
  });

  group('Phase 3 — Focused-node tier override', () {
    test('TEST 4: focused node is emphasised at FAR zoom', () {
      final isEmphasised = shouldOverrideFarTier(
        nodeId: 'person-A',
        focusedPersonId: 'person-A',
        selectedPersonId: null,
        pathNodeIds: null,
      );
      expect(isEmphasised, isTrue,
          reason: 'Focused node must be discoverable at FAR zoom');
    });

    test('non-focused node is NOT emphasised', () {
      final isEmphasised = shouldOverrideFarTier(
        nodeId: 'person-B',
        focusedPersonId: 'person-A',
        selectedPersonId: null,
        pathNodeIds: null,
      );
      expect(isEmphasised, isFalse);
    });
  });

  group('Phase 3 — Selected-node override', () {
    test('TEST 5: selected node is emphasised at FAR zoom', () {
      final isEmphasised = shouldOverrideFarTier(
        nodeId: 'person-C',
        focusedPersonId: null,
        selectedPersonId: 'person-C',
        pathNodeIds: null,
      );
      expect(isEmphasised, isTrue,
          reason: 'Selected node must be discoverable at FAR zoom');
    });
  });

  group('Phase 3 — Dot LOD remains reachable', () {
    test('TEST 6: FAR tier maps to dot LOD', () {
      expect(semanticTierToLodName(SemanticTier.far), 'dot');
      expect(semanticTierToLodName(SemanticTier.medium), 'chip');
      expect(semanticTierToLodName(SemanticTier.near), 'full');
    });

    test('TEST 6: FAR tier is reachable at low zoom', () {
      // With no hysteresis memory, zoom=0.5 → FAR
      expect(computeSemanticTier(0.5), SemanticTier.far);
      // With hysteresis memory, starting from FAR, zoom=0.5 stays FAR
      var tier = computeSemanticTier(0.5);
      tier = computeSemanticTier(0.5, currentTier: tier);
      expect(tier, SemanticTier.far);
    });
  });

  group('Phase 3 — Far tier excludes premium shadows', () {
    test('TEST 7: farTierExcludesPremiumEffects returns true for FAR', () {
      expect(farTierExcludesPremiumEffects(SemanticTier.far), isTrue);
    });

    test('TEST 7: farTierExcludesPremiumEffects returns false for NEAR/MEDIUM', () {
      expect(farTierExcludesPremiumEffects(SemanticTier.near), isFalse);
      expect(farTierExcludesPremiumEffects(SemanticTier.medium), isFalse);
    });

    test('TEST 7: shouldRenderText returns false at FAR', () {
      expect(shouldRenderText(SemanticTier.far), isFalse,
          reason: 'No text at FAR zoom — unreadable');
    });
  });

  group('Phase 3 — Path remains discoverable', () {
    test('TEST 8: path nodes are emphasised at FAR zoom', () {
      final pathNodeIds = {'person-X', 'person-Y', 'person-Z'};
      expect(
        shouldOverrideFarTier(
          nodeId: 'person-X',
          focusedPersonId: null,
          selectedPersonId: null,
          pathNodeIds: pathNodeIds,
        ),
        isTrue,
        reason: 'Path nodes must be discoverable at FAR zoom',
      );
    });

    test('TEST 8: non-path nodes are NOT emphasised', () {
      final pathNodeIds = {'person-X', 'person-Y'};
      expect(
        shouldOverrideFarTier(
          nodeId: 'person-W',
          focusedPersonId: null,
          selectedPersonId: null,
          pathNodeIds: pathNodeIds,
        ),
        isFalse,
      );
    });

    test('TEST 8: farTierDotRadius is larger for emphasised nodes', () {
      final normalRadius = farTierDotRadius(
        nodeId: 'person-A',
        focusedPersonId: null,
        selectedPersonId: null,
        pathNodeIds: null,
      );
      final emphasisedRadius = farTierDotRadius(
        nodeId: 'person-A',
        focusedPersonId: 'person-A',
        selectedPersonId: null,
        pathNodeIds: null,
      );
      expect(emphasisedRadius, greaterThan(normalRadius),
          reason: 'Emphasised dots must be larger for discoverability');
      expect(normalRadius, 6.0);
      expect(emphasisedRadius, 9.0);
    });
  });

  group('Phase 3 — Hysteresis thresholds', () {
    test('default thresholds have correct enter/leave values', () {
      const t = defaultThresholds;
      expect(t.nearEnter, 1.0);
      expect(t.nearLeave, 0.92);
      expect(t.mediumEnter, 0.72);
      expect(t.mediumLeave, 0.65);
    });

    test('hysteresis margins are positive', () {
      const t = defaultThresholds;
      expect(t.nearHysteresis, greaterThan(0));
      expect(t.mediumHysteresis, greaterThan(0));
    });
  });
}
