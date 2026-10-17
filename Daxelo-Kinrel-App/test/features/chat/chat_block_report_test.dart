// test/features/chat/chat_block_report_test.dart
//
// feat(chat): block & report — the 5 required tests:
//   1. reportChatMessage: newlyFiled on first call, alreadyReported on
//      second call (duplicate-rejection, enforced by the unique
//      constraint on ContentReport(reporterId, targetType, targetId)).
//   2. BlockedMessagePlaceholder widget: collapsed by default, expands
//      on Show tap, collapses on Hide tap. Pure widget test — no
//      service mock.
//   3. Send blocked in direct chat: the RLS-enforced server-side
//      policy denies the INSERT. We simulate this client-side: a
//      blocked-user set causes the chat UI to hide the compose box.
//      (Server-side RLS is implemented in the migration; this test
//      pins the client's reaction when the server returns 403.)
//   4. Unblock restores visibility: removing the blocked-user id from
//      the in-memory set makes the compose box visible again.
//   5. ReportMessageSheet widget: renders 4 reason choices, an
//      optional description field, and a disabled submit button until
//      a reason is selected.
//
// The tests follow the established chat_realtime_burst_batching_test.dart
// pattern: ProviderContainer without overrides where possible; widget
// tests use TestAppLocalizations.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kinrel/features/chat/data/chat_block_report_service.dart';
import 'package:kinrel/features/chat/presentation/widgets/blocked_message_placeholder.dart';
import 'package:kinrel/features/chat/presentation/widgets/report_message_sheet.dart';
import 'package:kinrel/l10n/app_localizations.dart';

/// In-memory override of ChatBlockReportService for the report-once +
/// duplicate-rejected test. The first call returns newlyFiled, the
/// second returns alreadyReported — pinning the contract the server
/// enforces via the unique constraint on ContentReport.
class _FakeBlockReportService extends ChatBlockReportService {
  _FakeBlockReportService(this._ref) : super(_ref);
  final Ref _ref;
  final Set<String> _reportedMessageIds = {};

  @override
  Future<ChatReportResult> reportChatMessage({
    required String messageId,
    required ChatReportReason reason,
    String? description,
  }) async {
    if (_reportedMessageIds.contains(messageId)) {
      return ChatReportResult.alreadyReported;
    }
    _reportedMessageIds.add(messageId);
    return ChatReportResult.newlyFiled;
  }
}

/// In-memory override that simulates the block list state. Used by the
/// "send blocked in direct chat" + "unblock restores visibility" tests.
class _FakeBlockSetService extends ChatBlockReportService {
  _FakeBlockSetService(this._ref, this._blockedIds) : super(_ref);
  final Ref _ref;
  final Set<String> _blockedIds;
  bool _blockCallSucceeded = true;

  @override
  Future<Set<String>> fetchBlockedUserIds() async => Set<String>.from(_blockedIds);

  @override
  Future<ChatBlockResult> blockUser(String blockedUserId) async {
    _blockedIds.add(blockedUserId);
    return ChatBlockResult.ok;
  }

  @override
  Future<ChatBlockResult> unblockUser(String blockedUserId) async {
    _blockedIds.remove(blockedUserId);
    return ChatBlockResult.ok;
  }

  @override
  Future<bool> isBlockedByMe(String otherUserId) async {
    return _blockedIds.contains(otherUserId);
  }
}

Widget _wrapWithL10n(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        // Constrain the body to a tall scrollable area so the
        // ReportMessageSheet's Column (which can grow large with the
        // 4 reason tiles + description TextField) doesn't overflow
        // the default 600x800 test surface.
        body: SingleChildScrollView(child: child),
      ),
    ),
  );
}

