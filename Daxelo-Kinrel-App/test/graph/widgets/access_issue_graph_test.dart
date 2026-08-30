// test/graph/widgets/access_issue_graph_test.dart
//
// v5.135 REGRESSION TEST: Ensures the Family Graph screen shows a DISTINCT
// "access issue" state (not the misleading "no members yet" empty state)
// when the stats/count query shows non-zero members but the direct graph
// query returns empty (RLS blocked access or stale session).
//
// This test prevents the exact confusing symptom reported in the bug:
// "No family members yet. Add someone to start the graph." showing
// simultaneously with "MEMBERS: 714" in the stats panel.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daxelo_kinrel/graph/widgets/engine/empty_graph.dart';

void main() {
  group('v5.135: AccessIssueGraph', () {
    testWidgets('shows "Unable to load graph" message (not "add someone")',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AccessIssueGraph(reportedMemberCount: 714),
          ),
        ),
      );

      // The access-issue message should be present
      expect(find.text('Unable to load graph'), findsOneWidget);
      // The misleading "add someone to start" message should NOT be present
      expect(find.textContaining('Add someone to start'), findsNothing);
      // The member count should be shown so the user understands data exists
      expect(find.textContaining('714'), findsOneWidget);
      // The "log out and back in" guidance should be present
      expect(find.textContaining('logging out and back in'), findsOneWidget);
    });

    testWidgets('shows lock icon (not family_restroom icon)',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AccessIssueGraph(reportedMemberCount: 100),
          ),
        ),
      );

      // The lock icon indicates an access issue, not an empty family
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      // The family_restroom icon is used by the EmptyGraph state — it
      // should NOT appear here
      expect(find.byIcon(Icons.family_restroom), findsNothing);
    });

    testWidgets('shows retry button when onRetry is provided',
        (WidgetTester tester) async {
      var retryPressed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccessIssueGraph(
              reportedMemberCount: 50,
              onRetry: () => retryPressed = true,
            ),
          ),
        ),
      );

      final retryButton = find.text('Retry');
      expect(retryButton, findsOneWidget);

      await tester.tap(retryButton);
      await tester.pump();

      expect(retryPressed, isTrue);
    });

    testWidgets('handles null reportedMemberCount gracefully',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AccessIssueGraph(),
          ),
        ),
      );

      expect(find.text('Unable to load graph'), findsOneWidget);
      expect(find.textContaining('session may have expired'), findsOneWidget);
    });
  });

  group('v5.135: EmptyGraph (genuinely empty family)', () {
    testWidgets('shows "add someone to start" message for 0-member family',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyGraph(),
          ),
        ),
      );

      // The genuinely-empty message should be present
      expect(find.textContaining('No family members yet'), findsOneWidget);
      expect(find.textContaining('Add someone to start'), findsOneWidget);
      // The access-issue message should NOT be present
      expect(find.text('Unable to load graph'), findsNothing);
      expect(find.byIcon(Icons.lock_outline), findsNothing);
    });
  });

  group('v5.135: Distinct states do not leak into each other', () {
    testWidgets('AccessIssueGraph and EmptyGraph render different content',
        (WidgetTester tester) async {
      // Render EmptyGraph
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyGraph(),
          ),
        ),
      );
      final emptyText = find.textContaining('No family members yet');
      expect(emptyText, findsOneWidget);

      // Re-render with AccessIssueGraph
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AccessIssueGraph(reportedMemberCount: 714),
          ),
        ),
      );
      // The empty message should be GONE now
      expect(find.textContaining('No family members yet'), findsNothing);
      // The access-issue message should be present
      expect(find.text('Unable to load graph'), findsOneWidget);
    });
  });
}
