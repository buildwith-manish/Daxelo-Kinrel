// lib/features/notifications/providers/notifications_provider.dart
//
// DAXELO KINREL — Notifications State Management
//
// Manages notification state using Riverpod StateNotifierProvider.
// Loads notifications from the backend API /api/notifications/v2 with
// polling-based real-time refresh every 30 seconds.
// Supports mark as read, mark all read, delete, and pin operations.
// Includes notification types, preferences, and grouping.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../../core/networking/dio_client.dart';
import '../../../core/services/supabase_service.dart';

// ═══════════════════════════════════════════════════════════════════════
// Notification Types
// ═══════════════════════════════════════════════════════════════════════

/// Typed notification categories for the app.
/// Each type maps to a specific user interaction or system event.
enum NotificationType {
  familyInvite,
  acceptedInvite,
  rejectedInvite,
  newMember,
  birthday,
  anniversary,
  relationshipUpdate,
  usernameChange,
  familyIdGenerated,
  memberJoined,
  familyCreated,
  inviteLinkReady,
  memberJoinedViaInvite,
}

/// Map from NotificationType to display-friendly label.
const Map<NotificationType, String> notificationTypeLabels = {
  NotificationType.familyInvite: 'Family Invite',
  NotificationType.acceptedInvite: 'Invite Accepted',
  NotificationType.rejectedInvite: 'Invite Rejected',
  NotificationType.newMember: 'New Member',
  NotificationType.birthday: 'Birthday',
  NotificationType.anniversary: 'Anniversary',
  NotificationType.relationshipUpdate: 'Relationship Update',
  NotificationType.usernameChange: 'Username Change',
  NotificationType.familyIdGenerated: 'Family ID Generated',
  NotificationType.memberJoined: 'Member Joined',
  NotificationType.familyCreated: 'Family',
  NotificationType.inviteLinkReady: 'Family',
  NotificationType.memberJoinedViaInvite: 'Family',
};

/// Map from NotificationType to NotificationCategory.
const Map<NotificationType, NotificationCategory> notificationTypeCategory = {
  NotificationType.familyInvite: NotificationCategory.family,
  NotificationType.acceptedInvite: NotificationCategory.family,
  NotificationType.rejectedInvite: NotificationCategory.family,
  NotificationType.newMember: NotificationCategory.family,
  NotificationType.birthday: NotificationCategory.celebrations,
  NotificationType.anniversary: NotificationCategory.celebrations,
  NotificationType.relationshipUpdate: NotificationCategory.family,
  NotificationType.usernameChange: NotificationCategory.system,
  NotificationType.familyIdGenerated: NotificationCategory.system,
  NotificationType.memberJoined: NotificationCategory.family,
  NotificationType.familyCreated: NotificationCategory.family,
  NotificationType.inviteLinkReady: NotificationCategory.family,
  NotificationType.memberJoinedViaInvite: NotificationCategory.family,
};

// ═══════════════════════════════════════════════════════════════════════
// Notification Preferences
// ═══════════════════════════════════════════════════════════════════════

/// Per-type notification preference.
class NotificationPreference {
  const NotificationPreference({
    this.push = true,
    this.inApp = true,
    this.email = false,
  });

  /// Whether to send push notifications for this type.
  final bool push;

  /// Whether to show in-app notifications for this type.
  final bool inApp;

  /// Whether to send email notifications for this type.
  final bool email;

  NotificationPreference copyWith({
    bool? push,
    bool? inApp,
    bool? email,
  }) {
    return NotificationPreference(
      push: push ?? this.push,
      inApp: inApp ?? this.inApp,
      email: email ?? this.email,
    );
  }

