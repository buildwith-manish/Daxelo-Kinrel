// test/features/chat/game_invite_lifecycle_state_machine_test.dart
//
// 5-state game-room lifecycle state machine — unit tests.
//
// Verifies the classification logic + the ChatMessage lifecycle getters
// that drive the new 5-state chip + card treatment on game-invite cards:
//
//   • waiting → amber chip + Join button
//   • open-to-join → green chip + Join button
//   • full → grey chip + Full label (transitional)
//   • inProgress → PULSING green LIVE NOW chip + Watch/Rejoin button
//   • completed → muted chip + winner display (privacy-gated)
//   • expired → greyed chip + static label (no interaction)
//
// Also verifies legacy status aliases ('accepted' = pre-state-machine
// 'in_progress', 'cancelled' = alias for 'expired') continue to render
// correctly so existing chat cards don't break.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/chat/presentation/widgets/game_invite_status_chip.dart';
import 'package:kinrel/features/chat/providers/chat_provider.dart';

ChatMessage _invite({
  String? status,
  int? currentPlayers,
  int? maxPlayers,
  String gameType = 'sos',
  String? winnerName,
  DateTime? completedAt,
}) {
  return ChatMessage(
    id: 'cm_test_${status ?? 'null'}_${currentPlayers ?? 0}_${maxPlayers ?? 0}',
    senderId: 'user_a',
    senderName: 'Host User',
    content: 'Host User started a SOS game',
    messageType: MessageType.gameInvite,
    timestamp: DateTime.parse('2026-10-04T12:00:00Z'),
    gameType: gameType,
    gameId: '11111111-2222-3333-4444-555555555555',
    roomCode: 'AB12CD',
    gameMaxPlayers: maxPlayers ?? 4,
    gameCurrentPlayers: currentPlayers ?? 1,
    gameInviteStatus: status,
    gameWinnerName: winnerName,
    gameCompletedAt: completedAt,
  );
}

