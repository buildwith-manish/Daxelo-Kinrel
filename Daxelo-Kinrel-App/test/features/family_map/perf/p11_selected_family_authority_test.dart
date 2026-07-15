// test/features/family_map/perf/p11_selected_family_authority_test.dart
//
// P11 — Selected Family Authority Tests
//
// Proves that the Family Map uses the AUTHORITATIVE familyId (not
// `families.first`) and that family switching is safe. These are pure
// unit tests because MapLibre's native plugins can't be instantiated in
// a widget test environment — we verify the contracts and signatures
// directly.
//
// Coverage:
//   1. `familyMapProvider` is a `FutureProvider.family` (not a plain
//      FutureProvider) — calling it with two different family IDs does
//      not throw and returns independent provider instances.
//   2. `FamilyMapScreen` exposes a `familyId` constructor parameter —
//      verified via mirror-free constructor signature inspection.
//   3. `FamilyMapLifecycleController` ignores stale callbacks across a
//      multi-family switch: family A starts → family B resets → family
//      A's late callback fires → family B's state is preserved.
//   4. `MapPin.locationSource` exists and defaults to null (legacy pin
//      backward compatibility).
//   5. `computeHouseholds` skips city-centroid pins — two pins at the
//      same coordinates but different `locationSource` produce
//      different household counts.
//   6. `selectedFamilyIdProvider` exists and can be set to different
//      family IDs (single source of truth for "current family").

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/family_map/data/family_map_lifecycle.dart';
import 'package:kinrel/features/family_map/data/map_location_source.dart';
import 'package:kinrel/features/family_map/presentation/family_map_screen.dart';
import 'package:kinrel/features/family_map/providers/family_map_provider.dart';
import 'package:kinrel/features/trackc/presentation/providers/trackc_providers.dart';

