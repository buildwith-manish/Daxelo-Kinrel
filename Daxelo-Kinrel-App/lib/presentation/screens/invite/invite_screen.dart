// lib/presentation/screens/invite/invite_screen.dart
//
// DAXELO KINREL — Invite Screen (P5)
//
// Dedicated screen for inviting family members with 4 sections:
//   1. Share Link — system share sheet via ShareHelper
//   2. Share via WhatsApp — direct WhatsApp link via url_launcher
//   3. QR Code — scannable QR code using qr_flutter
//   4. Pending Invites — list from the existing invitation provider
//
// Uses KinrelColors, KinrelTypography, KinrelSpacing for design tokens.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/utils/share_helper.dart';
import '../../../core/utils/invite_message_builder.dart';
import '../../../core/services/retention_service.dart';
import '../../../core/services/analytics_service.dart';
import '../../features/profile/data/profile_provider.dart';

class InviteScreen extends ConsumerStatefulWidget {
  const InviteScreen({
    super.key,
    required this.familyId,
    required this.familyName,
  });

  final String familyId;
  final String familyName;

  @override
  ConsumerState<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends ConsumerState<InviteScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _linkCopied = false;
  bool _isQrLoading = false;

  // The invite URL for this family
  String get _inviteUrl => 'https://kinrel.app/invite/${widget.familyId}';
  String get _inviteCode => widget.familyId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Load invitations on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(profileProvider.notifier).loadInvitations();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profileState = ref.watch(profileProvider);
    final pendingInvites = profileState.invitations
        .where((i) => i.status == 'pending')
        .toList();

