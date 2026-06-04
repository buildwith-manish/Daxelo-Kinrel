// lib/presentation/screens/debug/engagement_dashboard.dart
//
// DAXELO KINREL — Engagement Dashboard (P5 — Debug Only)
//
// Debug-only screen showing live local stats from Hive + Isar.
// Only accessible in dev flavor via /debug route.
// Shows: app opens, last open, graph views, members added,
// invite links sent, notifications, remote config, device tier,
// flavor, crashlytics/analytics status, premium, FCM token,
// referral code, and action buttons.
//
// DO NOT expose in production builds.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
// Hive removed — using Drift via IsarDatabase
import '../../../core/database/isar_database.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/config/app_environment.dart';
import '../../../core/services/retention_service.dart';
import '../../../core/services/premium_service.dart';
import '../../../core/services/remote_config_service.dart';
import '../../../core/services/local_notification_scheduler.dart';
import '../../../core/services/referral_service.dart';
import '../../../core/utils/device_tier.dart';
import '../../../core/networking/dio_client.dart';
import '../../../core/storage/secure_storage.dart';

class EngagementDashboard extends ConsumerStatefulWidget {
  const EngagementDashboard({super.key});

  @override
  ConsumerState<EngagementDashboard> createState() =>
      _EngagementDashboardState();
}

class _EngagementDashboardState extends ConsumerState<EngagementDashboard> {
  EngagementStats? _stats;
  bool _isPremium = false;
  String? _referralCode;
  String? _fcmTokenMasked;
  Map<String, dynamic>? _remoteConfigValues;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final stats = await RetentionService.getStats();
    final premium = await PremiumService.isPremium();
    final remoteConfig = RemoteConfigService.instance.getAllValues();

    // Get referral code (may fail if not authenticated)
    String? referralCode;
    try {
      final dio = ref.read(dioProvider);
      referralCode = await ReferralService.getCode(dio);
    } catch (_) {
      referralCode = 'N/A';
    }

    // Get masked FCM token
    String? fcmTokenMasked;
    try {
      // Try to get from secure storage or push notification service
      final storage = SecureStorageService();
      final token = await storage.getAccessToken();
      fcmTokenMasked = token != null
          ? '${token.substring(0, 6)}...${token.substring(token.length - 4)}'
          : 'Not available';
    } catch (_) {
      fcmTokenMasked = 'Error';
    }

