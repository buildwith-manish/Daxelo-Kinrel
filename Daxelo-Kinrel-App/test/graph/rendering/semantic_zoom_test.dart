// test/graph/rendering/semantic_zoom_test.dart
//
// Phase 3 + v5.111 — Semantic Zoom Presentation Tiers tests.
//
// Tests:
//   1. tier selection (NEAR/COMPACT/MINI/MICRO/FAR at correct zoom ranges)
//   2. threshold transitions (enter/leave boundaries)
//   3. hysteresis (no flicker when zoom oscillates near threshold)
//   4. focused-node tier override (discoverable at FAR)
//   5. selected-node override (discoverable at FAR)
//   6. dot LOD remains reachable
//   7. far tier excludes premium shadows
//   8. path remains discoverable
//   9. v5.111: MINI/MICRO tier sizing helpers
//
// v5.111: Rewritten for the 5-tier system (was 3-tier). The old MEDIUM
// tier is now COMPACT (full GraphNode with relation label faded), and
// two new intermediate tiers (MINI, MICRO) provide gradual degradation
// between COMPACT and FAR.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/rendering/semantic_zoom.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 3 — Tier selection (v5.111 5-tier)', () {
    test('TEST 1: NEAR tier at zoom >= 0.85 (initial, no hysteresis)', () {
      expect(computeSemanticTier(0.85), SemanticTier.near);
      expect(computeSemanticTier(1.0), SemanticTier.near);
      expect(computeSemanticTier(1.5), SemanticTier.near);
      expect(computeSemanticTier(2.5), SemanticTier.near);
    });

    test('TEST 1: COMPACT tier at 0.50 <= zoom < 0.85', () {
      expect(computeSemanticTier(0.50), SemanticTier.compact);
      expect(computeSemanticTier(0.70), SemanticTier.compact);
      expect(computeSemanticTier(0.84), SemanticTier.compact);
    });

    test('TEST 1: MINI tier at 0.28 <= zoom < 0.50', () {
      expect(computeSemanticTier(0.28), SemanticTier.mini);
      expect(computeSemanticTier(0.35), SemanticTier.mini);
      expect(computeSemanticTier(0.49), SemanticTier.mini);
    });

    test('TEST 1: MICRO tier at 0.16 <= zoom < 0.28', () {
      expect(computeSemanticTier(0.16), SemanticTier.micro);
      expect(computeSemanticTier(0.20), SemanticTier.micro);
      expect(computeSemanticTier(0.27), SemanticTier.micro);
    });

    test('TEST 1: FAR tier at zoom < 0.13', () {
      expect(computeSemanticTier(0.12), SemanticTier.far);
      expect(computeSemanticTier(0.10), SemanticTier.far);
      expect(computeSemanticTier(0.05), SemanticTier.far);
    });
  });

  group('Phase 3 — Threshold transitions', () {
    test('TEST 2: NEAR → COMPACT transition at nearLeave (0.78)', () {
      var tier = computeSemanticTier(1.0);
      expect(tier, SemanticTier.near);

      // Zoom out to just above nearLeave → still NEAR
      tier = computeSemanticTier(0.79, currentTier: tier);
      expect(tier, SemanticTier.near);

      // Zoom out past nearLeave → COMPACT
      tier = computeSemanticTier(0.77, currentTier: tier);
      expect(tier, SemanticTier.compact);
    });

    test('TEST 2: COMPACT → NEAR transition at nearEnter (0.85)', () {
      var tier = computeSemanticTier(0.70);
      expect(tier, SemanticTier.compact);

      // Zoom in to just below nearEnter → still COMPACT
      tier = computeSemanticTier(0.84, currentTier: tier);
      expect(tier, SemanticTier.compact);

      // Zoom in past nearEnter → NEAR
      tier = computeSemanticTier(0.86, currentTier: tier);
      expect(tier, SemanticTier.near);
    });

    test('TEST 2: COMPACT → MINI transition at compactLeave (0.45)', () {
      var tier = computeSemanticTier(0.50);
      expect(tier, SemanticTier.compact);

      tier = computeSemanticTier(0.46, currentTier: tier);
      expect(tier, SemanticTier.compact);

      tier = computeSemanticTier(0.44, currentTier: tier);
      expect(tier, SemanticTier.mini);
    });

    test('TEST 2: MINI → MICRO transition at miniLeave (0.24)', () {
      var tier = computeSemanticTier(0.28);
      expect(tier, SemanticTier.mini);

      tier = computeSemanticTier(0.25, currentTier: tier);
      expect(tier, SemanticTier.mini);

      tier = computeSemanticTier(0.23, currentTier: tier);
      expect(tier, SemanticTier.micro);
    });

    test('TEST 2: MICRO → FAR transition at microLeave (0.13)', () {
      var tier = computeSemanticTier(0.16);
      expect(tier, SemanticTier.micro);

      tier = computeSemanticTier(0.14, currentTier: tier);
      expect(tier, SemanticTier.micro);

      tier = computeSemanticTier(0.12, currentTier: tier);
      expect(tier, SemanticTier.far);
    });
  });

  group('Phase 3 — Hysteresis (no flicker)', () {
    test('TEST 3: zoom oscillating around nearEnter does NOT flap', () {
      var tier = computeSemanticTier(0.80);
      expect(tier, SemanticTier.compact);

      // Zoom up to 0.90 → NEAR
      tier = computeSemanticTier(0.90, currentTier: tier);
      expect(tier, SemanticTier.near);

      // Zoom back down to 0.80 → still NEAR (hysteresis: nearLeave=0.78)
      tier = computeSemanticTier(0.80, currentTier: tier);
      expect(tier, SemanticTier.near,
          reason: 'Hysteresis: should stay NEAR until zoom < 0.78');

      // Zoom down past nearLeave → COMPACT
      tier = computeSemanticTier(0.77, currentTier: tier);
      expect(tier, SemanticTier.compact);

      // Zoom back up to 0.80 → still COMPACT (hysteresis: nearEnter=0.85)
      tier = computeSemanticTier(0.80, currentTier: tier);
      expect(tier, SemanticTier.compact,
          reason: 'Hysteresis: should stay COMPACT until zoom >= 0.85');
    });

    test('TEST 3: zoom oscillating around compactEnter does NOT flap', () {
      var tier = computeSemanticTier(0.30);
      expect(tier, SemanticTier.mini);

      // Zoom up past compactEnter → COMPACT
      tier = computeSemanticTier(0.51, currentTier: tier);
      expect(tier, SemanticTier.compact);

      // Zoom back down to 0.47 → still COMPACT (hysteresis: compactLeave=0.45)
      tier = computeSemanticTier(0.47, currentTier: tier);
      expect(tier, SemanticTier.compact);

      // Zoom down past compactLeave → MINI
      tier = computeSemanticTier(0.44, currentTier: tier);
      expect(tier, SemanticTier.mini);
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
    test('TEST 6: FAR tier maps to overview LOD', () {
      // v5.111: SemanticTier.far now maps to 'overview' (was 'dot').
      expect(semanticTierToLodName(SemanticTier.far), 'overview');
      expect(semanticTierToLodName(SemanticTier.medium), 'chip');
      expect(semanticTierToLodName(SemanticTier.near), 'full');
      // v5.111: New tiers.
      expect(semanticTierToLodName(SemanticTier.compact), 'compact');
      expect(semanticTierToLodName(SemanticTier.mini), 'mini');
      expect(semanticTierToLodName(SemanticTier.micro), 'micro');
    });

    test('TEST 6: FAR tier is reachable at very low zoom', () {
      // v5.111: FAR now requires zoom < 0.13 (was < 0.65).
      expect(computeSemanticTier(0.10), SemanticTier.far);
      var tier = computeSemanticTier(0.10);
      tier = computeSemanticTier(0.10, currentTier: tier);
      expect(tier, SemanticTier.far);
    });
  });

  group('Phase 3 — Far tier excludes premium shadows', () {
    test('TEST 7: farTierExcludesPremiumEffects returns true for FAR', () {
      expect(farTierExcludesPremiumEffects(SemanticTier.far), isTrue);
    });

    test(
        'TEST 7: farTierExcludesPremiumEffects returns false for NEAR/COMPACT',
        () {
      expect(farTierExcludesPremiumEffects(SemanticTier.near), isFalse);
      expect(farTierExcludesPremiumEffects(SemanticTier.compact), isFalse);
    });

    test(
        'TEST 7: v5.111 farTierExcludesPremiumEffects returns true for MINI/MICRO',
        () {
      // v5.111: MINI and MICRO do NOT render premium effects (shadows,
      // specular, etc.) — they use single-painter circle rendering.
      expect(farTierExcludesPremiumEffects(SemanticTier.mini), isTrue);
      expect(farTierExcludesPremiumEffects(SemanticTier.micro), isTrue);
    });

    test('TEST 7: shouldRenderText returns false at FAR', () {
      expect(shouldRenderText(SemanticTier.far), isFalse,
          reason: 'No text at FAR zoom — unreadable');
    });

    test('TEST 7: v5.111 shouldRenderText returns false at MINI/MICRO', () {
      // MINI paints an initial letter, but it's not a Text widget —
      // shouldRenderText controls whether to build Text widgets.
      expect(shouldRenderText(SemanticTier.mini), isFalse);
      expect(shouldRenderText(SemanticTier.micro), isFalse);
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

    test('TEST 8: v5.111 farTierDotRadius is larger for emphasised nodes', () {
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
      // v5.111: Raised from 6.0/9.0 to 14.0/20.0.
      expect(normalRadius, 14.0);
      expect(emphasisedRadius, 20.0);
    });
  });

  group('Phase 3 — Hysteresis thresholds (v5.111)', () {
    test('default thresholds have correct enter/leave values', () {
      const t = defaultThresholds;
      // v5.111: New 5-tier thresholds.
      expect(t.nearEnter, 0.85);
      expect(t.nearLeave, 0.78);
      expect(t.compactEnter, 0.50);
      expect(t.compactLeave, 0.45);
      expect(t.miniEnter, 0.28);
      expect(t.miniLeave, 0.24);
      expect(t.microEnter, 0.16);
      expect(t.microLeave, 0.13);
    });

    test('hysteresis margins are positive', () {
      const t = defaultThresholds;
      expect(t.nearHysteresis, greaterThan(0));
      expect(t.compactHysteresis, greaterThan(0));
      expect(t.miniHysteresis, greaterThan(0));
      expect(t.microHysteresis, greaterThan(0));
    });
  });

  // ────────────────────────────────────────────────────────────────────
  // v102 (semantic-zoom fix): Small-family bypass.
  //
  // Graphs under 30 members must NEVER degrade below NEAR, regardless
  // of zoom level. The COMPACT/MINI/MICRO/FAR tiers exist to keep
  // LARGE trees legible at low zoom — they should never apply to a
  // 4-person family.
  // ────────────────────────────────────────────────────────────────────
  group('v102 — Small-family bypass (memberCount < 30)', () {
    test('4-member family stays NEAR at zoom 1.0 (default)', () {
      expect(computeSemanticTier(1.0, memberCount: 4), SemanticTier.near);
    });

    test('4-member family stays NEAR at zoom 0.5 (would be MINI without bypass)',
        () {
      expect(computeSemanticTier(0.5, memberCount: 4), SemanticTier.near,
          reason: 'A 4-person family must never degrade — '
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
      for (double z = 0.2; z <= 5.0; z += 0.1) {
        expect(computeSemanticTier(z, memberCount: 4), SemanticTier.near,
            reason: '4-member family must be NEAR at zoom $z');
      }
    });

    test('4-member family stays NEAR with hysteresis memory', () {
      var tier =
          computeSemanticTier(0.5, memberCount: 4, currentTier: SemanticTier.far);
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
      // v5.111: 30-member family at zoom 0.5 → MINI (was FAR).
      expect(computeSemanticTier(0.5, memberCount: 30), SemanticTier.mini,
          reason: '30 members is at the threshold — normal tier '
              'degradation applies (v5.111: 0.5 is now MINI, not FAR)');
    });

    test('100-member family degrades normally (large graph)', () {
      // v5.111: Updated for new thresholds.
      expect(computeSemanticTier(0.10, memberCount: 100), SemanticTier.far);
      expect(computeSemanticTier(0.20, memberCount: 100), SemanticTier.micro);
      expect(computeSemanticTier(0.35, memberCount: 100), SemanticTier.mini);
      expect(computeSemanticTier(0.60, memberCount: 100), SemanticTier.compact);
      expect(computeSemanticTier(1.5, memberCount: 100), SemanticTier.near);
    });

    test('1000-member family degrades normally (very large graph)', () {
      // v5.111: Large families use scaled-down thresholds.
      // For 1000 members (500-2000 range):
      //   nearEnter=0.75, compactEnter=0.40, miniEnter=0.20, microEnter=0.11
      expect(computeSemanticTier(0.10, memberCount: 1000), SemanticTier.far);
      expect(computeSemanticTier(0.15, memberCount: 1000), SemanticTier.micro);
      expect(computeSemanticTier(0.25, memberCount: 1000), SemanticTier.mini);
      expect(computeSemanticTier(0.50, memberCount: 1000), SemanticTier.compact);
      expect(computeSemanticTier(2.0, memberCount: 1000), SemanticTier.near);
    });

    test('null memberCount preserves old behavior (backward compat)', () {
      // v5.111: With null memberCount, default thresholds apply.
      expect(computeSemanticTier(0.10), SemanticTier.far);
      expect(computeSemanticTier(0.20), SemanticTier.micro);
      expect(computeSemanticTier(0.35), SemanticTier.mini);
      expect(computeSemanticTier(0.60), SemanticTier.compact);
      expect(computeSemanticTier(1.5), SemanticTier.near);
    });

    test('0 memberCount is treated as unknown (no bypass)', () {
      expect(computeSemanticTier(0.10, memberCount: 0), SemanticTier.far);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // P2.3: Semantic zoom + focus mode pairing
  // v5.111: Focus mode now floors at COMPACT (was MEDIUM).
  // ═══════════════════════════════════════════════════════════════════════

  group('P2.3: Focus mode pairing (v5.111 — floors at COMPACT)', () {
    test('zoom 0.10 with focus → COMPACT (floored from FAR)', () {
      // Without focus, zoom 0.10 → FAR. With focus, floored at COMPACT
      // so the focus subgraph remains legible with full GraphNode widgets.
      final tierWithoutFocus = computeSemanticTier(0.10, memberCount: 100);
      expect(tierWithoutFocus, SemanticTier.far);

      final tierWithFocus =
          computeSemanticTier(0.10, memberCount: 100, focusActive: true);
      expect(tierWithFocus, SemanticTier.compact,
          reason: 'Focus mode should floor the tier at COMPACT, never below');
    });

    test('zoom 0.2 with focus → COMPACT (floored from MICRO)', () {
      final tier =
          computeSemanticTier(0.2, memberCount: 100, focusActive: true);
      expect(tier, SemanticTier.compact,
          reason: 'Even at minimum zoom, focus keeps the graph at COMPACT');
    });

    test('zoom 1.5 with focus → NEAR (unchanged)', () {
      final tier =
          computeSemanticTier(1.5, memberCount: 100, focusActive: true);
      expect(tier, SemanticTier.near);
    });

    test('focus does not upgrade COMPACT to NEAR', () {
      // Focus only floors at COMPACT — it does NOT force NEAR.
      final tier =
          computeSemanticTier(0.70, memberCount: 100, focusActive: true);
      expect(tier, SemanticTier.compact);
    });

    test('focus + small family → NEAR (small-family bypass wins)', () {
      expect(computeSemanticTier(0.3, memberCount: 4, focusActive: true),
          SemanticTier.near);
    });

    test('tier transitions are stable during focus', () {
      var tier =
          computeSemanticTier(1.5, memberCount: 100, focusActive: true);
      expect(tier, SemanticTier.near);

      // Zoom out to 0.7 — should be COMPACT (not MINI/MICRO/FAR, because focus)
      tier = computeSemanticTier(0.7,
          currentTier: tier, memberCount: 100, focusActive: true);
      expect(tier, SemanticTier.compact);

      // Zoom further out to 0.10 — should stay COMPACT (focus floor)
      tier = computeSemanticTier(0.10,
          currentTier: tier, memberCount: 100, focusActive: true);
      expect(tier, SemanticTier.compact,
          reason: 'Focus floor prevents degradation below COMPACT');

      // Zoom back in to 1.5 — should return to NEAR
      tier = computeSemanticTier(1.5,
          currentTier: tier, memberCount: 100, focusActive: true);
      expect(tier, SemanticTier.near);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // v5.111: MINI and MICRO tier sizing helpers
  // ═══════════════════════════════════════════════════════════════════════

  group('v5.111 — MINI/MICRO sizing helpers', () {
    test('miniTierRadius returns correct sizes', () {
      expect(miniTierRadius(isEmphasised: false), 11.0,
          reason: 'Normal MINI radius: 11px (22px diameter)');
      expect(miniTierRadius(isEmphasised: true), 15.0,
          reason: 'Emphasised MINI radius: 15px (30px diameter)');
    });

    test('microTierRadius returns correct sizes', () {
      expect(microTierRadius(isEmphasised: false), 8.0,
          reason: 'Normal MICRO radius: 8px (16px diameter)');
      expect(microTierRadius(isEmphasised: true), 11.0,
          reason: 'Emphasised MICRO radius: 11px (22px diameter)');
    });

    test('emphasised radius is always larger than normal', () {
      expect(miniTierRadius(isEmphasised: true),
          greaterThan(miniTierRadius(isEmphasised: false)));
      expect(microTierRadius(isEmphasised: true),
          greaterThan(microTierRadius(isEmphasised: false)));
    });

    test('MINI is always larger than MICRO', () {
      expect(miniTierRadius(isEmphasised: false),
          greaterThan(microTierRadius(isEmphasised: false)));
      expect(miniTierRadius(isEmphasised: true),
          greaterThan(microTierRadius(isEmphasised: true)));
    });
  });
}
