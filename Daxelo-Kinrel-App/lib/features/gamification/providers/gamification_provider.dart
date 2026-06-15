// lib/features/gamification/providers/gamification_provider.dart
//
// DAXELO KINREL — Gamification & Achievements State Management
//
// Manages achievement badges, streaks, profile completion,
// and tree completeness using Riverpod StateNotifierProvider.
// Wired to the NestJS backend via GamificationService.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/gamification_service.dart';

// ═══════════════════════════════════════════════════════════════════════
// Badge Icon Mapping
// ═══════════════════════════════════════════════════════════════════════

/// Maps badge slugs to their Material icon codepoints.
class BadgeIcons {
  BadgeIcons._();

  static const IconData sprout = IconData(0xe549, fontFamily: 'MaterialIcons');
  static const IconData leaf = IconData(0xe3ab, fontFamily: 'MaterialIcons');
  static const IconData tree = IconData(0xe3c0, fontFamily: 'MaterialIcons');
  static const IconData book = IconData(0xe865, fontFamily: 'MaterialIcons');
  static const IconData map = IconData(0xe56c, fontFamily: 'MaterialIcons');
  static const IconData building = IconData(0xe8c1, fontFamily: 'MaterialIcons');
  static const IconData link = IconData(0xe3bc, fontFamily: 'MaterialIcons');
  static const IconData lightning = IconData(0xe430, fontFamily: 'MaterialIcons');
  static const IconData globe = IconData(0xe55b, fontFamily: 'MaterialIcons');
  static const IconData camera = IconData(0xe3af, fontFamily: 'MaterialIcons');
  static const IconData people = IconData(0xe7ef, fontFamily: 'MaterialIcons');
  static const IconData star = IconData(0xe838, fontFamily: 'MaterialIcons');

