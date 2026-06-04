// lib/features/notifications/providers/notifications_provider.dart
//
// DAXELO KINREL — Notifications State Management
//
// Manages notification state using Riverpod StateNotifierProvider.
// Supports mark as read, mark all read, delete, and pin operations.
// Includes notification types, preferences, and grouping.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../../core/networking/dio_client.dart';

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
    _loadDemoData();
  }

  final Ref _ref;

  // ── Helper: get the configured Dio client ──────────────────────
  Dio get _dio => _ref.read(dioProvider);

  // ── Actions ──────────────────────────────────────────────────────

  /// Mark a single notification as read.
  void markAsRead(String id) {
    final updated = state.notifications.map((n) {
      if (n.id == id) return n.copyWith(isRead: true);
      return n;
    }).toList();
    state = state.copyWith(notifications: updated);
  }

  /// Mark all notifications as read.
  void markAllRead() {
    final updated = state.notifications.map((n) {
      return n.copyWith(isRead: true);
    }).toList();
    state = state.copyWith(notifications: updated);
  }

  /// Delete a notification by id.
  void deleteNotification(String id) {
    final updated = state.notifications.where((n) => n.id != id).toList();
    state = state.copyWith(notifications: updated);
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

  // ── Notification Preferences ─────────────────────────────────────

  /// Get notification preferences from the server.
  /// Falls back to defaults if the API is unavailable.
  Future<Map<NotificationType, NotificationPreference>>
      getNotificationPreferences() async {
    try {
      final response = await _dio.get('/api/users/me/notification-preferences');
      final data = response.data;

      if (data is Map<String, dynamic>) {
        final prefs = <NotificationType, NotificationPreference>{};
        for (final type in NotificationType.values) {
          final typeData = data[type.name];
          if (typeData is Map<String, dynamic>) {
            prefs[type] = NotificationPreference.fromJson(typeData);
          } else {
            prefs[type] = const NotificationPreference();
          }
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
      await _dio.patch(
        '/api/users/me/notification-preferences',
        data: {
          type.name: newPref.toJson(),
        },
      );
      return true;
    } catch (e) {
      debugPrint('⚠️ Failed to update notification preference: $e');
      // Roll back — reload preferences
      await getNotificationPreferences();
      return false;
    }
  }

  // ── Demo Data ────────────────────────────────────────────────────

  void _loadDemoData() {
    const demo = <NotificationModel>[
      // ── Family Activity ──────────────────────────────────────────
      NotificationModel(
        id: 'n1',
        category: NotificationCategory.family,
        title: 'Priya Sharma was added to Sharma Family',
        body:
            'Rajesh Sharma added Priya Sharma as his daughter in the Sharma Family tree.',
        time: '2 min ago',
        isRead: false,
        avatarInitials: 'PS',
        avatarColor: 0xFFE8612A,
        notificationType: NotificationType.newMember,
        familyId: 'family_sharma',
      ),
      NotificationModel(
        id: 'n2',
        category: NotificationCategory.family,
        title: 'Arjun & Meera connected as spouses',
        body:
            'A new spousal relationship was established between Arjun Kapoor and Meera Kapoor.',
        time: '15 min ago',
        isRead: false,
        avatarInitials: 'AK',
        avatarColor: 0xFFF59240,
        notificationType: NotificationType.relationshipUpdate,
        familyId: 'family_kapoor',
      ),
      NotificationModel(
        id: 'n3',
        category: NotificationCategory.family,
        title: 'Kavita was added to Patel Family',
        body:
            'Anil Patel added Kavita Patel as his sister in the Patel Family tree.',
        time: '1 hr ago',
        isRead: true,
        avatarInitials: 'KP',
        avatarColor: 0xFF4CAF7A,
        notificationType: NotificationType.memberJoined,
        familyId: 'family_patel',
      ),
      NotificationModel(
        id: 'n4',
        category: NotificationCategory.family,
        title: 'Rohan & Sunita connected as parent-child',
        body:
            'Rohan Verma is now linked as the father of Sunita Verma in the Verma Family.',
        time: '3 hrs ago',
        isRead: true,
        avatarInitials: 'RV',
        avatarColor: 0xFF3B82F6,
        notificationType: NotificationType.relationshipUpdate,
        familyId: 'family_verma',
      ),

      // ── Celebrations ─────────────────────────────────────────────
      NotificationModel(
        id: 'n5',
        category: NotificationCategory.celebrations,
        title: "Ananya's birthday is tomorrow! 🎂",
        body:
            'Ananya Desai turns 28 tomorrow. Send her a Kinrel greeting card!',
        time: '30 min ago',
        isRead: false,
        avatarInitials: 'AD',
        avatarColor: 0xFFD4AF37,
        notificationType: NotificationType.birthday,
        familyId: 'family_desai',
      ),
      NotificationModel(
        id: 'n6',
        category: NotificationCategory.celebrations,
        title: "Rahul & Neha's anniversary is in 3 days! 💍",
        body:
            'Rahul and Neha Mehta celebrate their 12th wedding anniversary this Friday.',
        time: '2 hrs ago',
        isRead: false,
        avatarInitials: 'NM',
        avatarColor: 0xFFFF69B4,
        notificationType: NotificationType.anniversary,
        familyId: 'family_mehta',
      ),
      NotificationModel(
        id: 'n7',
        category: NotificationCategory.celebrations,
        title: "Vikram's birthday is next week",
        body: 'Vikram Singh turns 45 next Tuesday. Plan something special!',
        time: '5 hrs ago',
        isRead: true,
        avatarInitials: 'VS',
        avatarColor: 0xFF2E8B57,
        notificationType: NotificationType.birthday,
        familyId: 'family_singh',
      ),

      // ── Engagement ───────────────────────────────────────────────
      NotificationModel(
        id: 'n8',
        category: NotificationCategory.engagement,
        title: 'Your family graph is growing! 🌳',
        body:
            'You added 3 new members this week. Your Sharma Family tree now has 24 members.',
        time: '1 hr ago',
        isRead: false,
        iconData: const IconData(
          0xe3af,
          fontFamily: 'MaterialIcons',
        ), // Icons.trending_up
      ),
      NotificationModel(
        id: 'n9',
        category: NotificationCategory.engagement,
        title: 'Discover: kinship terms for "father\'s brother"',
        body:
            'Learn that your father\'s elder brother is called "Tau" and younger brother "Chacha" in Hindi.',
        time: '4 hrs ago',
        isRead: false,
        iconData: const IconData(
          0xe86f,
          fontFamily: 'MaterialIcons',
        ), // Icons.explore
      ),
      NotificationModel(
        id: 'n10',
        category: NotificationCategory.engagement,
        title: 'Weekly kinship challenge ready!',
        body:
            'This week: Can you name all 8 terms for cousins in Marathi? Take the quiz now.',
        time: '6 hrs ago',
        isRead: true,
        iconData: const IconData(
          0xe037,
          fontFamily: 'MaterialIcons',
        ), // Icons.emoji_events
      ),

      // ── System ───────────────────────────────────────────────────
      NotificationModel(
        id: 'n11',
        category: NotificationCategory.system,
        title: 'Welcome to Kinrel! 🎉',
        body:
            'Start building your family tree and discover the beauty of kinship. Tap to begin.',
        time: '1 day ago',
        isRead: true,
        isPinned: true,
        iconData: const IconData(
          0xe87e,
          fontFamily: 'MaterialIcons',
        ), // Icons.waving_hand
      ),
      NotificationModel(
        id: 'n12',
        category: NotificationCategory.system,
        title: 'Complete your profile',
        body:
            'Add your photo and birthday to help family members find and connect with you.',
        time: '1 day ago',
        isRead: true,
        iconData: const IconData(
          0xe7fd,
          fontFamily: 'MaterialIcons',
        ), // Icons.person
      ),
      NotificationModel(
        id: 'n13',
        category: NotificationCategory.system,
        title: 'App updated to v2.4.0',
        body:
            'New: Festival greeting cards, voice search for kinship terms, and bug fixes.',
        time: '2 days ago',
        isRead: true,
        iconData: const IconData(
          0xe896,
          fontFamily: 'MaterialIcons',
        ), // Icons.system_update
      ),
    ];

    state = state.copyWith(notifications: demo);
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
