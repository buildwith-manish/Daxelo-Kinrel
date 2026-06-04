// lib/features/profile/presentation/sessions_screen.dart
//
// DAXELO KINREL — Active Sessions Screen
//
// Shows all active sessions for the current user with the
// ability to revoke individual sessions or sign out all
// other devices. Loads sessions from profileProvider.

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

class SessionsScreen extends ConsumerStatefulWidget {
  const SessionsScreen({super.key});

  @override
  ConsumerState<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends ConsumerState<SessionsScreen> {
  bool _isRevokingAll = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(profileProvider.notifier).loadSessions();
    });
  }

  IconData _deviceIcon(String deviceType) {
    switch (deviceType.toLowerCase()) {
      case 'mobile':
      case 'phone':
      case 'ios':
      case 'android':
        return Icons.phone_android;
      case 'desktop':
      case 'macos':
      case 'windows':
      case 'linux':
        return Icons.computer;
      case 'web':
        return Icons.language;
      default:
        return Icons.devices;
    }
  }

  String _relativeTime(DateTime lastActive) {
    final now = DateTime.now();
    final diff = now.difference(lastActive);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${lastActive.day}/${lastActive.month}/${lastActive.year}';
  }

  Future<void> _revokeSession(String sessionId) async {
    final success = await ref
        .read(profileProvider.notifier)
        .revokeSession(sessionId);

    if (!mounted) return;

    if (success) {
      context.showSnackBar('Session revoked');
    } else {
      context.showSnackBar('Failed to revoke session', isError: true);
    }
  }

  Future<void> _revokeAllOtherSessions() async {
    setState(() => _isRevokingAll = true);

    final success = await ref
        .read(profileProvider.notifier)
        .revokeAllOtherSessions();

    if (!mounted) return;

    setState(() => _isRevokingAll = false);

    if (success) {
      context.showSnackBar('All other sessions have been signed out');
    } else {
      context.showSnackBar('Failed to sign out other devices', isError: true);
    }
  }

  void _showRevokeAllConfirmDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: _borderSubtle),
        ),
        title: const Text(
          'Sign Out All Other Devices?',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
        content: const Text(
          'This will sign out all devices except the current one. You\'ll need to log in again on those devices.',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 14,
            color: _textSecondary,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: _textDim)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _revokeAllOtherSessions();
            },
            child: const Text(
              'Sign Out All',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profileState = ref.watch(profileProvider);
    final sessions = profileState.sessions;

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
          'Active Sessions',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: profileState.isLoading
                ? _buildShimmerList()
                : sessions.isEmpty
                ? _buildEmptyState()
                : _buildSessionList(sessions),
          ),

          // ── Sign Out All Other Devices Button ─────────────────────
          if (sessions.length > 1)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    onPressed: _isRevokingAll
                        ? null
                        : _showRevokeAllConfirmDialog,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(
                        color: Colors.redAccent,
                        width: 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      backgroundColor: Colors.redAccent.withValues(alpha: 0.08),
                    ),
                    child: _isRevokingAll
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.redAccent,
                              ),
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(
                                Icons.logout,
                                color: Colors.redAccent,
                                size: 18,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Sign Out All Other Devices',
                                style: TextStyle(
                                  fontFamily: KinrelTypography.bodyFont,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.redAccent,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Session List ─────────────────────────────────────────────────

  Widget _buildSessionList(List<SessionModel> sessions) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      itemCount: sessions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final session = sessions[index];
        return _SessionCard(
          session: session,
          deviceIcon: _deviceIcon(session.deviceType),
          relativeTime: _relativeTime(session.lastActiveAt),
          onRevoke: session.isCurrentDevice
              ? null
              : () => _revokeSession(session.id),
        );
      },
    );
  }

  // ── Empty State ──────────────────────────────────────────────────

  Widget _buildEmptyState() {
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
            child: const Icon(Icons.devices_outlined, color: _orange, size: 36),
          ),
          const SizedBox(height: 16),
          const Text(
            'No Active Sessions',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your active sessions will appear here',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              color: _textDim,
            ),
          ),
        ],
      ),
    );
  }

  // ── Shimmer Loading ──────────────────────────────────────────────

  Widget _buildShimmerList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
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
                      width: 120,
                      height: 14,
                      decoration: BoxDecoration(
                        color: _bg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 80,
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
// Session Card
// ═══════════════════════════════════════════════════════════════════════

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.deviceIcon,
    required this.relativeTime,
    this.onRevoke,
  });

  final SessionModel session;
  final IconData deviceIcon;
  final String relativeTime;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: session.isCurrentDevice
              ? _orange.withValues(alpha: 0.3)
              : _borderSubtle,
        ),
      ),
      child: Row(
        children: [
          // Device Icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(deviceIcon, color: _orange, size: 22),
          ),
          const SizedBox(width: 14),

          // Device info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        session.deviceName ?? 'Unknown Device',
                        style: const TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (session.isCurrentDevice) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: _orange, width: 1),
                        ),
                        child: const Text(
                          'This device',
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: _orange,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (session.location != null) ...[
                      Icon(
                        Icons.location_on_outlined,
                        color: _textDim,
                        size: 12,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        session.location!,
                        style: const TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 12,
                          color: _textDim,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Icon(Icons.schedule, color: _textDim, size: 12),
                    const SizedBox(width: 3),
                    Text(
                      relativeTime,
                      style: const TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        color: _textDim,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Revoke button
          if (onRevoke != null)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onRevoke,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Revoke',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.redAccent,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
