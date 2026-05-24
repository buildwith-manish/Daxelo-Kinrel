import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/networking/dio_client.dart';

// ── Models ─────────────────────────────────────────────────────────────

class ReferralCode {
  final String code;
  final String shareUrl;
  final String shareText;

  const ReferralCode({
    required this.code,
    required this.shareUrl,
    required this.shareText,
  });

  factory ReferralCode.fromJson(Map<String, dynamic> json) {
    return ReferralCode(
      code: json['code'] as String? ?? '',
      shareUrl: json['shareUrl'] as String? ?? '',
      shareText: json['shareText'] as String? ?? '',
    );
  }
}

class ReferralApplication {
  final bool success;
  final String referrerId;
  final String reward;

  const ReferralApplication({
    required this.success,
    required this.referrerId,
    required this.reward,
  });

  factory ReferralApplication.fromJson(Map<String, dynamic> json) {
    return ReferralApplication(
      success: json['success'] as bool? ?? false,
      referrerId: json['referrerId'] as String? ?? '',
      reward: json['reward'] as String? ?? '',
    );
  }
}

class ReferralStats {
  final String code;
  final int totalReferrals;
  final List<String> rewards;
  final List<RecentReferral> recentReferrals;

  const ReferralStats({
    required this.code,
    required this.totalReferrals,
    required this.rewards,
    required this.recentReferrals,
  });

  factory ReferralStats.fromJson(Map<String, dynamic> json) {
    return ReferralStats(
      code: json['code'] as String? ?? '',
      totalReferrals: json['totalReferrals'] as int? ?? 0,
      rewards: (json['rewards'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      recentReferrals: (json['recentReferrals'] as List<dynamic>?)
              ?.map(
                  (e) => RecentReferral.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class RecentReferral {
  final String name;
  final String date;

  const RecentReferral({
    required this.name,
    required this.date,
  });

  factory RecentReferral.fromJson(Map<String, dynamic> json) {
    return RecentReferral(
      name: json['name'] as String? ?? '',
      date: json['date'] as String? ?? '',
    );
  }
}

class RewardTier {
  final int referrals;
  final String reward;
  final String? badge;
  final String description;

  const RewardTier({
    required this.referrals,
    required this.reward,
    this.badge,
    required this.description,
  });

  factory RewardTier.fromJson(Map<String, dynamic> json) {
    return RewardTier(
      referrals: json['referrals'] as int? ?? 0,
      reward: json['reward'] as String? ?? '',
      badge: json['badge'] as String?,
      description: json['description'] as String? ?? '',
    );
  }
}

class RewardsData {
  final List<RewardTier> tiers;

  const RewardsData({required this.tiers});

  factory RewardsData.fromJson(Map<String, dynamic> json) {
    return RewardsData(
      tiers: (json['tiers'] as List<dynamic>?)
              ?.map((e) => RewardTier.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

// ── Referral State ──────────────────────────────────────────────────────

class ReferralState {
  final ReferralCode? code;
  final ReferralStats? stats;
  final bool isGenerating;
  final bool isApplying;
  final String? error;

  const ReferralState({
    this.code,
    this.stats,
    this.isGenerating = false,
    this.isApplying = false,
    this.error,
  });

  ReferralState copyWith({
    ReferralCode? code,
    ReferralStats? stats,
    bool? isGenerating,
    bool? isApplying,
    String? error,
  }) {
    return ReferralState(
      code: code ?? this.code,
      stats: stats ?? this.stats,
      isGenerating: isGenerating ?? this.isGenerating,
      isApplying: isApplying ?? this.isApplying,
      error: error,
    );
  }
}

// ── Providers ──────────────────────────────────────────────────────────

final referralProvider =
    StateNotifierProvider<ReferralNotifier, ReferralState>((ref) {
  return ReferralNotifier(ref);
});

class ReferralNotifier extends StateNotifier<ReferralState> {
  final Ref _ref;

  ReferralNotifier(this._ref) : super(const ReferralState());

  Future<void> generateCode(String userId) async {
    state = state.copyWith(isGenerating: true, error: null);

    try {
      final dio = _ref.read(dioProvider);
      final response = await dio.post(
        '/v1/referral/generate',
        data: {'userId': userId},
      );

      final code =
          ReferralCode.fromJson(response.data as Map<String, dynamic>);

      state = state.copyWith(code: code, isGenerating: false);

      // Also fetch stats
      await fetchStats(userId);
    } catch (e) {
      state = state.copyWith(
        isGenerating: false,
        error: 'Failed to generate referral code',
      );
    }
  }

  Future<void> fetchStats(String userId) async {
    try {
      final dio = _ref.read(dioProvider);
      final response = await dio.get(
        '/v1/referral/stats',
        queryParameters: {'userId': userId},
      );

      final stats =
          ReferralStats.fromJson(response.data as Map<String, dynamic>);

      state = state.copyWith(stats: stats);
    } catch (e) {
      // Stats fetch failed silently
    }
  }

  Future<bool> applyCode(String code, String userId) async {
    state = state.copyWith(isApplying: true, error: null);

    try {
      final dio = _ref.read(dioProvider);
      await dio.post(
        '/v1/referral/apply',
        data: {'code': code, 'userId': userId},
      );

      state = state.copyWith(isApplying: false);
      return true;
    } catch (e) {
      state = state.copyWith(
        isApplying: false,
        error: 'Failed to apply referral code',
      );
      return false;
    }
  }
}

// ── Rewards Provider ───────────────────────────────────────────────────

final rewardsProvider = FutureProvider<RewardsData>((ref) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get('/v1/referral/rewards');
  return RewardsData.fromJson(response.data as Map<String, dynamic>);
});
