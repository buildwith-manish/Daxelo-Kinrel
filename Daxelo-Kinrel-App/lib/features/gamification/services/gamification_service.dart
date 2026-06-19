// lib/features/gamification/services/gamification_service.dart
//
// DAXELO KINREL — Gamification API Service
//
// Calls the NestJS gamification backend endpoints.
// Uses the shared dioProvider for authenticated HTTP requests.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/networking/dio_client.dart';

// ═══════════════════════════════════════════════════════════════════════
// API Response Models
// ═══════════════════════════════════════════════════════════════════════

class BadgeModel {
  const BadgeModel({
    required this.id,
    required this.slug,
    required this.name,
    required this.description,
    required this.tier,
    required this.category,
    this.threshold,
    this.iconUrl,
  });

  final String id;
  final String slug;
  final String name;
  final String description;
  final String tier; // bronze, silver, gold
  final String category; // tree_builder, connector, historian, social
  final int? threshold;
  final String? iconUrl;

  factory BadgeModel.fromJson(Map<String, dynamic> json) {
    return BadgeModel(
      id: json['id'] as String,
      slug: json['slug'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      tier: json['tier'] as String? ?? 'bronze',
      category: json['category'] as String? ?? 'tree_builder',
      threshold: json['threshold'] as int?,
      iconUrl: json['iconUrl'] as String?,
    );
  }
}

class UserBadgeModel {
  const UserBadgeModel({
    required this.id,
    required this.userId,
    required this.badgeId,
    required this.earnedAt,
    this.badge,
  });

  final String id;
  final String userId;
  final String badgeId;
  final DateTime earnedAt;
  final BadgeModel? badge;

  factory UserBadgeModel.fromJson(Map<String, dynamic> json) {
    return UserBadgeModel(
      id: json['id'] as String,
      userId: json['userId'] as String,
      badgeId: json['badgeId'] as String,
      earnedAt: DateTime.parse(json['earnedAt'] as String),
      badge: json['badge'] != null
          ? BadgeModel.fromJson(json['badge'] as Map<String, dynamic>)
          : null,
    );
  }
}

class ContributionModel {
  const ContributionModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.points,
    this.familyId,
    required this.createdAt,
    this.streakCount,
    this.lastCheckIn,
    this.level,
    this.totalPoints,
  });

  final String id;
  final String userId;
  final String type;
  final int points;
  final String? familyId;
  final DateTime createdAt;
  final int? streakCount;
  final DateTime? lastCheckIn;
  final int? level;
  final int? totalPoints;

  factory ContributionModel.fromJson(Map<String, dynamic> json) {
    return ContributionModel(
      id: json['id'] as String,
      userId: json['userId'] as String,
      type: json['type'] as String,
      points: json['points'] as int? ?? 0,
      familyId: json['familyId'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      streakCount: json['streakCount'] as int?,
      lastCheckIn: json['lastCheckIn'] != null
          ? DateTime.parse(json['lastCheckIn'] as String)
          : null,
      level: json['level'] as int?,
      totalPoints: json['totalPoints'] as int?,
    );
  }
}

class CheckInResult {
  const CheckInResult({
    required this.checkedIn,
    this.streakCount,
    this.longestStreak,
    this.pointsEarned,
    this.newBadges = const [],
    this.message,
  });

  final bool checkedIn;
  final int? streakCount;
  final int? longestStreak;
  final int? pointsEarned;
  final List<String> newBadges;
  final String? message;

  factory CheckInResult.fromJson(Map<String, dynamic> json) {
    return CheckInResult(
      checkedIn: json['checkedIn'] as bool? ?? false,
      streakCount: json['streakCount'] as int?,
      longestStreak: json['longestStreak'] as int?,
      pointsEarned: json['pointsEarned'] as int?,
      newBadges: (json['newBadges'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      message: json['message'] as String?,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// GamificationService — API calls
// ═══════════════════════════════════════════════════════════════════════

class GamificationService {
  GamificationService(this._ref);
  final Ref _ref;

  static const _basePath = '/v1/gamification';

  /// Get all available badges.
  Future<List<BadgeModel>> getBadges() async {
    final dio = _ref.read(dioProvider);
    final response = await dio.get('$_basePath/badges');
    final list = response.data as List<dynamic>;
    return list.map((e) => BadgeModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Get the current user's earned badges.
  Future<List<UserBadgeModel>> getMyBadges({String? familyId}) async {
    final dio = _ref.read(dioProvider);
    final query = <String, dynamic>{};
    if (familyId != null) query['familyId'] = familyId;
    final response = await dio.get('$_basePath/badges/mine', queryParameters: query);
    final list = response.data as List<dynamic>;
    return list.map((e) => UserBadgeModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Get the current user's contributions (points, level, streak).
  Future<ContributionModel> getContributions({String? familyId}) async {
    final dio = _ref.read(dioProvider);
    final query = <String, dynamic>{};
    if (familyId != null) query['familyId'] = familyId;
    final response = await dio.get('$_basePath/contributions', queryParameters: query);
    return ContributionModel.fromJson(response.data as Map<String, dynamic>);
  }

  /// Perform a daily check-in.
  Future<CheckInResult> checkIn({String? familyId}) async {
    final dio = _ref.read(dioProvider);
    final response = await dio.post('$_basePath/checkin', data: {
      if (familyId != null) 'familyId': familyId,
    });
    return CheckInResult.fromJson(response.data as Map<String, dynamic>);
  }

  /// Submit a daily challenge answer.
  Future<Map<String, dynamic>> submitDailyChallenge({
    required String answer,
    String? familyId,
  }) async {
    final dio = _ref.read(dioProvider);
    final query = <String, dynamic>{};
    if (familyId != null) query['familyId'] = familyId;
    final response = await dio.post(
      '$_basePath/daily-challenge/submit',
      data: {'answer': answer},
      queryParameters: query,
    );
    return response.data as Map<String, dynamic>;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Provider
// ═══════════════════════════════════════════════════════════════════════

final gamificationServiceProvider = Provider<GamificationService>((ref) {
  return GamificationService(ref);
});
