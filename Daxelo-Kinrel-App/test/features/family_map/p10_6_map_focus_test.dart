// test/features/family_map/p10_6_map_focus_test.dart
//
// P10.6 — Unit tests for the Map Focus Mode extension.
//
// Verifies:
//   - GraphFocusState has an isMapFocus field (default false).
//   - copyWith preserves isMapFocus when not provided.
//   - copyWith(isMapFocus: true) toggles it.
//   - == / hashCode consider isMapFocus.
//   - tierOf returns the correct tier for focused / 1st / 2nd / unrelated.
//   - focusTierOpacity returns the correct opacity per tier.
//   - MapFocusController can be constructed + enterFocus / exitFocus
//     do not throw when mapController is null (graceful no-op).

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/interaction/graph_focus_state.dart';
import 'package:kinrel/features/family_map/widgets/map_focus_controller.dart';
import 'package:kinrel/features/family_map/config/map_visual_constants.dart';
import 'package:kinrel/features/family_map/providers/family_map_provider.dart';

void main() {
  group('P10.6 GraphFocusState.isMapFocus', () {
    test('default is false', () {
      expect(const GraphFocusState().isMapFocus, isFalse);
      expect(GraphFocusState.empty.isMapFocus, isFalse);
    });

    test('copyWith preserves isMapFocus when not provided', () {
      final s = const GraphFocusState().copyWith(
        focusedPersonId: 'p1',
        isMapFocus: true,
      );
      final s2 = s.copyWith(); // no isMapFocus arg
      expect(s2.isMapFocus, isTrue);
    });

    test('copyWith can toggle isMapFocus', () {
      final s = const GraphFocusState().copyWith(isMapFocus: true);
      final s2 = s.copyWith(isMapFocus: false);
      expect(s.isMapFocus, isTrue);
      expect(s2.isMapFocus, isFalse);
    });

    test('== and hashCode consider isMapFocus', () {
      final a = const GraphFocusState(
        focusedPersonId: 'p1',
        revision: 1,
        isMapFocus: true,
      );
      final b = const GraphFocusState(
        focusedPersonId: 'p1',
        revision: 1,
        isMapFocus: false,
      );
      expect(a == b, isFalse);
      expect(a.hashCode == b.hashCode, isFalse);
    });

    test('same focus + revision + isMapFocus are equal', () {
      final a = const GraphFocusState(
        focusedPersonId: 'p1',
        revision: 1,
        isMapFocus: true,
      );
      final b = const GraphFocusState(
        focusedPersonId: 'p1',
        revision: 1,
        isMapFocus: true,
      );
      expect(a == b, isTrue);
      expect(a.hashCode == b.hashCode, isTrue);
    });
  });

  group('P10.6 GraphFocusState.tierOf', () {
    final state = GraphFocusState(
      focusedPersonId: 'p1',
      firstDegreeIds: const {'p2', 'p3'},
      secondDegreeIds: const {'p4'},
    );

    test('returns focused for the focused person', () {
      expect(state.tierOf('p1'), equals(FocusTier.focused));
    });

    test('returns firstDegree for direct neighbours', () {
      expect(state.tierOf('p2'), equals(FocusTier.firstDegree));
      expect(state.tierOf('p3'), equals(FocusTier.firstDegree));
    });

    test('returns secondDegree for two-hop neighbours', () {
      expect(state.tierOf('p4'), equals(FocusTier.secondDegree));
    });

    test('returns unrelated for everyone else', () {
      expect(state.tierOf('p999'), equals(FocusTier.unrelated));
    });
  });

  group('P10.6 GraphFocusState.hasFocus', () {
    test('true when focusedPersonId is set', () {
      expect(const GraphFocusState(focusedPersonId: 'p1').hasFocus, isTrue);
    });
    test('false when focusedPersonId is null', () {
      expect(const GraphFocusState().hasFocus, isFalse);
    });
  });

  group('P10.6 focusTierOpacity', () {
    test('focused + firstDegree = focusOpacity', () {
      expect(focusTierOpacity(FocusTier.focused),
          equals(MapVisualConstants.focusOpacity));
      expect(focusTierOpacity(FocusTier.firstDegree),
          equals(MapVisualConstants.focusOpacity));
    });
    test('unrelated = nonFocusOpacity', () {
      expect(focusTierOpacity(FocusTier.unrelated),
          equals(MapVisualConstants.nonFocusOpacity));
    });
    test('secondDegree is between non-focus and focus', () {
      final v = focusTierOpacity(FocusTier.secondDegree);
      expect(v, greaterThan(MapVisualConstants.nonFocusOpacity));
      expect(v, lessThanOrEqualTo(MapVisualConstants.focusOpacity));
    });
  });

  group('P10.6 MapFocusController lifecycle', () {
    test('enterFocus is a graceful no-op when mapController is null',
        () async {
      final controller = MapFocusController(reducedMotion: true);
      const pin = MapPin(
          personId: 'p1', name: 'X', city: 'Y', photoUrl: null,
          lat: 18.52, lng: 73.85);
      const focusState = GraphFocusState(focusedPersonId: 'p1');
      final ctx = await controller.enterFocus(
        mapController: null,
        style: null,
        familyBuildings: null,
        pin: pin,
        focusState: focusState,
      );
      expect(ctx.pin, equals(pin));
      expect(ctx.tier, equals(FocusTier.focused));
    });

    test('exitFocus is a graceful no-op when familyBuildings is null',
        () async {
      final controller = MapFocusController();
      await controller.exitFocus(
        mapController: null,
        style: null,
        familyBuildings: null,
      );
      expect(true, isTrue);
    });
  });
}
