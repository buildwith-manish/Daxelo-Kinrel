// lib/features/profile/presentation/invitations_screen.dart
//
// DAXELO KINREL — Invitations Screen
//
// Shows family invitations with two tabs: Received and Sent.
// Received invites can be accepted or declined. Sent invites
// show their status (pending/accepted/expired).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/constants/brand_typography.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/utils/device_tier.dart';
import '../data/profile_provider.dart';

// ── Design Tokens ──────────────────────────────────────────────────
const Color _bg = Color(0xFF131416);
const Color _cardBg = Color(0xFF191B2C);
const Color _orange = Color(0xFFE8612A);
const Color _textPrimary = Color(0xFFF5F0EE);
const Color _textSecondary = Color(0xFFC9B4A8);
const Color _textDim = Color(0xFF8A7A72);
const Color _borderSubtle = Color(0x0FFFFFFF);

class InvitationsScreen extends ConsumerStatefulWidget {
  const InvitationsScreen({super.key, this.inviteCode});

  /// Optional invite code from a deep link (e.g. /invite/:code).
  /// When provided, the screen can highlight or auto-process this invite.
  final String? inviteCode;

  @override
  ConsumerState<InvitationsScreen> createState() => _InvitationsScreenState();
}

class _InvitationsScreenState extends ConsumerState<InvitationsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(profileProvider.notifier).loadInvitations();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _relativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
  }

  Future<void> _acceptInvitation(InvitationModel invitation) async {
    final success = await ref
        .read(profileProvider.notifier)
        .acceptInvitation(invitation.id);

    if (!mounted) return;

    if (success) {
      context.showSnackBar('Joined "${invitation.familyName}"!');
      // Navigate to family graph
      await context.push('/families');
    } else {
      context.showSnackBar('Failed to accept invitation', isError: true);
    }
  }

  Future<void> _declineInvitation(InvitationModel invitation) async {
    final success = await ref
        .read(profileProvider.notifier)
        .declineInvitation(invitation.id);

    if (!mounted) return;

    if (success) {
      context.showSnackBar('Invitation declined');
    } else {
      context.showSnackBar('Failed to decline invitation', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileState = ref.watch(profileProvider);
    final allInvitations = profileState.invitations;

    // Split into received (pending) and sent (non-pending from user)
    final receivedInvitations = allInvitations
        .where((i) => i.status == 'pending')
        .toList();
    final sentInvitations = allInvitations
        .where((i) => i.status != 'pending')
        .toList();

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _textPrimary),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Invitations',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _orange,
          indicatorWeight: 2.5,
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: _orange,
          unselectedLabelColor: _textDim,
          labelStyle: const TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: const TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          tabs: [
            Tab(text: 'Received', iconMargin: EdgeInsets.zero),
            Tab(text: 'Sent', iconMargin: EdgeInsets.zero),
          ],
        ),
      ),
      body: profileState.isLoading
          ? _buildShimmerList()
          : TabBarView(
              controller: _tabController,
              children: [
                // ── Received Tab ─────────────────────────────────
                receivedInvitations.isEmpty
                    ? _buildEmptyState(
                        icon: Icons.mail_outline,
                        title: 'No pending invitations',
                        subtitle:
                            'When someone invites you to a family, it will appear here',
                      )
                    : _buildReceivedList(receivedInvitations),

                // ── Sent Tab ─────────────────────────────────────
                sentInvitations.isEmpty
                    ? _buildEmptyState(
                        icon: Icons.send_outlined,
                        title: 'No sent invitations',
                        subtitle:
                            'Invitations you send to others will appear here',
                      )
                    : _buildSentList(sentInvitations),
              ],
            ),
    );
  }

  // ── Received Invitations List ────────────────────────────────────

  Widget _buildReceivedList(List<InvitationModel> invitations) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      itemCount: invitations.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final invitation = invitations[index];
        return _ReceivedInvitationCard(
          invitation: invitation,
          relativeTime: _relativeTime(invitation.createdAt),
          onAccept: () => _acceptInvitation(invitation),
          onDecline: () => _declineInvitation(invitation),
        );
      },
    );
  }

  // ── Sent Invitations List ────────────────────────────────────────

  Widget _buildSentList(List<InvitationModel> invitations) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      itemCount: invitations.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final invitation = invitations[index];
        return _SentInvitationCard(
          invitation: invitation,
          relativeTime: _relativeTime(invitation.createdAt),
        );
      },
    );
  }

  // ── Empty State ──────────────────────────────────────────────────

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _orange.withValues(alpha: 0.12),
            ),
            child: Icon(icon, color: _orange, size: 36),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              color: _textDim,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── Shimmer Loading ──────────────────────────────────────────────

  Widget _buildShimmerList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      itemCount: 3,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final _shimmerChild = Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _borderSubtle),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 130,
                      height: 14,
                      decoration: BoxDecoration(
                        color: _bg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 100,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _bg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 70,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _bg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

        if (!DeviceTierCache.instance.shouldShimmer) {
          return _shimmerChild;
        }

        return Shimmer.fromColors(
          baseColor: const Color(0xFF202338),
          highlightColor: const Color(0xFF13141E),
          period: const Duration(milliseconds: 1500),
          child: _shimmerChild,
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Received Invitation Card
// ═══════════════════════════════════════════════════════════════════════

class _ReceivedInvitationCard extends StatelessWidget {
  const _ReceivedInvitationCard({
    required this.invitation,
    required this.relativeTime,
    required this.onAccept,
    required this.onDecline,
  });

  final InvitationModel invitation;
  final String relativeTime;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top Row: Family info ────────────────────────────────
          Row(
            children: [
              // Family avatar placeholder
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.family_restroom,
                  color: _orange,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),

              // Family name + inviter info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invitation.familyName,
                      style: const TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Invited by ${invitation.inviterName}${invitation.inviterUsername != null ? ' @${invitation.inviterUsername}' : ''}',
                      style: const TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        color: _textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Time
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  relativeTime,
                  style: const TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 10,
                    color: _textDim,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // ── Action Buttons ──────────────────────────────────────
          Row(
            children: [
              // Decline button (red, outlined)
              Expanded(
                child: OutlinedButton(
                  onPressed: onDecline,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: Colors.redAccent.withValues(alpha: 0.5),
                      width: 1,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    backgroundColor: Colors.redAccent.withValues(alpha: 0.06),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: const Text(
                    'Decline',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.redAccent,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Accept button (green, filled)
              Expanded(
                child: ElevatedButton(
                  onPressed: onAccept,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2ECC71),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Accept',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Sent Invitation Card
// ═══════════════════════════════════════════════════════════════════════

class _SentInvitationCard extends StatelessWidget {
  const _SentInvitationCard({
    required this.invitation,
    required this.relativeTime,
  });

  final InvitationModel invitation;
  final String relativeTime;

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'accepted':
        return const Color(0xFF2ECC71);
      case 'expired':
        return Colors.grey;
      case 'declined':
        return Colors.redAccent;
      case 'pending':
      default:
        return const Color(0xFFF1C40F);
    }
  }

  IconData _statusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'accepted':
        return Icons.check_circle;
      case 'expired':
        return Icons.access_time;
      case 'declined':
        return Icons.cancel;
      case 'pending':
      default:
        return Icons.hourglass_empty;
    }
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'accepted':
        return 'Accepted';
      case 'expired':
        return 'Expired';
      case 'declined':
        return 'Declined';
      case 'pending':
      default:
        return 'Pending';
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(invitation.status);
    final statusIcon = _statusIcon(invitation.status);
    final statusLabel = _statusLabel(invitation.status);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderSubtle),
      ),
      child: Row(
        children: [
          // Family avatar placeholder
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.family_restroom, color: _orange, size: 22),
          ),
          const SizedBox(width: 14),

          // Family name + invitee info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invitation.familyName,
                  style: const TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  'Invited ${invitation.inviterName}',
                  style: const TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    color: _textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  relativeTime,
                  style: const TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 10,
                    color: _textDim,
                  ),
                ),
              ],
            ),
          ),

          // Status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: statusColor.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(statusIcon, color: statusColor, size: 12),
                const SizedBox(width: 4),
                Text(
                  statusLabel,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