  factory NotificationPreference.fromJson(Map<String, dynamic> json) {
    return NotificationPreference(
      push: json['push'] as bool? ?? true,
      inApp: json['inApp'] as bool? ?? true,
      email: json['email'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'push': push,
        'inApp': inApp,
        'email': email,
      };
}

// ═══════════════════════════════════════════════════════════════════════
// Notification Grouping
// ═══════════════════════════════════════════════════════════════════════

/// A group of notifications keyed by familyId and type.
class NotificationGroup {
  const NotificationGroup({
    required this.familyId,
    required this.type,
    required this.notifications,
  });

  /// The family ID this group belongs to (empty string for non-family).
  final String familyId;

  /// The NotificationType for this group.
  final NotificationType type;

  /// The notifications in this group.
  final List<NotificationModel> notifications;

  /// Count of unread notifications in this group.
  int get unreadCount => notifications.where((n) => !n.isRead).length;

  /// The most recent notification in this group.
  NotificationModel get latest =>
      notifications.isNotEmpty ? notifications.first : throw StateError('Empty group');
}

// ═══════════════════════════════════════════════════════════════════════
// Models
// ═══════════════════════════════════════════════════════════════════════

/// Notification category — drives the segmented control filter.
enum NotificationCategory { family, celebrations, engagement, system }

/// A single notification item.
class NotificationModel {
  const NotificationModel({
    required this.id,
    required this.category,
    required this.title,
    required this.body,
    required this.time,
    this.isRead = false,
    this.isPinned = false,
    this.avatarInitials,
    this.avatarColor,
    this.iconData,
    this.notificationType,
    this.familyId,
  });

  /// Unique identifier.
  final String id;

  /// Category for filtering.
  final NotificationCategory category;

  /// Bold title line (14px, white).
  final String title;

  /// Body text (12px, #C9B4A8).
  final String body;

  /// Relative time string (11px, #8A7A72).
  final String time;

  /// Whether the notification has been read.
  final bool isRead;

  /// Whether the notification is pinned.
  final bool isPinned;

  /// Optional initials for person avatar (40px).
  /// When null, the notification uses a category icon instead.
  final String? avatarInitials;

  /// Background color for the avatar circle.
  final int? avatarColor;

  /// Icon for system / engagement notifications
  /// that don't have a person avatar.
  final IconData? iconData;

  /// The specific notification type (for grouping and preferences).
  final NotificationType? notificationType;

  /// The family ID this notification relates to (for grouping).
  final String? familyId;

  NotificationModel copyWith({bool? isRead, bool? isPinned}) {
    return NotificationModel(
      id: id,
      category: category,
      title: title,
      body: body,
      time: time,
      isRead: isRead ?? this.isRead,
      isPinned: isPinned ?? this.isPinned,
      avatarInitials: avatarInitials,
      avatarColor: avatarColor,
      iconData: iconData,
      notificationType: notificationType,
      familyId: familyId,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// State
// ═══════════════════════════════════════════════════════════════════════

/// Immutable state for the notifications feature.
class NotificationsState {
  const NotificationsState({
    this.notifications = const [],
    this.selectedCategory,
    this.notificationPreferences = const {},
    this.isLoadingPreferences = false,
  });

  /// All notifications (unfiltered).
  final List<NotificationModel> notifications;

  /// Currently selected filter. `null` means "All".
  final NotificationCategory? selectedCategory;

  /// Per-type notification preferences.
  final Map<NotificationType, NotificationPreference> notificationPreferences;

  /// Whether preferences are currently loading from the server.
  final bool isLoadingPreferences;

  /// Unread count.
  int get unreadCount => notifications.where((n) => !n.isRead).length;

  /// Filtered list based on [selectedCategory].
  List<NotificationModel> get filtered {
    if (selectedCategory == null) return notifications;
    return notifications.where((n) => n.category == selectedCategory).toList();
  }

  /// Group notifications by familyId and notificationType.
  List<NotificationGroup> get grouped {
    final groupMap = <String, List<NotificationModel>>{};

    for (final notification in notifications) {
      final familyId = notification.familyId ?? '_no_family';
      final typeKey = notification.notificationType?.name ?? '_no_type';
      final groupKey = '${familyId}_$typeKey';

      groupMap.putIfAbsent(groupKey, () => []).add(notification);
    }

    return groupMap.entries.map((entry) {
      final parts = entry.key.split('_');
      final familyId = parts[0] == '_no' ? '' : parts[0];
      final typeName = parts.length > 1 ? parts.sublist(1).join('_') : '_no_type';

      return NotificationGroup(
        familyId: familyId,
        type: NotificationType.values.firstWhere(
          (t) => t.name == typeName,
          orElse: () => NotificationType.newMember,
        ),
        notifications: entry.value,
      );
    }).toList();
  }

  NotificationsState copyWith({
    List<NotificationModel>? notifications,
    NotificationCategory? Function()? selectedCategory,
    Map<NotificationType, NotificationPreference>? notificationPreferences,
    bool? isLoadingPreferences,
  }) {
    return NotificationsState(
      notifications: notifications ?? this.notifications,
      selectedCategory: selectedCategory != null
          ? selectedCategory()
          : this.selectedCategory,
      notificationPreferences:
          notificationPreferences ?? this.notificationPreferences,
      isLoadingPreferences:
          isLoadingPreferences ?? this.isLoadingPreferences,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Notifier
// ═══════════════════════════════════════════════════════════════════════

class NotificationsNotifier extends StateNotifier<NotificationsState> {
  NotificationsNotifier(this._ref) : super(const NotificationsState()) {
    loadNotifications();
    _startPolling();
  }

  final Ref _ref;
  Timer? _pollTimer;

  // ── Helper: get the configured Dio client ──────────────────────
  Dio get _dio => _ref.read(dioProvider);

  /// Start polling for new notifications every 30 seconds
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      loadNotifications();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  // ── Data Loading ─────────────────────────────────────────────────

  /// Load notifications directly from Supabase (bypasses NestJS which
  /// rejects Supabase JWTs due to ES256/HS256 signing mismatch).
  Future<void> loadNotifications() async {
    try {
      final client = _ref.read(supabaseProvider);
      if (client == null || client.auth.currentUser == null) return;

      final userId = client.auth.currentUser!.id;
      final response = await client
          .from('Notification')
          .select()
          .eq('userId', userId)
          .order('createdAt', ascending: false)
          .limit(50)
          .timeout(const Duration(seconds: 10));

      final notifications = response
          .map((e) => _mapNotification(e as Map<String, dynamic>))
          .toList();

      state = state.copyWith(notifications: notifications);
    } catch (e) {
      debugPrint('⚠️ Failed to load notifications: $e');
      // Fallback to NestJS API (will likely 401, but try anyway)
      try {
        final response = await _dio.get(
          '/api/notifications/v2',
          queryParameters: {'page': 1, 'limit': 50},
        );
        final data = response.data;
        if (data is Map<String, dynamic>) {
          final notificationsList =
              data['notifications'] as List? ?? data['items'] as List? ?? [];
          final notifications = notificationsList
              .map((e) => _mapNotification(e as Map<String, dynamic>))
              .toList();
          state = state.copyWith(notifications: notifications);
        } else if (data is List) {
          final notifications = data
              .map((e) => _mapNotification(e as Map<String, dynamic>))
              .toList();
          state = state.copyWith(notifications: notifications);
        }
      } catch (_) {}
    }
  }

  /// Map backend notification to Flutter NotificationModel
  NotificationModel _mapNotification(Map<String, dynamic> json) {
    final eventType = json['eventType'] as String? ?? '';
    final notificationType = _mapEventType(eventType);
    final category =
        notificationTypeCategory[notificationType] ?? NotificationCategory.system;
    final title = json['title'] as String? ?? '';
    final body = json['body'] as String? ?? '';
    final createdAt = json['createdAt'] as String? ?? '';
    final isRead = json['read'] as bool? ?? false;
    final familyId = json['familyId'] as String?;

    // Generate initials from title
    final words = title.split(' ').where((w) => w.isNotEmpty).take(2);
    final initials = words.map((w) => w[0].toUpperCase()).join();

    return NotificationModel(
      id: json['id'] as String? ?? '',
      category: category,
      title: title,
      body: body,
      time: _formatTime(createdAt),
      isRead: isRead,
      isPinned: false,
      avatarInitials: initials.isNotEmpty ? initials : null,
      avatarColor: _colorForType(notificationType),
      notificationType: notificationType,
      familyId: familyId,
    );
  }

  /// Map backend eventType to NotificationType
  NotificationType _mapEventType(String eventType) {
    switch (eventType) {
      case 'invitation_received':
        return NotificationType.familyInvite;
      case 'invitation_accepted':
        return NotificationType.acceptedInvite;
      case 'new_relative':
        return NotificationType.newMember;
      case 'birthday_reminder':
        return NotificationType.birthday;
      case 'anniversary_reminder':
        return NotificationType.anniversary;
      case 'profile_update':
        return NotificationType.relationshipUpdate;
      case 'family:created':
        return NotificationType.familyCreated;
      case 'family:invite_link_ready':
        return NotificationType.inviteLinkReady;
      case 'family:joined':
        return NotificationType.acceptedInvite;
      case 'family:member_joined':
        return NotificationType.memberJoinedViaInvite;
      case 'member_joined':
        return NotificationType.memberJoined;
      case 'family_id_generated':
        return NotificationType.familyIdGenerated;
      default:
        return NotificationType.newMember;
    }
  }

  /// Format ISO timestamp to relative time
  String _formatTime(String isoTimestamp) {
    if (isoTimestamp.isEmpty) return '';
    try {
      final dt = DateTime.tryParse(isoTimestamp);
      if (dt == null) return '';
      final now = DateTime.now();
      final diff = now.difference(dt);

      if (diff.inSeconds < 60) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
      if (diff.inHours < 24) return '${diff.inHours} hr ago';
      if (diff.inDays == 1) return 'Yesterday';
      if (diff.inDays < 7) return '${diff.inDays} days ago';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return '';
    }
  }

  /// Get a consistent color for notification type
  int _colorForType(NotificationType type) {
    switch (type) {
      case NotificationType.familyInvite:
        return 0xFFE8612A; // orange
      case NotificationType.acceptedInvite:
        return 0xFF4CAF7A; // green
      case NotificationType.rejectedInvite:
        return 0xFFEF4444; // red
      case NotificationType.newMember:
        return 0xFFF59240; // amber
      case NotificationType.birthday:
        return 0xFFD4AF37; // gold
      case NotificationType.anniversary:
        return 0xFFFF69B4; // pink
      case NotificationType.relationshipUpdate:
        return 0xFF3B82F6; // blue
      case NotificationType.usernameChange:
        return 0xFF8B5CF6; // purple
      case NotificationType.familyIdGenerated:
        return 0xFF06B6D4; // cyan
      case NotificationType.familyCreated:
        return 0xFFE8612A; // Kinrel orange
      case NotificationType.inviteLinkReady:
        return 0xFF06B6D4; // cyan
      case NotificationType.memberJoinedViaInvite:
        return 0xFF4CAF7A; // green
      case NotificationType.memberJoined:
        return 0xFF4CAF7A; // green
    }
  }

  // ── Actions (now with real API calls) ──────────────────────────

  /// Mark a single notification as read.
  Future<void> markAsRead(String id) async {
    // Optimistic update
    final updated = state.notifications.map((n) {
      if (n.id == id) return n.copyWith(isRead: true);
      return n;
    }).toList();
    state = state.copyWith(notifications: updated);

    // Update via Supabase directly (bypasses NestJS)
    try {
      final client = _ref.read(supabaseProvider);
      if (client != null && client.auth.currentUser != null) {
        await client
            .from('Notification')
            .update({'read': true, 'readAt': DateTime.now().toUtc().toIso8601String()})
            .eq('id', id)
            .eq('userId', client.auth.currentUser!.id);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to mark notification as read: $e');
    }
  }

  /// Mark all notifications as read.
  Future<void> markAllRead() async {
    // Optimistic update
    final updated = state.notifications.map((n) {
      return n.copyWith(isRead: true);
    }).toList();
    state = state.copyWith(notifications: updated);

    // Update via Supabase directly (bypasses NestJS)
    try {
      final client = _ref.read(supabaseProvider);
      if (client != null && client.auth.currentUser != null) {
        await client
            .from('Notification')
            .update({'read': true, 'readAt': DateTime.now().toUtc().toIso8601String()})
            .eq('userId', client.auth.currentUser!.id)
            .eq('read', false);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to mark all notifications as read: $e');
    }
  }

  /// Delete a notification by id.
  Future<void> deleteNotification(String id) async {
    // Optimistic update
    final updated = state.notifications.where((n) => n.id != id).toList();
    state = state.copyWith(notifications: updated);

    // Note: There's no delete endpoint in the v2 API, so we just remove locally
    // If needed, the old v1 endpoint could be used
  }

  /// Toggle pin on a notification.
  void pinNotification(String id) {
    final updated = state.notifications.map((n) {
      if (n.id == id) return n.copyWith(isPinned: !n.isPinned);
      return n;
    }).toList();
    state = state.copyWith(notifications: updated);
  }

  /// Set the category filter. Pass `null` for "All".
  void setCategory(NotificationCategory? category) {
    state = state.copyWith(selectedCategory: () => category);
  }

  /// Refresh notifications from the server
  Future<void> refresh() async {
    await loadNotifications();
  }

  // ── Notification Preferences ─────────────────────────────────────

  /// Get notification preferences from the server.
  Future<Map<NotificationType, NotificationPreference>>
      getNotificationPreferences() async {
    try {
      final response = await _dio.get('/api/notifications/v2/preferences');
      final data = response.data;

      if (data is Map<String, dynamic> && data['preferences'] is List) {
        final prefs = <NotificationType, NotificationPreference>{};
        final prefList = data['preferences'] as List;

        for (final pref in prefList) {
          if (pref is Map<String, dynamic>) {
            final eventType = pref['eventType'] as String? ?? '';
            final type = _mapEventType(eventType);
            prefs[type] = NotificationPreference(
              push: pref['push'] as bool? ?? true,
              inApp: pref['inApp'] as bool? ?? true,
              email: pref['email'] as bool? ?? false,
            );
          }
        }

        // Fill in defaults for missing types
        for (final type in NotificationType.values) {
          prefs.putIfAbsent(type, () => const NotificationPreference());
        }

        state = state.copyWith(notificationPreferences: prefs);
        return prefs;
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load notification preferences: $e');
    }

    // Return defaults
    final defaults = <NotificationType, NotificationPreference>{};
    for (final type in NotificationType.values) {
      defaults[type] = const NotificationPreference();
    }
    state = state.copyWith(notificationPreferences: defaults);
    return defaults;
  }

  /// Update notification preference for a specific type.
  Future<bool> updateNotificationPreference(
    NotificationType type, {
    bool push = true,
    bool inApp = true,
    bool email = false,
  }) async {
    final newPref = NotificationPreference(
      push: push,
      inApp: inApp,
      email: email,
    );

    // Optimistic update
    final updatedPrefs = Map<NotificationType, NotificationPreference>.from(
      state.notificationPreferences,
    );
    updatedPrefs[type] = newPref;
    state = state.copyWith(notificationPreferences: updatedPrefs);

    try {
      // Map back to backend eventType
      final eventType = _notificationTypeToEventType(type);
      await _dio.patch('/api/notifications/v2/preferences', data: {
        'eventType': eventType,
        'push': push,
        'inApp': inApp,
        'email': email,
      });
      return true;
    } catch (e) {
      debugPrint('⚠️ Failed to update notification preference: $e');
      await getNotificationPreferences();
      return false;
    }
  }

  /// Map NotificationType back to backend eventType string
  String _notificationTypeToEventType(NotificationType type) {
    switch (type) {
      case NotificationType.familyInvite:
        return 'invitation_received';
      case NotificationType.acceptedInvite:
        return 'invitation_accepted';
      case NotificationType.rejectedInvite:
        return 'invitation_rejected';
      case NotificationType.newMember:
        return 'new_relative';
      case NotificationType.birthday:
        return 'birthday_reminder';
      case NotificationType.anniversary:
        return 'anniversary_reminder';
      case NotificationType.relationshipUpdate:
        return 'profile_update';
      case NotificationType.usernameChange:
        return 'username_change';
      case NotificationType.familyIdGenerated:
        return 'family_id_generated';
      case NotificationType.familyCreated:
        return 'family:created';
      case NotificationType.inviteLinkReady:
        return 'family:invite_link_ready';
      case NotificationType.memberJoinedViaInvite:
        return 'family:member_joined';
      case NotificationType.memberJoined:
        return 'member_joined';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Provider
// ═══════════════════════════════════════════════════════════════════════

/// Global notifications provider.
final notificationsProvider =
    StateNotifierProvider<NotificationsNotifier, NotificationsState>(
      (ref) => NotificationsNotifier(ref),
    );

/// Convenience: unread count provider (can be watched independently).
final unreadCountProvider = Provider<int>((ref) {
  return ref.watch(notificationsProvider).unreadCount;
});

/// Convenience: notification preferences provider.
final notificationPreferencesProvider =
    Provider<Map<NotificationType, NotificationPreference>>((ref) {
  return ref.watch(notificationsProvider).notificationPreferences;
});

/// Convenience: grouped notifications provider.
final groupedNotificationsProvider = Provider<List<NotificationGroup>>((ref) {
  return ref.watch(notificationsProvider).grouped;
});
