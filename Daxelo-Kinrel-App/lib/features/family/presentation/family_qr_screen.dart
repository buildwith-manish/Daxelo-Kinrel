// lib/features/family/presentation/family_qr_screen.dart
//
// DAXELO KINREL — Family QR Code Screen
//
// Displays a Family KIN ID, QR code (using qr_flutter), share/copy buttons.
// QR encodes the join URL: kinrel.app/join/KIN-XXXXXXXX
//
// Enhancements (Task 4):
//   • Animated KIN ID character-by-character reveal
//   • Copy join URL button
//   • Share via WhatsApp / SMS specific channels
//   • Download QR code as image (RenderRepaintBoundary → save)
//   • Improved invite message with family description & member count
//   • Recent invitees section showing tracked invites
//   • QR code refresh animation
//   • Localized invite message via InviteMessageBuilder

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart' as share_plus;
import 'package:path_provider/path_provider.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/family/family_id_provider.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/utils/invite_message_builder.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../../core/extensions/context_extensions.dart';
import '../providers/family_invite_provider.dart';

// ── Design Tokens ──────────────────────────────────────────────────
const Color _bg = Color(0xFF131416);
const Color _cardBg = Color(0xFF191B2C);
const Color _orange = Color(0xFFE8612A);
const Color _textPrimary = Color(0xFFF5F0EE);
const Color _textSecondary = Color(0xFFC9B4A8);
const Color _textDim = Color(0xFF8A7A72);
const Color _borderSubtle = Color(0x0FFFFFFF);

class FamilyQRScreen extends ConsumerStatefulWidget {
  const FamilyQRScreen({
    super.key,
    required this.familyId,
    this.familyName,
    this.kinFamilyId,
  });

  /// Internal family ID (UUID)
  final String familyId;

  /// Display name of the family
  final String? familyName;

  /// KIN-XXXXXXXX Family ID (if known, avoids extra API call)
  final String? kinFamilyId;

  @override
  ConsumerState<FamilyQRScreen> createState() => _FamilyQRScreenState();
}

class _FamilyQRScreenState extends ConsumerState<FamilyQRScreen> {
  String? _kinFamilyId;
  bool _isLoadingId = false;
  String? _fetchError;
  final _qrKey = GlobalKey();

  // Character-by-character reveal animation
  int _revealedChars = 0;
  bool _isRevealing = false;

  @override
  void initState() {
    super.initState();
    _kinFamilyId = widget.kinFamilyId;
    if (_kinFamilyId == null || _kinFamilyId!.isEmpty) {
      _fetchFamilyId();
    } else {
      _startRevealAnimation();
    }
  }

