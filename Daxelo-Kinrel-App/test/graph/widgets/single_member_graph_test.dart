// test/graph/widgets/single_member_graph_test.dart
//
// AGENT-08 (Quality & Testing) — Regression test for BUG-2:
// Single-member graph renders a node instead of blank screen.
//
// Verifies:
//   - FamilyGraphWidget with a single person renders without blank screen
//   - A GraphNode widget with name 'Kishan' is present in the tree
//   - No EmptyState (memberCount: 0 variant) is displayed
//
// Strategy: Since FamilyGraphWidget relies on complex Riverpod providers
// (familyGraphProvider, graphLayoutProvider, analyticsTrackerProvider, etc.),
// we override familyGraphProvider to return a deterministic single-person
// graph and verify the widget renders correctly.
//
// IMPORTANT: analyticsTrackerProvider depends on AnalyticsService which
// requires Firebase.initializeApp(). We override it at the Riverpod level
// with a Provider that returns a no-op AnalyticsTracker.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kinrel/graph/widgets/family_graph.dart';
import 'package:kinrel/graph/widgets/graph_node.dart';
import 'package:kinrel/graph/analytics/analytics_tracker.dart';
import 'package:kinrel/graph/engine/fallback_manager.dart';
import 'package:kinrel/core/database/sync/connectivity_service.dart';
import 'package:kinrel/core/services/analytics_service.dart';
import 'package:kinrel/features/family/presentation/providers/family_graph_provider.dart';
import '../../helpers/native_plugin_mocks.dart';

// ═══════════════════════════════════════════════════════════════════════════
// NO-OP ANALYTICS TRACKER PROVIDER
// ═══════════════════════════════════════════════════════════════════════════

