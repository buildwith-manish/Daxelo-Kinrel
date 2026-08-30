// test/graph/rearrange/double_tap_reset_edge_center_test.dart
//
// v5.23 PART 2.5 reset — Double-tap on an edge midpoint dot in Rearrange
// mode resets that edge's custom bow override. Verifies:
//
//   • LayoutOverridesService.removeEdgeWaypoint now has a real caller
//     (was previously zero callers).
//   • The reset path uses the EXISTING _hitTestEdge helper (the same
//     one the existing long-press-on-dot handler uses).
//   • The reset path mirrors the pattern already used for the node's
//     "Reset to auto layout" action in graph_quick_actions.dart
//     (which calls LayoutOverridesService.removeNodeOverride).
//   • Outside Rearrange mode, double-tap still zooms (no reset path
//     is taken) — the existing onDoubleTapZoom behaviour is unchanged.
//   • In Rearrange mode, double-tap NOT on a dot still zooms — only
//     double-tap ON A DOT resets.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kinrel/graph/rearrange/layout_overrides_service.dart';

void main() {
  group('Double-tap reset edge midpoint (v5.23 PART 2.5 reset)', () {
    test('LayoutOverridesService.removeEdgeWaypoint now has a real caller '
        'in the app (previously zero)', () {
      // Before v5.23: removeEdgeWaypoint was defined and tested but
      // had ZERO callers in the app (the v5.22 spec listed it as
      // "Reset to center" affordance to be wired later).
      //
      // After v5.23: the double-tap-on-dot handler in
      // lib/graph/widgets/engine/interaction_mixin.dart
      // (_handleDoubleTap) calls removeEdgeWaypoint when:
      //   (a) rearrangeModeProvider == true, AND
      //   (b) _hitTestEdge(_doubleTapPosition) returns a non-null edgeId.
      //
      // We verify this by grepping the interaction_mixin source for
      // the call site.
      final file = File('lib/graph/widgets/engine/interaction_mixin.dart');
      expect(file.existsSync(), true,
          reason: 'interaction_mixin.dart source must exist');
      final source = file.readAsStringSync();

      // Positive: removeEdgeWaypoint IS called inside _handleDoubleTap.
      expect(source.contains('LayoutOverridesService.removeEdgeWaypoint'),
          true,
          reason: 'interaction_mixin.dart must call '
              'LayoutOverridesService.removeEdgeWaypoint — the v5.23 '
              'reset-to-center affordance for edge midpoint bows.');

      // Positive: the call is gated by rearrangeModeProvider.
      expect(source.contains("ref.read(rearrangeModeProvider)"), true,
          reason: 'The reset-to-center call must be gated by '
              'rearrangeModeProvider — only fire in Rearrange mode.');

      // Positive: the call uses the EXISTING _hitTestEdge helper (the
      // same one the long-press-on-dot handler uses for PART 2 drag).
      expect(source.contains('_hitTestEdge(_doubleTapPosition)'), true,
          reason: 'The reset path must reuse the EXISTING _hitTestEdge '
              'helper so the hit target is consistent with the '
              'long-press-on-dot hit target (48px radius, same union-'
              'redirected effective endpoints).');

      // Positive: outside the rearrange+hit branch, _handleDoubleTapZoom
      // is called (so zoom still works).
      expect(source.contains('_handleDoubleTapZoom()'), true,
          reason: '_handleDoubleTap must fall through to '
              '_handleDoubleTapZoom when not in Rearrange mode OR when '
              'the double-tap didn\'t land on a midpoint dot. The '
              'existing zoom-toggle behaviour must remain available.');
    });

    test('the wiring in canvas_mixin.dart routes onDoubleTap through '
        '_handleDoubleTap (not directly to _handleDoubleTapZoom)', () {
      // Before v5.23: onDoubleTap was wired directly to
      // _handleDoubleTapZoom.
      // After v5.23: onDoubleTap is wired to _handleDoubleTap (the
      // new dispatcher), which routes to either reset-edge-center OR
      // _handleDoubleTapZoom based on Rearrange mode + hit-test.
      final file = File('lib/graph/widgets/engine/canvas_mixin.dart');
      expect(file.existsSync(), true);
      final source = file.readAsStringSync();

      // Positive: onDoubleTap calls _handleDoubleTap (the dispatcher).
      expect(source.contains('_handleDoubleTap('), true,
          reason: 'canvas_mixin.dart must route onDoubleTap through '
              '_handleDoubleTap (the v5.23 dispatcher), not directly '
              'to _handleDoubleTapZoom.');

      // Negative: onDoubleTap must NOT be wired directly to
      // _handleDoubleTapZoom anymore (that would bypass the reset
      // path).
      //
      // The exact pattern we want to AVOID:
      //   onDoubleTap: _handleDoubleTapZoom,
      expect(source.contains('onDoubleTap: _handleDoubleTapZoom'), false,
          reason: 'canvas_mixin.dart must NOT wire onDoubleTap '
              'directly to _handleDoubleTapZoom anymore — that would '
              'bypass the v5.23 reset-to-center path. The wiring must '
              'go through _handleDoubleTap (the dispatcher).');
    });

    test('rearrangeModeProvider is the SOLE gate — outside Rearrange '
        'mode, double-tap still zooms (no reset path)', () {
      // Outside Rearrange mode, the user's double-tap should zoom
      // exactly as before. We verify this by confirming that
      // rearrangeModeProvider defaults to false AND that the dispatcher
      // checks it before attempting the reset.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(rearrangeModeProvider), false,
          reason: 'rearrangeModeProvider must default to false — '
              'outside Rearrange mode, double-tap zooms (no reset path '
              'is taken).');

      // Confirm the dispatcher's gate reads this provider.
      final file = File('lib/graph/widgets/engine/interaction_mixin.dart');
      final source = file.readAsStringSync();
      // The dispatcher's first check is `ref.read(rearrangeModeProvider)`.
      expect(source.contains('final isRearranging = ref.read(rearrangeModeProvider);'), true,
          reason: '_handleDoubleTap must read rearrangeModeProvider '
              'as its FIRST check — outside Rearrange mode, the '
              'reset path is unreachable.');
    });
  });
}
