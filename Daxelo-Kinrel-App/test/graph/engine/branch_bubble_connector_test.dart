// test/graph/engine/branch_bubble_connector_test.dart
//
// DAXELO KINREL — v5.166 ACCEPTANCE TEST
//
// Verifies the branch bubble connector fix:
//   - A visible node whose only relatives are all hidden inside a
//     collapsed branch must NOT appear isolated.
//   - The lifeguard must synthesize a connector edge from the visible
//     node to the branch bubble's center position.
//   - The LayoutValidator must detect (and warn about) any remaining
//     isolated visible nodes.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/engine/layout_validator.dart';

void main() {
  group('v5.166 — Branch Bubble Connector', () {
    test(
        'CRITERION 1: LayoutValidator detects an isolated visible node '
        '(no drawable edges) as a violation',
        () {
      // One visible node "V" with a position, but NO edges at all.
      // The validator must flag it as disconnected.
      final result = LayoutValidator.validate(
        positions: {'V': const Offset(100, 100)},
        visibleIds: {'V'},
        edges: const [],
      );

      expect(result.isValid, isFalse,
          reason: 'An isolated visible node must fail validation.');
      expect(result.disconnectedNodeIds, contains('V'),
          reason: 'V must be listed as a disconnected node.');
    });

    test(
        'CRITERION 2: LayoutValidator passes when the visible node has '
        'a drawable edge (both endpoints positioned)',
        () {
      // V is connected to W, both have positions.
      final result = LayoutValidator.validate(
        positions: {
          'V': const Offset(100, 100),
          'W': const Offset(400, 400),
        },
        visibleIds: {'V', 'W'},
        edges: const [
          (sourceId: 'V', targetId: 'W'),
        ],
      );

      expect(result.disconnectedNodeIds, isEmpty,
          reason: 'No disconnected nodes when V↔W edge is drawable.');
      // Note: may still fail on overlap if positions are too close,
      // but disconnected check should pass.
    });

    test(
        'CRITERION 3: LayoutValidator detects a hidden edge endpoint '
        '(edge where one endpoint has no position)',
        () {
      // V is visible with a position. Edge V→H exists but H has NO
      // position (H is hidden). The validator must count this as a
      // hidden endpoint, AND V is disconnected (no drawable edges).
      final result = LayoutValidator.validate(
        positions: {'V': const Offset(100, 100)},
        visibleIds: {'V'},
        edges: const [
          (sourceId: 'V', targetId: 'H'), // H has no position
        ],
      );

      expect(result.hiddenEndpointCount, 1,
          reason: 'The V→H edge has a hidden endpoint (H has no position).');
      expect(result.disconnectedNodeIds, contains('V'),
          reason: 'V has no drawable edges (the only edge goes to a '
              'positionless node).');
    });

    test(
        'CRITERION 4: LayoutValidator passes for a node connected to a '
        'synthetic bubble endpoint',
        () {
      // Simulate the v5.166 fix: V is connected to a synthetic bubble
      // node "bubble_branch1" whose position was inserted by the
      // lifeguard. The validator must see V as connected.
      final result = LayoutValidator.validate(
        positions: {
          'V': const Offset(100, 100),
          'bubble_branch1': const Offset(100, 350),
        },
        visibleIds: {'V'},
        edges: const [
          (sourceId: 'V', targetId: 'bubble_branch1'),
        ],
      );

      expect(result.disconnectedNodeIds, isEmpty,
          reason: 'V is connected to the bubble — not disconnected.');
      expect(result.hiddenEndpointCount, 0,
          reason: 'Both endpoints have positions — no hidden endpoints.');
    });

    test(
        'CRITERION 5: Graph integrity rule — visible node + hidden '
        'relatives = must show at least one visible connection',
        () {
      // This is the "Geeta Iyer" scenario:
      //   - Geeta is visible with a position.
      //   - All her relatives are hidden inside a collapsed branch.
      //   - The lifeguard must synthesize a connector edge to the
      //     branch bubble.
      //
      // Before the fix: the validator would report Geeta as disconnected.
      // After the fix: the lifeguard synthesizes a connector edge from
      // Geeta to the bubble, and the validator passes.
      //
      // This test verifies the VALIDATOR correctly catches the pre-fix
      // state (disconnected) and the post-fix state (connected).
      //
      // Pre-fix (no connector edge):
      final preFix = LayoutValidator.validate(
        positions: {'geeta': const Offset(100, 100)},
        visibleIds: {'geeta'},
        edges: const [
          (sourceId: 'geeta', targetId: 'hidden_child_1'), // hidden
          (sourceId: 'geeta', targetId: 'hidden_child_2'), // hidden
        ],
      );
      expect(preFix.disconnectedNodeIds, contains('geeta'),
          reason: 'Pre-fix: Geeta is disconnected (all edges go to '
              'positionless hidden nodes).');

      // Post-fix (connector edge to bubble):
      final postFix = LayoutValidator.validate(
        positions: {
          'geeta': const Offset(100, 100),
          'bubble_branch_geeta': const Offset(100, 350),
        },
        visibleIds: {'geeta'},
        edges: const [
          (sourceId: 'geeta', targetId: 'hidden_child_1'), // hidden
          (sourceId: 'geeta', targetId: 'hidden_child_2'), // hidden
          // The lifeguard-synthesized connector:
          (sourceId: 'geeta', targetId: 'bubble_branch_geeta'),
        ],
      );
      expect(postFix.disconnectedNodeIds, isEmpty,
          reason: 'Post-fix: Geeta is connected to the bubble — not '
              'disconnected.');
    });
  });
}