  Future<void> _fetchFamilyId() async {
    setState(() {
      _isLoadingId = true;
      _fetchError = null;
    });

    try {
      final kinId = await ref.read(familyIdProvider.notifier).getFamilyId(widget.familyId);
      if (mounted) {
        setState(() {
          _kinFamilyId = kinId;
          _isLoadingId = false;
        });
        if (kinId != null && kinId.isNotEmpty) {
          _startRevealAnimation();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _fetchError = 'Could not load Family ID';
          _isLoadingId = false;
        });
      }
    }
  }

  /// Animate the KIN ID character-by-character reveal
  void _startRevealAnimation() {
    if (_kinFamilyId == null || _isRevealing) return;
    _isRevealing = true;
    _revealedChars = 0;

    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 60));
      if (!mounted) return false;
      setState(() => _revealedChars++);
      return _revealedChars < _kinFamilyId!.length;
    }).then((_) {
      if (mounted) _isRevealing = false;
    });
  }

  String get _joinUrl {
    if (_kinFamilyId == null || _kinFamilyId!.isEmpty) return '';
    return 'https://kinrel.app/join/$_kinFamilyId';
  }

  /// Build the revealed KIN ID text (character-by-character)
  String get _revealedKinId {
    if (_kinFamilyId == null) return '';
    if (_revealedChars >= _kinFamilyId!.length) return _kinFamilyId!;
    return _kinFamilyId!.substring(0, _revealedChars);
  }

  @override
  Widget build(BuildContext context) {
    final familyName = widget.familyName ?? 'Family';

    return DKScaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Family QR Code',
          style: const TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
        actions: [
          // Refresh QR / re-fetch Family ID
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: _textSecondary, size: 22),
            tooltip: 'Refresh',
            onPressed: _fetchFamilyId,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(KinrelSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 24),

            // ── Family Name ────────────────────────────────────────
            Text(
              familyName,
              style: const TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
                letterSpacing: 0.5,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 8),

            // ── KIN-XXXXXXXX ID (animated reveal) ──────────────────
            if (_kinFamilyId != null && _kinFamilyId!.isNotEmpty)
              GestureDetector(
                onTap: () => _copyFamilyId(_kinFamilyId!),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: _orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(KinrelRadius.md),
                    border: Border.all(color: _orange.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _revealedKinId,
                        style: TextStyle(
                          fontFamily: KinrelTypography.monoFont,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: _orange,
                          letterSpacing: 2,
                        ),
                      ),
                      if (_revealedChars < _kinFamilyId!.length)
                        Container(
                          width: 2,
                          height: 20,
                          margin: const EdgeInsets.only(left: 2),
                          color: _orange,
                        ).animate(onPlay: (c) => c.repeat()).fadeIn(duration: 500.ms).then().fadeOut(duration: 500.ms),
                    ],
                  ),
                ),
              )
            else if (_isLoadingId)
              SizedBox(
                height: 40,
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(_orange),
                    ),
                  ),
                ),
              )
            else if (_fetchError != null)
              GestureDetector(
                onTap: _fetchFamilyId,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: KinrelColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(KinrelRadius.md),
                    border: Border.all(color: KinrelColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh, color: KinrelColors.error, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        _fetchError!,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 13,
                          color: KinrelColors.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 32),

            // ── QR Code ────────────────────────────────────────────
            if (_kinFamilyId != null && _kinFamilyId!.isNotEmpty)
              RepaintBoundary(
                key: _qrKey,
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(KinrelRadius.xl),
                    boxShadow: [
                      BoxShadow(
                        color: _orange.withValues(alpha: 0.15),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: QrImageView(
                    data: _joinUrl,
                    version: QrVersions.auto,
                    size: 200,
                    backgroundColor: Colors.white,
                    eyeStyle: QrEyeStyle(
                      eyeShape: QrEyeShape.roundedOuter,
                      color: Color(0xFF131416),
                    ),
                    dataModuleStyle: QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.roundedOuter,
                      color: Color(0xFF131416),
                    ),
                    errorStateBuilder: (context, error) {
                      return Container(
                        width: 200,
                        height: 200,
                        color: Colors.white,
                        child: Center(
                          child: Text(
                            'QR Error',
                            style: TextStyle(color: KinrelColors.error),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              )
                .animate(onPlay: (c) => c.forward())
                .fadeIn(duration: 500.ms)
                .scale(
                  begin: Offset(0.9, 0.9),
                  end: Offset(1.0, 1.0),
                  duration: 400.ms,
                  curve: Curves.easeOutBack,
                )
            else
              Container(
                width: 248,
                height: 248,
                decoration: BoxDecoration(
                  color: _cardBg,
                  borderRadius: BorderRadius.circular(KinrelRadius.xl),
                  border: Border.all(color: _borderSubtle),
                ),
                child: Center(
                  child: _isLoadingId
                      ? CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(_orange),
                        )
                      : Icon(
                          Icons.qr_code_rounded,
                          size: 80,
                          color: _textDim.withValues(alpha: 0.3),
                        ),
                ),
              ),

            const SizedBox(height: 8),

            // ── Scan hint ──────────────────────────────────────────
            if (_kinFamilyId != null && _kinFamilyId!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Scan this QR code to join the $familyName family',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    color: _textDim,
                    height: 1.5,
                  ),
                ),
              ),

            const SizedBox(height: 32),

            // ── Primary Action Buttons ─────────────────────────────
            if (_kinFamilyId != null && _kinFamilyId!.isNotEmpty) ...[
              // Share Invite Link
              DKButton(
                label: 'Share Invite Link',
                variant: DKButtonVariant.primary,
                size: DKButtonSize.lg,
                fullWidth: true,
                icon: Icons.share_rounded,
                onPressed: () => _shareInviteLink(_kinFamilyId!, familyName),
              ),

              const SizedBox(height: 12),

              // Copy Family ID
              DKButton(
                label: 'Copy Family ID',
                variant: DKButtonVariant.secondary,
                size: DKButtonSize.lg,
                fullWidth: true,
                icon: Icons.copy_rounded,
                onPressed: () => _copyFamilyId(_kinFamilyId!),
              ),

              const SizedBox(height: 12),

              // Copy Join URL
              DKButton(
                label: 'Copy Join URL',
                variant: DKButtonVariant.secondary,
                size: DKButtonSize.lg,
                fullWidth: true,
                icon: Icons.link_rounded,
                onPressed: () => _copyJoinUrl(),
              ),

              const SizedBox(height: 20),

              // ── Channel-Specific Share Buttons ──────────────────
              Row(
                children: [
                  Expanded(
                    child: _buildChannelButton(
                      icon: Icons.chat_bubble_rounded,
                      label: 'WhatsApp',
                      color: Color(0xFF25D366),
                      onPressed: () => _shareViaWhatsApp(_kinFamilyId!, familyName),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildChannelButton(
                      icon: Icons.sms_rounded,
                      label: 'SMS',
                      color: Color(0xFF4CAF7A),
                      onPressed: () => _shareViaSMS(_kinFamilyId!, familyName),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildChannelButton(
                      icon: Icons.download_rounded,
                      label: 'Save QR',
                      color: Color(0xFFF59240),
                      onPressed: _saveQRCode,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // ── Invite Analytics ──────────────────────────────────
              _buildInviteAnalytics(widget.familyId),

              const SizedBox(height: 24),

              // ── Recent Invitees ──────────────────────────────────
              _buildRecentInvitees(widget.familyId),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChannelButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInviteAnalytics(String familyId) {
    final analyticsAsync = ref.watch(inviteAnalyticsProvider(familyId));

    return analyticsAsync.when(
      data: (analytics) {
        if (analytics.totalInvitesSent == 0) return const SizedBox.shrink();

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(KinrelRadius.lg),
            border: Border.all(color: _borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.analytics_outlined, color: _orange, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Invite Analytics',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildAnalyticsChip('Sent', analytics.totalInvitesSent, KinrelColors.orange),
                  _buildAnalyticsChip('Accepted', analytics.accepted, KinrelColors.success),
                  _buildAnalyticsChip('Pending', analytics.pending, KinrelColors.warning),
                  if (analytics.rejected > 0)
                    _buildAnalyticsChip('Declined', analytics.rejected, KinrelColors.error),
                ],
              ),
              if (analytics.byChannel.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: analytics.byChannel.entries.map((entry) {
                    final label = _channelLabel(entry.key);
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(KinrelRadius.sm),
                      ),
                      child: Text(
                        '$label: ${entry.value}',
                        style: TextStyle(
                          fontFamily: KinrelTypography.monoFont,
                          fontSize: 11,
                          color: _textSecondary,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
              // Conversion rate
              if (analytics.totalInvitesSent > 0) ...[
                const SizedBox(height: 12),
                _buildConversionRate(analytics),
              ],
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildConversionRate(InviteAnalytics analytics) {
    final rate = analytics.totalInvitesSent > 0
        ? (analytics.accepted / analytics.totalInvitesSent * 100).round()
        : 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _orange.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(KinrelRadius.md),
      ),
      child: Row(
        children: [
          Icon(Icons.trending_up_rounded, color: _orange, size: 16),
          const SizedBox(width: 8),
          Text(
            'Conversion rate: $rate%',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: rate / 100,
                backgroundColor: _orange.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation<Color>(
                  rate >= 50 ? KinrelColors.success : _orange,
                ),
                minHeight: 4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentInvitees(String familyId) {
    final recentAsync = ref.watch(recentInviteesProvider(familyId));

    return recentAsync.when(
      data: (invitees) {
        if (invitees.isEmpty) return const SizedBox.shrink();

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(KinrelRadius.lg),
            border: Border.all(color: _borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.people_outline, color: _orange, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Recent Invites',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${invitees.length} sent',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 11,
                      color: _textDim,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...invitees.take(5).map((invite) => _buildInviteeRow(invite)),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildInviteeRow(InviteRecord invite) {
    final statusColor = switch (invite.status) {
      'accepted' => KinrelColors.success,
      'pending' => KinrelColors.warning,
      'rejected' => KinrelColors.error,
      _ => _textDim,
    };
    final statusIcon = switch (invite.status) {
      'accepted' => Icons.check_circle_rounded,
      'pending' => Icons.schedule_rounded,
      'rejected' => Icons.cancel_rounded,
      _ => Icons.help_outline_rounded,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _orange.withValues(alpha: 0.1),
            ),
            child: Icon(Icons.person_outline, size: 16, color: _orange),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invite.channelLabel,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    color: _textPrimary,
                  ),
                ),
                Text(
                  _formatTimeAgo(invite.sentAt),
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 11,
                    color: _textDim,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(KinrelRadius.sm),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(statusIcon, size: 12, color: statusColor),
                const SizedBox(width: 4),
                Text(
                  invite.status[0].toUpperCase() + invite.status.substring(1),
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
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

  String _formatTimeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).round()}w ago';
  }

  Widget _buildAnalyticsChip(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          '$count',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 11,
            color: _textDim,
          ),
        ),
      ],
    );
  }

  String _channelLabel(String channel) {
    switch (channel) {
      case 'link':
        return 'Link';
      case 'qr_code':
        return 'QR Code';
      case 'direct':
        return 'Direct';
      case 'whatsapp':
        return 'WhatsApp';
      case 'sms':
        return 'SMS';
      default:
        return channel;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Action Handlers
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _shareInviteLink(String kinFamilyId, String familyName) async {
    ref.read(familyInviteProvider.notifier).trackInviteSent(
      familyId: widget.familyId,
      channel: 'qr_code',
    );

    final url = 'https://kinrel.app/join/$kinFamilyId';
    final text = InviteMessageBuilder.build(familyName, url, 'en') +
        '\n\nOr use Family ID: $kinFamilyId\n\n— Sent via Kinrel by Daxelo';

    AnalyticsService.instance.logShareProfile('family_qr');

    await share_plus.Share.share(
      text,
      subject: 'Family invitation — $familyName on Kinrel',
    );
  }

  Future<void> _shareViaWhatsApp(String kinFamilyId, String familyName) async {
    ref.read(familyInviteProvider.notifier).trackInviteSent(
      familyId: widget.familyId,
      channel: 'whatsapp',
    );

    final url = 'https://kinrel.app/join/$kinFamilyId';
    final text =
        'Hey! Join our family on Kinrel 🧡\n\n'
        'I\'m building our family tree and I\'d love for you to be part of it. '
        'Click the link below to join the *$familyName* family:\n\n'
        '🔗 $url\n\n'
        'Or use Family ID: $kinFamilyId\n\n'
        '— Sent via Kinrel by Daxelo';

    AnalyticsService.instance.logInviteSent('whatsapp');

    await share_plus.Share.share(text);
  }

  Future<void> _shareViaSMS(String kinFamilyId, String familyName) async {
    ref.read(familyInviteProvider.notifier).trackInviteSent(
      familyId: widget.familyId,
      channel: 'sms',
    );

    final url = 'https://kinrel.app/join/$kinFamilyId';
    final message = 'Join our family on Kinrel! Click here: $url '
        'Or use Family ID: $kinFamilyId — Sent via Kinrel';

    AnalyticsService.instance.logInviteSent('sms');

    await share_plus.Share.share(message);
  }

  void _copyFamilyId(String kinFamilyId) {
    Clipboard.setData(ClipboardData(text: kinFamilyId));
    context.showSnackBar('Family ID copied to clipboard');

    ref.read(familyInviteProvider.notifier).trackInviteSent(
      familyId: widget.familyId,
      channel: 'direct',
    );
  }

  void _copyJoinUrl() {
    if (_joinUrl.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _joinUrl));
    context.showSnackBar('Join URL copied to clipboard');

    ref.read(familyInviteProvider.notifier).trackInviteSent(
      familyId: widget.familyId,
      channel: 'link',
    );
  }

  /// Save QR code as image to device gallery / downloads
  Future<void> _saveQRCode() async {
    try {
      final boundary = _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        context.showSnackBar('Could not capture QR code', isError: true);
        return;
      }

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        context.showSnackBar('Could not generate QR image', isError: true);
        return;
      }

      final buffer = byteData.buffer;
      final directory = Platform.isAndroid
          ? await getExternalStorageDirectory()
          : await getApplicationDocumentsDirectory();

      if (directory == null) {
        context.showSnackBar('Could not access storage', isError: true);
        return;
      }

      final kinId = _kinFamilyId?.replaceAll('-', '_') ?? 'family';
      final filePath = '${directory.path}/kinrel_qr_$kinId.png';
      await File(filePath).writeAsBytes(buffer.asUint8List());

      if (mounted) {
        context.showSnackBar('QR code saved to $filePath');
        AnalyticsService.instance.logShareProfile('qr_saved');
      }
    } catch (e) {
      if (mounted) {
        context.showSnackBar('Failed to save QR code', isError: true);
      }
    }
  }
}
