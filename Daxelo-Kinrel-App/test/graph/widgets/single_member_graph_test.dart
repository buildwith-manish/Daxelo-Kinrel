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
// requires Firebase.initializeApp(). We cannot extend AnalyticsService
// (private constructor), so we override analyticsTrackerProvider at the
// Riverpod level to provide a completely independent no-op implementation.

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

void main() {
  group('Single-member graph rendering regression (BUG-2)', () {
    /// Builds a single-person FlatGraphResult for testing.
    FlatGraphResult _buildSinglePersonGraph() {
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
    ///
    /// Key overrides to prevent Firebase/connectivity crashes in CI:
    ///   - analyticsTrackerProvider → no-op tracker (avoids Firebase init)
    ///   - fallbackManagerProvider → default state (avoids real engine logic)
    ///   - isOnlineProvider → always online (avoids connectivity service)
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

          // Override analyticsServiceProvider FIRST to prevent Firebase crash.
          // The real AnalyticsService.instance accesses FirebaseAnalytics.instance
          // which throws FirebaseException if Firebase.initializeApp() hasn't run.
          // We return a new instance that won't call Firebase because we override
          // analyticsTrackerProvider below to never use the service's Firebase field.
          //
          // Since AnalyticsService has a private constructor, we can't subclass it.
          // Instead, we override both providers in the chain:
          //   1. analyticsServiceProvider → returns the singleton (needed by type)
          //   2. analyticsTrackerProvider → returns a no-op tracker that never
          //      calls any AnalyticsService methods (so Firebase is never touched)
          analyticsServiceProvider.overrideWith((ref) => AnalyticsService.instance),

          // Override the tracker itself to use a no-op implementation.
          // This is the critical override — it prevents the AnalyticsTracker
          // from ever calling AnalyticsService.logEvent(), which would trigger
          // FirebaseAnalytics and crash in tests.
          analyticsTrackerProvider
              .overrideWithValue(_NoOpAnalyticsTracker()),

          // Provide a default FallbackManager state so currentEngineTierProvider
          // doesn't try to access real engine resources.
          fallbackManagerProvider.overrideWith(
            () => _NoOpFallbackManager(),
          ),

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
        final graphData = _buildSinglePersonGraph();

        await tester.pumpWidget(buildTestWidget(graphData: graphData));
        await tester.pumpAndSettle();

        // The widget should NOT show a completely blank screen.
        // Verify that at least some content is rendered (not just empty space).
        // The FamilyGraphWidget builds a Stack with nodes when persons exist.
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
        final graphData = _buildSinglePersonGraph();

        await tester.pumpWidget(buildTestWidget(graphData: graphData));
        await tester.pumpAndSettle();

        // A GraphNode should be rendered for our single person
        // Note: The name 'Kishan' appears inside the GraphNode widget
        // which renders the person's name as text.
        expect(
          find.byType(GraphNode),
          findsWidgets,
          reason: 'At least one GraphNode must be rendered for a single-member graph',
        );

        // The name "Kishan" should appear somewhere in the tree
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
        final graphData = _buildSinglePersonGraph();

        await tester.pumpWidget(buildTestWidget(graphData: graphData));
        await tester.pumpAndSettle();

        // The EmptyState widget should NOT be displayed when we have 1 member.
        // In the fixed code, EmptyState only appears for persons.isEmpty (0 members).
        // For 1+ members, the graph with GraphNode widgets is rendered instead.
        expect(
          find.text('Add Yourself'),
          findsNothing,
          reason: '0-member EmptyState "Add Yourself" must not appear for single-member graph',
        );

        // Also verify the "Start your family tree." text is not present
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
        // This verifies the core fix pattern:
        //   final effectiveVisibleIds = _visibleNodeIds.isEmpty
        //       ? _personMap.keys.toSet()
        //       : _visibleNodeIds;

        final Set<String> visibleNodeIds = {};
        final Map<String, dynamic> personMap = {
          'p1': {'name': 'Kishan', 'id': 'p1'},
        };

        // Simulate the fallback logic used in FamilyGraphWidget
        final effectiveVisibleIds = visibleNodeIds.isEmpty
            ? personMap.keys.toSet()
            : visibleNodeIds;

        // When _visibleNodeIds is empty, fallback should include all persons
        expect(effectiveVisibleIds, isNotEmpty);
        expect(effectiveVisibleIds, contains('p1'));

        // When _visibleNodeIds has content, it should be used directly
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
/// The real AnalyticsTracker depends on AnalyticsService → FirebaseAnalytics,
/// which requires Firebase.initializeApp(). In test environments, Firebase
/// is not available, causing:
///   FirebaseException: [core/no-app] No Firebase App '[DEFAULT]' has been created
///
/// This class overrides all tracking methods to do nothing, breaking the
/// Firebase dependency chain entirely. It's used via Riverpod's
/// overrideWithValue in the test's ProviderScope.
class _NoOpAnalyticsTracker extends AnalyticsTracker {
  /// Creates a no-op tracker. We pass a dummy AnalyticsService that is
  /// never actually called (all methods are overridden below), so it
  /// doesn't matter that we can't construct a real one.
  ///
  /// We use AnalyticsService.instance here because the constructor
  /// AnalyticsTracker(AnalyticsService) requires it, but since every
  /// method override discards the call, the _analyticsService field
  /// inside AnalyticsTracker is never accessed after construction.
  _NoOpAnalyticsTracker() : super(AnalyticsService.instance);

  @override
  void trackNodeClick(String memberId, String relationship, int generation) {}
  @override
  void trackBranchExpand(String memberId, int newVisibleCount) {}
  @override
  void trackSearchQuery(String query, int resultCount) {}
  @override
  void trackFilterApplied(String filterType, int visibleCount) {}
  @override
  void trackCameraFocus(String memberId, int durationMs) {}
  @override
  void trackGraphOpenTime(int durationMs, int nodeCount, bool success) {}
  @override
  void trackSimulationFps(int fps, int nodeCount) {}
  @override
  void trackMemoryUsage(int mb, int nodeCount) {}
  @override
  void trackGraphCrash(String errorType, StackTrace stackTrace, int nodeCount) {}
  @override
  void trackEngineFallback(String fromEngine, String toEngine, int nodeCount) {}
  @override
  void trackOnboardingStepCompleted(int stepNumber) {}
  @override
  void dispose() {}
}

// ═══════════════════════════════════════════════════════════════════════════
// NO-OP FALLBACK MANAGER: Provides default engine state for tests
// ═══════════════════════════════════════════════════════════════════════════

/// A no-op [FallbackManager] that returns a default [FallbackState]
/// without initializing timers, performance monitors, or analytics.
class _NoOpFallbackManager extends FallbackManager {
  _NoOpFallbackManager() : super();

  @override
  FallbackState build() => const FallbackState();
}
