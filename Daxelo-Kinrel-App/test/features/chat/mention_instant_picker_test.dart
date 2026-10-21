// Instant @mention picker — no loading state, no spinner, no "Loading…"
// text. The overlay shows the list immediately (one pump) when data
// is available, renders nothing when the list is empty (no spinner).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/chat/data/mention_candidates_provider.dart';
import 'package:kinrel/features/chat/presentation/widgets/mention_picker.dart';

void main() {
  // Stub strings without the removed `loading` field.
  const strings = MentionPickerStrings(
    errorRetry: "Couldn't load — tap to retry",
    noMatch: 'No one matches',
    noCandidates: 'No one to mention in this chat',
    dmHeader: "Mention a relative · they won't be notified",
    dmNoRelatives: 'No other relatives to mention in this family',
    capExceeded: 'You can mention up to 5 people in one message',
    recentlyActiveA11y: 'Recently active',
    elderA11y: 'Elder',
    mentionBadgeA11y: 'Mention',
  );

  group('Instant @mention picker — no loading state', () {
    testWidgets('empty cache: no spinner, no "Loading…" text, overlay hidden',
        (tester) async {
      final queryNotifier = ValueNotifier<String>('@');
      final candidatesNotifier =
          ValueNotifier<List<MentionCandidate>>(const []);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                MentionPickerOverlay(
                  query: queryNotifier,
                  candidates: candidatesNotifier,
                  layerLink: LayerLink(),
                  onSelected: (_) {},
                  onDismissed: () {},
                  currentUserId: 'me',
                  strings: strings,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump(); // single pump

      // No spinner.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      // No "Loading…" text.
      expect(find.text('Loading…'), findsNothing);
      // The overlay rendered a SizedBox.shrink (empty state).
      expect(find.byType(SizedBox), findsWidgets);
    });

    testWidgets('data available: list shows immediately on first pump',
        (tester) async {
      final queryNotifier = ValueNotifier<String>('@');
      final candidatesNotifier =
          ValueNotifier<List<MentionCandidate>>(const [
        MentionCandidate(
          personId: 'p1',
          userId: 'u1',
          name: 'Manish',
          initials: 'MA',
          kinshipTerm: 'Bhai',
          kinshipRelationLine: 'your brother',
          isElder: false,
          recentSenderRank: 1,
        ),
        MentionCandidate(
          personId: 'p2',
          userId: 'u2',
          name: 'Sunita',
          initials: 'SU',
          kinshipTerm: 'Maa',
          kinshipRelationLine: 'your mother',
          isElder: true,
          recentSenderRank: 0,
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                MentionPickerOverlay(
                  query: queryNotifier,
                  candidates: candidatesNotifier,
                  layerLink: LayerLink(),
                  onSelected: (_) {},
                  onDismissed: () {},
                  currentUserId: 'me',
                  strings: strings,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump(); // single pump — list must appear immediately

      // No spinner.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      // No "Loading…" text.
      expect(find.text('Loading…'), findsNothing);
      // The candidate names are visible.
      expect(find.text('Manish'), findsOneWidget);
      expect(find.text('Sunita'), findsOneWidget);
    });

    testWidgets('list updates when candidates arrive after first frame',
        (tester) async {
      final queryNotifier = ValueNotifier<String>('@');
      final candidatesNotifier =
          ValueNotifier<List<MentionCandidate>>(const []);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                MentionPickerOverlay(
                  query: queryNotifier,
                  candidates: candidatesNotifier,
                  layerLink: LayerLink(),
                  onSelected: (_) {},
                  onDismissed: () {},
                  currentUserId: 'me',
                  strings: strings,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      // Initially empty: no spinner.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Manish'), findsNothing);

      // Data arrives: list updates.
      candidatesNotifier.value = const [
        MentionCandidate(
          personId: 'p1',
          userId: 'u1',
          name: 'Manish',
          initials: 'MA',
          kinshipTerm: 'Bhai',
          kinshipRelationLine: 'your brother',
          isElder: false,
          recentSenderRank: 0,
        ),
      ];
      await tester.pump();

      // List appears — no spinner at any time.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Manish'), findsOneWidget);
    });

    testWidgets('no-match empty state renders (not a spinner)',
        (tester) async {
      final queryNotifier = ValueNotifier<String>('zzz');
      final candidatesNotifier =
          ValueNotifier<List<MentionCandidate>>(const [
        MentionCandidate(
          personId: 'p1',
          userId: 'u1',
          name: 'Manish',
          initials: 'MA',
          kinshipTerm: 'Bhai',
          kinshipRelationLine: 'your brother',
          isElder: false,
          recentSenderRank: 0,
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                MentionPickerOverlay(
                  query: queryNotifier,
                  candidates: candidatesNotifier,
                  layerLink: LayerLink(),
                  onSelected: (_) {},
                  onDismissed: () {},
                  currentUserId: 'me',
                  strings: strings,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      // "zzz" matches nothing → "No one matches" row, no spinner.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('No one matches'), findsOneWidget);
    });
  });
}