    if (mounted) {
      setState(() {
        _stats = stats;
        _isPremium = premium;
        _referralCode = referralCode;
        _fcmTokenMasked = fcmTokenMasked;
        _remoteConfigValues = remoteConfig;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final env = AppEnvironmentConfig.current;
    final tier = DeviceTierCache.instance.tier;

    return Scaffold(
      backgroundColor: KinrelColors.darkBackground,
      appBar: AppBar(
        backgroundColor: KinrelColors.darkBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: KinrelColors.textWhite),
          onPressed: () => context.pop(),
        ),
        title: Row(
          children: [
            const Text(
              'Engagement Dashboard',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: KinrelColors.warning.withValues(alpha: 0.15),
              ),
              child: const Text(
                'DEBUG',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.warning,
                ),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: KinrelColors.orange,
          backgroundColor: KinrelColors.darkCard,
          onRefresh: _loadStats,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(
              horizontal: KinrelSpacing.base,
              vertical: KinrelSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Engagement Stats ────────────────────────────────
                _buildSectionTitle('Engagement Stats'),
                _buildStatsGrid(),

                const SizedBox(height: 20),

                // ── System Info ─────────────────────────────────────
                _buildSectionTitle('System Info'),
                _buildSystemInfoList(env, tier),

                const SizedBox(height: 20),

                // ── Remote Config ───────────────────────────────────
                _buildSectionTitle('Remote Config'),
                _buildRemoteConfigList(),

                const SizedBox(height: 20),

                // ── Debug Actions ───────────────────────────────────
                _buildSectionTitle('Debug Actions'),
                _buildActionButtons(),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // SECTION TITLE
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: KinrelTypography.displayFont,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: KinrelColors.orange,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // ENGAGEMENT STATS GRID
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildStatsGrid() {
    if (_stats == null) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            color: KinrelColors.orange,
            strokeWidth: 2,
          ),
        ),
      );
    }

    final items = [
      _StatItem('App Opens', '${_stats!.appOpens}', Icons.phone_android_rounded),
      _StatItem('Last Open', _formatDateTime(_stats!.lastOpenDateTime), Icons.access_time_rounded),
      _StatItem('Graph Views', '${_stats!.graphViews}', Icons.account_tree_rounded),
      _StatItem('Members Added', '${_stats!.membersAdded}', Icons.person_add_rounded),
      _StatItem('Invites Sent', '${_stats!.inviteLinksSent}', Icons.send_rounded),
    ];

    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.2,
      children: items.map((item) => _buildStatCard(item)).toList(),
    );
  }

  Widget _buildStatCard(_StatItem item) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
        border: Border.all(
          color: KinrelColors.darkSurface.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(item.icon, color: KinrelColors.orange, size: 14),
              const SizedBox(width: 6),
              Text(
                item.label,
                style: const TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 10,
                  color: KinrelColors.textDim,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            item.value,
            style: const TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // SYSTEM INFO LIST
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildSystemInfoList(AppEnvironment env, DeviceTier tier) {
    final isarReady = IsarDatabase.isInitialized;
    final rcInitialized = RemoteConfigService.instance.isInitialized;

    final items = [
      _InfoRow('Device Tier', tier.name),
      _InfoRow('Current Flavor', env.displayName),
      _InfoRow('Crashlytics Enabled', env.shouldReportCrashes.toString()),
      _InfoRow('Analytics Enabled', (!env.isDev).toString()),
      _InfoRow('Premium', _isPremium ? 'Yes' : 'No'),
      _InfoRow('FCM Token (masked)', _fcmTokenMasked ?? 'N/A'),
      _InfoRow('Referral Code', _referralCode ?? 'N/A'),
      _InfoRow('Isar DB', isarReady ? 'Initialized' : 'Not ready'),
      _InfoRow('Remote Config', rcInitialized ? 'Initialized' : 'Using defaults'),
      _InfoRow('Notifications Scheduled', 'Retention active'),
    ];

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
        border: Border.all(
          color: KinrelColors.darkSurface.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        children: items.map((item) => _buildInfoRow(item)).toList(),
      ),
    );
  }

  Widget _buildInfoRow(_InfoRow item) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Text(
            item.label,
            style: const TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              color: KinrelColors.textSilver,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              item.value,
              style: const TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 11,
                color: KinrelColors.textWhite,
              ),
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // REMOTE CONFIG LIST
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildRemoteConfigList() {
    if (_remoteConfigValues == null || _remoteConfigValues!.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'No remote config values loaded',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 12,
            color: KinrelColors.textDim,
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
        border: Border.all(
          color: KinrelColors.darkSurface.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        children: _remoteConfigValues!.entries.map((entry) {
          return _buildInfoRow(_InfoRow(entry.key, '${entry.value}'));
        }).toList(),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // ACTION BUTTONS
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildActionButtons() {
    return Column(
      children: [
        _buildActionButton(
          icon: Icons.restart_alt_rounded,
          label: 'Reset Onboarding',
          color: KinrelColors.warning,
          onTap: _resetOnboarding,
        ),
        const SizedBox(height: 8),
        _buildActionButton(
          icon: Icons.delete_sweep_rounded,
          label: 'Clear Hive',
          color: KinrelColors.error,
          onTap: _clearHive,
        ),
        const SizedBox(height: 8),
        _buildActionButton(
          icon: Icons.notifications_active_rounded,
          label: 'Trigger Test Notification',
          color: KinrelColors.info,
          onTap: _triggerTestNotification,
        ),
        const SizedBox(height: 8),
        _buildActionButton(
          icon: Icons.refresh_rounded,
          label: 'Refresh Stats',
          color: KinrelColors.success,
          onTap: _loadStats,
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 10),
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
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _resetOnboarding() async {
    try {
      final storage = SecureStorageService();
      await storage.setOnboardingComplete(false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Onboarding reset ✅'),
            backgroundColor: KinrelColors.success,
          ),
        );
      }
    } catch (e) {
      _showError('Failed to reset onboarding: $e');
    }
  }

  Future<void> _clearHive() async {
    try {
      await RetentionService.clearAll();
      await _loadStats();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hive engagement data cleared 🗑️'),
            backgroundColor: KinrelColors.success,
          ),
        );
      }
    } catch (e) {
      _showError('Failed to clear Hive: $e');
    }
  }

  Future<void> _triggerTestNotification() async {
    try {
      await LocalNotificationScheduler.showTestNotification();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Test notification sent 🔔'),
            backgroundColor: KinrelColors.info,
          ),
        );
      }
    } catch (e) {
      _showError('Failed to trigger notification: $e');
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: KinrelColors.error,
        ),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return 'Never';
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

// ═══════════════════════════════════════════════════════════════════════
// HELPER CLASSES
// ═══════════════════════════════════════════════════════════════════════

class _StatItem {
  const _StatItem(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;
}

class _InfoRow {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;
}
