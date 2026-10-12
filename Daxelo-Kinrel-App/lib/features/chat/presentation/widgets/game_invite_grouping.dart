// lib/features/chat/presentation/widgets/game_invite_grouping.dart
//
// DAXELO KINREL — v143/Step 8 — Pure grouping function for game
// invite display items.
//
// Takes the ordered chat items (ChatMessage list) and returns a list
// of display items: regular message, active invite, one-liner,
// collapsed run (holding the list of invites), or result card.
//
// Collapse rule: a run of 3+ consecutive expired/completed (no winner)
// invites, with nothing between them, collapses into one summary row.
// Fewer than 3 stay as separate one-line rows. The run is broken by
// any regular text message, any other message type, or any live
// invite (waiting, full, or in-progress). Result cards (completed
// with winner) NEVER join a collapsed run.
//
// Header wording: if every invite in the run is expired/cancelled,
// say "N game invites · expired". If the run mixes expired and
// completed, say "N game invites · finished".

import '../../providers/chat_provider.dart';
import 'game_invite_action.dart';

/// A display item produced by the grouping function.
sealed class ChatDisplayItem {}

/// A regular (non-invite) message.
class RegularMessage extends ChatDisplayItem {
  const RegularMessage(this.message);
  final ChatMessage message;
}

/// An active game invite (pending / in-progress).
class ActiveInvite extends ChatDisplayItem {
  const ActiveInvite(this.message);
  final ChatMessage message;
}

/// A terminal invite one-liner (expired / completed-no-winner).
class TerminalInvite extends ChatDisplayItem {
  const TerminalInvite(this.message);
  final ChatMessage message;
}

/// A result card (completed with winner).
class ResultCard extends ChatDisplayItem {
  const ResultCard(this.message);
  final ChatMessage message;
}

/// A collapsed run of 3+ terminal invites.
class CollapsedInviteRun extends ChatDisplayItem {
  const CollapsedInviteRun(this.messages, {required this.allExpired});
  final List<ChatMessage> messages;
  /// True when every invite in the run is expired/cancelled (→
  /// header says "expired"). False when the run mixes expired and
  /// completed (→ header says "finished").
  final bool allExpired;
}

/// Whether a message is a terminal game invite (expired / cancelled /
/// completed-without-winner) that can join a collapsed run.
///
/// Result cards (completed + winner known) NEVER join a collapsed
/// run — they render as full result cards.
bool isTerminalInvite(ChatMessage msg) {
  if (msg.messageType != MessageType.gameInvite) return false;
  final s = msg.gameInviteStatus ?? 'pending';
  if (s == 'expired' || s == 'cancelled') return true;
  if (s == 'completed') {
    final w = msg.gameWinnerName;
    return w == null || w.isEmpty;
  }
  return false;
}

/// Whether a message is a result card (completed + winner known).
bool isResultCard(ChatMessage msg) {
  if (msg.messageType != MessageType.gameInvite) return false;
  final s = msg.gameInviteStatus ?? 'pending';
  if (s != 'completed') return false;
  final w = msg.gameWinnerName;
  return w != null && w.isNotEmpty;
}

/// Whether a message is an active invite (pending / in-progress).
bool isActiveInvite(ChatMessage msg) {
  if (msg.messageType != MessageType.gameInvite) return false;
  final s = msg.gameInviteStatus ?? 'pending';
  return s == 'pending' ||
      s == 'in_progress' ||
      s == 'accepted' ||
      s == 'active';
}

/// Group an ordered list of ChatMessages into display items.
///
/// Rules:
/// - Regular messages → [RegularMessage].
/// - Active invites → [ActiveInvite].
/// - Result cards → [ResultCard].
/// - Terminal invites: if 3+ consecutive, collapse into
///   [CollapsedInviteRun]. Fewer than 3 → individual [TerminalInvite].
/// - A run is broken by any non-terminal message.
/// - Header wording: "expired" if all are expired/cancelled,
///   "finished" if the run mixes expired and completed.
List<ChatDisplayItem> groupChatItems(List<ChatMessage> messages) {
  final items = <ChatDisplayItem>[];
  var i = 0;
  while (i < messages.length) {
    final msg = messages[i];

    // Non-invite messages → RegularMessage.
    if (msg.messageType != MessageType.gameInvite) {
      items.add(RegularMessage(msg));
      i++;
      continue;
    }

    // Result card → ResultCard (never joins a collapsed run).
    if (isResultCard(msg)) {
      items.add(ResultCard(msg));
      i++;
      continue;
    }

    // Active invite → ActiveInvite.
    if (isActiveInvite(msg)) {
      items.add(ActiveInvite(msg));
      i++;
      continue;
    }

    // Terminal invite: check for a run of 3+ consecutive.
    if (isTerminalInvite(msg)) {
      // Collect the run.
      final run = <ChatMessage>[msg];
      var j = i + 1;
      while (j < messages.length && isTerminalInvite(messages[j])) {
        run.add(messages[j]);
        j++;
      }

      if (run.length >= 3) {
        // Collapse into one row.
        final allExpired = run.every((m) {
          final s = m.gameInviteStatus ?? 'pending';
          return s == 'expired' || s == 'cancelled';
        });
        items.add(CollapsedInviteRun(run, allExpired: allExpired));
      } else {
        // Fewer than 3 → individual one-liners.
        for (final m in run) {
          items.add(TerminalInvite(m));
        }
      }
      i = j;
      continue;
    }

    // Fallback: treat as a regular message (shouldn't reach here for
    // game invites, but handles any edge case).
    items.add(RegularMessage(msg));
    i++;
  }
  return items;
}