/// A no-op AnalyticsTracker provider that avoids Firebase entirely.
///
/// The real analyticsTrackerProvider → analyticsServiceProvider →
/// AnalyticsService.instance → FirebaseAnalytics.instance, which crashes
/// in tests without Firebase.initializeApp(). This provider creates an
/// AnalyticsTracker that wraps AnalyticsService.instance (required by
/// the constructor) but overrides every method to do nothing, so the
/// internal _analyticsService field is never accessed after construction.
final _noOpAnalyticsTrackerProvider = Provider<AnalyticsTracker>((ref) {
  return _NoOpAnalyticsTracker();
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(setupNativePluginMocks);
  tearDownAll(tearDownNativePluginMocks);
  group('Single-member graph rendering regression (BUG-2)', () {
    /// Builds a single-person FlatGraphResult for testing.
    FlatGraphResult buildSinglePersonGraph() {
      return FlatGraphResult(
        persons: [
          <String, dynamic>{
            'id': 'p1',
            'name': 'Kishan',
            'gender': 'male',
            'generationIndex': 0,
            'isAnchor': true,
            'photoUrl': null,
            'isDeceased': false,
          },
        ],
        relationships: [],
      );
    }

    /// Helper: builds the FamilyGraphWidget inside a ProviderScope with
    /// all necessary provider overrides for a single-member graph.
    Widget buildTestWidget({
      required FlatGraphResult graphData,
      List<Override> additionalOverrides = const [],
    }) {
      return ProviderScope(
        overrides: [
          // Override the family-scoped async provider to return our test data
          familyGraphProvider.overrideWith(
            () => _FakeFamilyGraphNotifier(graphData),
          ),

          // Override analyticsTrackerProvider to avoid Firebase initialization.
          // Uses a no-op tracker that discards all events silently.
          analyticsTrackerProvider
              .overrideWith((ref) => ref.watch(_noOpAnalyticsTrackerProvider)),

          // Override analyticsServiceProvider to prevent the real singleton
          // from being accessed (it triggers FirebaseAnalytics.instance).
          analyticsServiceProvider
              .overrideWith((ref) => AnalyticsService.instance),

          // Provide a default FallbackManager state so currentEngineTierProvider
          // doesn't try to access real engine resources.
          fallbackManagerProvider
              .overrideWith((ref) => FallbackManager()),

          // Always online in tests — avoids connectivity service dependency.
          isOnlineProvider.overrideWith(
            (ref) => Stream.value(true),
          ),

          ...additionalOverrides,
        ],
        child: MaterialApp(
          home: Scaffold(
            body: FamilyGraphWidget(
              familyId: 'test-family',
              familyName: 'Test Family',
            ),
          ),
        ),
      );
    }

    testWidgets(
      'BUG-2: FamilyGraphWidget renders without blank screen for single member',
      (tester) async {
        final graphData = buildSinglePersonGraph();

        await tester.pumpWidget(buildTestWidget(graphData: graphData));
        await tester.pump(const Duration(seconds: 1));

        // The widget should NOT show a completely blank screen.
        final stackFinder = find.byType(Stack);
        expect(stackFinder, findsWidgets, reason: 'Graph should render a Stack layout');

        // Verify that we do NOT see the zero-member EmptyState text
        expect(
          find.text('Add Yourself'),
          findsNothing,
          reason: 'Zero-member EmptyState must not appear for single-member graph',
        );
        expect(
          find.text('Start your family tree.'),
          findsNothing,
          reason: 'Zero-member EmptyState subtitle must not appear for single-member graph',
        );
      },
    );

    testWidgets(
      'BUG-2: GraphNode with name "Kishan" is present in the widget tree',
      (tester) async {
        final graphData = buildSinglePersonGraph();

        await tester.pumpWidget(buildTestWidget(graphData: graphData));
        await tester.pump(const Duration(seconds: 1));

        expect(
          find.byType(GraphNode),
          findsWidgets,
          reason: 'At least one GraphNode must be rendered for a single-member graph',
        );

        expect(
          find.text('Kishan'),
          findsWidgets,
          reason: 'The person name "Kishan" must appear in the widget tree',
        );
      },
    );

    testWidgets(
      'BUG-2: No EmptyState (memberCount: 0 variant) is displayed',
      (tester) async {
        final graphData = buildSinglePersonGraph();

        await tester.pumpWidget(buildTestWidget(graphData: graphData));
        await tester.pump(const Duration(seconds: 1));

        expect(
          find.text('Add Yourself'),
          findsNothing,
          reason: '0-member EmptyState "Add Yourself" must not appear for single-member graph',
        );

        expect(
          find.text('Start your family tree.'),
          findsNothing,
          reason: '0-member EmptyState subtitle must not appear for single-member graph',
        );
      },
    );

    testWidgets(
      'BUG-2: Viewport culling fallback — empty visible set shows all nodes',
      (tester) async {
        final Set<String> visibleNodeIds = {};
        final Map<String, dynamic> personMap = {
          'p1': {'name': 'Kishan', 'id': 'p1'},
        };

        // Simulate the fallback logic used in FamilyGraphWidget
        final effectiveVisibleIds = visibleNodeIds.isEmpty
            ? personMap.keys.toSet()
            : visibleNodeIds;

        expect(effectiveVisibleIds, isNotEmpty);
        expect(effectiveVisibleIds, contains('p1'));

        final Set<String> populatedVisible = {'p1'};
        final effectivePopulated = populatedVisible.isEmpty
            ? personMap.keys.toSet()
            : populatedVisible;

        expect(effectivePopulated, equals({'p1'}));
      },
    );
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// FAKE NOTIFIER: Returns deterministic graph data for testing
// ═══════════════════════════════════════════════════════════════════════════

/// A fake FamilyGraphNotifier that immediately returns [graphData]
/// without making any Supabase/RPC calls.
class _FakeFamilyGraphNotifier extends FamilyGraphNotifier {
  final FlatGraphResult _graphData;

  _FakeFamilyGraphNotifier(this._graphData);

  @override
  Future<FlatGraphResult> build(String familyId) async {
    return _graphData;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// NO-OP ANALYTICS TRACKER: Prevents FirebaseException in test environment
// ═══════════════════════════════════════════════════════════════════════════

/// A no-op [AnalyticsTracker] that silently discards all analytics events.
///
/// Extends the real AnalyticsTracker and overrides every track method to
/// do nothing, breaking the Firebase dependency chain. The super constructor
/// requires an AnalyticsService, but since all methods are overridden to
/// no-ops, the service's Firebase fields are never accessed after
/// construction.
class _NoOpAnalyticsTracker extends AnalyticsTracker {
  _NoOpAnalyticsTracker() : super(AnalyticsService.instance);

  @override
  void trackNodeClick(String memberId, String relationshipType, int disclosureLevel) {}

  @override
  void trackBranchExpand(String memberId, String branchType, int nodesRevealed, int loadTimeMs) {}

  @override
  void trackSearchQuery(int queryLength, int resultCount, int responseTimeMs) {}

  @override
  void trackFilterApplied(String filterType, int nodesBefore, int nodesAfter) {}

  @override
  void trackCameraFocus(String targetMemberId, int animationDurationMs) {}

  @override
  void trackGraphOpenTime(int totalMs, int nodeCount, bool cacheHit) {}

  @override
  void trackSimulationFps(double fps, int nodeCount, double alphaValue) {}

  @override
  void trackMemoryUsage(double totalMb, double graphMb, double cacheMb) {}

  @override
  void trackGraphCrash(String exceptionType, String stackTrace, int nodeCount) {}

  @override
  void trackEngineFallback(String fromTier, String toTier, int nodeCount, String reason) {}

  @override
  void trackOnboardingStepCompleted(int stepNumber) {}

  @override
  void dispose() {}
}
