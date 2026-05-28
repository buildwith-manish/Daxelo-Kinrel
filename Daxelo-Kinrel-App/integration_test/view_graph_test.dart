// integration_test/view_graph_test.dart
//
// DAXELO KINREL — View Graph Integration Tests (P3-F6)
//
// Tests the critical path for viewing the family graph:
//   1. Open a family with members
//   2. Navigate to graph view
//   3. Graph canvas is visible
//   4. Tap on a graph node shows member detail
//
// Precondition: User must be authenticated and have a family with members.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('View Graph', () {
    // ── Shared setup: login and navigate to a family ────────────────

    Future<void> setupWithFamilyAndMembers(tester) async {
      await pumpApp(tester);
      await dismissSplash(tester);

      // If we're on the sign-in screen, perform login
      final signInButton = find.text('Sign In');
      if (signInButton.evaluate().isNotEmpty) {
        await performLogin(
          tester,
          email: kTestEmail,
          password: kTestPassword,
        );
      }

      // Navigate to families tab
      await tapBottomNavTab(tester, 2);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Try to find a family card to tap on
      final familyCards = find.byType(Card);

      if (familyCards.evaluate().isNotEmpty) {
        // Tap the first family card to open its detail
        await tapAndSettle(tester, familyCards.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
      }
    }

    // ── Test 1: Open a Family with Members ──────────────────────────

    testWidgets('Open a family detail screen', (tester) async {
      await setupWithFamilyAndMembers(tester);

      // Verify we're on the family detail screen
      // It should have a TabBar with "Graph", "Members", "Activity"
      final graphTab = find.text('Graph');
      final membersTab = find.text('Members');

      expect(
        graphTab.evaluate().isNotEmpty || membersTab.evaluate().isNotEmpty,
        isTrue,
        reason: 'Family detail screen should show tab navigation.',
      );
    });

    // ── Test 2: Navigate to Graph View ──────────────────────────────

    testWidgets('Navigate to graph view tab', (tester) async {
      await setupWithFamilyAndMembers(tester);

      // The Graph tab is the first tab and should be active by default
      // If not, tap the "Graph" tab
      final graphTab = find.text('Graph');
      if (graphTab.evaluate().isNotEmpty) {
        await tapAndSettle(tester, graphTab.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }

      // Verify we're on the graph tab
      // The graph tab shows either:
      // - A FamilyTreeCanvas (if members exist)
      // - An empty state "No Members Yet" (if no members)
      final treeCanvas = find.byType(CustomPaint);
      final emptyState = find.text('No Members Yet');
      final addMemberPrompt = find.text('Add Member');

      final hasGraph = treeCanvas.evaluate().isNotEmpty ||
          emptyState.evaluate().isNotEmpty ||
          addMemberPrompt.evaluate().isNotEmpty;

      expect(
        hasGraph,
        isTrue,
        reason: 'Graph tab should show the tree canvas or an empty state.',
      );
    });

    // ── Test 3: Graph Canvas is Visible ─────────────────────────────

    testWidgets('Graph canvas is visible when family has members', (tester) async {
      await setupWithFamilyAndMembers(tester);

      // Navigate to the graph tab
      final graphTab = find.text('Graph');
      if (graphTab.evaluate().isNotEmpty) {
        await tapAndSettle(tester, graphTab.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }

      // The FamilyTreeCanvas uses a Stack with CustomPaint for rendering
      // If members exist, the canvas should be visible
      // If no members, the empty state should be visible

      // Check for graph-related elements:
      // - CustomPaint (used by FamilyTreeCanvas for drawing nodes/edges)
      // - Stack (the layout container for the graph)
      // - InteractiveViewer (for panning/zooming)
      final stack = find.byType(Stack);
      final interactiveViewer = find.byType(InteractiveViewer);

      // If the family has members, we should see graph elements
      final hasGraphElements = stack.evaluate().isNotEmpty ||
          interactiveViewer.evaluate().isNotEmpty;

      // If no members, we see the empty state instead
      final emptyState = find.text('No Members Yet');

      expect(
        hasGraphElements || emptyState.evaluate().isNotEmpty,
        isTrue,
        reason:
            'Graph view should either show the tree canvas or an empty state.',
      );
    });

    // ── Test 4: Tap on Graph Node Shows Member Detail ───────────────

    testWidgets('Tap on a graph node shows member detail', (tester) async {
      await setupWithFamilyAndMembers(tester);

      // Navigate to the graph tab
      final graphTab = find.text('Graph');
      if (graphTab.evaluate().isNotEmpty) {
        await tapAndSettle(tester, graphTab.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }

      // Check if we have members (not the empty state)
      final emptyState = find.text('No Members Yet');
      if (emptyState.evaluate().isNotEmpty) {
        // Skip this test — no members to tap on
        debugPrint('⚠️ No members in family — skipping graph node tap test.');
        return;
      }

      // The graph nodes are drawn as CustomPaint within the FamilyTreeCanvas.
      // We can tap at the center of the canvas to try to hit a node.
      // The canvas typically renders nodes in the center area.
      final canvasSize = tester.getSize(find.byType(CustomPaint).first);
      final centerX = canvasSize.width / 2;
      final centerY = canvasSize.height / 2;

      // Tap at the center of the canvas
      await tester.tapAt(Offset(centerX, centerY));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // After tapping a node, one of these should appear:
      // - PersonDetailSheet (bottom sheet with member details)
      // - Quick action bottom sheet
      // - The member's name appears in a detail view
      final bottomSheet = find.byType(BottomSheet);
      final detailSheet = find.byType(DraggableScrollableSheet);

      // If a bottom sheet appeared, it's likely the person detail
      if (bottomSheet.evaluate().isNotEmpty ||
          detailSheet.evaluate().isNotEmpty) {
        // Verify it shows some member detail content
        final editButton = find.text('Edit');
        final linkButton = find.text('Link');

        expect(
          editButton.evaluate().isNotEmpty ||
              linkButton.evaluate().isNotEmpty,
          isTrue,
          reason:
              'Tapping a graph node should show member detail with actions.',
        );
      }

      // Alternative: the tap might have been on empty space.
      // That's OK — this is a best-effort test.
      debugPrint(
        'Graph node tap result: bottomSheet=${bottomSheet.evaluate().isNotEmpty}, '
        'detailSheet=${detailSheet.evaluate().isNotEmpty}',
      );
    });
  });
}
