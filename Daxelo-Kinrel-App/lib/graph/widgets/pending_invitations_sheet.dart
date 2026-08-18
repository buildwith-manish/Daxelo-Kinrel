// lib/graph/widgets/pending_invitations_sheet.dart
//
// DAXELO KINREL — v5.41 Pending Invitations Bottom Sheet
//
// Shows all pending graph-originated invitations for a family.
// Each invitation displays:
//   • Recipient name / email / phone
//   • The relationship that will be created (e.g. "Father of Manish")
//   • When it was sent
//   • A "Cancel" button (for the inviter)
//
// This sheet is opened from the "Pending Invitations" pill button on
// the family graph screen (similar to the "Unlinked Members" pill).
//
// The graph itself does NOT show pending invitations as nodes — only
// confirmed, accepted members appear in the graph. This sheet is the
// single surface where pending invitations are visible.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/brand_colors.dart';
import '../../core/constants/brand_typography.dart';
import '../../core/widgets/person_avatar.dart';
import '../../features/family/presentation/providers/graph_pending_invitations_provider.dart';

/// Shows the pending invitations bottom sheet.
///
/// [familyId] — the family whose pending invitations to show.
/// [onInvitationCancelled] — optional callback invoked after an invitation
///   is cancelled (e.g. to refresh the graph).
void showPendingInvitationsSheet(
  BuildContext context,
  WidgetRef ref,
  String familyId, {
  VoidCallback? onInvitationCancelled,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: KinrelColors.darkCard,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
    ),
    builder: (ctx) => _PendingInvitationsSheet(
      familyId: familyId,
      onInvitationCancelled: onInvitationCancelled,
    ),
  );
}

class _PendingInvitationsSheet extends ConsumerStatefulWidget {
  const _PendingInvitationsSheet({
    required this.familyId,
    this.onInvitationCancelled,
  });

  final String familyId;
  final VoidCallback? onInvitationCancelled;

  @override
  ConsumerState<_PendingInvitationsSheet> createState() =>
      _PendingInvitationsSheetState();
}

class _PendingInvitationsSheetState
    extends ConsumerState<_PendingInvitationsSheet> {
  final Set<String> _cancellingIds = {};

  Future<void> _cancelInvitation(GraphPendingInvitation invitation) async {
    setState(() => _cancellingIds.add(invitation.id));
    try {
      final notifier = ref.read(
        graphPendingInvitationsProvider(widget.familyId).notifier,
      );
      final success = await notifier.cancelInvitation(invitation.id);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invitation to ${invitation.recipientDisplayName} cancelled'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
        widget.onInvitationCancelled?.call();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not cancel invitation. Please try again.'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _cancellingIds.remove(invitation.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final invitationsAsync =
        ref.watch(graphPendingInvitationsProvider(widget.familyId));

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 12.0, bottom: 4.0),
              child: Container(
                width: 40.0,
                height: 4.0,
                decoration: BoxDecoration(
                  color: KinrelColors.textDim,
                  borderRadius: BorderRadius.circular(2.0),
                ),
              ),
            ),
            // Header
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.mail_outline,
                          size: 20, color: KinrelColors.tealAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Pending Invitations',
                          style: TextStyle(
                            fontFamily: KinrelTypography.displayFont,
                            fontSize: 18.0,
                            fontWeight: FontWeight.w700,
                            color: KinrelColors.textWhite,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'People you\'ve invited from the graph. They\'ll appear '
                    'in the graph once they accept.',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      color: KinrelColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0x1AFFFFFF), height: 1.0),
            // List
            Flexible(
              child: invitationsAsync.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(color: KinrelColors.tealAccent),
                  ),
                ),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'Could not load invitations.\nPlease try again later.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: KinrelColors.textDim,
                        fontFamily: KinrelTypography.bodyFont,
                      ),
                    ),
                  ),
                ),
                data: (invitations) {
                  if (invitations.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_outline,
                                size: 48, color: KinrelColors.tealAccent),
                            const SizedBox(height: 12),
                            Text(
                              'No pending invitations',
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: KinrelColors.textWhite,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Invite someone from the graph by long-pressing '
                              'a node and tapping "Invite".',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 12,
                                color: KinrelColors.textDim,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: invitations.length,
                    itemBuilder: (ctx, i) {
                      final inv = invitations[i];
                      final isCancelling = _cancellingIds.contains(inv.id);
                      return _InvitationTile(
                        invitation: inv,
                        isCancelling: isCancelling,
                        onCancel: () => _cancelInvitation(inv),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _InvitationTile extends StatelessWidget {
  const _InvitationTile({
    required this.invitation,
    required this.isCancelling,
    required this.onCancel,
  });

  final GraphPendingInvitation invitation;
  final bool isCancelling;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: KinrelColors.darkElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: KinrelColors.tealAccent.withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          children: [
            PersonAvatar(
              name: invitation.recipientDisplayName,
              size: 44,
              backgroundColor:
                  KinrelColors.tealAccent.withValues(alpha: 0.15),
              textColor: KinrelColors.tealAccent,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    invitation.recipientDisplayName,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    invitation.relationshipDescription,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: KinrelColors.tealAccent,
                    ),
                  ),
                  if (invitation.createdAt != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      _formatDate(invitation.createdAt!),
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 11,
                        color: KinrelColors.textDim,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            isCancelling
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: KinrelColors.textDim,
                    ),
                  )
                : TextButton(
                    onPressed: onCancel,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      minimumSize: const Size(0, 0),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
