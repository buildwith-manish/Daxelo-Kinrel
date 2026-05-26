// lib/features/gamification/providers/gamification_provider.dart
//
// DAXELO KINREL — Gamification & Achievements State Management
//
// Manages achievement badges, streaks, profile completion,
// and tree completeness using Riverpod StateNotifierProvider.
// Follows KINREL Global Top 1 Prompt Section 25 specs.
//
// 9 Achievement Badges:
//   First Steps, Growing Family, Deep Roots, Family Historian,
//   Generation Mapper, Ancient Roots, Connector, Super Connector, Linguist
//
// Demo data: 4 unlocked, 5 locked, 7-day streak, 75% profile, 60% tree

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ═══════════════════════════════════════════════════════════════════════
// Badge Icon Mapping
// ═══════════════════════════════════════════════════════════════════════

/// Maps badge IDs to their Material icon codepoints.
/// Used by the UI layer to render the correct icon per badge.
class BadgeIcons {
  BadgeIcons._();

  static const int sprout = 0xe549;     // eco / sprout
  static const int leaf = 0xe3ab;       // nature / leaf
  static const int tree = 0xe3c0;       // park / tree
  static const int book = 0xe865;       // menu_book / book
  static const int map = 0xe56c;        // map / map
  static const int building = 0xe8c1;   // account_balance / building
  static const int link = 0xe3bc;       // link / link
  static const int lightning = 0xe430;  // bolt / lightning
  static const int globe = 0xe55b;      // public / globe
}

// ═══════════════════════════════════════════════════════════════════════
// AchievementBadge
// ═══════════════════════════════════════════════════════════════════════

/// A single achievement badge — either unlocked or locked.
class AchievementBadge {
  const AchievementBadge({
    required this.id,
    required this.name,
    required this.description,
    required this.iconCodePoint,
    required this.isUnlocked,
    this.unlockedDate,
    required this.condition,
  });

  /// Unique identifier for the badge.
  final String id;

  /// Display name (e.g., "First Steps").
  final String name;

  /// Short description of the achievement.
  final String description;

  /// Material Icon codepoint (see [BadgeIcons]).
  final int iconCodePoint;

  /// Whether the badge has been earned.
  final bool isUnlocked;

  /// Date when the badge was unlocked (null if locked).
  final DateTime? unlockedDate;

  /// Condition text shown on locked badges (e.g., "Add 10 members").
  final String condition;

