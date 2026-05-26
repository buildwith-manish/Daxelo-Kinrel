// lib/features/notifications/providers/notifications_provider.dart
//
// DAXELO KINREL — Notifications State Management
//
// Manages notification state using Riverpod StateNotifierProvider.
// Supports mark as read, mark all read, delete, and pin operations.
// Includes realistic demo data for Family, Celebrations, Engagement,
// and System notification types.

import 'package:flutter_riverpod/flutter_riverpod.dart';

// ═══════════════════════════════════════════════════════════════════════
// Models
// ═══════════════════════════════════════════════════════════════════════

/// Notification category — drives the segmented control filter.
enum NotificationCategory {
  family,
  celebrations,
  engagement,
  system,
}

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

  /// Icon codepoint for system / engagement notifications
  /// that don't have a person avatar.
  final int? iconData;

  NotificationModel copyWith({
    bool? isRead,
    bool? isPinned,
  }) {
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
  });

  /// All notifications (unfiltered).
  final List<NotificationModel> notifications;

  /// Currently selected filter. `null` means "All".
  final NotificationCategory? selectedCategory;

  /// Unread count.
  int get unreadCount =>
      notifications.where((n) => !n.isRead).length;

  /// Filtered list based on [selectedCategory].
  List<NotificationModel> get filtered {
    if (selectedCategory == null) return notifications;
    return notifications
        .where((n) => n.category == selectedCategory)
        .toList();
  }

  NotificationsState copyWith({
    List<NotificationModel>? notifications,
    NotificationCategory? Function()? selectedCategory,
  }) {
    return NotificationsState(
      notifications: notifications ?? this.notifications,
      selectedCategory:
          selectedCategory != null ? selectedCategory() : this.selectedCategory,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Notifier
// ═══════════════════════════════════════════════════════════════════════

class NotificationsNotifier extends StateNotifier<NotificationsState> {
  NotificationsNotifier() : super(const NotificationsState()) {
    _loadDemoData();
  }

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
    final updated =
        state.notifications.where((n) => n.id != id).toList();
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
    state = state.copyWith(
      selectedCategory: () => category,
    );
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
      ),
      NotificationModel(
        id: 'n7',
        category: NotificationCategory.celebrations,
        title: "Vikram's birthday is next week",
        body:
            'Vikram Singh turns 45 next Tuesday. Plan something special!',
        time: '5 hrs ago',
        isRead: true,
        avatarInitials: 'VS',
        avatarColor: 0xFF2E8B57,
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
        iconData: 0xe3af, // Icons.trending_up
      ),
      NotificationModel(
        id: 'n9',
        category: NotificationCategory.engagement,
        title: 'Discover: kinship terms for "father\'s brother"',
        body:
            'Learn that your father\'s elder brother is called "Tau" and younger brother "Chacha" in Hindi.',
        time: '4 hrs ago',
        isRead: false,
        iconData: 0xe86f, // Icons.explore
      ),
      NotificationModel(
        id: 'n10',
        category: NotificationCategory.engagement,
        title: 'Weekly kinship challenge ready!',
        body:
            'This week: Can you name all 8 terms for cousins in Marathi? Take the quiz now.',
        time: '6 hrs ago',
        isRead: true,
        iconData: 0xe037, // Icons.emoji_events
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
        iconData: 0xe87e, // Icons.waving_hand
      ),
      NotificationModel(
        id: 'n12',
        category: NotificationCategory.system,
        title: 'Complete your profile',
        body:
            'Add your photo and birthday to help family members find and connect with you.',
        time: '1 day ago',
        isRead: true,
        iconData: 0xe7fd, // Icons.person
      ),
      NotificationModel(
        id: 'n13',
        category: NotificationCategory.system,
        title: 'App updated to v2.4.0',
        body:
            'New: Festival greeting cards, voice search for kinship terms, and bug fixes.',
        time: '2 days ago',
        isRead: true,
        iconData: 0xe896, // Icons.system_update
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
  (ref) => NotificationsNotifier(),
);

/// Convenience: unread count provider (can be watched independently).
final unreadCountProvider = Provider<int>((ref) {
  return ref.watch(notificationsProvider).unreadCount;
});
