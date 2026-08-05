// test/graph/rendering/relationship_label_opacity_test.dart
//
// Tests for the smooth relationship-label zoom-fade (v104).
//
// Verifies:
//   1. Labels are FULLY VISIBLE (opacity 1.0) at and above
//      kLabelFullyVisibleZoom — they do NOT disappear immediately
//      when the user starts zooming out from 1.0.
//   2. Labels are FULLY HIDDEN (opacity 0.0) at and below
//      kLabelFullyHiddenZoom — the fade completes BEFORE the DOT
//      tier (zoom 0.65) so there is no flicker at the LOD boundary.
//   3. The fade is SMOOTH and MONOTONIC between the two thresholds —
//      no flicker, no sudden jumps.
//   4. Small-family bypass: graphs < 30 members keep labels fully
//      visible at ALL zoom levels (matches computeSemanticTier's
//      NEAR pin).
//   5. Focus-mode bypass: labels stay fully visible while focus is
//      active (matches computeSemanticTier's MEDIUM floor).
//   6. relationLabelVisibleAt returns true iff opacity > 0.
//   7. Defensive: NaN / infinite / non-positive zoom never produces
//      a NaN opacity.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/rendering/relationship_label_opacity.dart';

void main() {
  group('relationLabelOpacityFor — fully-visible range', () {
    test('opacity is 1.0 at kLabelFullyVisibleZoom', () {
      expect(relationLabelOpacityFor(zoom: kLabelFullyVisibleZoom), 1.0);
    });

    test('opacity is 1.0 above kLabelFullyVisibleZoom', () {
      expect(relationLabelOpacityFor(zoom: 0.9), 1.0);
      expect(relationLabelOpacityFor(zoom: 1.0), 1.0);
      expect(relationLabelOpacityFor(zoom: 1.5), 1.0);
      expect(relationLabelOpacityFor(zoom: 5.0), 1.0);
    });

    test(
        'labels do NOT disappear immediately when zooming out from 1.0 — '
        'they stay fully visible down to kLabelFullyVisibleZoom',
        () {
      // The user starts at zoom 1.0 (the old hard threshold) and
      // zooms out. Under the old behaviour the label vanished the
      // instant zoom dropped below 1.0. Under v104/v105 the label
      // stays fully visible all the way down to kLabelFullyVisibleZoom
      // (0.9 in v105 — tuned per the requested fade band).
      for (double z = 1.0; z >= kLabelFullyVisibleZoom; z -= 0.01) {
        expect(relationLabelOpacityFor(zoom: z), 1.0,
            reason: 'At zoom $z the label should still be fully visible');
      }
    });
  });

  group('relationLabelOpacityFor — fully-hidden range', () {
    test('opacity is 0.0 at kLabelFullyHiddenZoom', () {
      expect(relationLabelOpacityFor(zoom: kLabelFullyHiddenZoom), 0.0);
    });

    test('opacity is 0.0 below kLabelFullyHiddenZoom', () {
      expect(relationLabelOpacityFor(zoom: 0.5), 0.0);
      expect(relationLabelOpacityFor(zoom: 0.3), 0.0);
      expect(relationLabelOpacityFor(zoom: 0.2), 0.0);
    });

    test(
        'the fade COMPLETES before the DOT tier (zoom 0.65) — no flicker '
        'at the LOD boundary', () {
      // DOT tier starts at zoom 0.65 (per defaultThresholds.mediumLeave).
      // The label must be fully hidden BEFORE the node degrades to a
      // dot, so there is never a frame where a dot has a half-visible
      // label hovering over it.
      expect(relationLabelOpacityFor(zoom: 0.65), 0.0);
      expect(relationLabelOpacityFor(zoom: 0.64), 0.0);
    });
  });

  group('relationLabelOpacityFor — smooth monotonic fade', () {
    test('opacity is strictly increasing across the fade range', () {
      double prev = 0.0;
      for (double z = kLabelFullyHiddenZoom; z <= kLabelFullyVisibleZoom;
          z += 0.01) {
        final op = relationLabelOpacityFor(zoom: z);
        expect(op >= prev, isTrue,
            reason:
                'Opacity at zoom $z ($op) should be >= previous ($prev)');
        prev = op;
      }
    });

    test('opacity is 0.5 at the midpoint of the fade range', () {
      final mid = (kLabelFullyVisibleZoom + kLabelFullyHiddenZoom) / 2;
      final op = relationLabelOpacityFor(zoom: mid);
      expect((op - 0.5).abs(), lessThan(0.01),
          reason: 'Midpoint opacity should be ~0.5, got $op');
    });

    test('opacity is in [0, 1] for every zoom in the camera range', () {
      // Camera range is 0.2–5.0.
      for (double z = 0.2; z <= 5.0; z += 0.01) {
        final op = relationLabelOpacityFor(zoom: z);
        expect(op >= 0.0 && op <= 1.0, isTrue,
            reason: 'Opacity $op out of [0,1] at zoom $z');
      }
    });
  });

  group('relationLabelOpacityFor — small-family bypass', () {
    test('labels fully visible at ALL zoom levels for < 30 members', () {
      for (double z = 0.2; z <= 5.0; z += 0.1) {
        expect(relationLabelOpacityFor(zoom: z, memberCount: 4), 1.0,
            reason: 'Small family should keep labels visible at zoom $z');
      }
    });

    test('labels fully visible at the small-family boundary (29 members)', () {
      expect(relationLabelOpacityFor(zoom: 0.3, memberCount: 29), 1.0);
    });

    test('fade IS applied at the large-family boundary (30 members)', () {
      // 30 members is NOT a small family — the fade should apply.
      expect(relationLabelOpacityFor(zoom: 0.3, memberCount: 30), 0.0);
      expect(relationLabelOpacityFor(zoom: 1.0, memberCount: 30), 1.0);
    });

    test('memberCount 0 / null → fade applies (no bypass)', () {
      expect(relationLabelOpacityFor(zoom: 0.3, memberCount: 0), 0.0);
      expect(relationLabelOpacityFor(zoom: 0.3, memberCount: null), 0.0);
    });
  });

  group('relationLabelOpacityFor — focus-mode bypass', () {
    test('labels fully visible at ALL zoom levels while focus is active', () {
      for (double z = 0.2; z <= 5.0; z += 0.1) {
        expect(
          relationLabelOpacityFor(zoom: z, memberCount: 1000, focusActive: true),
          1.0,
          reason: 'Focus mode should keep labels visible at zoom $z',
        );
      }
    });

    test('focus override applies even for large families', () {
      // Without focus: a 1000-member family at zoom 0.3 → fully hidden.
      expect(relationLabelOpacityFor(zoom: 0.3, memberCount: 1000), 0.0);
      // With focus: same family at zoom 0.3 → fully visible.
      expect(
        relationLabelOpacityFor(zoom: 0.3, memberCount: 1000, focusActive: true),
        1.0,
      );
    });
  });

  group('relationLabelOpacityFor — defensive inputs', () {
    test('NaN zoom never produces a NaN opacity', () {
      final op = relationLabelOpacityFor(zoom: double.nan);
      expect(op.isNaN, isFalse);
      expect(op >= 0.0 && op <= 1.0, isTrue);
    });

    test('infinite zoom never produces a NaN opacity', () {
      final op = relationLabelOpacityFor(zoom: double.infinity);
      expect(op.isNaN, isFalse);
      expect(op, 1.0); // infinity >= kLabelFullyVisibleZoom
    });

    test('zero / negative zoom never produces a NaN opacity', () {
      expect(relationLabelOpacityFor(zoom: 0.0).isNaN, isFalse);
      expect(relationLabelOpacityFor(zoom: -1.0).isNaN, isFalse);
    });
  });

  group('relationLabelVisibleAt', () {
    test('returns true iff opacity > 0', () {
      // Fully visible range → visible.
      expect(relationLabelVisibleAt(zoom: 1.0), isTrue);
      expect(relationLabelVisibleAt(zoom: kLabelFullyVisibleZoom), isTrue);
      // Fully hidden range → not visible.
      expect(relationLabelVisibleAt(zoom: 0.3), isFalse);
      expect(relationLabelVisibleAt(zoom: kLabelFullyHiddenZoom), isFalse);
      // Mid-fade → visible (opacity > 0).
      final mid = (kLabelFullyVisibleZoom + kLabelFullyHiddenZoom) / 2;
      expect(relationLabelVisibleAt(zoom: mid), isTrue);
    });

    test('small-family bypass → visible at all zoom levels', () {
      expect(relationLabelVisibleAt(zoom: 0.2, memberCount: 4), isTrue);
    });

    test('focus-mode bypass → visible at all zoom levels', () {
      expect(
        relationLabelVisibleAt(zoom: 0.2, memberCount: 1000, focusActive: true),
        isTrue,
      );
    });
  });

  group('threshold constants', () {
    test('kLabelFullyVisibleZoom is below the old hard threshold of 1.0', () {
      // This is the whole point of v104: labels should NOT disappear
      // the instant zoom drops below 1.0. The new fully-visible
      // threshold must be strictly below 1.0.
      expect(kLabelFullyVisibleZoom, lessThan(1.0));
    });

    test('kLabelFullyHiddenZoom is below the DOT tier threshold (0.65)', () {
      // The fade must complete BEFORE the graph degrades to dots so
      // there's no flicker at the LOD boundary.
      expect(kLabelFullyHiddenZoom, lessThan(0.65));
    });

    test('fully-visible threshold is above fully-hidden threshold', () {
      expect(kLabelFullyVisibleZoom, greaterThan(kLabelFullyHiddenZoom));
    });
  });
}
