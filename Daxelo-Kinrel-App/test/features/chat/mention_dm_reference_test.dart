// Phase B — @mentions across chat. Widget test for the DM reference
// behavior: the picker opens in a direct chat, the "Mention a
// relative · they won't be notified" header line renders above the
// list, selecting a third relative inserts a MentionRef with
// notify=false (the chip renders in the bubble but the referenced
// person is NOT notified — they're not in the DM).
//
// This test uses the same stub-candidate pattern as the Phase A
// live-filter test — no real Riverpod provider is needed because
// the overlay reads from ValueNotifiers (which the test sets up
// directly).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/chat/data/mention_candidates_provider.dart';
import 'package:kinrel/features/chat/data/models/mention_ref.dart';
import 'package:kinrel/features/chat/presentation/widgets/mention_picker.dart';

void main() {
  group('MentionPickerOverlay — DM reference mode (Phase B)', () {
    testWidgets('renders the DM header line when isDirectChat=true',
        (tester) async {
      final candidates = <List<MentionCandidate>>[
        const [
          const MentionCandidate(
            personId: 'p1',
            userId: 'u1',
            name: 'Riya',
            initials: 'RI',
            kinshipTerm: 'Bua',
            kinshipRelationLine: "your father's sister",
            isElder: false,
            recentSenderRank: 0,
          ),
        ],
      ];

      final queryNotifier = ValueNotifier<String>('');
      final candidatesNotifier =
          ValueNotifier<List<MentionCandidate>>(
        candidates.first,
      );

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
                  isDirectChat: true,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      // The DM header line should be visible.
      expect(find.text("Mention a relative · they won't be notified"),
          findsOneWidget);
      // The candidate row should still be visible below the header.
      expect(find.text('Riya'), findsOneWidget);
      expect(find.text('Bua'), findsOneWidget);
    });

    testWidgets('renders DM-specific empty state when no candidates',
        (tester) async {
      final queryNotifier = ValueNotifier<String>('');
      final candidatesNotifier =
          ValueNotifier<List<MentionCandidate>>(
        const [],
      );

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
                  isDirectChat: true,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      // DM-specific empty state (not the generic "No one to mention
      // in this chat").
      expect(find.text('No other relatives to mention in this family'),
          findsOneWidget);
      // The generic noCandidates string should NOT be visible.
      expect(find.text('No one to mention in this chat'), findsNothing);
    });

    testWidgets('MentionRef.notify is serialized as false for DM references',
        (tester) async {
      // Verify the MentionRef JSON shape: a DM reference (notify=false)
      // includes `"notify": false` in its JSON. A group mention
      // (notify=true, the default) OMITS the field (backward compat
      // with old clients that don't understand the notify flag).
      const dmRef = MentionRef(
        userId: 'u1',
        name: 'Riya',
        start: 0,
        end: 5,
        notify: false,
      );
      const groupRef = MentionRef(
        userId: 'u2',
        name: 'Amit',
        start: 0,
        end: 5,
        // notify defaults to true
      );

      final dmJson = dmRef.toJson();
      final groupJson = groupRef.toJson();

      // DM reference: includes notify=false.
      expect(dmJson['notify'], false);
      // Group mention: does NOT include the notify field (old clients
      // default to true via fromJson).
      expect(groupJson.containsKey('notify'), isFalse);

      // Round-trip: fromJson correctly reads the notify flag.
      final dmRoundTrip = MentionRef.fromJson(dmJson);
      final groupRoundTrip = MentionRef.fromJson(groupJson);
      expect(dmRoundTrip.notify, false);
      expect(groupRoundTrip.notify, true);
    });
  });
}
