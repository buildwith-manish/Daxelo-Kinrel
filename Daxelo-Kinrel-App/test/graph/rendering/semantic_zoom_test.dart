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

  // ────────────────────────────────────────────────────────────────────
  // v102 (semantic-zoom fix): Small-family bypass.
  //
  // Graphs under 30 members must NEVER degrade below NEAR, regardless
  // of zoom level. The MEDIUM and FAR tiers exist to keep LARGE trees
  // legible at low zoom — they should never apply to a 4-person family.
  // The 30 threshold matches branch_collapse_state.dart's convention.
  // ────────────────────────────────────────────────────────────────────
  group('v102 — Small-family bypass (memberCount < 30)', () {
    test('4-member family stays NEAR at zoom 1.0 (default)', () {
      expect(computeSemanticTier(1.0, memberCount: 4), SemanticTier.near);
    });

    test('4-member family stays NEAR at zoom 0.5 (would be FAR without bypass)', () {
      expect(computeSemanticTier(0.5, memberCount: 4), SemanticTier.near,
          reason: 'A 4-person family must never degrade to FAR — '
              'there is no legibility benefit to collapsing a tiny graph');
    });

    test('4-member family stays NEAR at zoom 0.2 (camera minimum)', () {
      expect(computeSemanticTier(0.2, memberCount: 4), SemanticTier.near,
          reason: 'Even at the lowest possible zoom, a 4-person family '
              'stays in full-detail NEAR tier');
    });

    test('4-member family stays NEAR at zoom 5.0 (camera maximum)', () {
      expect(computeSemanticTier(5.0, memberCount: 4), SemanticTier.near);
    });

    test('4-member family stays NEAR across the FULL zoom range', () {
      // Test every zoom level from 0.2 to 5.0 in 0.1 steps.
      for (double z = 0.2; z <= 5.0; z += 0.1) {
        expect(computeSemanticTier(z, memberCount: 4), SemanticTier.near,
            reason: '4-member family must be NEAR at zoom $z');
      }
    });

    test('4-member family stays NEAR with hysteresis memory', () {
      // Even with a currentTier of FAR, a small family overrides to NEAR.
      var tier = computeSemanticTier(0.5, memberCount: 4, currentTier: SemanticTier.far);
      expect(tier, SemanticTier.near,
          reason: 'Small family overrides hysteresis — always NEAR');
    });

    test('15-member family stays NEAR (under 30 threshold)', () {
      expect(computeSemanticTier(0.3, memberCount: 15), SemanticTier.near);
    });

    test('29-member family stays NEAR (just under threshold)', () {
      expect(computeSemanticTier(0.2, memberCount: 29), SemanticTier.near);
    });

    test('30-member family degrades normally (at threshold)', () {
      // 30 is NOT small (the check is < 30, not <= 30).
      // A 30-member family at zoom 0.5 → FAR (normal behavior).
      expect(computeSemanticTier(0.5, memberCount: 30), SemanticTier.far,
          reason: '30 members is at the threshold — normal tier degradation applies');
    });

    test('100-member family degrades normally (large graph)', () {
      expect(computeSemanticTier(0.5, memberCount: 100), SemanticTier.far);
      expect(computeSemanticTier(0.8, memberCount: 100), SemanticTier.medium);
      expect(computeSemanticTier(1.5, memberCount: 100), SemanticTier.near);
    });

    test('1000-member family degrades normally (very large graph)', () {
      // The bypass must NOT accidentally pin large graphs to NEAR.
      expect(computeSemanticTier(0.3, memberCount: 1000), SemanticTier.far);
      expect(computeSemanticTier(0.7, memberCount: 1000), SemanticTier.medium);
      expect(computeSemanticTier(2.0, memberCount: 1000), SemanticTier.near);
    });

    test('null memberCount preserves old behavior (backward compat)', () {
      // When memberCount is not provided, the function behaves exactly
      // as before — no bypass. This ensures existing callers that don't
      // pass memberCount are unaffected.
      expect(computeSemanticTier(0.5), SemanticTier.far);
      expect(computeSemanticTier(0.8), SemanticTier.medium);
      expect(computeSemanticTier(1.5), SemanticTier.near);
    });

    test('0 memberCount is treated as unknown (no bypass)', () {
      // memberCount=0 (empty graph) should not trigger the bypass —
      // it's a degenerate case. Treat it as "unknown" so we don't pin
      // an empty graph to NEAR (which would be harmless but wasteful).
      expect(computeSemanticTier(0.5, memberCount: 0), SemanticTier.far);
    });
  });
}
