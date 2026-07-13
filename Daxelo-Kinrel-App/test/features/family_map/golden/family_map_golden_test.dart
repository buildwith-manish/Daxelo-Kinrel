// test/features/family_map/golden/family_map_golden_test.dart
//
// P11.8 — Golden tests for the Family Map.
//
// Captures the visual baseline of the map widgets so any unintended
// visual regression is caught by CI. Uses Flutter's built-in matchesGoldenFile
// (no golden_toolkit dependency needed — keeps the dev_deps minimal per
// Rule: zero infrastructure cost).
//
// Golden files are generated on Linux CI. Cross-platform font rendering
// differences may cause goldens to fail locally on macOS/Windows —
// regenerate with `flutter test --update-goldens` on Linux for the
// canonical baseline.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kinrel/features/family_map/widgets/avatar_marker_overlay.dart';
import 'package:kinrel/features/family_map/widgets/household_cluster_marker.dart';
import 'package:kinrel/features/family_map/widgets/map_polish_overlay.dart';
import 'package:kinrel/features/family_map/widgets/map_skeleton.dart';
import 'package:kinrel/features/family_map/widgets/map_timeline_scrubber.dart';
import 'package:kinrel/features/family_map/providers/family_map_provider.dart';
import 'package:kinrel/features/family_map/providers/live_location_provider.dart';

void main() {
  group('P11.8 — Family Map Golden Tests', () {
    testWidgets('MapSkeleton golden', (tester) async {
      // Use reduced-motion to avoid the infinite shimmer animation
      // (pumpAndSettle times out on repeating animations).
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: MapSkeleton(reducedMotion: true)),
        ),
      );
      await tester.pump();
      await expectLater(
        find.byType(MapSkeleton),
        matchesGoldenFile('goldens/map_skeleton.png'),
      );
    });

    testWidgets('MapSkeleton reduced-motion golden', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: MapSkeleton(reducedMotion: true)),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MapSkeleton),
        matchesGoldenFile('goldens/map_skeleton_reduced_motion.png'),
      );
    });

    testWidgets('AvatarMarkerWidget golden (unselected)', (tester) async {
      const pin = MapPin(
        personId: 'p1',
        name: 'Ravi Sharma',
        city: 'Pune',
        photoUrl: null,
        lat: 18.52,
        lng: 73.85,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.grey[900],
            body: Center(
              child: AvatarMarkerWidget(
                pin: pin,
                selected: false,
                reducedMotion: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(AvatarMarkerWidget),
        matchesGoldenFile('goldens/avatar_marker_unselected.png'),
      );
    });

    testWidgets('AvatarMarkerWidget golden (selected)', (tester) async {
      const pin = MapPin(
        personId: 'p1',
        name: 'Ravi Sharma',
        city: 'Pune',
        photoUrl: null,
        lat: 18.52,
        lng: 73.85,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.grey[900],
            body: Center(
              child: AvatarMarkerWidget(
                pin: pin,
                selected: true,
                reducedMotion: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(AvatarMarkerWidget),
        matchesGoldenFile('goldens/avatar_marker_selected.png'),
      );
    });

    testWidgets('HouseholdClusterMarkerWidget golden (size=3)', (tester) async {
      final household = Household(
        id: 'h1',
        members: List.generate(3, (i) => MapPin(
          personId: 'p$i',
          name: 'Member $i',
          city: 'Pune',
          photoUrl: null,
          lat: 18.52,
          lng: 73.85,
        )),
        lat: 18.52,
        lng: 73.85,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.grey[900],
            body: Center(
              child: HouseholdClusterMarkerWidget(
                household: household,
                reducedMotion: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(HouseholdClusterMarkerWidget),
        matchesGoldenFile('goldens/household_cluster_3.png'),
      );
    });

    testWidgets('HouseholdClusterMarkerWidget golden (size=5 with badge)',
        (tester) async {
      final household = Household(
        id: 'h5',
        members: List.generate(5, (i) => MapPin(
          personId: 'p$i',
          name: 'Member $i',
          city: 'Pune',
          photoUrl: null,
          lat: 18.52,
          lng: 73.85,
        )),
        lat: 18.52,
        lng: 73.85,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.grey[900],
            body: Center(
              child: HouseholdClusterMarkerWidget(
                household: household,
                reducedMotion: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(HouseholdClusterMarkerWidget),
        matchesGoldenFile('goldens/household_cluster_5_badge.png'),
      );
    });

    testWidgets('MapPolishOverlay golden', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            backgroundColor: Color(0xFF131416),
            body: SizedBox(
              width: 300,
              height: 600,
              child: MapPolishOverlay(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MapPolishOverlay),
        matchesGoldenFile('goldens/map_polish_overlay.png'),
      );
    });
  });
}
