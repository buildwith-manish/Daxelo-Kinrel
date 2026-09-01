// test/graph/widgets/fab_presence_test.dart
//
// Widget tests for the FamilyGraphScreen AppBar actions.
//
// v4 (2026-06-18) updates:
//   - Zoom In / Zoom Out icons were REMOVED from the AppBar per user
//     request. Zoom is now handled exclusively by pinch gestures and
//     double-tap-to-zoom in the engine view's interaction_mixin.dart
//     (ScaleGestureRecognizer on a Listener widget — see the v9
//     Android fix in lib/graph/widgets/engine/interaction_mixin.dart).
//   - The two zoom-related tests were replaced with tests that verify
//     the zoom icons are NOT present (so we don't regress by re-adding
//     them).
//
// v5.x (dead-code cleanup): these comments previously claimed
// GraphPanZoom handled the gestures. GraphPanZoom was never
// instantiated — the real gesture handlers live in
// interaction_mixin.dart (which replaced GraphPanZoom with a
// Listener + ScaleGestureRecognizer approach). Comments corrected
// here too so the test file does not lie about the code path.
//
// Verifies:
//   - No FloatingActionButton exists in FamilyGraphScreen
//   - "Add Member" icon (person_add_alt_1_rounded) exists in AppBar actions
//   - Zoom in/out icons do NOT exist in AppBar (removed in v4)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:kinrel/features/family/presentation/family_graph_screen.dart';
import '../../helpers/native_plugin_mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(setupNativePluginMocks);
  tearDownAll(tearDownNativePluginMocks);
  group('FamilyGraphScreen AppBar actions', () {
    GoRouter _buildTestRouter() {
      return GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const FamilyGraphScreen(
              familyId: 'test_family',
              familyName: 'Test Family',
            ),
          ),
          GoRoute(
            path: '/family/:familyId/add-person',
            builder: (context, state) => const Scaffold(
              body: Text('Add Person Sheet'),
            ),
          ),
        ],
      );
    }

    testWidgets(
      'No FloatingActionButton exists in the graph screen',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp.router(
              routerConfig: _buildTestRouter(),
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 1));

        // No FAB should be present
        expect(find.byType(FloatingActionButton), findsNothing);
      },
    );

    testWidgets(
      'Add Member icon exists in AppBar actions',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp.router(
              routerConfig: _buildTestRouter(),
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 1));

        // The person_add icon should exist (in AppBar actions)
        expect(find.byIcon(Icons.person_add_alt_1_rounded), findsOneWidget);
      },
    );

    testWidgets(
      'v4: Zoom In icon is NOT in AppBar (removed — pinch-to-zoom only)',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp.router(
              routerConfig: _buildTestRouter(),
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 1));

        // The zoom_in icon should NOT be present — we removed it in v4
        // in favor of pinch-to-zoom gestures handled by the engine
        // view's interaction_mixin.dart (ScaleGestureRecognizer on a
        // Listener widget). GraphPanZoom is dead code — never
        // instantiated.
        expect(find.byIcon(Icons.zoom_in_rounded), findsNothing);
      },
    );

    testWidgets(
      'v4: Zoom Out icon is NOT in AppBar (removed — pinch-to-zoom only)',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp.router(
              routerConfig: _buildTestRouter(),
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 1));

        // The zoom_out icon should NOT be present — we removed it in v4
        // in favor of pinch-to-zoom gestures handled by the engine
        // view's interaction_mixin.dart (ScaleGestureRecognizer on a
        // Listener widget). GraphPanZoom is dead code — never
        // instantiated.
        expect(find.byIcon(Icons.zoom_out_rounded), findsNothing);
      },
    );
  });
}
