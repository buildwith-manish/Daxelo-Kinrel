// test/graph/rearrange/override_applied_on_load_test.dart
//
// v5.22 PART 1.4 — Saved node position is applied on load and the
// overridden node is NOT recomputed by auto-layout, while other
// nodes still auto-layout normally.
//
// The override is applied by PersonalLayoutOverrides.applyTo(), which
// the engine view calls in its build method (see canvas_mixin.dart
// lines 113-118). The contract is:
//
//   effectivePositions =
//     autoLayout ⊕ savedOverrides.nodePositions
//
// where ⊕ means "saved overrides replace auto-layout for matching
// personIds". Other persons keep auto-layout.

import 'package:flutter/material.dart' show Offset;
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/rearrange/layout_overrides_service.dart';

void main() {
  group('Saved override applied on load (PART 1.4)', () {
    test('a saved override for ONE person applies that override on load '
        'and leaves every OTHER person at auto-layout', () {
      // Simulate the auto-layout output for a 3-person family.
      final autoLayout = <String, Offset>{
        'a': const Offset(100.0, 100.0),
        'b': const Offset(200.0, 100.0),
        'c': const Offset(300.0, 100.0),
      };
      // Simulate a saved override for person 'b' that drags it to a
      // new position.
      const savedOverride = PersonalLayoutOverrides(
        nodePositions: {
          'b': Offset(275.0, 175.0),
        },
      );

      final effective = savedOverride.applyTo(autoLayout);

      // Person 'b' uses the SAVED override position (not auto-layout).
      expect(effective['b'], const Offset(275.0, 175.0),
          reason: 'Person with a saved override must render at the '
              'saved position, not at auto-layout.');

      // Persons 'a' and 'c' keep their auto-layout positions.
      expect(effective['a'], const Offset(100.0, 100.0));
      expect(effective['c'], const Offset(300.0, 100.0));

      // The override ONLY changes the overridden person — every other
      // person's position is byte-identical to auto-layout.
      for (final entry in autoLayout.entries) {
        if (entry.key == 'b') continue;
        expect(effective[entry.key], entry.value,
            reason: '${entry.key} must keep its auto-layout position '
                'because no override was saved for it.');
      }
    });

    test('a saved override for ALL persons replaces every position', () {
      final autoLayout = <String, Offset>{
        'a': const Offset(100.0, 100.0),
        'b': const Offset(200.0, 100.0),
      };
      const savedOverride = PersonalLayoutOverrides(
        nodePositions: {
          'a': Offset(10.0, 20.0),
          'b': Offset(30.0, 40.0),
        },
      );
      final effective = savedOverride.applyTo(autoLayout);
      expect(effective['a'], const Offset(10.0, 20.0));
      expect(effective['b'], const Offset(30.0, 40.0));
    });

    test('live drag override layer is applied on TOP of saved override '
        '(LIVE takes precedence over SAVED which takes precedence over '
        'AUTO-LAYOUT)', () {
      // This is the precedence contract documented in canvas_mixin.dart
      // lines 91-118. We verify the precedence order in isolation by
      // simulating the same overlay math the build method runs.
      final autoLayout = <String, Offset>{
        'a': const Offset(100.0, 100.0), // auto-layout position
      };
      const savedOverride = PersonalLayoutOverrides(
        nodePositions: {
          'a': Offset(200.0, 200.0), // saved (last committed drag)
        },
      );
      // Live drag in progress — finger is at (300, 300).
      final liveDrag = <String, Offset>{
        'a': const Offset(300.0, 300.0),
      };

      // Mirror the build method's overlay math.
      final effective = savedOverride.applyTo(autoLayout);
      expect(effective['a'], const Offset(200.0, 200.0),
          reason: 'Without live drag, saved override wins.');

      // Now layer the live drag on top (the build method does this in
      // canvas_mixin.dart line 117-119).
      final effectiveWithLive = Map<String, Offset>.from(effective);
      if (liveDrag.isNotEmpty) {
        effectiveWithLive.addAll(liveDrag);
      }
      expect(effectiveWithLive['a'], const Offset(300.0, 300.0),
          reason: 'LIVE drag override takes precedence over both '
              'saved override and auto-layout.');
    });
  });
}
