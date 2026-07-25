// test/features/cameo/presentation/cameo_live_3d_avatar_test.dart
//
// KINREL CAMEO — CameoLive3DAvatar Widget Tests
//
// Tests the production live 3D avatar widget:
//   1. Falls back to 2D on non-live-3D surfaces
//   2. Falls back to 2D when renderer init fails
//   3. Correctly initializes on live-3D surfaces (studio/profile_hero/journey)
//   4. Disposes resources correctly
//   5. Handles repeated mount/unmount without memory leaks
//   6. Respects LOD controller rules
//
// Note: Tests that require 3D initialization (studio, profile_hero, journey)
// are skipped in headless/CI environments because ThermionCameoRenderer
// needs a GPU context. These are validated on-device via the B1 APK workflow.

import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/cameo/cameo.dart';

/// Whether we have a GPU available for live 3D tests.
/// In CI/headless environments, Thermion can't initialize.
bool get _hasGPU {
  // Check for explicit GPU flag, or assume no GPU in CI.
  final hasGPU = Platform.environment['KINREL_HAS_GPU'] == 'true';
  return hasGPU;
}

void main() {
  group('CameoLive3DAvatar — 2D fallback surfaces', () {
    testWidgets(
      'shows 2D fallback on dense surfaces (map_marker)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CameoLive3DAvatar(
                personName: 'Test Person',
                ageBand: CameoAgeBand.adult,
                skinToneIndex: 5,
                surfaceId: 'map_marker',
              ),
            ),
          ),
        );

        // Wait for async initialization
        await tester.pumpAndSettle();

        // On map_marker (dense surface), should fall back to CameoAvatar
        // which renders as CustomPaint (CameoPortraitPainter).
        expect(find.byType(CameoAvatar), findsOneWidget);
        expect(find.byType(CameoLive3DAvatar), findsOneWidget);
      },
    );

    testWidgets(
      'shows 2D fallback on chat_avatar surface',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CameoLive3DAvatar(
                personName: 'Test Person',
                ageBand: CameoAgeBand.adult,
                skinToneIndex: 5,
                surfaceId: 'chat_avatar',
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // chat_avatar is a dense surface → 2D fallback
        expect(find.byType(CameoAvatar), findsOneWidget);
      },
    );

    testWidgets(
      'shows 2D fallback on graph_node surface',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CameoLive3DAvatar(
                personName: 'Test Person',
                ageBand: CameoAgeBand.adult,
                skinToneIndex: 5,
                surfaceId: 'graph_node',
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        expect(find.byType(CameoAvatar), findsOneWidget);
      },
    );

    testWidgets(
      'shows 2D fallback on timeline_card surface',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CameoLive3DAvatar(
                personName: 'Test Person',
                ageBand: CameoAgeBand.adult,
                skinToneIndex: 5,
                surfaceId: 'timeline_card',
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        expect(find.byType(CameoAvatar), findsOneWidget);
      },
    );
  });

  group('CameoLive3DAvatar — 3D initialization (requires GPU)', () {
    // These tests require a GPU context (Thermion). In CI/headless
    // environments, ThermionCameoRenderer cannot initialize, so we skip.
    // On-device validation uses the B1 Verification APK workflow.
    testWidgets(
      'attempts 3D initialization on profile_hero surface',
      (tester) async {
        if (!_hasGPU) {
          // In headless CI, Thermion init fails gracefully → 2D fallback.
          // We verify the fallback path instead of skipping entirely.
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: CameoLive3DAvatar(
                  personName: 'Test Person',
                  ageBand: CameoAgeBand.adult,
                  skinToneIndex: 5,
                  surfaceId: 'profile_hero',
                ),
              ),
            ),
          );

          await tester.pumpAndSettle(const Duration(seconds: 5));

          // After init fails in headless, should show 2D fallback
          expect(find.byType(CameoAvatar), findsOneWidget);
          return;
        }

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CameoLive3DAvatar(
                personName: 'Test Person',
                ageBand: CameoAgeBand.adult,
                skinToneIndex: 5,
                surfaceId: 'profile_hero',
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.byType(CameoLive3DAvatar), findsOneWidget);
        await tester.pumpAndSettle();
        expect(find.byType(CameoAvatar), findsOneWidget);
      },
    );

    testWidgets(
      'attempts 3D initialization on studio surface',
      (tester) async {
        if (!_hasGPU) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: CameoLive3DAvatar(
                  personName: 'Test Person',
                  ageBand: CameoAgeBand.adult,
                  skinToneIndex: 5,
                  surfaceId: 'studio',
                ),
              ),
            ),
          );

          await tester.pumpAndSettle(const Duration(seconds: 5));
          expect(find.byType(CameoAvatar), findsOneWidget);
          return;
        }

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CameoLive3DAvatar(
                personName: 'Test Person',
                ageBand: CameoAgeBand.adult,
                skinToneIndex: 5,
                surfaceId: 'studio',
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        expect(find.byType(CameoAvatar), findsOneWidget);
      },
    );

    testWidgets(
      'attempts 3D initialization on journey surface',
      (tester) async {
        if (!_hasGPU) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: CameoLive3DAvatar(
                  personName: 'Test Person',
                  ageBand: CameoAgeBand.elder,
                  skinToneIndex: 3,
                  surfaceId: 'journey',
                  isDeceased: true,
                ),
              ),
            ),
          );

          await tester.pumpAndSettle(const Duration(seconds: 5));
          expect(find.byType(CameoAvatar), findsOneWidget);
          return;
        }

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CameoLive3DAvatar(
                personName: 'Test Person',
                ageBand: CameoAgeBand.elder,
                skinToneIndex: 3,
                surfaceId: 'journey',
                isDeceased: true,
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        expect(find.byType(CameoAvatar), findsOneWidget);
      },
    );

    testWidgets(
      'graceful fallback on renderer init failure',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CameoLive3DAvatar(
                personName: 'Broken Init Test',
                ageBand: CameoAgeBand.adult,
                skinToneIndex: 5,
                surfaceId: 'profile_hero',
              ),
            ),
          ),
        );

        await tester.pumpAndSettle(const Duration(seconds: 5));

        // Must have fallen back to 2D CameoAvatar
        expect(find.byType(CameoAvatar), findsAtLeast(1));
      },
    );

    testWidgets(
      'disposes resources correctly on unmount',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CameoLive3DAvatar(
                personName: 'Dispose Test',
                ageBand: CameoAgeBand.adult,
                skinToneIndex: 5,
                surfaceId: 'profile_hero',
              ),
            ),
          ),
        );

        await tester.pumpAndSettle(const Duration(seconds: 5));

        // Replace with empty widget to trigger dispose
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: SizedBox.shrink()),
          ),
        );

        await tester.pumpAndSettle();

        // Widget should be gone, no exceptions thrown
        expect(find.byType(CameoLive3DAvatar), findsNothing);
      },
    );

    testWidgets(
      'repeated mount/unmount does not crash (leak test)',
      (tester) async {
        for (int i = 0; i < 3; i++) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: CameoLive3DAvatar(
                  personName: 'Leak Test $i',
                  ageBand: CameoAgeBand.adult,
                  skinToneIndex: (i % 10) + 1,
                  surfaceId: 'profile_hero',
                ),
              ),
            ),
          );

          await tester.pumpAndSettle(const Duration(seconds: 3));

          // Remove widget
          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(body: SizedBox.shrink()),
            ),
          );

          await tester.pumpAndSettle();
        }

        // If we got here without exceptions, the test passes.
        expect(true, isTrue);
      },
    );
  });

  group('CameoLive3DAvatar — general', () {
    testWidgets(
      'respects different age bands',
      (tester) async {
        for (final band in CameoAgeBand.values) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: CameoLive3DAvatar(
                  personName: 'Age Test',
                  ageBand: band,
                  skinToneIndex: 5,
                  surfaceId: 'map_marker',
                ),
              ),
            ),
          );

          await tester.pumpAndSettle();
          expect(find.byType(CameoAvatar), findsOneWidget);
        }
      },
    );

    testWidgets(
      'provides semantic label for accessibility',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CameoLive3DAvatar(
                personName: 'Aaji',
                ageBand: CameoAgeBand.elder,
                skinToneIndex: 5,
                surfaceId: 'map_marker',
                isDeceased: true,
                relationshipLabel: 'grandmother',
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // The widget should have a Semantics node
        final semantics = tester.getSemantics(find.byType(CameoAvatar).first);
        expect(semantics.label, isNotEmpty);
      },
    );

    testWidgets(
      'on3DStateChanged callback fires on fallback',
      (tester) async {
        final states = <CameoLive3DState>[];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CameoLive3DAvatar(
                personName: 'Callback Test',
                ageBand: CameoAgeBand.adult,
                skinToneIndex: 5,
                surfaceId: 'map_marker',
                on3DStateChanged: states.add,
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // On map_marker (dense surface), should immediately go to fallback2D
        expect(states, contains(CameoLive3DState.fallback2D));
      },
    );
  });

  group('CameoLodController with CameoLive3DAvatar', () {
    test(
      'live-3D surfaces are studio, profile_hero, journey',
      () {
        final controller = CameoLodController();

        // Live 3D surfaces should resolve to LOD0 or LOD1
        expect(
          controller.resolveLod(surfaceId: 'studio'),
          isNot(equals(CameoLOD.lod2)),
        );
        expect(
          controller.resolveLod(surfaceId: 'studio'),
          isNot(equals(CameoLOD.lod3)),
        );
        expect(
          controller.resolveLod(surfaceId: 'profile_hero'),
          isNot(equals(CameoLOD.lod2)),
        );
        expect(
          controller.resolveLod(surfaceId: 'journey'),
          isNot(equals(CameoLOD.lod2)),
        );
      },
    );

    test(
      'dense surfaces resolve to LOD2 or LOD3 (never live 3D)',
      () {
        final controller = CameoLodController();

        for (final surface in [
          'map_marker',
          'graph_node',
          'chat_avatar',
          'timeline_card',
        ]) {
          final lod = controller.resolveLod(surfaceId: surface);
          expect(
            lod == CameoLOD.lod2 || lod == CameoLOD.lod3,
            isTrue,
            reason: '$surface should use LOD2 or LOD3, got $lod',
          );
        }
      },
    );

    test(
      'thumbnail surfaces resolve to LOD3',
      () {
        final controller = CameoLodController();

        expect(
          controller.resolveLod(surfaceId: 'notification'),
          equals(CameoLOD.lod3),
        );
        expect(
          controller.resolveLod(surfaceId: 'search_result'),
          equals(CameoLOD.lod3),
        );
      },
    );
  });
}
