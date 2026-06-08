import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/follow_model.dart';
import '../repositories/follow_repository.dart';

// ── State ────────────────────────────────────────────────────────────

class FollowState {
  final Map<String, String> statusMap; // userId -> 'none'|'pending'|'following'|'self'
  final List<FollowModel> followers;
  final List<FollowModel> following;
  final List<FollowModel> pendingRequests;
  final Map<String, int> followCounts; // userId -> followers count
  final bool isLoading;
  final String? error;

  const FollowState({
    this.statusMap = const {},
    this.followers = const [],
    this.following = const [],
    this.pendingRequests = const [],
    this.followCounts = const {},
    this.isLoading = false,
    this.error,
  });

  FollowState copyWith({
    Map<String, String>? statusMap,
    List<FollowModel>? followers,
    List<FollowModel>? following,
    List<FollowModel>? pendingRequests,
    Map<String, int>? followCounts,
    bool? isLoading,
    String? error,
  }) {
    return FollowState(
      statusMap: statusMap ?? this.statusMap,
      followers: followers ?? this.followers,
      following: following ?? this.following,
      pendingRequests: pendingRequests ?? this.pendingRequests,
      followCounts: followCounts ?? this.followCounts,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

// ── Notifier ─────────────────────────────────────────────────────────

class FollowNotifier extends StateNotifier<FollowState> {
  FollowNotifier(this._ref) : super(const FollowState());

  final Ref _ref;

  /// Follow a user
  Future<void> followUser(String userId) async {
    try {
      final repo = _ref.read(followRepositoryProvider);
      await repo.followUser(userId);
      // Optimistically update status
      state = state.copyWith(
        statusMap: {...state.statusMap, userId: 'following'},
      );
    } catch (e) {
      // Revert on error — check if target is private
      try {
        final status = await _ref.read(followRepositoryProvider).getFollowStatus(userId);
        state = state.copyWith(
          statusMap: {...state.statusMap, userId: status},
        );
      } catch (_) {}
    }
  }

  /// Unfollow a user
  Future<void> unfollowUser(String userId) async {
    final prevStatus = state.statusMap[userId];
    state = state.copyWith(
      statusMap: {...state.statusMap, userId: 'none'},
    );
    try {
      await _ref.read(followRepositoryProvider).unfollowUser(userId);
    } catch (e) {
      // Revert
      state = state.copyWith(
        statusMap: {...state.statusMap, userId: prevStatus ?? 'following'},
      );
    }
  }

  /// Accept a follow request
  Future<void> acceptRequest(String followId, String userId) async {
    try {
      await _ref.read(followRepositoryProvider).acceptRequest(followId);
      state = state.copyWith(
        pendingRequests: state.pendingRequests.where((f) => f.id != followId).toList(),
      );
    } catch (e) {
      // Keep request in list on error
    }
  }

  /// Reject a follow request
  Future<void> rejectRequest(String followId, String userId) async {
    try {
      await _ref.read(followRepositoryProvider).rejectRequest(followId);
      state = state.copyWith(
        pendingRequests: state.pendingRequests.where((f) => f.id != followId).toList(),
      );
    } catch (e) {
      // Keep request in list on error
    }
  }

  /// Load follow status for a user
  Future<void> loadFollowStatus(String userId) async {
    try {
      final status = await _ref.read(followRepositoryProvider).getFollowStatus(userId);
      state = state.copyWith(
        statusMap: {...state.statusMap, userId: status},
      );
    } catch (e) {
      // Silently fail — status defaults to 'none'
    }
  }

  /// Load followers list
  Future<void> loadFollowers({int page = 1}) async {
    try {
      final followers = await _ref.read(followRepositoryProvider).getFollowers(page: page);
      state = state.copyWith(followers: followers);
    } catch (e) {
      state = state.copyWith(error: 'Failed to load followers');
    }
  }

  /// Load following list
  Future<void> loadFollowing({int page = 1}) async {
    try {
      final following = await _ref.read(followRepositoryProvider).getFollowing(page: page);
      state = state.copyWith(following: following);
    } catch (e) {
      state = state.copyWith(error: 'Failed to load following');
    }
  }

  /// Load pending follow requests
  Future<void> loadPendingRequests() async {
    try {
      final requests = await _ref.read(followRepositoryProvider).getPendingRequests();
      state = state.copyWith(pendingRequests: requests);
    } catch (e) {
      state = state.copyWith(error: 'Failed to load requests');
    }
  }

  /// Load follow counts for a user
  Future<void> loadFollowCounts(String userId) async {
    try {
      final counts = await _ref.read(followRepositoryProvider).getFollowCounts(userId);
      state = state.copyWith(followCounts: {...state.followCounts, userId: counts['followers'] ?? 0});
    } catch (e) {
      // Silently fail
    }
  }

  /// Handle socket event: follow:request received
  void onFollowRequestReceived(Map<String, dynamic> data) {
    // Add to pending requests optimistically
    final follow = FollowModel.fromJson(data);
    state = state.copyWith(
      pendingRequests: [follow, ...state.pendingRequests],
    );
  }

  /// Handle socket event: follow:accepted
  void onFollowAccepted(String userId) {
    state = state.copyWith(
      statusMap: {...state.statusMap, userId: 'following'},
    );
  }

  /// Handle socket event: follow:new (someone followed you)
  void onNewFollower(String userId) {
    // Trigger a refresh of followers list
    loadFollowers();
  }
}

// ── Providers ────────────────────────────────────────────────────────

final followProvider = StateNotifierProvider<FollowNotifier, FollowState>((ref) {
  return FollowNotifier(ref);
});

/// Returns the follow status for a specific user
final followStatusProvider = Provider.family<String, String>((ref, userId) {
  final state = ref.watch(followProvider);
  return state.statusMap[userId] ?? 'none';
});

/// Returns follow counts for a specific user
final followCountsProvider = FutureProvider.family<Map<String, int>, String>((ref, userId) async {
  final repo = ref.read(followRepositoryProvider);
  return repo.getFollowCounts(userId);
});
