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

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../shared/widgets/dk_components.dart';
import '../providers/notifications_provider.dart';

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
    with SingleTickerProviderStateMixin {
  late final AnimationController _emptyAnimController;

  @override
  void initState() {
    super.initState();
    _emptyAnimController = AnimationController(
      vsync: this,
      duration: KinrelMotion.ceremonial,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _emptyAnimController.dispose();
    super.dispose();
  }

  // ── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
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

          // ── Mark all read ───────────────────────────────────────
          if (unreadCount > 0) _buildMarkAllRead(unreadCount),

          // ── Notification List / Empty State ─────────────────────
          Expanded(
            child: filtered.isEmpty
                ? _buildEmptyState()
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
            DKBadge(
              count: unreadCount,
              size: 22,
              color: KinrelColors.orange,
            ),

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
          label: 'Celebrations', category: NotificationCategory.celebrations),
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
                    color: isActive
                        ? KinrelColors.orange
                        : Colors.transparent,
                    borderRadius:
                        BorderRadius.circular(KinrelRadius.lg),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    seg.label,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      fontWeight:
                          isActive ? FontWeight.w600 : FontWeight.w400,
                      color: isActive
                          ? Colors.white
                          : KinrelColors.textSilver,
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
          onTap: () =>
              ref.read(notificationsProvider.notifier).markAllRead(),
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
    return ListView.builder(
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
    );
  }

  // ── Empty State ─────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Bell illustration with K-graph animation
          AnimatedBuilder(
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
                        color: KinrelColors.orange
                            .withValues(alpha: glowAlpha),
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
  const _SegmentItem({
    required this.label,
    required this.category,
  });

  final String label;
  final NotificationCategory? category;
}

// ═══════════════════════════════════════════════════════════════════════
// Notification Item Widget
// ═══════════════════════════════════════════════════════════════════════

class _NotificationItem extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
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
        border: Border.all(
          color: iconColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Icon(
        icon,
        size: 20,
        color: iconColor,
      ),
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
            notification.isPinned
                ? Icons.push_pin
                : Icons.push_pin_outlined,
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
                  leading: Icon(Icons.done_rounded,
                      color: KinrelColors.success),
                  title: Text(
                    'Mark as read',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                  onTap: () =>
                      Navigator.pop(context, _SwipeAction.markRead),
                ),

              ListTile(
                leading:
                    Icon(Icons.delete_outline, color: KinrelColors.error),
                title: Text(
                  'Delete',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    color: KinrelColors.textWhite,
                  ),
                ),
                onTap: () =>
                    Navigator.pop(context, _SwipeAction.delete),
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
      NotificationCategory.celebrations =>
        ('Celebrations', KinrelColors.gold),
      NotificationCategory.engagement =>
        ('Engagement', KinrelColors.amber),
      NotificationCategory.system => ('System', KinrelColors.textDim),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: KinrelSpacing.sm,
        vertical: 2,
      ),
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
