// lib/features/chat/presentation/widgets/poll_card.dart
//
// DAXELO KINREL — Poll card bubble (Phase 22, Task 5)
//
// Renders a poll message (MessageType.poll) as a card inside the
// standard bubble constraints. Mirrors the gameInvite card pattern:
// distinct card surface, question + options as tappable rows, live
// vote counts via realtime, "you voted" indicator.
//
// v1 scope per the user's task:
//   ✓ 2–6 options
//   ✓ one-tap voting (tap an option → vote)
//   ✓ live vote counts via realtime (chat_provider subscribes to
//     ChatMessage UPDATEs, so fn_vote_poll's UPDATE propagates the
//     new pollVoteCounts + pollVoterIds to every open chat)
//   ✓ "you voted" state (read from message.pollVoterIds — no extra
//     query)
//   ✗ no anonymous voting (voter IDs stored, just not shown in card)
//   ✗ no multi-select (UNIQUE on messageId+userId enforces one vote)
//   ✗ no vote switching (RPC returns 'already_voted' with the
//     previously-chosen option; the card highlights the user's
//     existing choice)
//
// Why a separate file: chat_screen.dart is ~190KB / 4852 lines. Pulling
// the poll card into its own widget keeps the diff in chat_screen.dart
// small (import + case branch) and makes the card testable in
// isolation. Same approach as mention_picker.dart.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../providers/chat_provider.dart';

class PollCard extends ConsumerWidget {
  const PollCard({
    super.key,
    required this.message,
    required this.currentUserId,
    required this.onVote,
  });

  final ChatMessage message;
  final String currentUserId;
  final void Function(int optionIndex) onVote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final question = message.pollQuestion ?? message.content;
    final options = message.pollOptions;
    final counts = message.pollVoteCounts;
    final totalVotes = message.pollTotalVotes;
    final myVote = message.votedOptionIndex(currentUserId);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: KinrelColors.ember.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header: "Poll" label + total votes ──
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: KinrelColors.ember.withValues(alpha: 0.18),
                ),
                child: Icon(
                  Icons.poll_rounded,
                  size: 14,
                  color: KinrelColors.ember,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'POLL',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.ember,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              Text(
                '$totalVotes ${totalVotes == 1 ? 'vote' : 'votes'}',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 10,
                  color: KinrelColors.textDim,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // ── Question ──
          Text(
            question,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textWhite,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          // ── Options ──
          ...List.generate(options.length, (i) {
            final option = options[i];
            final count = i < counts.length ? counts[i] : 0;
            final isMyVote = myVote == i;
            final pct = totalVotes > 0 ? (count / totalVotes) : 0.0;

            return _PollOption(
              label: option,
              count: count,
              pct: pct,
              isMyVote: isMyVote,
              onTap: myVote == null ? () => onVote(i) : null,
            );
          }),
        ],
      ),
    );
  }
}

class _PollOption extends StatelessWidget {
  const _PollOption({
    required this.label,
    required this.count,
    required this.pct,
    required this.isMyVote,
    required this.onTap,
  });

  final String label;
  final int count;
  final double pct;
  final bool isMyVote;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Ink(
            decoration: BoxDecoration(
              color: isMyVote
                  ? KinrelColors.ember.withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isMyVote
                    ? KinrelColors.ember.withValues(alpha: 0.55)
                    : Colors.white.withValues(alpha: 0.08),
                width: isMyVote ? 1.2 : 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (isMyVote) ...[
                              Icon(
                                Icons.check_circle_rounded,
                                size: 14,
                                color: KinrelColors.ember,
                              ),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontFamily: KinrelTypography.bodyFont,
                                  fontSize: 14,
                                  fontWeight:
                                      isMyVote ? FontWeight.w600 : FontWeight.w500,
                                  color: KinrelColors.textWhite,
                                ),
                              ),
                            ),
                          ],
                        ),
                        // Vote count + percentage
                        if (count > 0) ...[
                          const SizedBox(height: 4),
                          Text(
                            '$count ${count == 1 ? 'vote' : 'votes'} · ${(pct * 100).round()}%',
                            style: TextStyle(
                              fontFamily: KinrelTypography.monoFont,
                              fontSize: 10,
                              color: KinrelColors.textDim,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (enabled && !isMyVote)
                    Icon(
                      Icons.radio_button_unchecked_rounded,
                      size: 18,
                      color: KinrelColors.textDim,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
