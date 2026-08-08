import 'package:kinrel/core/widgets/global_error_widget.dart';
// lib/features/notifications/presentation/notifications_screen.dart
//
// DAXELO KINREL — Notifications / Alerts Screen
//
// Follows KINREL Global Top 1 Prompt specifications:
//   - Background: #13141E (KinrelColors.darkSurface)
//   - Header: "Notifications" in Heading Large, unread count badge (orange)
//   - Segmented Control: All | Family | Celebrations | System — orange active state
//   - Notification items with avatar/icon, title, body, time, unread dot
//   - Unread items have subtle orange tint (#E8612A05)
//   - Swipe left: Mark as read / Delete
//   - Swipe right: Pin
//   - Empty state: Bell illustration with K-graph animation
//
// Uses ConsumerStatefulWidget + Riverpod for state management.

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/family/family_provider.dart';
import '../../../shared/widgets/dk_components.dart';
import '../providers/notifications_provider.dart';
import '../../occasions/providers/occasion_reminders_provider.dart';
import '../../occasions/widgets/upcoming_occasions_row.dart';

// ═══════════════════════════════════════════════════════════════════════
// Screen
// ═══════════════════════════════════════════════════════════════════════

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final AnimationController _emptyAnimController;
  Timer? _refreshTimer;
  StreamSubscription? _realtimeSub;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _emptyAnimController = AnimationController(
      vsync: this,
      duration: KinrelMotion.ceremonial,
    )..repeat(reverse: true);

    // Load notifications on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationsProvider.notifier).loadNotifications();
      _setupRealtimeSubscription();
    });

    // v109: Refresh every 10 seconds for real-time timestamp updates.
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      ref.read(notificationsProvider.notifier).loadNotifications();
    });
  }

  /// v109.1: Subscribe to Supabase Realtime for the Notification table.
  /// When a new notification is INSERTED (e.g., a new invite is received,
  /// or an invite acceptance/rejection notification is created), the
  /// subscription fires and the notification list refreshes immediately —
  /// no polling delay, no page reload required.
  void _setupRealtimeSubscription() {
    try {
      final client = ref.read(supabaseProvider);
      if (client == null) return;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;

      _realtimeSub = client
          .channel('notifications_realtime')
          .onPostgresChangeEvent(
            PostgresChangeEvent.insert,
            schema: 'public',
            table: 'Notification',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'userId',
              value: userId,
            ),
            callback: (payload) {
              // New notification inserted — refresh immediately
              if (mounted) {
                ref.read(notificationsProvider.notifier).loadNotifications();
              }
            },
          )
          .onPostgresChangeEvent(
            PostgresChangeEvent.update,
            schema: 'public',
            table: 'Notification',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'userId',
              value: userId,
            ),
            callback: (payload) {
              // Notification updated (e.g., marked as read) — refresh
              if (mounted) {
                ref.read(notificationsProvider.notifier).loadNotifications();
              }
            },
          )
          .subscribe();
    } catch (e) {
      // Best-effort — polling timer still works as fallback
      debugPrint('⚠️ Realtime subscription failed: $e');
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _realtimeSub?.cancel();
    _emptyAnimController.dispose();
    super.dispose();
  }

  // ── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required by AutomaticKeepAliveClientMixin
    final notifState = ref.watch(notificationsProvider);
    final filtered = notifState.filtered;
    final unreadCount = notifState.unreadCount;

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      body: Column(
        children: [
          // ── Header ──────────────────────────────────────────────
          _buildHeader(unreadCount),

          // ── Segmented Control ───────────────────────────────────
          _buildSegmentedControl(notifState.selectedCategory),

          // ── Upcoming Occasions Preview ────────────────────────────
          Builder(builder: (context) {
            final occasionsAsync = ref.watch(occasionRemindersProvider);
            return occasionsAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (occasionsState) {
                final upcomingOccasions = occasionsState.withinSevenDays;
                if (upcomingOccasions.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: KinrelSpacing.base,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      UpcomingOccasionsRow(
                        occasions: upcomingOccasions,
                        showTitle: true,
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: () => context.push('/occasions'),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 8),
                            child: Text(
                              'See all',
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: KinrelColors.orange,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          }),

          // ── Mark all read ───────────────────────────────────────
          if (unreadCount > 0) _buildMarkAllRead(unreadCount),

          // ── Notification List / Empty State ─────────────────────
          Expanded(
            child: filtered.isEmpty
                ? RefreshIndicator(
                    color: KinrelColors.orange,
                    backgroundColor: KinrelColors.darkCard,
                    onRefresh: () => ref
                        .read(notificationsProvider.notifier)
                        .loadNotifications(),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.5,
                          child: _buildEmptyState(),
                        ),
                      ],
                    ),
                  )
                : _buildNotificationList(filtered),
          ),
        ],
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────

  Widget _buildHeader(int unreadCount) {
    return Padding(
      padding: EdgeInsets.only(
        left: KinrelSpacing.base,
        right: KinrelSpacing.base,
        top: KinrelSpacing.md,
        bottom: KinrelSpacing.sm,
      ),
      child: Row(
        children: [
          // Title
          Text(
            'Notifications',
            style: KinrelTypography.headlineLarge.copyWith(
              color: KinrelColors.textWhite,
            ),
          ),
          const SizedBox(width: KinrelSpacing.sm),

          // Unread badge
          if (unreadCount > 0)
            DKBadge(count: unreadCount, size: 22, color: KinrelColors.orange),

          const Spacer(),

          // Settings icon
          GestureDetector(
            onTap: () {
              // TODO: Navigate to notification settings
            },
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KinrelColors.darkElevated,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.settings_outlined,
                size: 20,
                color: KinrelColors.textSilver,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Segmented Control ───────────────────────────────────────────

  Widget _buildSegmentedControl(NotificationCategory? selected) {
    const segments = <_SegmentItem>[
      _SegmentItem(label: 'All', category: null),
      _SegmentItem(label: 'Family', category: NotificationCategory.family),
      _SegmentItem(
        label: 'Celebrations',
        category: NotificationCategory.celebrations,
      ),
      _SegmentItem(label: 'System', category: NotificationCategory.system),
    ];

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: KinrelSpacing.base,
        vertical: KinrelSpacing.sm,
      ),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(KinrelRadius.xl),
        ),
        child: Row(
          children: segments.map((seg) {
            final isActive = selected == seg.category;
            return Expanded(
              child: GestureDetector(
                onTap: () => ref
                    .read(notificationsProvider.notifier)
                    .setCategory(seg.category),
                child: AnimatedContainer(
                  duration: KinrelMotion.fast,
                  curve: KinrelMotion.easeOut,
                  margin: EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: isActive ? KinrelColors.orange : Colors.transparent,
                    borderRadius: BorderRadius.circular(KinrelRadius.lg),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    seg.label,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                      color: isActive ? Colors.white : KinrelColors.textSilver,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── Mark All Read ───────────────────────────────────────────────

  Widget _buildMarkAllRead(int unreadCount) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: KinrelSpacing.base,
        vertical: KinrelSpacing.xs,
      ),
      child: Align(
        alignment: Alignment.centerRight,
        child: GestureDetector(
          onTap: () => ref.read(notificationsProvider.notifier).markAllRead(),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Text(
              'Mark all as read',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: KinrelColors.orange,
                height: 1.4,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Notification List ───────────────────────────────────────────

  Widget _buildNotificationList(List<NotificationModel> notifications) {
    return RefreshIndicator(
      color: KinrelColors.orange,
      backgroundColor: KinrelColors.darkCard,
      onRefresh: () =>
          ref.read(notificationsProvider.notifier).loadNotifications(),
      child: ListView.builder(
        scrollCacheExtent: ScrollCacheExtent.pixels(500),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(
          horizontal: KinrelSpacing.base,
          vertical: KinrelSpacing.sm,
        ),
        itemCount: notifications.length,
        itemBuilder: (context, index) {
          final notification = notifications[index];
          return _NotificationItem(
            key: ValueKey(notification.id),
            notification: notification,
            onMarkRead: () => ref
                .read(notificationsProvider.notifier)
                .markAsRead(notification.id),
            onDelete: () => ref
                .read(notificationsProvider.notifier)
                .deleteNotification(notification.id),
            onPin: () => ref
                .read(notificationsProvider.notifier)
                .pinNotification(notification.id),
          );
        },
      ),
    );
  }

  // ── Empty State ─────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Bell illustration with K-graph animation
          KinrelAnimatedBuilder(
            animation: _emptyAnimController,
            builder: (context, child) {
              final t = _emptyAnimController.value;
              final scale = 1.0 + 0.05 * sin(t * 2 * pi);
              final glowAlpha = 0.12 + 0.06 * sin(t * 2 * pi);

              return Transform.scale(
                scale: scale,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: KinrelColors.orange.withValues(alpha: 0.1),
                    boxShadow: [
                      BoxShadow(
                        color: KinrelColors.orange.withValues(alpha: glowAlpha),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // K-graph nodes animation
                      ..._buildKGraphNodes(t),
                      // Bell icon
                      Icon(
                        Icons.notifications_none_rounded,
                        size: 44,
                        color: KinrelColors.orange.withValues(alpha: 0.8),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: KinrelSpacing.xl),

          Text(
            'All caught up!',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite,
              height: 1.3,
            ),
          ),
          const SizedBox(height: KinrelSpacing.sm),

          Text(
            'No new notifications.',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: KinrelColors.textSilver,
              height: 1.5,
            ),
          ),
          const SizedBox(height: KinrelSpacing.xxxl),
        ],
      ),
    );
  }

  /// Subtle animated K-graph nodes around the bell icon.
  List<Widget> _buildKGraphNodes(double t) {
    const nodeCount = 5;
    const radius = 36.0;
    final nodes = <Widget>[];

    for (int i = 0; i < nodeCount; i++) {
      final angle = (i / nodeCount) * 2 * pi + t * 0.5;
      final x = radius * cos(angle);
      final y = radius * sin(angle);
      final opacity = 0.3 + 0.2 * sin(t * 2 * pi + i);

      nodes.add(
        Positioned(
          left: 50 + x - 3,
          top: 50 + y - 3,
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: KinrelColors.orange.withValues(alpha: opacity),
            ),
          ),
        ),
      );

      // Connecting line to center
      nodes.add(
        Positioned(
          left: 50 + x * 0.5 - 1,
          top: 50 + y * 0.5 - 0.5,
          child: Container(
            width: max(1.0, (x * 0.5).abs()),
            height: 1,
            color: KinrelColors.orange.withValues(alpha: opacity * 0.5),
          ),
        ),
      );
    }
    return nodes;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Segment Item (private)
// ═══════════════════════════════════════════════════════════════════════

class _SegmentItem {
  const _SegmentItem({required this.label, required this.category});

  final String label;
  final NotificationCategory? category;
}

// ═══════════════════════════════════════════════════════════════════════
// Notification Item Widget
// ═══════════════════════════════════════════════════════════════════════

class _NotificationItem extends ConsumerWidget {
  const _NotificationItem({
    super.key,
    required this.notification,
    required this.onMarkRead,
    required this.onDelete,
    required this.onPin,
  });

  final NotificationModel notification;
  final VoidCallback onMarkRead;
  final VoidCallback onDelete;
  final VoidCallback onPin;

  // v109: Accept a family invite — calls fn_accept_family_invite RPC
  // which inserts a FamilyMember row + marks the notification as read.
  Future<void> _acceptInvite(BuildContext context, WidgetRef ref) async {
    final familyId = notification.familyId;
    if (familyId == null || familyId.isEmpty) return;

    // Extract inviter user ID from the actionUrl if available
    // (the RPC stores it in the notification's actionUrl as the invite URL)
    String? inviterUserId;
    try {
      final client = ref.read(supabaseProvider);
      inviterUserId = client?.auth.currentUser?.id;
    } catch (_) {}

    try {
      final client = ref.read(supabaseProvider);
      if (client == null) return;

      // Extract family name from the notification body
      final familyName = notification.body.contains('join ')
          ? notification.body.split('join ').last
          : 'the family';

      final response = await client.rpc(
        'fn_accept_family_invite',
        params: {
          'p_family_id': familyId,
          'p_family_name': familyName,
          'p_inviter_user_id': null, // The RPC handles this
        },
      ).timeout(const Duration(seconds: 10));

      final result = response as Map<String, dynamic>?;
      final success = result?['success'] as bool? ?? false;

      if (success) {
        // Refresh notifications + family data
        ref.read(notificationsProvider.notifier).loadNotifications();
        // v109: Invalidate family providers so the member count updates
        // immediately on the family detail screen + family list.
        try {
          ref.invalidate(familyListProvider);
          ref.invalidate(familyDetailProvider(familyId));
          ref.invalidate(familyMembersProvider(familyId));
        } catch (_) {}
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result?['message'] as String? ??
                  'Successfully joined the family'),
              backgroundColor: KinrelColors.success,
            ),
          );
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result?['message'] as String? ??
                  'Could not accept invitation. Please try again.'),
              backgroundColor: KinrelColors.error,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        // v109: Never show database/PostgreSQL errors to users.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not accept invitation. Please try again.'),
            backgroundColor: KinrelColors.error,
          ),
        );
      }
    }
  }

  // v109: Reject a family invite — calls fn_reject_family_invite RPC
  // which marks the notification as read + sets actionUrl to 'rejected:familyId'.
  Future<void> _rejectInvite(BuildContext context, WidgetRef ref) async {
    final familyId = notification.familyId;
    if (familyId == null || familyId.isEmpty) return;

    try {
      final client = ref.read(supabaseProvider);
      if (client == null) return;

      final response = await client.rpc(
        'fn_reject_family_invite',
        params: {
          'p_family_id': familyId,
          'p_inviter_user_id': null,
        },
      ).timeout(const Duration(seconds: 10));

      final result = response as Map<String, dynamic>?;
      final success = result?['success'] as bool? ?? false;

      if (success) {
        ref.read(notificationsProvider.notifier).loadNotifications();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invitation rejected'),
              backgroundColor: KinrelColors.darkCard,
            ),
          );
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not reject invitation. Please try again.'),
              backgroundColor: KinrelColors.error,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not reject invitation. Please try again.'),
            backgroundColor: KinrelColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ── Dismissible for swipe actions ─────────────────────────────
    return Dismissible(
      key: ValueKey(notification.id),
      direction: DismissDirection.horizontal,

      // Swipe left → Mark as read / Delete
      background: _buildSwipeRightBackground(),

      // Swipe right → Pin
      secondaryBackground: _buildSwipeLeftBackground(),

      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          // Swipe right → Pin
          onPin();
          return false; // Don't dismiss, just toggle pin
        } else {
          // Swipe left → Show action sheet
          final action = await _showSwipeActionSheet(context);
          if (action == _SwipeAction.markRead) {
            onMarkRead();
            return false;
          } else if (action == _SwipeAction.delete) {
            return true; // Dismiss and delete
          }
          return false;
        }
      },
      onDismissed: (_) => onDelete(),

      child: Container(
        margin: EdgeInsets.only(bottom: KinrelSpacing.sm),
        padding: EdgeInsets.all(KinrelSpacing.md),
        decoration: BoxDecoration(
          // Unread items get subtle orange tint: #E8612A05
          color: notification.isRead
              ? KinrelColors.darkCard
              : const Color(0x05E8612A),
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
          border: Border.all(
            color: notification.isPinned
                ? KinrelColors.orange.withValues(alpha: 0.3)
                : const Color(0xFF3A3A4A),
            width: notification.isPinned ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Left: Avatar or Icon ────────────────────────────
            _buildLeading(),

            const SizedBox(width: KinrelSpacing.md),

            // ── Center: Title + Body + Time ─────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category tag + pin indicator
                  Row(
                    children: [
                      _CategoryTag(category: notification.category),
                      if (notification.isPinned) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.push_pin,
                          size: 12,
                          color: KinrelColors.orange.withValues(alpha: 0.7),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Title — Bold, white, 14px
                  Text(
                    notification.title,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      fontWeight: notification.isRead
                          ? FontWeight.w500
                          : FontWeight.w700,
                      color: KinrelColors.textWhite,
                      height: 1.35,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),

                  // Body — Regular, #C9B4A8, 12px
                  Text(
                    notification.body,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: KinrelColors.textSilver,
                      height: 1.45,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),

                  // Time — #8A7A72, 11px
                  Text(
                    notification.time,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: KinrelColors.textDim,
                      height: 1.4,
                    ),
                  ),

                  // v109: Accept/Reject buttons for family invite notifications
                  // that haven't been acted on yet.
                  if (notification.notificationType ==
                          NotificationType.familyInvite &&
                      !notification.isInviteActedUpon) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        // Accept button
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => _acceptInvite(context, ref),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: KinrelColors.orange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              elevation: 0,
                            ),
                            child: const Text(
                              'Accept',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Reject button
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _rejectInvite(context, ref),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: KinrelColors.textSilver,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              side: BorderSide(
                                color: KinrelColors.border,
                                width: 1,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              'Reject',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  // v109.1: Show status badge if the invite was already acted on.
                  // The RPC updates the notification's body to "You joined X"
                  // (accept) or "You declined the invitation" (reject), so the
                  // body itself shows the post-action status. This badge is a
                  // compact visual indicator.
                  if (notification.notificationType ==
                          NotificationType.familyInvite &&
                      notification.isInviteActedUpon) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: notification.isInviteRejected
                            ? Colors.red.withValues(alpha: 0.12)
                            : KinrelColors.orange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            notification.isInviteRejected
                                ? Icons.close_rounded
                                : Icons.check_circle_rounded,
                            size: 12,
                            color: notification.isInviteRejected
                                ? Colors.red.shade400
                                : KinrelColors.orange,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            notification.isInviteRejected
                                ? 'Invitation declined'
                                : 'Invitation accepted',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: notification.isInviteRejected
                                  ? Colors.red.shade400
                                  : KinrelColors.orange,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ── Right: Unread dot ───────────────────────────────
            if (!notification.isRead)
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 4),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: KinrelColors.orange,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Leading: Avatar or Icon ─────────────────────────────────────

  Widget _buildLeading() {
    if (notification.avatarInitials != null) {
      // Person avatar (40px)
      final color = notification.avatarColor != null
          ? Color(notification.avatarColor!)
          : KinrelColors.orange;
      return DKAvatar(
        size: DKAvatarSize.md, // 40px
        initials: notification.avatarInitials,
        backgroundColor: color.withValues(alpha: 0.25),
        borderColor: color.withValues(alpha: 0.5),
      );
    }

    // System / engagement icon
    final icon = notification.iconData ?? Icons.notifications;

    final iconColor = _categoryIconColor(notification.category);
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: iconColor.withValues(alpha: 0.15),
        border: Border.all(color: iconColor.withValues(alpha: 0.3), width: 1),
      ),
      child: Icon(icon, size: 20, color: iconColor),
    );
  }

  Color _categoryIconColor(NotificationCategory category) {
    switch (category) {
      case NotificationCategory.engagement:
        return KinrelColors.amber;
      case NotificationCategory.system:
        return KinrelColors.textSilver;
      case NotificationCategory.family:
        return KinrelColors.orange;
      case NotificationCategory.celebrations:
        return KinrelColors.gold;
    }
  }

  // ── Swipe Backgrounds ───────────────────────────────────────────

  /// Swipe right → Pin (green background on left side)
  Widget _buildSwipeRightBackground() {
    return Container(
      margin: EdgeInsets.only(bottom: KinrelSpacing.sm),
      decoration: BoxDecoration(
        color: KinrelColors.gold.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
      ),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            notification.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
            color: KinrelColors.gold,
            size: 22,
          ),
          const SizedBox(height: 2),
          Text(
            notification.isPinned ? 'Unpin' : 'Pin',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: KinrelColors.gold,
            ),
          ),
        ],
      ),
    );
  }

  /// Swipe left → Mark as read / Delete (red background on right side)
  Widget _buildSwipeLeftBackground() {
    return Container(
      margin: EdgeInsets.only(bottom: KinrelSpacing.sm),
      decoration: BoxDecoration(
        color: KinrelColors.error.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            notification.isRead ? Icons.delete_outline : Icons.done,
            color: notification.isRead
                ? KinrelColors.error
                : KinrelColors.success,
            size: 22,
          ),
          const SizedBox(height: 2),
          Text(
            notification.isRead ? 'Delete' : 'Read',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: notification.isRead
                  ? KinrelColors.error
                  : KinrelColors.success,
            ),
          ),
        ],
      ),
    );
  }

  // ── Action Sheet ────────────────────────────────────────────────

  Future<_SwipeAction?> _showSwipeActionSheet(BuildContext context) async {
    return showModalBottomSheet<_SwipeAction>(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.xxl),
        ),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF3A3A4A),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              if (!notification.isRead)
                ListTile(
                  leading: Icon(
                    Icons.done_rounded,
                    color: KinrelColors.success,
                  ),
                  title: Text(
                    'Mark as read',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                  onTap: () => Navigator.pop(context, _SwipeAction.markRead),
                ),

              ListTile(
                leading: Icon(Icons.delete_outline, color: KinrelColors.error),
                title: Text(
                  'Delete',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    color: KinrelColors.textWhite,
                  ),
                ),
                onTap: () => Navigator.pop(context, _SwipeAction.delete),
              ),

              ListTile(
                leading: Icon(Icons.close, color: KinrelColors.textDim),
                title: Text(
                  'Cancel',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    color: KinrelColors.textSilver,
                  ),
                ),
                onTap: () => Navigator.pop(context),
              ),

              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Category Tag
// ═══════════════════════════════════════════════════════════════════════

class _CategoryTag extends StatelessWidget {
  const _CategoryTag({required this.category});

  final NotificationCategory category;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (category) {
      NotificationCategory.family => ('Family', KinrelColors.orange),
      NotificationCategory.celebrations => ('Celebrations', KinrelColors.gold),
      NotificationCategory.engagement => ('Engagement', KinrelColors.amber),
      NotificationCategory.system => ('System', KinrelColors.textDim),
    };

    return Container(
      padding: EdgeInsets.symmetric(horizontal: KinrelSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(KinrelRadius.xs),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: KinrelTypography.monoFont,
          fontSize: 9,
          fontWeight: FontWeight.w500,
          color: color,
          height: 1.3,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Swipe Action Enum
// ═══════════════════════════════════════════════════════════════════════

enum _SwipeAction { markRead, delete }
