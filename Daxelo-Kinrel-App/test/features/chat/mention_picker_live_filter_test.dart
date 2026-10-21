// Phase A — @mentions across chat. Widget test for the reactive
// MentionPickerOverlay: verify the list narrows as the query changes.
//
// This is the most critical regression test for the Phase A rewrite:
// the previous StatelessWidget version captured the first query at
// construction time and never updated, so typing "@m" then "@ma" then
// "@mam" showed the SAME list (the first one). The new reactive
// overlay reads the query from a ValueNotifier and re-filters on
// every change.
//
// What this proves:
//   • The overlay's ValueListenableBuilder re-renders when the query
//     ValueNotifier changes.
//   • The search index narrows the candidate list per query.
//   • The "no match" empty state renders visibly (was silent
//     SizedBox.shrink in the old version).
//
// Deferred (see MENTIONS_DEPLOY.md "Deferred items" #5):
//   • mention_picker_empty_state_test.dart (loading / error rows)
//   • mention_tracker_offset_test.dart (Hindi + emoji + paste)
//   • mention_candidates_provider_test.dart (group scope + self/blocked)
//   • chat.service.spec.ts extends (cap-reject, non-member-reject ×2,
//     dedupe, notify-derivation ×2)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/chat/data/mention_candidates_provider.dart';
import 'package:kinrel/features/chat/presentation/widgets/mention_picker.dart';

void main() {
  group('MentionPickerOverlay — live filtering', () {
    testWidgets('narrows the candidate list as the query changes',
        (tester) async {
      // Build a small candidate list (3 members with kinship terms).
      final candidates = <List<MentionCandidate>>[
        [
          const MentionCandidate(
            personId: 'p1',
            userId: 'u1',
            name: 'Manish',
            initials: 'MA',
            kinshipTerm: 'Bhai',
            kinshipRelationLine: 'your brother',
            isElder: false,
            recentSenderRank: 3,
          ),
          const MentionCandidate(
            personId: 'p2',
            userId: 'u2',
            name: 'Malti',
            initials: 'ML',
            kinshipTerm: 'Bua',
            kinshipRelationLine: "your father's sister",
            isElder: false,
            recentSenderRank: 2,
          ),
          const MentionCandidate(
            personId: 'p3',
            userId: 'u3',
            name: 'Sunita',
            initials: 'SU',
            kinshipTerm: 'Maa',
            kinshipRelationLine: 'your mother',
            isElder: true,
            recentSenderRank: 1,
          ),
        ],
      ];

      final queryNotifier = ValueNotifier<String>('');
      final candidatesNotifier =
          ValueNotifier<List<MentionCandidate>>(
        candidates.first,
      );

      // Stub localized strings — the overlay never calls .of(context)
      // so this is just the constructor arg.
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

      // Empty query → all 3 candidates visible (capped at 8, so all 3).
      expect(find.text('Manish'), findsOneWidget);
      expect(find.text('Malti'), findsOneWidget);
      expect(find.text('Sunita'), findsOneWidget);

      // Type "m" — narrows to 2 (Manish + Malti). Sunita is filtered out.
      queryNotifier.value = 'm';
      await tester.pump();
      expect(find.text('Manish'), findsOneWidget);
      expect(find.text('Malti'), findsOneWidget);
      expect(find.text('Sunita'), findsNothing);

      // Type "ma" — narrows further. Both Manish + Malti still match
      // (name starts with "Ma"). No "no match" state yet.
      queryNotifier.value = 'ma';
      await tester.pump();
      expect(find.text('Manish'), findsOneWidget);
      expect(find.text('Malti'), findsOneWidget);

      // Type "manis" — only Manish matches now.
      queryNotifier.value = 'manis';
      await tester.pump();
      expect(find.text('Manish'), findsOneWidget);
      expect(find.text('Malti'), findsNothing);

      // Type "xyz" — no matches. The "No one matches" row should
      // render visibly (was silent SizedBox.shrink in the old
      // StatelessWidget version).
      queryNotifier.value = 'xyz';
      await tester.pump();
      expect(find.text('Manish'), findsNothing);
      expect(find.text('Malti'), findsNothing);
      expect(find.text('No one matches'), findsOneWidget);
    });
  });
}