void main() {
  group('5-state lifecycle — classifyGameInviteStatus', () {
    // ── PRE-GAME: 3 sub-states by capacity ──────────────────────────

    test('pending + currentPlayers<=1 → waitingForPlayers (amber)', () {
      final c = classifyGameInviteStatus(_invite(
        status: 'pending',
        currentPlayers: 1,
        maxPlayers: 4,
      ));
      expect(c.kind, GameInviteStatusKind.waitingForPlayers);
      expect(c.label, 'Waiting for players');
    });

    test('null status treated as pending → waitingForPlayers', () {
      // Defensively: a fresh row that hasn't been written by sync yet
      // has gameInviteStatus = null. The classifier should treat null
      // as 'pending' and apply the same waiting-for-players logic.
      final c = classifyGameInviteStatus(_invite(
        status: null,
        currentPlayers: 1,
        maxPlayers: 4,
      ));
      expect(c.kind, GameInviteStatusKind.waitingForPlayers);
    });

    test('pending + 1<current<max → openToJoin with spots-left label (green)', () {
      // Per the user-facing spec, the chip surfaces the explicit
      // remaining-slot count ("X spots left") instead of a generic
      // "Open to join". The card also renders a separate "X/Y players"
      // line above the chip, so the user gets both the absolute count
      // and the remaining-slot count at a glance.
      final c2of4 = classifyGameInviteStatus(_invite(
        status: 'pending',
        currentPlayers: 2,
        maxPlayers: 4,
      ));
      expect(c2of4.kind, GameInviteStatusKind.openToJoin);
      expect(c2of4.label, '2 spots left');

      // Singular form when only 1 slot remains.
      final c3of4 = classifyGameInviteStatus(_invite(
        status: 'pending',
        currentPlayers: 3,
        maxPlayers: 4,
      ));
      expect(c3of4.kind, GameInviteStatusKind.openToJoin);
      expect(c3of4.label, '1 spot left');
    });

    test('pending + currentPlayers>=max → full (grey, transitional)', () {
      final c = classifyGameInviteStatus(_invite(
        status: 'pending',
        currentPlayers: 4,
        maxPlayers: 4,
      ));
      expect(c.kind, GameInviteStatusKind.full);
      expect(c.label, 'Room full');
    });

    // ── IN-PROGRESS: legacy aliases ─────────────────────────────────

    test('in_progress → inProgress (pulsing LIVE NOW)', () {
      final c = classifyGameInviteStatus(_invite(
        status: 'in_progress',
        currentPlayers: 4,
        maxPlayers: 4,
      ));
      expect(c.kind, GameInviteStatusKind.inProgress);
      expect(c.label, 'LIVE NOW');
    });

    test('legacy "accepted" alias → inProgress (back-compat)', () {
      // Pre-state-machine rows had gameInviteStatus='accepted' on host-start.
      // These continue to render as inProgress (LIVE NOW) — no migration
      // needed for existing chat cards.
      final c = classifyGameInviteStatus(_invite(
        status: 'accepted',
        currentPlayers: 4,
        maxPlayers: 4,
      ));
      expect(c.kind, GameInviteStatusKind.inProgress);
      expect(c.label, 'LIVE NOW');
    });

    test('legacy "active" alias (SOS/RedLight vocabulary) → inProgress', () {
      // SOS uses 'active' for started games; the classifier maps it to
      // inProgress so a single chip kind covers all game vocabularies.
      final c = classifyGameInviteStatus(_invite(
        status: 'active',
        currentPlayers: 4,
        maxPlayers: 4,
      ));
      expect(c.kind, GameInviteStatusKind.inProgress);
    });

    // ── COMPLETED ──────────────────────────────────────────────────

    test('completed → completed (muted)', () {
      final c = classifyGameInviteStatus(_invite(
        status: 'completed',
        currentPlayers: 4,
        maxPlayers: 4,
        winnerName: 'Manish',
        completedAt: DateTime.parse('2026-10-04T12:30:00Z'),
      ));
      expect(c.kind, GameInviteStatusKind.completed);
      expect(c.label, 'Completed');
    });

    // ── EXPIRED / CANCELLED ────────────────────────────────────────

    test('expired → expired (greyed, inactive)', () {
      final c = classifyGameInviteStatus(_invite(
        status: 'expired',
        currentPlayers: 1,
        maxPlayers: 4,
      ));
      expect(c.kind, GameInviteStatusKind.expired);
      expect(c.label, 'Expired');
    });

    test('cancelled → expired kind, label "Cancelled"', () {
      // Per the spec, 'cancelled' is an alias for 'expired' — both render
      // the same greyed-out, non-interactive treatment. The label differs
      // so the user knows which terminal state they're looking at.
      final c = classifyGameInviteStatus(_invite(
        status: 'cancelled',
        currentPlayers: 4,
        maxPlayers: 4,
      ));
      expect(c.kind, GameInviteStatusKind.expired);
      expect(c.label, 'Cancelled');
    });

    // ── UNIFORM ACROSS GAME TYPES ──────────────────────────────────

    test('applies uniformly across game types (SOS, Bingo, etc.)', () {
      // The chip is a SINGLE component used by ALL game-invite card
      // variants — so the same input state must produce the same chip
      // kind regardless of gameType.
      for (final gameType in ['sos', 'bingo', 'prediction-battle', 'unknown']) {
        final c = classifyGameInviteStatus(_invite(
          status: 'in_progress',
          currentPlayers: 2,
          maxPlayers: 4,
          gameType: gameType,
        ));
        expect(c.kind, GameInviteStatusKind.inProgress,
            reason: '$gameType should classify identically');
      }
    });
  });

  group('5-state lifecycle — ChatMessage lifecycle getters', () {
    // These getters are used by the message_bubble._buildGameInviteCard
    // to decide which action button treatment to render.

    test('isGameInProgress true for in_progress + legacy aliases', () {
      expect(_invite(status: 'in_progress').isGameInProgress, isTrue);
      expect(_invite(status: 'accepted').isGameInProgress, isTrue);
      expect(_invite(status: 'active').isGameInProgress, isTrue);
    });

    test('isGameInProgress false for pending/completed/expired', () {
      expect(_invite(status: 'pending').isGameInProgress, isFalse);
      expect(_invite(status: 'completed').isGameInProgress, isFalse);
      expect(_invite(status: 'expired').isGameInProgress, isFalse);
      expect(_invite(status: 'cancelled').isGameInProgress, isFalse);
    });

    test('isGameCompleted true only for completed', () {
      expect(_invite(status: 'completed').isGameCompleted, isTrue);
      expect(_invite(status: 'in_progress').isGameCompleted, isFalse);
      expect(_invite(status: 'expired').isGameCompleted, isFalse);
      expect(_invite(status: 'cancelled').isGameCompleted, isFalse);
      expect(_invite(status: 'pending').isGameCompleted, isFalse);
    });

    test('isGameExpired true for expired AND cancelled (alias)', () {
      expect(_invite(status: 'expired').isGameExpired, isTrue);
      expect(_invite(status: 'cancelled').isGameExpired, isTrue);
      expect(_invite(status: 'pending').isGameExpired, isFalse);
      expect(_invite(status: 'in_progress').isGameExpired, isFalse);
      expect(_invite(status: 'completed').isGameExpired, isFalse);
    });

    test('isGameJoinable true only for pending + not full', () {
      expect(_invite(status: 'pending', currentPlayers: 1, maxPlayers: 4).isGameJoinable, isTrue);
      expect(_invite(status: 'pending', currentPlayers: 2, maxPlayers: 4).isGameJoinable, isTrue);
      // Full + pending → not joinable (transitional state).
      expect(_invite(status: 'pending', currentPlayers: 4, maxPlayers: 4).isGameJoinable, isFalse);
      // Non-pending states → not joinable.
      expect(_invite(status: 'in_progress').isGameJoinable, isFalse);
      expect(_invite(status: 'completed').isGameJoinable, isFalse);
      expect(_invite(status: 'expired').isGameJoinable, isFalse);
    });

    test('isGameInviteClosed covers all terminal states', () {
      // Anything not 'pending' (or null) is closed — this is the
      // existing getter that the chat-smoothness work used.
      expect(_invite(status: 'pending').isGameInviteClosed, isFalse);
      expect(_invite(status: null).isGameInviteClosed, isFalse);
      expect(_invite(status: 'in_progress').isGameInviteClosed, isTrue);
      expect(_invite(status: 'completed').isGameInviteClosed, isTrue);
      expect(_invite(status: 'expired').isGameInviteClosed, isTrue);
      expect(_invite(status: 'cancelled').isGameInviteClosed, isTrue);
    });

    test('non-gameInvite messages never report any lifecycle state', () {
      // Defensive: a plain text message should not accidentally report
      // isGameInProgress / isGameCompleted / etc. — even if its
      // gameInviteStatus field happens to be set (shouldn't happen, but
      // the getter guards against it).
      final textMsg = ChatMessage(
        id: 'cm_text_1',
        senderId: 'u',
        senderName: 'U',
        content: 'hello',
        messageType: MessageType.text,
        timestamp: DateTime.now(),
        gameInviteStatus: 'in_progress', // wrong field for a text msg
      );
      expect(textMsg.isGameInProgress, isFalse);
      expect(textMsg.isGameCompleted, isFalse);
      expect(textMsg.isGameExpired, isFalse);
      expect(textMsg.isGameJoinable, isFalse);
      expect(textMsg.isGameFull, isFalse);
    });
  });

  group('5-state lifecycle — natural progression', () {
    // The spec's testing requirement: "a room correctly transitions from
    // Waiting → Full → In Progress → Completed through its natural
    // lifecycle via existing game-state triggers."
    //
    // We simulate the lifecycle by creating ChatMessage snapshots at
    // each transition point (mirroring what the realtime UPDATE
    // subscription delivers to the chat UI) and verifying the classifier
    // produces the expected kind at each step.

    test('Waiting → Full → In Progress → Completed lifecycle', () {
      // Step 1: room created, just the host.
      final waiting = _invite(
        status: 'pending',
        currentPlayers: 1,
        maxPlayers: 4,
      );
      expect(classifyGameInviteStatus(waiting).kind,
          GameInviteStatusKind.waitingForPlayers);
      expect(waiting.isGameJoinable, isTrue);

      // Step 2: a few players joined (still pre-game).
      final openToJoin = _invite(
        status: 'pending',
        currentPlayers: 2,
        maxPlayers: 4,
      );
      expect(classifyGameInviteStatus(openToJoin).kind,
          GameInviteStatusKind.openToJoin);
      expect(openToJoin.isGameJoinable, isTrue);

      // Step 3: room reaches capacity (transitional full state).
      final full = _invite(
        status: 'pending',
        currentPlayers: 4,
        maxPlayers: 4,
      );
      expect(classifyGameInviteStatus(full).kind,
          GameInviteStatusKind.full);
      expect(full.isGameFull, isTrue);
      expect(full.isGameJoinable, isFalse);  // full = not joinable

      // Step 4: host starts the game (trigger fires; chat card updates
      // via realtime).
      final inProgress = _invite(
        status: 'in_progress',
        currentPlayers: 4,
        maxPlayers: 4,
      );
      expect(classifyGameInviteStatus(inProgress).kind,
          GameInviteStatusKind.inProgress);
      expect(inProgress.isGameInProgress, isTrue);
      expect(inProgress.isGameJoinable, isFalse);

      // Step 5: game finishes normally with a winner.
      final completed = _invite(
        status: 'completed',
        currentPlayers: 4,
        maxPlayers: 4,
        winnerName: 'Manish',
        completedAt: DateTime.parse('2026-10-04T12:30:00Z'),
      );
      expect(classifyGameInviteStatus(completed).kind,
          GameInviteStatusKind.completed);
      expect(completed.isGameCompleted, isTrue);
      expect(completed.isGameExpired, isFalse);
      expect(completed.gameWinnerName, 'Manish');
    });

    test('Waiting → Expired (room never filled in time)', () {
      // Alternative path: a room created but never reached capacity.
      // The pg_cron sweep transitions it to 'expired' after the 30-min
      // waiting window elapses.
      final waiting = _invite(
        status: 'pending',
        currentPlayers: 1,
        maxPlayers: 4,
      );
      expect(classifyGameInviteStatus(waiting).kind,
          GameInviteStatusKind.waitingForPlayers);

      // Sweep fires → status flips to 'expired'.
      final expired = _invite(
        status: 'expired',
        currentPlayers: 1,
        maxPlayers: 4,
      );
      expect(classifyGameInviteStatus(expired).kind,
          GameInviteStatusKind.expired);
      expect(expired.isGameExpired, isTrue);
      expect(expired.isGameJoinable, isFalse);
      expect(expired.isGameCompleted, isFalse);  // expired ≠ completed
    });

    test('Full → Expired (room filled but never started in time)', () {
      // Another alternative: room reached capacity, but the host never
      // pressed Start. The shorter 10-min full-state expiry window
      // kicks in and the sweep transitions to 'expired'.
      final full = _invite(
        status: 'pending',
        currentPlayers: 4,
        maxPlayers: 4,
      );
      expect(classifyGameInviteStatus(full).kind,
          GameInviteStatusKind.full);

      // Sweep fires → status flips to 'expired' (NOT 'completed' — the
      // game never actually started, so it's an expiry not a completion).
      final expired = _invite(
        status: 'expired',
        currentPlayers: 4,
        maxPlayers: 4,
      );
      expect(classifyGameInviteStatus(expired).kind,
          GameInviteStatusKind.expired);
      expect(expired.isGameExpired, isTrue);
      expect(expired.isGameCompleted, isFalse,
          reason: 'A room that filled but never started is expired, '
              'NOT completed — completion requires the game to have '
              'actually run to a natural finish with a winner.');
    });

    test('In-progress rooms are NEVER swept (per spec)', () {
      // The spec is explicit: "Once in_progress, a room should NOT
      // expire on this same timer — only pre-game states (Waiting, Full)
      // are subject to expiry."
      //
      // This is enforced server-side by the fn_sweep_expired_game_rooms
      // WHERE clause (status IN ('waiting', 'lobby', 'setup', ...)),
      // but we verify the invariant at the model level too: an in-progress
      // room's gameInviteStatus can never transition directly to
      // 'expired' via the sweep — only via host cancel.
      final inProgress = _invite(
        status: 'in_progress',
        currentPlayers: 4,
        maxPlayers: 4,
      );
      expect(inProgress.isGameInProgress, isTrue);
      expect(inProgress.isGameExpired, isFalse);

      // If the host cancels mid-game (rare but possible), the status
      // flips to 'cancelled' — classified as expired kind per our model
      // (terminal, greyed-out). This is the only path from in_progress
      // to a terminal state other than natural completion.
      final cancelled = _invite(
        status: 'cancelled',
        currentPlayers: 4,
        maxPlayers: 4,
      );
      expect(cancelled.isGameExpired, isTrue);
      expect(cancelled.isGameInProgress, isFalse);
    });
  });

  group('5-state lifecycle — privacy gating (winner display)', () {
    // The privacy gate is enforced server-side by fn_sync_game_invite_status:
    // gameWinnerName is only written to ChatMessage if auth.uid() is a
    // participant of the match (verified via game_participants).
    //
    // At the model level, this means:
    //   • Participants see gameWinnerName = 'Manish' → card renders the
    //     "Winner: Manish" pill below the status chip.
    //   • Non-participants see gameWinnerName = null → card renders just
    //     the "Completed" chip without the winner pill.
    //
    // Both viewers see the SAME card frame + chip — only the winner pill
    // differs. This matches the existing match-result privacy model
    // (20260917140000_family_arena_privacy_and_participation.sql + the
    // column-level GRANTs in 20260917140001).

    test('participant sees winner name on completed card', () {
      final participantView = _invite(
        status: 'completed',
        currentPlayers: 4,
        maxPlayers: 4,
        winnerName: 'Manish',
        completedAt: DateTime.parse('2026-10-04T12:30:00Z'),
      );
      expect(participantView.gameWinnerName, 'Manish');
      expect(participantView.isGameCompleted, isTrue);
    });

    test('non-participant sees null winner name on completed card', () {
      // The server only wrote gameInviteStatus + gameCompletedAt —
      // gameWinnerName was withheld by the privacy gate.
      final nonParticipantView = _invite(
        status: 'completed',
        currentPlayers: 4,
        maxPlayers: 4,
        winnerName: null,  // privacy gate withheld this
        completedAt: DateTime.parse('2026-10-04T12:30:00Z'),
      );
      expect(nonParticipantView.gameWinnerName, isNull);
      // Card still renders the completed chip + "Game completed" label.
      expect(nonParticipantView.isGameCompleted, isTrue);
      expect(classifyGameInviteStatus(nonParticipantView).kind,
          GameInviteStatusKind.completed);
    });

    test('expired rooms never carry a winner name', () {
      // An expired room (never started) has no winner — gameWinnerName
      // should always be null regardless of viewer.
      final expired = _invite(
        status: 'expired',
        currentPlayers: 1,
        maxPlayers: 4,
        winnerName: null,
      );
      expect(expired.gameWinnerName, isNull);
      expect(expired.isGameExpired, isTrue);
    });
  });

  group('5-state lifecycle — copyWith preserves winner/completedAt', () {
    // Regression test for the realtime UPDATE path: chat_provider's
    // _handleMessageUpdate re-parses the row via ChatMessage.fromJson
    // and then copyWith(reactions: ...). If copyWith dropped the new
    // gameWinnerName / gameCompletedAt fields, the card would lose
    // its completed-state display on every realtime UPDATE.

    test('unrelated copyWith keeps all lifecycle fields', () {
      final original = _invite(
        status: 'completed',
        winnerName: 'Manish',
        completedAt: DateTime.parse('2026-10-04T12:30:00Z'),
      );
      final copied = original.copyWith(isRead: true);
      expect(copied.gameInviteStatus, 'completed');
      expect(copied.gameWinnerName, 'Manish');
      expect(copied.gameCompletedAt, DateTime.parse('2026-10-04T12:30:00Z'));
    });

    test('copyWith can update lifecycle fields independently', () {
      final waiting = _invite(status: 'pending', currentPlayers: 1, maxPlayers: 4);
      final inProgress = waiting.copyWith(
        gameInviteStatus: 'in_progress',
        gameCurrentPlayers: 4,
      );
      expect(inProgress.gameInviteStatus, 'in_progress');
      expect(inProgress.gameCurrentPlayers, 4);
      expect(inProgress.isGameInProgress, isTrue);

      final completed = inProgress.copyWith(
        gameInviteStatus: 'completed',
        gameWinnerName: 'Manish',
        gameCompletedAt: DateTime.parse('2026-10-04T12:30:00Z'),
      );
      expect(completed.gameInviteStatus, 'completed');
      expect(completed.gameWinnerName, 'Manish');
      expect(completed.gameCompletedAt, DateTime.parse('2026-10-04T12:30:00Z'));
      expect(completed.isGameCompleted, isTrue);
    });
  });
}