  /// Formatted unlock date string.
  String get formattedUnlockDate {
    if (unlockedDate == null) return '';
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[unlockedDate!.month - 1]} ${unlockedDate!.day}, ${unlockedDate!.year}';
  }

  /// IconData from the codepoint.
  IconData get icon => IconData(iconCodePoint, fontFamily: 'MaterialIcons');

  AchievementBadge copyWith({
    bool? isUnlocked,
    DateTime? unlockedDate,
  }) {
    return AchievementBadge(
      id: id,
      name: name,
      description: description,
      iconCodePoint: iconCodePoint,
      isUnlocked: isUnlocked ?? this.isUnlocked,
      unlockedDate: unlockedDate ?? this.unlockedDate,
      condition: condition,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// StreakData
// ═══════════════════════════════════════════════════════════════════════

/// Daily check-in streak information.
class StreakData {
  const StreakData({
    required this.currentStreak,
    required this.longestStreak,
    required this.lastCheckInDate,
    this.todayCheckedIn = false,
    this.streakStartDate,
  });

  /// Current consecutive days streak.
  final int currentStreak;

  /// All-time longest streak.
  final int longestStreak;

  /// Date of the last check-in.
  final DateTime? lastCheckInDate;

  /// Whether the user has checked in today.
  final bool todayCheckedIn;

  /// When the current streak started.
  final DateTime? streakStartDate;

  /// Motivational streak message.
  String get streakMessage {
    if (currentStreak == 1) {
      return "You've started your streak! Come back tomorrow to keep it going.";
    } else if (currentStreak < 7) {
      return "You've been building your family tree for $currentStreak days straight!";
    } else if (currentStreak < 30) {
      return "Amazing! $currentStreak days in a row — your family tree is thriving!";
    } else {
      return "Incredible! $currentStreak day streak — you're a family tree legend!";
    }
  }

  /// Formatted last check-in date.
  String get formattedLastCheckIn {
    if (lastCheckInDate == null) return 'Never';
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[lastCheckInDate!.month - 1]} ${lastCheckInDate!.day}, ${lastCheckInDate!.year}';
  }

  StreakData copyWith({
    int? currentStreak,
    int? longestStreak,
    DateTime? lastCheckInDate,
    bool? todayCheckedIn,
    DateTime? streakStartDate,
  }) {
    return StreakData(
      currentStreak: currentStreak ?? this.currentStreak,
      longestStreak: longestStreak ?? this.longestStreak,
      lastCheckInDate: lastCheckInDate ?? this.lastCheckInDate,
      todayCheckedIn: todayCheckedIn ?? this.todayCheckedIn,
      streakStartDate: streakStartDate ?? this.streakStartDate,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// ProfileCompletion
// ═══════════════════════════════════════════════════════════════════════

/// User profile completion ring data (LinkedIn-style circular progress).
class ProfileCompletion {
  const ProfileCompletion({
    required this.percentage,
    required this.totalFields,
    required this.completedFields,
    this.missingItems = const [],
  });

  /// Completion percentage (0-100).
  final double percentage;

  /// Total number of profile fields.
  final int totalFields;

  /// Number of completed profile fields.
  final int completedFields;

  /// List of incomplete profile items.
  final List<String> missingItems;

  /// Next suggested action to improve profile.
  String get nextStep {
    if (missingItems.isEmpty) return 'Your profile is complete!';
    return 'Add your ${missingItems.first.toLowerCase()} to reach ${(percentage + (100 / totalFields)).round()}%';
  }

  ProfileCompletion copyWith({
    double? percentage,
    int? totalFields,
    int? completedFields,
    List<String>? missingItems,
  }) {
    return ProfileCompletion(
      percentage: percentage ?? this.percentage,
      totalFields: totalFields ?? this.totalFields,
      completedFields: completedFields ?? this.completedFields,
      missingItems: missingItems ?? this.missingItems,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// TreeCompleteness
// ═══════════════════════════════════════════════════════════════════════

/// Family tree completeness data with actionable suggestions.
class TreeCompleteness {
  const TreeCompleteness({
    required this.percentage,
    required this.totalMembers,
    required this.generations,
    required this.relationships,
    this.nextStepHint,
    this.nextStepTarget,
  });

  /// Tree completeness percentage (0-100).
  final double percentage;

  /// Total number of members in the tree.
  final int totalMembers;

  /// Number of mapped generations.
  final int generations;

  /// Total number of relationships.
  final int relationships;

  /// Human-readable next step suggestion.
  final String? nextStepHint;

  /// Target percentage after completing the next step.
  final double? nextStepTarget;

  /// Full hint text with target percentage.
  String get fullHintText {
    if (nextStepHint == null) return 'Your tree is looking great!';
    final target = nextStepTarget != null
        ? ' to reach ${nextStepTarget!.round()}%'
        : '';
    return 'Your tree is ${percentage.round()}% complete — $nextStepHint$target';
  }

  TreeCompleteness copyWith({
    double? percentage,
    int? totalMembers,
    int? generations,
    int? relationships,
    String? nextStepHint,
    double? nextStepTarget,
  }) {
    return TreeCompleteness(
      percentage: percentage ?? this.percentage,
      totalMembers: totalMembers ?? this.totalMembers,
      generations: generations ?? this.generations,
      relationships: relationships ?? this.relationships,
      nextStepHint: nextStepHint ?? this.nextStepHint,
      nextStepTarget: nextStepTarget ?? this.nextStepTarget,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SuggestedStep
// ═══════════════════════════════════════════════════════════════════════

/// An actionable next-step card for the "Suggested Next Steps" section.
class SuggestedStep {
  const SuggestedStep({
    required this.id,
    required this.title,
    required this.description,
    required this.iconCodePoint,
    required this.accentColor,
    this.actionLabel,
    this.route,
  });

  final String id;
  final String title;
  final String description;
  final int iconCodePoint;
  final int accentColor;
  final String? actionLabel;
  final String? route;

  IconData get icon => IconData(iconCodePoint, fontFamily: 'MaterialIcons');
  Color get color => Color(accentColor);
}

// ═══════════════════════════════════════════════════════════════════════
// GamificationState
// ═══════════════════════════════════════════════════════════════════════

/// Immutable state for the gamification feature.
class GamificationState {
  const GamificationState({
    this.badges = const [],
    this.streak = const StreakData(
      currentStreak: 0,
      longestStreak: 0,
      lastCheckInDate: null,
    ),
    this.profileCompletion = const ProfileCompletion(
      percentage: 0,
      totalFields: 0,
      completedFields: 0,
    ),
    this.treeCompleteness = const TreeCompleteness(
      percentage: 0,
      totalMembers: 0,
      generations: 0,
      relationships: 0,
    ),
    this.suggestedSteps = const [],
  });

  /// All achievement badges (unlocked + locked).
  final List<AchievementBadge> badges;

  /// Daily check-in streak data.
  final StreakData streak;

  /// Profile completion ring data.
  final ProfileCompletion profileCompletion;

  /// Family tree completeness data.
  final TreeCompleteness treeCompleteness;

  /// Suggested next-step cards.
  final List<SuggestedStep> suggestedSteps;

  // ── Computed Getters ────────────────────────────────────────────────

  /// Badges that have been unlocked.
  List<AchievementBadge> get unlockedBadges =>
      badges.where((b) => b.isUnlocked).toList();

  /// Badges that are still locked.
  List<AchievementBadge> get lockedBadges =>
      badges.where((b) => !b.isUnlocked).toList();

  /// Number of unlocked badges.
  int get unlockedCount => unlockedBadges.length;

  /// Total number of badges.
  int get totalBadges => badges.length;

  GamificationState copyWith({
    List<AchievementBadge>? badges,
    StreakData? streak,
    ProfileCompletion? profileCompletion,
    TreeCompleteness? treeCompleteness,
    List<SuggestedStep>? suggestedSteps,
  }) {
    return GamificationState(
      badges: badges ?? this.badges,
      streak: streak ?? this.streak,
      profileCompletion: profileCompletion ?? this.profileCompletion,
      treeCompleteness: treeCompleteness ?? this.treeCompleteness,
      suggestedSteps: suggestedSteps ?? this.suggestedSteps,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// GamificationNotifier
// ═══════════════════════════════════════════════════════════════════════

class GamificationNotifier extends StateNotifier<GamificationState> {
  GamificationNotifier() : super(const GamificationState()) {
    _loadDemoData();
  }

  // ── Actions ────────────────────────────────────────────────────────

  /// Simulate a daily check-in.
  void checkIn() {
    final now = DateTime.now();
    final newStreak = state.streak.todayCheckedIn
        ? state.streak
        : state.streak.copyWith(
            currentStreak: state.streak.currentStreak + 1,
            longestStreak: state.streak.currentStreak + 1 > state.streak.longestStreak
                ? state.streak.currentStreak + 1
                : state.streak.longestStreak,
            lastCheckInDate: now,
            todayCheckedIn: true,
          );
    state = state.copyWith(streak: newStreak);
  }

  /// Unlock a badge by ID.
  void unlockBadge(String badgeId) {
    final updated = state.badges.map((b) {
      if (b.id == badgeId && !b.isUnlocked) {
        return b.copyWith(isUnlocked: true, unlockedDate: DateTime.now());
      }
      return b;
    }).toList();
    state = state.copyWith(badges: updated);
  }

  // ── Demo Data ──────────────────────────────────────────────────────

  void _loadDemoData() {
    final now = DateTime.now();

    // ── 9 Achievement Badges (4 unlocked, 5 locked) ─────────────────
    const badges = <AchievementBadge>[
      // ── Unlocked ──────────────────────────────────────────────────
      AchievementBadge(
        id: 'first_steps',
        name: 'First Steps',
        description: 'You added your first family member — every great tree starts with a single branch!',
        iconCodePoint: BadgeIcons.sprout,
        isUnlocked: true,
        unlockedDate: null, // Will be set below
        condition: 'Add first family member',
      ),
      AchievementBadge(
        id: 'growing_family',
        name: 'Growing Family',
        description: '10 members and counting — your family tree is taking shape!',
        iconCodePoint: BadgeIcons.leaf,
        isUnlocked: true,
        unlockedDate: null,
        condition: 'Add 10 members',
      ),
      AchievementBadge(
        id: 'generation_mapper',
        name: 'Generation Mapper',
        description: '3 generations mapped — you\'re bridging the past and present!',
        iconCodePoint: BadgeIcons.map,
        isUnlocked: true,
        unlockedDate: null,
        condition: 'Map 3 generations',
      ),
      AchievementBadge(
        id: 'connector',
        name: 'Connector',
        description: '10 relationships created — you\'re the family glue!',
        iconCodePoint: BadgeIcons.link,
        isUnlocked: true,
        unlockedDate: null,
        condition: 'Create 10 relationships',
      ),

      // ── Locked ────────────────────────────────────────────────────
      AchievementBadge(
        id: 'deep_roots',
        name: 'Deep Roots',
        description: '25 members — your tree is becoming a forest!',
        iconCodePoint: BadgeIcons.tree,
        isUnlocked: false,
        condition: 'Add 25 members',
      ),
      AchievementBadge(
        id: 'family_historian',
        name: 'Family Historian',
        description: '50 members — you\'re a true keeper of family heritage!',
        iconCodePoint: BadgeIcons.book,
        isUnlocked: false,
        condition: 'Add 50 members',
      ),
      AchievementBadge(
        id: 'ancient_roots',
        name: 'Ancient Roots',
        description: '5+ generations — reaching back through time itself!',
        iconCodePoint: BadgeIcons.building,
        isUnlocked: false,
        condition: 'Map 5+ generations',
      ),
      AchievementBadge(
        id: 'super_connector',
        name: 'Super Connector',
        description: '50 relationships — the ultimate family networker!',
        iconCodePoint: BadgeIcons.lightning,
        isUnlocked: false,
        condition: 'Create 50 relationships',
      ),
      AchievementBadge(
        id: 'linguist',
        name: 'Linguist',
        description: 'Kinship terms in 3 languages — a true multilingual!',
        iconCodePoint: BadgeIcons.globe,
        isUnlocked: false,
        condition: 'Use kinship terms in 3 languages',
      ),
    ];

    // Set realistic unlock dates for unlocked badges
    final unlockedBadges = badges.map((b) {
      if (b.isUnlocked) {
        DateTime? date;
        if (b.id == 'first_steps') {
          date = now.subtract(const Duration(days: 30));
        } else if (b.id == 'growing_family') {
          date = now.subtract(const Duration(days: 18));
        } else if (b.id == 'generation_mapper') {
          date = now.subtract(const Duration(days: 10));
        } else if (b.id == 'connector') {
          date = now.subtract(const Duration(days: 5));
        }
        return b.copyWith(unlockedDate: date);
      }
      return b;
    }).toList();

    // ── Streak Data (7-day streak) ──────────────────────────────────
    const streak = StreakData(
      currentStreak: 7,
      longestStreak: 12,
      lastCheckInDate: null, // Will be set below
      todayCheckedIn: false,
      streakStartDate: null,
    );

    final streakWithDates = streak.copyWith(
      lastCheckInDate: now.subtract(const Duration(hours: 5)),
      streakStartDate: now.subtract(const Duration(days: 7)),
    );

    // ── Profile Completion (75%) ────────────────────────────────────
    const profileCompletion = ProfileCompletion(
      percentage: 75,
      totalFields: 12,
      completedFields: 9,
      missingItems: ['Date of Birth', 'Occupation', 'Current City'],
    );

    // ── Tree Completeness (60%) ─────────────────────────────────────
    const treeCompleteness = TreeCompleteness(
      percentage: 60,
      totalMembers: 14,
      generations: 3,
      relationships: 22,
      nextStepHint: "add parents' details",
      nextStepTarget: 70,
    );

    // ── Suggested Next Steps ────────────────────────────────────────
    const suggestedSteps = <SuggestedStep>[
      SuggestedStep(
        id: 'add_parents',
        title: "Add Your Parents' Details",
        description: 'Filling in parent information unlocks the Deep Roots badge and brings your tree to 70%.',
        iconCodePoint: 0xef3d, // family_restroom
        accentColor: 0xFFE8612A,
        actionLabel: 'Add Parents',
        route: '/families',
      ),
      SuggestedStep(
        id: 'daily_checkin',
        title: 'Complete Today\'s Check-In',
        description: 'Keep your 7-day streak alive! Daily check-ins earn you bonus points toward the Super Connector badge.',
        iconCodePoint: 0xe7ed, // check_circle
        accentColor: 0xFFF59240,
        actionLabel: 'Check In Now',
      ),
      SuggestedStep(
        id: 'learn_languages',
        title: 'Explore Kinship in a New Language',
        description: 'You\'ve used Hindi and English — try Marathi or Bengali to unlock the Linguist badge!',
        iconCodePoint: 0xe55b, // public
        accentColor: 0xFFD4AF37,
        actionLabel: 'Explore Terms',
        route: '/kinship-search',
      ),
    ];

    state = GamificationState(
      badges: unlockedBadges,
      streak: streakWithDates,
      profileCompletion: profileCompletion,
      treeCompleteness: treeCompleteness,
      suggestedSteps: suggestedSteps,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Providers
// ═══════════════════════════════════════════════════════════════════════

/// Global gamification provider.
final gamificationProvider =
    StateNotifierProvider<GamificationNotifier, GamificationState>(
  (ref) => GamificationNotifier(),
);

/// Convenience: unlocked badge count provider.
final unlockedBadgeCountProvider = Provider<int>((ref) {
  return ref.watch(gamificationProvider).unlockedCount;
});

/// Convenience: current streak provider.
final currentStreakProvider = Provider<int>((ref) {
  return ref.watch(gamificationProvider).streak.currentStreak;
});