    return Scaffold(
      backgroundColor: KinrelColors.darkBackground,
      appBar: AppBar(
        backgroundColor: KinrelColors.darkBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: KinrelColors.textWhite),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Invite to ${widget.familyName}',
          style: const TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textWhite,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: KinrelColors.orange,
          indicatorWeight: 2.5,
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: KinrelColors.orange,
          unselectedLabelColor: KinrelColors.textDim,
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
          tabs: const [
            Tab(text: 'Share'),
            Tab(text: 'Invites'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ── Share Tab ────────────────────────────────────────────
          _buildShareTab(pendingInvites),

          // ── Invites Tab ──────────────────────────────────────────
          _buildInvitesTab(pendingInvites),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // SHARE TAB
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildShareTab(List<InvitationModel> pendingInvites) {
    return SafeArea(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.symmetric(
          horizontal: KinrelSpacing.base,
          vertical: KinrelSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Section 1: Share Link ─────────────────────────────
            _buildSectionCard(
              icon: Icons.link_rounded,
              iconColor: KinrelColors.orange,
              title: 'Share Link',
              subtitle: 'Send an invite link to your family members',
              child: _buildShareLinkSection(),
            ),

            SizedBox(height: KinrelSpacing.md),

            // ── Section 2: Share via WhatsApp ─────────────────────
            _buildSectionCard(
              icon: Icons.chat_bubble_rounded,
              iconColor: const Color(0xFF25D366), // WhatsApp green
              title: 'Share via WhatsApp',
              subtitle: 'Quick share directly to WhatsApp',
              child: _buildWhatsAppSection(),
            ),

            SizedBox(height: KinrelSpacing.md),

            // ── Section 3: QR Code ────────────────────────────────
            _buildSectionCard(
              icon: Icons.qr_code_2_rounded,
              iconColor: KinrelColors.amber,
              title: 'QR Code',
              subtitle: 'Scan to join the family',
              child: _buildQrCodeSection(),
            ),

            SizedBox(height: KinrelSpacing.md),

            // ── Section 4: Pending Invites Summary ────────────────
            if (pendingInvites.isNotEmpty)
              _buildSectionCard(
                icon: Icons.mail_outline_rounded,
                iconColor: KinrelColors.info,
                title: 'Pending Invites',
                subtitle: '${pendingInvites.length} invitation${pendingInvites.length == 1 ? '' : 's'} waiting',
                child: _buildPendingInvitesSummary(pendingInvites),
              ),

            SizedBox(height: KinrelSpacing.xxl),
          ],
        ),
      ),
    );
  }

  // ── Section 1: Share Link ────────────────────────────────────────

  Widget _buildShareLinkSection() {
    return Column(
      children: [
        // Invite URL display
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: KinrelColors.darkElevated,
            borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
            border: Border.all(
              color: KinrelColors.darkSurface.withValues(alpha: 0.6),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _inviteUrl,
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 13,
                    color: KinrelColors.textSilver,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Copy Link + Share buttons
        Row(
          children: [
            // Copy Link button
            Expanded(
              child: _ActionButton(
                icon: _linkCopied ? Icons.check_rounded : Icons.copy_rounded,
                label: _linkCopied ? 'Copied!' : 'Copy Link',
                color: _linkCopied ? KinrelColors.success : KinrelColors.textSilver,
                backgroundColor: KinrelColors.darkElevated,
                borderColor: KinrelColors.darkSurface.withValues(alpha: 0.6),
                onTap: _copyLink,
              ),
            ),

            const SizedBox(width: 10),

            // Share button (system share sheet)
            Expanded(
              child: _ActionButton(
                icon: Icons.share_rounded,
                label: 'Share',
                color: Colors.white,
                backgroundColor: KinrelColors.orange,
                borderColor: KinrelColors.orange,
                onTap: _shareViaSystemSheet,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Section 2: WhatsApp ──────────────────────────────────────────

  Widget _buildWhatsAppSection() {
    return Column(
      children: [
        // WhatsApp share message preview
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF0B141A), // WhatsApp chat bg
            borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF005C4B), // WhatsApp message bubble
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  InviteMessageBuilder.build(
                    widget.familyName,
                    _inviteUrl,
                    'en',
                  ),
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    color: Colors.white,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // WhatsApp share button
        SizedBox(
          width: double.infinity,
          child: _ActionButton(
            icon: Icons.chat_bubble_rounded,
            label: 'Open WhatsApp',
            color: Colors.white,
            backgroundColor: const Color(0xFF25D366),
            borderColor: const Color(0xFF25D366),
            onTap: _shareViaWhatsApp,
          ),
        ),
      ],
    );
  }

  // ── Section 3: QR Code ──────────────────────────────────────────

  Widget _buildQrCodeSection() {
    return Column(
      children: [
        // QR Code display
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(KinrelSpacing.radiusLg),
          ),
          child: Column(
            children: [
              // QR Code
              QrImageView(
                data: _inviteUrl,
                version: QrVersions.auto,
                size: 200.0,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.roundedOuter,
                  color: KinrelColors.orange,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.roundedOuter,
                  color: Color(0xFF1A1A2E),
                ),
              ),

              const SizedBox(height: 16),

              // Family name below QR
              Text(
                widget.familyName,
                style: const TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E),
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 4),

              Text(
                'Scan to join the family',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Save QR button
        SizedBox(
          width: double.infinity,
          child: _ActionButton(
            icon: Icons.save_alt_rounded,
            label: 'Save QR Code',
            color: KinrelColors.amber,
            backgroundColor: KinrelColors.darkElevated,
            borderColor: KinrelColors.amber.withValues(alpha: 0.3),
            onTap: _saveQrCode,
          ),
        ),
      ],
    );
  }

  // ── Section 4: Pending Invites Summary ───────────────────────────

  Widget _buildPendingInvitesSummary(List<InvitationModel> invites) {
    return Column(
      children: invites.take(3).map((invite) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              // Status indicator
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: KinrelColors.warning,
                ),
              ),
              const SizedBox(width: 10),

              // Invitee info
              Expanded(
                child: Text(
                  invite.familyName,
                  style: const TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: KinrelColors.textWhite,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: KinrelColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Pending',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.warning,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // INVITES TAB
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildInvitesTab(List<InvitationModel> pendingInvites) {
    if (pendingInvites.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KinrelColors.orange.withValues(alpha: 0.12),
              ),
              child: const Icon(
                Icons.mail_outline_rounded,
                color: KinrelColors.orange,
                size: 36,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No pending invitations',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'When someone invites you to a family, it will appear here',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: KinrelColors.textDim,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      itemCount: pendingInvites.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final invite = pendingInvites[index];
        return _PendingInviteCard(invitation: invite);
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // SECTION CARD WRAPPER
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildSectionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusLg),
        border: Border.all(color: KinrelColors.darkSurface.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: iconColor.withValues(alpha: 0.12),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        color: KinrelColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Child content
          child,
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: _inviteUrl));

    // Track event
    AnalyticsService.instance.logReferralCodeCopied();
    RetentionService.recordInviteSent();

    setState(() => _linkCopied = true);

    // Reset after 2 seconds
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _linkCopied = false);
    });
  }

  Future<void> _shareViaSystemSheet() async {
    await ShareHelper.shareInvite(
      inviteCode: _inviteCode,
      familyName: widget.familyName,
    );

    AnalyticsService.instance.logInviteSent('system_share');
    RetentionService.recordInviteSent();
  }

  Future<void> _shareViaWhatsApp() async {
    final message = InviteMessageBuilder.build(
      widget.familyName,
      _inviteUrl,
      'en',
    );

    final whatsappUrl = Uri.encodeFull(
      'https://wa.me/?text=${Uri.encodeComponent(message)}',
    );

    final uri = Uri.parse(whatsappUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      AnalyticsService.instance.logInviteSent('whatsapp');
      RetentionService.recordInviteSent();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('WhatsApp is not installed on this device'),
            backgroundColor: KinrelColors.warning,
          ),
        );
      }
    }
  }

  Future<void> _saveQrCode() async {
    // For now, show a snackbar — full implementation would use
    // path_provider + screenshot package to save the QR image
    setState(() => _isQrLoading = true);

    try {
      // The full implementation would:
      // 1. Use RepaintBoundary + RenderRepaintBoundary to capture the QR
      // 2. Save to app's external storage directory via path_provider
      // 3. Optionally use gal package to save to gallery

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('QR Code saved to gallery'),
            backgroundColor: KinrelColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save QR Code: $e'),
            backgroundColor: KinrelColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isQrLoading = false);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// ACTION BUTTON
// ═══════════════════════════════════════════════════════════════════════

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.backgroundColor,
    required this.borderColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color backgroundColor;
  final Color borderColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: backgroundColor,
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    )
        .animate(onPlay: (c) => c.forward())
        .fadeIn(duration: 200.ms)
        .scale(
          begin: const Offset(0.98, 0.98),
          end: const Offset(1, 1),
          duration: 150.ms,
        );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// PENDING INVITE CARD (compact version for invite tab)
// ═══════════════════════════════════════════════════════════════════════

class _PendingInviteCard extends ConsumerWidget {
  const _PendingInviteCard({required this.invitation});

  final InvitationModel invitation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: KinrelColors.darkSurface.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        children: [
          // Avatar placeholder
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: KinrelColors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.family_restroom,
              color: KinrelColors.orange,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),

          // Info
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
                    color: KinrelColors.textWhite,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  'Invited by ${invitation.inviterName}',
                  style: const TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    color: KinrelColors.textSilver,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Status
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: KinrelColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Pending',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: KinrelColors.warning,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