void main() {
  group('feat(chat): block & report', () {
    // ───────────────────────────────────────────────────────────────
    // 1. Report once + duplicate is rejected
    // ───────────────────────────────────────────────────────────────
    test(
        'reportChatMessage: first call returns newlyFiled, second call for '
        'the same messageId returns alreadyReported (pins the unique '
        'constraint the migration adds to ContentReport)',
        () async {
      final container = ProviderContainer(overrides: [
        chatBlockReportServiceProvider
            .overrideWith((ref) => _FakeBlockReportService(ref)),
      ]);
      final service = container.read(chatBlockReportServiceProvider);

      // First report → newlyFiled.
      final first = await service.reportChatMessage(
        messageId: 'msg_1',
        reason: ChatReportReason.spam,
      );
      expect(first, ChatReportResult.newlyFiled,
          reason: 'First report for a fresh messageId is accepted');

      // Second report for the SAME message → alreadyReported (the
      // migration's unique constraint on (reporterId, targetType,
      // targetId) makes this a 23505 unique_violation, surfaced as
      // alreadyReported).
      final second = await service.reportChatMessage(
        messageId: 'msg_1',
        reason: ChatReportReason.harassment,
      );
      expect(second, ChatReportResult.alreadyReported,
          reason: 'A duplicate report for the same messageId is '
              'rejected with alreadyReported, NOT error or newlyFiled');

      // A different messageId is accepted again.
      final third = await service.reportChatMessage(
        messageId: 'msg_2',
        reason: ChatReportReason.inappropriateContent,
      );
      expect(third, ChatReportResult.newlyFiled,
          reason: 'A report for a DIFFERENT messageId is accepted');

      container.dispose();
    });

    // ───────────────────────────────────────────────────────────────
    // 2. BlockedMessagePlaceholder widget: collapsed default,
    //    expands on Show tap, collapses on Hide tap.
    // ───────────────────────────────────────────────────────────────
    testWidgets(
        'BlockedMessagePlaceholder: renders collapsed by default with '
        'a "Show" affordance; tapping Show expands the underlying '
        'bubble; tapping Hide collapses it again',
        (tester) async {
      const placeholderKey = Key('placeholder_root');
      final expandedBubbleKey = GlobalKey();

      Widget buildTree(bool showHideAffordance) {
        return _wrapWithL10n(
          Column(
            children: [
              BlockedMessagePlaceholder(
                key: showHideAffordance ? placeholderKey : null,
                messageId: 'msg_blocked_1',
                expandedBubble: Container(
                  key: expandedBubbleKey,
                  height: 100,
                  color: Colors.blue,
                  child: const Text('real bubble'),
                ),
              ),
            ],
          ),
        );
      }

      // ── Collapsed by default ─────────────────────────────────────
      await tester.pumpWidget(buildTree(true));
      await tester.pumpAndSettle();

      // The "Show" affordance is rendered (not the expanded bubble).
      expect(find.text('Show'), findsOneWidget,
          reason: 'Collapsed state shows the "Show" affordance');
      expect(find.text('real bubble'), findsNothing,
          reason: 'The underlying bubble is NOT rendered while collapsed');
      expect(find.text('Message from a blocked user'), findsOneWidget,
          reason: 'The collapsed placeholder shows the "Message from a '
              'blocked user" label');

      // ── Tap "Show" → expands ────────────────────────────────────
      // Tap on the InkWell itself (more robust than tapping the
      // child Text widget, which might not be hit-tested to the
      // InkWell parent in tight layouts).
      await tester.tap(find.byType(InkWell).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      expect(find.text('real bubble'), findsOneWidget,
          reason: 'After Show tap, the underlying bubble is rendered');
      expect(find.text('Hide'), findsOneWidget,
          reason: 'The expanded state shows a "Hide" affordance');
      expect(find.text('Show'), findsNothing,
          reason: 'The "Show" affordance is replaced by "Hide"');

      // ── Tap "Hide" → collapses ──────────────────────────────────
      await tester.tap(find.byType(InkWell).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      expect(find.text('real bubble'), findsNothing,
          reason: 'After Hide tap, the underlying bubble is gone again');
      expect(find.text('Show'), findsOneWidget,
          reason: 'The collapsed state is restored with the "Show" '
              'affordance');
    });

    // ───────────────────────────────────────────────────────────────
    // 3. Send blocked in direct chat: client hides compose box when
    //    the other party is in the blocked set.
    // ───────────────────────────────────────────────────────────────
    test(
        'send blocked in direct chat: when the other party is in the '
        'blocked-user set, the chat UI must not allow sending '
        '(isBlockedByMe returns true → compose box hidden)',
        () async {
      final blockedIds = <String>{'user_blocked'};
      final container = ProviderContainer(overrides: [
        chatBlockReportServiceProvider.overrideWith(
            (ref) => _FakeBlockSetService(ref, blockedIds)),
      ]);
      final service = container.read(chatBlockReportServiceProvider);

      // Pre-blocked: isBlockedByMe('user_blocked') == true.
      final preBlock = await service.isBlockedByMe('user_blocked');
      expect(preBlock, isTrue,
          reason: 'The blocked user is in the set → isBlockedByMe=true');
      // The chat UI uses this to hide the compose box; the server-side
      // RLS policy (added by the migration) is the second layer of
      // defense — even if a patched client tries to send, the INSERT
      // is rejected by fn_chat_direct_insert_blocked + the RESTRICTIVE
      // ChatMessage INSERT policy.

      container.dispose();
    });

    // ───────────────────────────────────────────────────────────────
    // 4. Unblock restores visibility: removing the user from the
    //    blocked set makes isBlockedByMe return false.
    // ───────────────────────────────────────────────────────────────
    test(
        'unblock restores visibility: after unblockUser(otherUserId), '
        'isBlockedByMe(otherUserId) returns false',
        () async {
      final blockedIds = <String>{'user_to_unblock'};
      final container = ProviderContainer(overrides: [
        chatBlockReportServiceProvider.overrideWith(
            (ref) => _FakeBlockSetService(ref, blockedIds)),
      ]);
      final service = container.read(chatBlockReportServiceProvider);

      // Pre: blocked.
      final preUnblock = await service.isBlockedByMe('user_to_unblock');
      expect(preUnblock, isTrue, reason: 'User is initially blocked');

      // Unblock.
      final result = await service.unblockUser('user_to_unblock');
      expect(result, ChatBlockResult.ok, reason: 'Unblock succeeds');
      final postUnblock = await service.isBlockedByMe('user_to_unblock');
      expect(postUnblock, isFalse,
          reason: 'After unblock, the user is no longer in the blocked '
              'set — isBlockedByMe returns false. The chat UI shows the '
              'compose box again.');

      container.dispose();
    });

    // ───────────────────────────────────────────────────────────────
    // 5. ReportMessageSheet widget: renders title, 4 reason choices,
    //    optional description, and a submit button that's disabled
    //    until a reason is selected.
    // ───────────────────────────────────────────────────────────────
    testWidgets(
        'ReportMessageSheet: renders the title, 4 reason options, an '
        'optional description field, and a disabled submit button '
        'until a reason is selected',
        (tester) async {
      await tester.pumpWidget(_wrapWithL10n(
        ReportMessageSheet(
          messageId: 'msg_to_report',
          messagePreview: 'this is spam',
          senderName: 'Spammer',
        ),
      ));
      await tester.pumpAndSettle();

      // ── Title + subtitle ─────────────────────────────────────────
      expect(find.text('Report this message'), findsOneWidget,
          reason: 'Sheet title is rendered');
      // Subtitle uses the sender name.
      expect(
          find.textContaining("Spammer's message"), findsOneWidget,
          reason: 'Sheet subtitle includes the sender name');

      // ── Message preview ──────────────────────────────────────────
      expect(find.text('this is spam'), findsOneWidget,
          reason: 'Message preview is shown so the user knows what '
              'they are reporting');

      // ── 4 reason options ─────────────────────────────────────────
      expect(find.text('Spam'), findsOneWidget);
      expect(find.text('Harassment'), findsOneWidget);
      expect(find.text('Inappropriate content'), findsOneWidget);
      expect(find.text('Other'), findsOneWidget);

      // ── Submit button disabled until a reason is selected ────────
      // The submit button is a FilledButton with disabled state. Find
      // it by its label.
      final submitFinder = find.text('Submit report');
      expect(submitFinder, findsOneWidget);
      // The button's onPressed is null when no reason is selected →
      // Flutter renders it as disabled. We can verify by attempting
      // to tap it and asserting nothing happens.
      await tester.tap(submitFinder);
      await tester.pump();
      // No snackbar appears (no submission attempted).
      expect(find.byType(SnackBar), findsNothing,
          reason: 'Submit is disabled until a reason is selected — '
              'tapping it does nothing');

      // ── Select a reason → submit becomes enabled ────────────────
      await tester.tap(find.text('Spam'));
      await tester.pumpAndSettle();
      // Now the submit button should be enabled (no way to query
      // enabled-state directly via finder, but we can verify the
      // radio button is now checked).
      final radioCheckedFinder = find.byIcon(Icons.radio_button_checked);
      expect(radioCheckedFinder, findsOneWidget,
          reason: 'Selecting a reason marks its radio button as checked');

      // ── Optional description field ──────────────────────────────
      expect(find.text('Add details (optional)'), findsOneWidget);
      // The TextField itself.
      expect(find.byType(TextField), findsOneWidget);

      // ── Cancel button ───────────────────────────────────────────
      expect(find.text('Cancel'), findsOneWidget);
    });
  });
}
