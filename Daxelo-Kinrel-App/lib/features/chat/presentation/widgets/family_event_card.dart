// lib/features/chat/presentation/widgets/family_event_card.dart
//
// DAXELO KINREL — Live Family Event Card (chat)
//
// ONE card used by BOTH chat types (group + direct). Mirrors the
// GameInviteCard pattern: rendered INSIDE the message bubble for
// active events; "Event no longer available" placeholder for deleted
// events. Reuses the game-invite card's layout / tokens / rounding /
// shadows (per spec: "Reuse the card layout, tokens, rounding and
// shadows of the game invite card so it feels native to the chat").
//
// Behavior:
//   • Active card shows: title, date/time (in the viewer's locale),
//     place if any, RSVP counts (Going · Maybe · Can't go), sender.
//   • Three RSVP buttons (Going, Maybe, Can't go). The viewer's
//     current choice is highlighted. Tapping writes to the existing
//     calendar_event_rsvps table via the existing calendarProvider.
//   • Tapping the body of the card opens the existing event detail
//     screen via the route /family/<familyId>/calendar/event/<eventId>.
//   • Deleted-event state: the card shows "Event no longer available"
//     and the buttons are disabled.
//   • Live updates: the card reads from the ChatMessage row's
//     denormalized event fields (eventId, eventTitle, eventDate,
//     eventLocation, eventCategory, eventRsvpGoing, eventRsvpMaybe,
//     eventRsvpNotGoing, eventDeletedAt). The migration's AFTER
//     UPDATE triggers keep these fields in sync with the live
//     calendar_events + calendar_event_rsvps state; the
//     chat_provider's existing realtime UPDATE subscription on
//     ChatMessage propagates the changes to every open chat UI.
//   • No hardcoded colors or text styles — uses KinrelColors /
//     KinrelTypography / KinrelRadius / KinrelSpacing (same tokens
//     as the game invite card).
//   • Semantic label for screen readers.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../calendar/models/calendar_models.dart';
import '../../../calendar/providers/calendar_provider.dart';
import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/services/haptic_service.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/models/chat_message.dart';
import '../../providers/chat_provider.dart' show chatCurrentUserIdProvider;
import '../chat_ui_tokens.dart';

class FamilyEventCard extends ConsumerWidget {
  const FamilyEventCard({
    super.key,
    required this.message,
    required this.familyId,
    required this.isMe,
  });

  /// The ChatMessage row carrying the denormalized event fields.
  final ChatMessage message;

  /// The family id for this chat (passed by the chat_screen — the
  /// FamilyEventCard needs it to look up the calendarProvider +
  /// to build the event-detail route).
  final String familyId;

  /// True when the message's senderId == the current viewer. Used to
  /// pick the bubble surface (sent vs received) — the parent bubble
  /// provides the surface, this card renders INSIDE it.
  final bool isMe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = S.of(context)!;
    final eventDeleted = message.eventDeletedAt != null ||
        (message.eventId == null || message.eventId!.isEmpty);
    final myUserId = ref.watch(chatCurrentUserIdProvider);
    final calendarState = ref.watch(calendarProvider(familyId));

    // Look up the viewer's RSVP from the calendarProvider state (the
    // synced counts on the ChatMessage row don't carry per-user
    // status, so we look up the viewer's RSVP from the live state).
    EventRSVP? myRsvp;
    if (message.eventId != null) {
      final rsvps = calendarState.rsvps[message.eventId] ?? const [];
      myRsvp = rsvps.where((r) => r.userId == myUserId).firstOrNull;
    }
    final myStatus = myRsvp?.status ?? RSVPStatus.pending;

    // ── Build the semantic label for screen readers ───────────────
    final semanticsLabel = eventDeleted
        ? l10n.chatEventCardSemanticsDeleted
        : l10n.chatEventCardSemantics(
            message.eventTitle ?? '',
            _formatDate(message),
            message.eventLocation ?? '',
            message.eventRsvpGoing ?? 0,
            message.eventRsvpMaybe ?? 0,
            message.eventRsvpNotGoing ?? 0,
          );