void main() {
  // ─────────────────────────────────────────────────────────────────────
  // 1. familyMapProvider IS A FAMILY PROVIDER
  // ─────────────────────────────────────────────────────────────────────
  //
  // The map screen reads the SELECTED family's id and calls
  // `familyMapProvider(familyId)`. If this were a plain FutureProvider
  // (one global instance), switching families would either (a) show the
  // wrong family's pins, or (b) require manual cache invalidation. By
  // being a `.family`, each familyId gets its own cached result that is
  // independently invalidated when that family's members change.
  group('familyMapProvider — .family authority', () {
    test('is callable with two different family IDs without throwing', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Two independent familyId arguments — this only works because
      // familyMapProvider is FutureProvider.family<FamilyMapResult, String>.
      // A plain FutureProvider would not accept an argument at all and
      // the call `familyMapProvider('fam-a')` would be a compile error.
      final providerA = familyMapProvider('fam-a');
      final providerB = familyMapProvider('fam-b');

      // Different familyId arguments → different provider identities.
      expect(
        identical(providerA, providerB),
        isFalse,
        reason:
            'familyMapProvider must be a FutureProvider.family so '
            'each familyId yields an independent provider instance.',
      );

      // Reading both must not throw. Both will resolve to an empty
      // FamilyMapResult because the test container has no Supabase
      // client and no seeded family members — the important thing is
      // that calling the family provider with an argument is valid.
      expect(
        () => container.read(providerA.future),
        returnsNormally,
        reason:
            'familyMapProvider must accept a familyId argument '
            '(i.e. must be FutureProvider.family).',
      );
      expect(() => container.read(providerB.future), returnsNormally);
    });

    test('empty familyId returns an empty result without error', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final result = await container.read(familyMapProvider('').future);
      expect(result.pins, isEmpty);
      expect(result.unpinnedCount, 0);
      expect(result.familyId, '');
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // 2. FamilyMapScreen ACCEPTS A familyId PARAMETER
  // ─────────────────────────────────────────────────────────────────────
  //
  // The screen MUST take a familyId — it no longer falls back to
  // `familyListProvider.first`. We can't fully mount it in a unit test
  // (MapLibre's native plugin requires a real platform), but we can
  // verify the constructor signature: `familyId` is a required,
  // non-nullable `String` field.
  group('FamilyMapScreen — familyId constructor parameter', () {
    test('has a required, non-nullable String familyId field', () {
      // Read the field off the Type via a constructed instance. We can't
      // mount the widget, but constructing it does not require any
      // platform channels — the map plugin is only touched in build().
      //
      // Passing familyId is required: omitting it would be a compile
      // error. Passing the empty string is allowed at the constructor
      // (the provider handles the empty case above).
      final screen = FamilyMapScreen(familyId: 'fam-test');
      expect(screen.familyId, 'fam-test');
      expect(screen.familyId, isA<String>());
    });

    test('two screens with different familyIds carry different ids', () {
      // This proves the familyId is per-instance, not a global constant
      // — the map screen can render family A OR family B based on what
      // the caller passes.
      final screenA = FamilyMapScreen(familyId: 'fam-a');
      final screenB = FamilyMapScreen(familyId: 'fam-b');
      expect(screenA.familyId, 'fam-a');
      expect(screenB.familyId, 'fam-b');
      expect(screenA.familyId, isNot(screenB.familyId));
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // 3. FAMILY MAP LIFECYCLE — MULTI-FAMILY STALE CALLBACK
  // ─────────────────────────────────────────────────────────────────────
  //
  // Scenario: family A's map starts initializing (attempt 0). The user
  // switches to family B (reset() → attempt 1). Family A's late
  // style-loaded callback finally fires with attempt 0 — it MUST be
  // ignored so family B's freshly-initialized state is not clobbered.
  //
  // This is the multi-family variant of the existing hardening test
  // ("stale attempt transition is ignored") — it makes the family-switch
  // semantics explicit.
  group('FamilyMapLifecycleController — multi-family switch safety', () {
    test(
      'family A late callback cannot overwrite family B state after switch',
      () {
        final c = FamilyMapLifecycleController();
        addTearDown(c.dispose);

        // ── Family A starts loading ────────────────────────────────────
        // Attempt 0. The map screen reads style JSON and waits for
        // onStyleLoaded.
        final attemptA = c.currentAttempt; // 0
        expect(attemptA, 0);
        c.transition(FamilyMapLifecycle.loadingStyle, attempt: attemptA);
        expect(
          c.state,
          FamilyMapLifecycle.loadingStyle,
          reason: 'Family A should be in loadingStyle.',
        );

        // ── User switches to family B ─────────────────────────────────
        // reset() invalidates family A's in-flight callbacks by bumping
        // the attempt counter.
        c.reset();
        final attemptB = c.currentAttempt; // 1
        expect(attemptB, 1);
        expect(
          c.state,
          FamilyMapLifecycle.initializing,
          reason: 'Family B should start fresh in initializing.',
        );

        // Family B progresses normally through its own lifecycle.
        c.transition(FamilyMapLifecycle.loadingStyle, attempt: attemptB);
        c.transition(FamilyMapLifecycle.preparingLayers, attempt: attemptB);
        c.transition(FamilyMapLifecycle.ready, attempt: attemptB);
        expect(
          c.state,
          FamilyMapLifecycle.ready,
          reason: 'Family B should be fully ready.',
        );

        // ── Family A's late callback finally fires ────────────────────
        // It carries the stale attemptA (0). The controller MUST drop it
        // silently — family B's `ready` state must be preserved.
        c.transition(FamilyMapLifecycle.ready, attempt: attemptA);
        expect(
          c.state,
          FamilyMapLifecycle.ready,
          reason:
              'Family A\'s stale callback must NOT overwrite '
              'family B\'s ready state.',
        );

        // And a stale transition to a *different* state must also be
        // dropped (e.g. family A's late "empty" callback).
        c.transition(FamilyMapLifecycle.empty, attempt: attemptA);
        expect(
          c.state,
          FamilyMapLifecycle.ready,
          reason:
              'Family A\'s stale transition to empty must be '
              'dropped — family B is still ready.',
        );
      },
    );

    test(
      'multiple rapid family switches keep the latest attempt authoritative',
      () {
        final c = FamilyMapLifecycleController();
        addTearDown(c.dispose);

        // Family A
        final attemptA = c.currentAttempt;
        c.transition(FamilyMapLifecycle.loadingStyle, attempt: attemptA);

        // Switch to family B
        c.reset();
        final attemptB = c.currentAttempt;
        c.transition(FamilyMapLifecycle.loadingStyle, attempt: attemptB);

        // Switch to family C (rapid, before B's style even loaded)
        c.reset();
        final attemptC = c.currentAttempt;
        c.transition(FamilyMapLifecycle.loadingStyle, attempt: attemptC);
        c.transition(FamilyMapLifecycle.ready, attempt: attemptC);

        // Late callbacks from A and B both fire — both must be dropped.
        c.transition(FamilyMapLifecycle.ready, attempt: attemptA);
        c.transition(FamilyMapLifecycle.empty, attempt: attemptB);
        expect(
          c.state,
          FamilyMapLifecycle.ready,
          reason:
              'Family C is the current authoritative attempt; '
              'A and B callbacks must be ignored.',
        );

        expect(c.currentAttempt, attemptC);
      },
    );
  });

  // ─────────────────────────────────────────────────────────────────────
  // 4. MapPin.locationSource EXISTS AND DEFAULTS TO NULL
  // ─────────────────────────────────────────────────────────────────────
  //
  // Pins constructed without locationSource (legacy callers, or pins
  // built before P10.1 enrichment) must remain valid. computeHouseholds
  // treats null locationSource as clusterable (see hardening_test.dart).
  group('MapPin — locationSource field', () {
    test('locationSource defaults to null when not provided', () {
      const pin = MapPin(
        personId: 'p1',
        name: 'A',
        city: 'Mumbai',
        photoUrl: null,
        lat: 19.076,
        lng: 72.877,
      );
      expect(
        pin.locationSource,
        isNull,
        reason:
            'MapPin.locationSource must default to null for '
            'backward compatibility with legacy callers.',
      );
    });

    test('locationSource can be set to a specific source', () {
      const pin = MapPin(
        personId: 'p1',
        name: 'A',
        city: 'Mumbai',
        photoUrl: null,
        lat: 19.076,
        lng: 72.877,
        locationSource: MapLocationSource.cityCentroid,
      );
      expect(pin.locationSource, MapLocationSource.cityCentroid);
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // 5. computeHouseholds SKIPS CITY-CENTROID PINS
  // ─────────────────────────────────────────────────────────────────────
  //
  // Two pins at the SAME coordinates but with DIFFERENT locationSource
  // values produce different household counts. This is the
  // authority-by-source rule: a city-centroid pin is a low-confidence
  // fallback and must NEVER collapse into a household with an exact
  // pin — even if they happen to share coordinates.
  group('computeHouseholds — locationSource authority', () {
    test('two pins at same coords: both city-centroid → no household; '
        'both exact → one household; mixed → only the exact pin clusters', () {
      const lat = 19.076;
      const lng = 72.877;

      MapPin pin({required MapLocationSource? source, required String id}) =>
          MapPin(
            personId: id,
            name: id,
            city: 'Mumbai',
            photoUrl: null,
            lat: lat,
            lng: lng,
            locationSource: source,
          );

      // Case A: both city-centroid → skipped → 0 households.
      final householdsA = computeHouseholds([
        pin(source: MapLocationSource.cityCentroid, id: 'a1'),
        pin(source: MapLocationSource.cityCentroid, id: 'a2'),
      ]);
      expect(
        householdsA,
        isEmpty,
        reason: 'City-centroid pins must never cluster.',
      );

      // Case B: both exactPlace → 1 multi-member household.
      final householdsB = computeHouseholds([
        pin(source: MapLocationSource.exactPlace, id: 'b1'),
        pin(source: MapLocationSource.exactPlace, id: 'b2'),
      ]);
      expect(householdsB, hasLength(1));
      expect(householdsB.first.isMulti, isTrue);
      expect(householdsB.first.size, 2);

      // Case C: mixed (one city-centroid, one exactPlace) → only the
      // exactPlace pin forms a (single-member) household. The
      // city-centroid pin is skipped and does NOT join the cluster.
      final householdsC = computeHouseholds([
        pin(source: MapLocationSource.cityCentroid, id: 'c1'),
        pin(source: MapLocationSource.exactPlace, id: 'c2'),
      ]);
      expect(
        householdsC,
        hasLength(1),
        reason:
            'Only the exactPlace pin should cluster; the '
            'city-centroid pin is skipped.',
      );
      expect(householdsC.first.size, 1);
      expect(householdsC.first.members.first.personId, 'c2');
    });

    test('null locationSource (legacy pin) at same coords as city-centroid '
        'pin: legacy pin clusters alone, city-centroid skipped', () {
      const lat = 12.9716;
      const lng = 77.5946;

      final households = computeHouseholds([
        const MapPin(
          personId: 'legacy',
          name: 'Legacy',
          city: 'Bengaluru',
          photoUrl: null,
          lat: lat,
          lng: lng,
          // locationSource intentionally omitted (legacy pin).
        ),
        const MapPin(
          personId: 'centroid',
          name: 'Centroid',
          city: 'Bengaluru',
          photoUrl: null,
          lat: lat,
          lng: lng,
          locationSource: MapLocationSource.cityCentroid,
        ),
      ]);

      // The legacy pin (null source) clusters → 1 single-member household.
      // The city-centroid pin is skipped.
      expect(households, hasLength(1));
      expect(households.first.members.first.personId, 'legacy');
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // 6. selectedFamilyIdProvider — SINGLE SOURCE OF TRUTH
  // ─────────────────────────────────────────────────────────────────────
  //
  // selectedFamilyIdProvider is the authoritative "current family" for
  // Track C sub-routes (and the router sets it before navigating into
  // the map). It must exist, start as null, and be settable to
  // different family IDs.
  group('selectedFamilyIdProvider — current family authority', () {
    test('starts as null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(selectedFamilyIdProvider), isNull);
    });

    test('can be set to family A, then family B', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(selectedFamilyIdProvider.notifier).state = 'fam-a';
      expect(container.read(selectedFamilyIdProvider), 'fam-a');

      // Switching families overwrites the previous value — there is
      // only one "selected family" at a time.
      container.read(selectedFamilyIdProvider.notifier).state = 'fam-b';
      expect(container.read(selectedFamilyIdProvider), 'fam-b');
      expect(container.read(selectedFamilyIdProvider), isNot('fam-a'));
    });

    test('can be cleared back to null (family deselected)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(selectedFamilyIdProvider.notifier).state = 'fam-a';
      expect(container.read(selectedFamilyIdProvider), 'fam-a');

      container.read(selectedFamilyIdProvider.notifier).state = null;
      expect(container.read(selectedFamilyIdProvider), isNull);
    });
  });
}