  /// Maps backend badge slugs to their icon.
  static IconData forSlug(String slug) {
    switch (slug) {
      case 'first_person':
        return sprout;
      case 'centurion':
        return star;
      case 'bond_maker':
        return link;
      case 'super_connector':
        return lightning;
      case 'storyteller':
        return book;
      case 'memory_keeper':
        return tree;
      case 'photographer':
        return camera;
      case 'social_butterfly':
        return people;
      case 'family_organizer':
        return building;
      default:
        return globe;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// AchievementBadge
// ═══════════════════════════════════════════════════════════════════════

class AchievementBadge {
  const AchievementBadge({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.isUnlocked,
    this.unlockedDate,
    required this.condition,
    this.tier,
    this.category,
  });

  final String id;
  final String name;
  final String description;
  final IconData icon;
  final bool isUnlocked;
  final DateTime? unlockedDate;
  final String condition;
  final String? tier;
  final String? category;

  String get formattedUnlockDate {
    if (unlockedDate == null) return '';
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[unlockedDate!.month - 1]} ${unlockedDate!.day}, ${unlockedDate!.year}';
  }

  AchievementBadge copyWith({bool? isUnlocked, DateTime? unlockedDate}) {
    return AchievementBadge(
      id: id,
      name: name,
      description: description,
      icon: icon,
      isUnlocked: isUnlocked ?? this.isUnlocked,
      unlockedDate: unlockedDate ?? this.unlockedDate,
      condition: condition,
      tier: tier,
      category: category,
    );
  }

  /// Create from API BadgeModel + optional UserBadgeModel.
  factory AchievementBadge.fromApi({
    required BadgeModel badge,
    UserBadgeModel? userBadge,
  }) {
    return AchievementBadge(
      id: badge.slug,
      name: badge.name,
      description: badge.description,
      icon: BadgeIcons.forSlug(badge.slug),
      isUnlocked: userBadge != null,
      unlockedDate: userBadge?.earnedAt,
      condition: badge.threshold != null
          ? 'Reach ${badge.threshold} ${badge.category.replaceAll('_', ' ')}'
          : badge.description,
      tier: badge.tier,
      category: badge.category,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// StreakData
// ═══════════════════════════════════════════════════════════════════════

class StreakData {
  const StreakData({
    required this.currentStreak,
    required this.longestStreak,
    required this.lastCheckInDate,
    this.todayCheckedIn = false,
    this.streakStartDate,
  });

  final int currentStreak;
  final int longestStreak;
  final DateTime? lastCheckInDate;
  final bool todayCheckedIn;
  final DateTime? streakStartDate;

  String get streakMessage {
    if (currentStreak == 1) {
      return "You've started your streak! Come back tomorrow to keep it going.";
    } else if (currentStreak < 7) {
      return "You've been building your family tree for $currentStreak days straight!";
    } else if (currentStreak < 30) {
      return 'Amazing! $currentStreak days in a row — your family tree is thriving!';
    } else {
      return "Incredible! $currentStreak day streak — you're a family tree legend!";
    }
  }

  String get formattedLastCheckIn {
    if (lastCheckInDate == null) return 'Never';
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
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

  /// Create from API CheckInResult or ContributionModel.
  factory StreakData.fromApi({
    int? streakCount,
    int? longestStreak,
    DateTime? lastCheckIn,
    bool todayCheckedIn = false,
  }) {
    return StreakData(
      currentStreak: streakCount ?? 0,
      longestStreak: longestStreak ?? streakCount ?? 0,
      lastCheckInDate: lastCheckIn,
      todayCheckedIn: todayCheckedIn,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// ProfileCompletion
// ═══════════════════════════════════════════════════════════════════════

class ProfileCompletion {
  const ProfileCompletion({
    required this.percentage,
    required this.totalFields,
    required this.completedFields,
    this.missingItems = const [],
  });

  final double percentage;
  final int totalFields;
  final int completedFields;
  final List<String> missingItems;

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

class TreeCompleteness {
  const TreeCompleteness({
    required this.percentage,
    required this.totalMembers,
    required this.generations,
    required this.relationships,
    this.nextStepHint,
    this.nextStepTarget,
  });

  final double percentage;
  final int totalMembers;
  final int generations;
  final int relationships;
  final String? nextStepHint;
  final double? nextStepTarget;

  String get fullHintText {
    if (nextStepHint == null) return 'Your tree is looking great!';
    final target = nextStepTarget != null ? ' to reach ${nextStepTarget!.round()}%' : '';
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

class SuggestedStep {
  const SuggestedStep({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.accentColor,
    this.actionLabel,
    this.route,
  });

  final String id;
  final String title;
  final String description;
  final IconData icon;
  final int accentColor;
  final String? actionLabel;
  final String? route;

  Color get color => Color(accentColor);
}

// ═══════════════════════════════════════════════════════════════════════
// GamificationState
// ═══════════════════════════════════════════════════════════════════════

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
    this.isLoading = false,
    this.error,
  });

  final List<AchievementBadge> badges;
  final StreakData streak;
  final ProfileCompletion profileCompletion;
  final TreeCompleteness treeCompleteness;
  final List<SuggestedStep> suggestedSteps;
  final bool isLoading;
  final String? error;

  List<AchievementBadge> get unlockedBadges => badges.where((b) => b.isUnlocked).toList();
  List<AchievementBadge> get lockedBadges => badges.where((b) => !b.isUnlocked).toList();
  int get unlockedCount => unlockedBadges.length;
  int get totalBadges => badges.length;

  GamificationState copyWith({
    List<AchievementBadge>? badges,
    StreakData? streak,
    ProfileCompletion? profileCompletion,
    TreeCompleteness? treeCompleteness,
    List<SuggestedStep>? suggestedSteps,
    bool? isLoading,
    String? error,
  }) {
    return GamificationState(
      badges: badges ?? this.badges,
      streak: streak ?? this.streak,
      profileCompletion: profileCompletion ?? this.profileCompletion,
      treeCompleteness: treeCompleteness ?? this.treeCompleteness,
      suggestedSteps: suggestedSteps ?? this.suggestedSteps,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// GamificationNotifier
// ═══════════════════════════════════════════════════════════════════════

class GamificationNotifier extends StateNotifier<GamificationState> {
  GamificationNotifier(this._ref) : super(const GamificationState()) {
    loadData();
  }

  final Ref _ref;

  /// Load all gamification data from the backend API.
  Future<void> loadData({String? familyId}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final service = _ref.read(gamificationServiceProvider);

      // Fetch badges and user badges in parallel
      final results = await Future.wait([
        service.getBadges(),
        service.getMyBadges(familyId: familyId),
        service.getContributions(familyId: familyId),
      ]);

      final allBadges = results[0] as List<BadgeModel>;
      final userBadges = results[1] as List<UserBadgeModel>;
      final contribution = results[2] as ContributionModel;

      // Build a map of earned badge IDs for quick lookup
      final earnedBadgeIds = <String, UserBadgeModel>{};
      for (final ub in userBadges) {
        earnedBadgeIds[ub.badgeId] = ub;
      }

      // Merge all badges with unlock status
      final achievementBadges = allBadges.map((badge) {
        final userBadge = earnedBadgeIds[badge.id];
        return AchievementBadge.fromApi(badge: badge, userBadge: userBadge);
      }).toList();

      // Build streak data from contribution
      final now = DateTime.now();
      final lastCheckIn = contribution.lastCheckIn;
      final todayCheckedIn = lastCheckIn != null &&
          lastCheckIn.year == now.year &&
          lastCheckIn.month == now.month &&
          lastCheckIn.day == now.day;

      final streak = StreakData.fromApi(
        streakCount: contribution.streakCount,
        longestStreak: contribution.streakCount, // Server doesn't track longest separately yet
        lastCheckIn: lastCheckIn,
        todayCheckedIn: todayCheckedIn,
      );

      // Build suggested steps based on locked badges
      final suggestedSteps = _buildSuggestedSteps(achievementBadges, streak);

      state = state.copyWith(
        badges: achievementBadges,
        streak: streak,
        suggestedSteps: suggestedSteps,
        isLoading: false,
      );
    } catch (e) {
      // Fallback to demo data on error
      state = state.copyWith(isLoading: false, error: e.toString());
      _loadDemoData();
    }
  }

  /// Perform a daily check-in via the API.
  Future<void> checkIn({String? familyId}) async {
    try {
      final service = _ref.read(gamificationServiceProvider);
      final result = await service.checkIn(familyId: familyId);

      if (result.checkedIn) {
        final newStreak = state.streak.copyWith(
          currentStreak: result.streakCount ?? state.streak.currentStreak,
          longestStreak: result.longestStreak ?? state.streak.longestStreak,
          todayCheckedIn: true,
          lastCheckInDate: DateTime.now(),
        );
        state = state.copyWith(streak: newStreak);

        // Reload to pick up any new badges
        await loadData(familyId: familyId);
      }
    } catch (e) {
      // Silently fail — the UI already shows the current state
    }
  }

  /// Submit a daily challenge answer.
  Future<Map<String, dynamic>?> submitDailyChallenge({
    required String answer,
    String? familyId,
  }) async {
    try {
      final service = _ref.read(gamificationServiceProvider);
      final result = await service.submitDailyChallenge(
        answer: answer,
        familyId: familyId,
      );
      // Reload data after challenge submission
      await loadData(familyId: familyId);
      return result;
    } catch (e) {
      return null;
    }
  }

  /// Build suggested steps based on current badge and streak state.
  List<SuggestedStep> _buildSuggestedSteps(
    List<AchievementBadge> badges,
    StreakData streak,
  ) {
    final steps = <SuggestedStep>[];

    // If streak is active but not checked in today
    if (!streak.todayCheckedIn) {
      steps.add(SuggestedStep(
        id: 'daily_checkin',
        title: "Complete Today's Check-In",
        description: streak.currentStreak > 0
            ? 'Keep your ${streak.currentStreak}-day streak alive! Daily check-ins earn bonus points.'
            : 'Start your daily check-in streak today and earn bonus points!',
        icon: const IconData(0xe7ed, fontFamily: 'MaterialIcons'),
        accentColor: 0xFFF59240,
        actionLabel: 'Check In Now',
      ));
    }

    // Find the first locked badge and suggest action
    final firstLocked = badges.where((b) => !b.isUnlocked).firstOrNull;
    if (firstLocked != null) {
      steps.add(SuggestedStep(
        id: 'unlock_${firstLocked.id}',
        title: 'Unlock "${firstLocked.name}"',
        description: firstLocked.condition,
        icon: firstLocked.icon,
        accentColor: 0xFFE8612A,
        actionLabel: 'Learn More',
      ));
    }

    // Suggest exploring kinship terms
    steps.add(SuggestedStep(
      id: 'learn_languages',
      title: 'Explore Kinship in a New Language',
      description: 'Discover how family relationships are named across Indian languages!',
      icon: const IconData(0xe55b, fontFamily: 'MaterialIcons'),
      accentColor: 0xFFD4AF37,
      actionLabel: 'Explore Terms',
      route: '/kinship-search',
    ));

    return steps;
  }

  /// Load demo data as fallback when API is unavailable.
  void _loadDemoData() {
    final now = DateTime.now();

    const badges = <AchievementBadge>[
      AchievementBadge(id: 'first_steps', name: 'First Steps', description: 'You added your first family member!', icon: BadgeIcons.sprout, isUnlocked: true, condition: 'Add first family member'),
      AchievementBadge(id: 'growing_family', name: 'Growing Family', description: '10 members and counting!', icon: BadgeIcons.leaf, isUnlocked: true, condition: 'Add 10 members'),
      AchievementBadge(id: 'generation_mapper', name: 'Generation Mapper', description: '3 generations mapped!', icon: BadgeIcons.map, isUnlocked: true, condition: 'Map 3 generations'),
      AchievementBadge(id: 'connector', name: 'Connector', description: '10 relationships created!', icon: BadgeIcons.link, isUnlocked: true, condition: 'Create 10 relationships'),
      AchievementBadge(id: 'deep_roots', name: 'Deep Roots', description: '25 members!', icon: BadgeIcons.tree, isUnlocked: false, condition: 'Add 25 members'),
      AchievementBadge(id: 'family_historian', name: 'Family Historian', description: '50 members!', icon: BadgeIcons.book, isUnlocked: false, condition: 'Add 50 members'),
      AchievementBadge(id: 'ancient_roots', name: 'Ancient Roots', description: '5+ generations!', icon: BadgeIcons.building, isUnlocked: false, condition: 'Map 5+ generations'),
      AchievementBadge(id: 'super_connector', name: 'Super Connector', description: '50 relationships!', icon: BadgeIcons.lightning, isUnlocked: false, condition: 'Create 50 relationships'),
      AchievementBadge(id: 'linguist', name: 'Linguist', description: 'Kinship in 3 languages!', icon: BadgeIcons.globe, isUnlocked: false, condition: 'Use kinship terms in 3 languages'),
    ];

    final unlockedBadges = badges.map((b) {
      if (b.isUnlocked) {
        DateTime? date;
        if (b.id == 'first_steps') date = now.subtract(const Duration(days: 30));
        else if (b.id == 'growing_family') date = now.subtract(const Duration(days: 18));
        else if (b.id == 'generation_mapper') date = now.subtract(const Duration(days: 10));
        else if (b.id == 'connector') date = now.subtract(const Duration(days: 5));
        return b.copyWith(unlockedDate: date);
      }
      return b;
    }).toList();

    const streak = StreakData(currentStreak: 7, longestStreak: 12, lastCheckInDate: null, todayCheckedIn: false);
    final streakWithDates = streak.copyWith(
      lastCheckInDate: now.subtract(const Duration(hours: 5)),
      streakStartDate: now.subtract(const Duration(days: 7)),
    );

    const profileCompletion = ProfileCompletion(percentage: 75, totalFields: 12, completedFields: 9, missingItems: ['Date of Birth', 'Occupation', 'Current City']);
    const treeCompleteness = TreeCompleteness(percentage: 60, totalMembers: 14, generations: 3, relationships: 22, nextStepHint: "add parents' details", nextStepTarget: 70);

    state = state.copyWith(
      badges: unlockedBadges,
      streak: streakWithDates,
      profileCompletion: profileCompletion,
      treeCompleteness: treeCompleteness,
      suggestedSteps: _buildSuggestedSteps(unlockedBadges, streakWithDates),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Providers
// ═══════════════════════════════════════════════════════════════════════

final gamificationProvider = StateNotifierProvider<GamificationNotifier, GamificationState>(
  (ref) => GamificationNotifier(ref),
);

final unlockedBadgeCountProvider = Provider<int>((ref) {
  return ref.watch(gamificationProvider).unlockedCount;
});

final currentStreakProvider = Provider<int>((ref) {
  return ref.watch(gamificationProvider).streak.currentStreak;
});