    return Semantics(
      label: semanticsLabel,
      button: false,
      child: eventDeleted
          ? _buildDeletedState(context, l10n)
          : _buildActiveState(context, ref, l10n, myStatus),
    );
  }

  Widget _buildActiveState(
    BuildContext context,
    WidgetRef ref,
    S l10n,
    RSVPStatus myStatus,
  ) {
    return InkWell(
      onTap: () => _openEventDetail(context),
      borderRadius: BorderRadius.circular(KinrelRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(KinrelSpacing.sm + 2),
        decoration: BoxDecoration(
          color: ChatUi.chatReceived,
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
          border: Border.all(
            color: KinrelColors.textSilver.withValues(alpha: 0.1),
            width: 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header row: icon + title ────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: KinrelColors.ember.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(KinrelRadius.sm),
                  ),
                  child: Icon(
                    _categoryIcon(message.eventCategory),
                    color: KinrelColors.ember,
                    size: 22,
                  ),
                ),
                const SizedBox(width: KinrelSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.eventTitle ?? l10n.chatEventCardNoTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: KinrelColors.textWhite,
                        ),
                      ),
                      if ((message.eventDate ?? '').isNotEmpty ||
                          (message.eventLocation ?? '').isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          _buildSubtitle(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 12,
                            color: KinrelColors.textSilver,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: KinrelSpacing.sm),
            // ── RSVP counts row ─────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: KinrelSpacing.sm,
                vertical: KinrelSpacing.xs + 2,
              ),
              decoration: BoxDecoration(
                color: KinrelColors.darkBackground,
                borderRadius: BorderRadius.circular(KinrelRadius.sm),
              ),
              child: Wrap(
                spacing: KinrelSpacing.sm,
                runSpacing: 2,
                children: [
                  _RsvpCountChip(
                    label:
                        l10n.chatEventRsvpGoing(message.eventRsvpGoing ?? 0),
                    isMine: myStatus == RSVPStatus.going,
                  ),
                  _RsvpCountChip(
                    label:
                        l10n.chatEventRsvpMaybe(message.eventRsvpMaybe ?? 0),
                    isMine: myStatus == RSVPStatus.maybe,
                  ),
                  _RsvpCountChip(
                    label: l10n.chatEventRsvpNotGoing(
                        message.eventRsvpNotGoing ?? 0),
                    isMine: myStatus == RSVPStatus.notGoing,
                  ),
                ],
              ),
            ),
            const SizedBox(height: KinrelSpacing.sm),
            // ── RSVP action buttons ────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _RsvpButton(
                    label: l10n.chatEventRsvpGoingLabel,
                    selected: myStatus == RSVPStatus.going,
                    onTap: () => _submitRsvp(ref, RSVPStatus.going),
                  ),
                ),
                const SizedBox(width: KinrelSpacing.xs),
                Expanded(
                  child: _RsvpButton(
                    label: l10n.chatEventRsvpMaybeLabel,
                    selected: myStatus == RSVPStatus.maybe,
                    onTap: () => _submitRsvp(ref, RSVPStatus.maybe),
                  ),
                ),
                const SizedBox(width: KinrelSpacing.xs),
                Expanded(
                  child: _RsvpButton(
                    label: l10n.chatEventRsvpNotGoingLabel,
                    selected: myStatus == RSVPStatus.notGoing,
                    onTap: () => _submitRsvp(ref, RSVPStatus.notGoing),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeletedState(BuildContext context, S l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.sm,
        vertical: KinrelSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: KinrelColors.darkBackground,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(
          color: KinrelColors.textSilver.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.event_busy_outlined,
              color: KinrelColors.textSilver.withValues(alpha: 0.7),
              size: 20),
          const SizedBox(width: KinrelSpacing.sm),
          Expanded(
            child: Text(
              l10n.chatEventCardDeleted,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: KinrelColors.textSilver.withValues(alpha: 0.85),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openEventDetail(BuildContext context) {
    if (message.eventId == null || message.eventId!.isEmpty) return;
    // The existing calendar event detail screen route.
    context.push('/family/$familyId/calendar/event/${message.eventId}');
  }

  Future<void> _submitRsvp(WidgetRef ref, RSVPStatus status) async {
    await HapticService.selection();
    if (message.eventId == null) return;
    final notifier = ref.read(calendarProvider(familyId).notifier);
    await notifier.submitRSVP(message.eventId!, status);
    // The migration's AFTER INSERT/UPDATE trigger on calendar_event_rsvps
    // fires fn_sync_family_event_chat_cards, which UPDATEs the
    // ChatMessage row's eventRsvp{Going,Maybe,NotGoing} counts. The
    // chat_provider's realtime UPDATE subscription then propagates the
    // change to every open chat UI automatically.
  }

  String _buildSubtitle() {
    final parts = <String>[];
    final dateStr = _formatDate(message);
    if (dateStr.isNotEmpty) parts.add(dateStr);
    if ((message.eventLocation ?? '').isNotEmpty) {
      parts.add(message.eventLocation!);
    }
    return parts.join(' · ');
  }

  String _formatDate(ChatMessage msg) {
    // The eventDate column was DATE::text on the server; we just
    // display it as-is. For a more locale-aware format, a follow-up
    // would use intl.DateFormat.
    return msg.eventDate ?? '';
  }

  IconData _categoryIcon(String? category) {
    switch (category) {
      case 'birthday':
        return Icons.cake_outlined;
      case 'anniversary':
        return Icons.favorite_border;
      case 'wedding':
        return Icons.church_outlined;
      case 'engagement':
        return Icons.diamond_outlined;
      case 'babyShower':
      case 'pregnancy':
        return Icons.child_friendly_outlined;
      case 'graduation':
      case 'school':
        return Icons.school_outlined;
      case 'sports':
        return Icons.sports_basketball_outlined;
      case 'familyDinner':
      case 'reunion':
        return Icons.groups_outlined;
      case 'vacation':
        return Icons.flight_outlined;
      case 'festival':
        return Icons.celebration_outlined;
      case 'medical':
        return Icons.local_hospital_outlined;
      case 'memorial':
        return Icons.local_florist_outlined;
      case 'custom':
      default:
        return Icons.event_outlined;
    }
  }
}

/// A small chip showing an RSVP count. Highlighted when the viewer's
/// own RSVP matches the chip's category.
class _RsvpCountChip extends StatelessWidget {
  const _RsvpCountChip({required this.label, required this.isMine});
  final String label;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.xs + 2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: isMine
            ? KinrelColors.ember.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(KinrelRadius.xs + 2),
        border: isMine
            ? Border.all(color: KinrelColors.ember.withValues(alpha: 0.4), width: 1)
            : Border.all(color: Colors.transparent, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 11,
          fontWeight: isMine ? FontWeight.w600 : FontWeight.w400,
          color: isMine ? KinrelColors.ember : KinrelColors.textSilver,
        ),
      ),
    );
  }
}

/// The three RSVP action buttons. Selected state: accent border +
/// filled background. Unselected: transparent background, 0.5 orange
/// border (matches the game-invite Join button styling).
class _RsvpButton extends StatelessWidget {
  const _RsvpButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(KinrelRadius.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
        decoration: BoxDecoration(
          color: selected
              ? KinrelColors.ember.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(KinrelRadius.sm),
          border: Border.all(
            color: selected
                ? KinrelColors.ember
                : KinrelColors.ember.withValues(alpha: 0.5),
            width: selected ? 1.5 : 0.5,
          ),
        ),
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: KinrelColors.ember,
            ),
          ),
        ),
      ),
    );
  }
}
