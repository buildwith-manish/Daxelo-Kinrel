import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/sparq_model.dart';
import '../repositories/sparq_repository.dart';

// ── State ────────────────────────────────────────────────────────────

class SparqState {
  final List<UserSparqGroup> feed;
  final bool isLoading;
  final String? error;
  final bool isCreating;
  final double createProgress; // 0.0 to 1.0

  const SparqState({
    this.feed = const [],
    this.isLoading = false,
    this.error,
    this.isCreating = false,
    this.createProgress = 0.0,
  });

  SparqState copyWith({
    List<UserSparqGroup>? feed,
    bool? isLoading,
    String? error,
    bool? isCreating,
    double? createProgress,
  }) {
    return SparqState(
      feed: feed ?? this.feed,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      isCreating: isCreating ?? this.isCreating,
      createProgress: createProgress ?? this.createProgress,
    );
  }
}

// ── Notifier ─────────────────────────────────────────────────────────

class SparqNotifier extends StateNotifier<SparqState> {
  SparqNotifier(this._ref) : super(const SparqState());

  final Ref _ref;

  /// Refresh the Sparq feed
  Future<void> refreshFeed() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final feed = await _ref.read(sparqRepositoryProvider).getFeed();
      state = state.copyWith(feed: feed, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Failed to load Sparqs');
    }
  }

  /// Create a new Sparq
  Future<bool> createSparq({
    required String type,
    String? text,
    String? backgroundColor,
    String audience = 'PUBLIC',
    File? mediaFile,
    int? duration,
  }) async {
    state = state.copyWith(isCreating: true, createProgress: 0.1);
    try {
      await _ref.read(sparqRepositoryProvider).createSparq(
        type: type,
        text: text,
        backgroundColor: backgroundColor,
        audience: audience,
        mediaFile: mediaFile,
        duration: duration,
      );
      state = state.copyWith(isCreating: false, createProgress: 1.0);
      // Refresh feed to show new Sparq
      await refreshFeed();
      return true;
    } catch (e) {
      state = state.copyWith(isCreating: false, createProgress: 0.0, error: 'Failed to create Sparq');
      return false;
    }
  }

  /// Mark a Sparq as viewed and update seen status locally
  Future<void> markSparqViewed(String sparqId, String userId) async {
    // Optimistically update feed
    final updatedFeed = state.feed.map((group) {
      if (group.userId == userId) {
        return UserSparqGroup(
          userId: group.userId,
          userName: group.userName,
          userAvatarUrl: group.userAvatarUrl,
          sparqs: group.sparqs,
          allSeen: group.sparqs.every((s) =>
            s.id == sparqId || _isViewed(s.id)),
        );
      }
      return group;
    }).toList();
    state = state.copyWith(feed: updatedFeed);

    // Fire and forget API call
    try {
      await _ref.read(sparqRepositoryProvider).markViewed(sparqId);
    } catch (e) {
      // Silently fail — optimistic update is fine
    }
  }

  /// Delete your own Sparq
  Future<void> deleteSparq(String sparqId) async {
    try {
      await _ref.read(sparqRepositoryProvider).deleteSparq(sparqId);
      // Remove from feed
      final updatedFeed = state.feed.map((group) {
        final updatedSparqs = group.sparqs.where((s) => s.id != sparqId).toList();
        if (updatedSparqs.isEmpty) return null;
        return UserSparqGroup(
          userId: group.userId,
          userName: group.userName,
          userAvatarUrl: group.userAvatarUrl,
          sparqs: updatedSparqs,
          allSeen: updatedSparqs.every((s) => _isViewed(s.id)),
        );
      }).whereType<UserSparqGroup>().toList();
      state = state.copyWith(feed: updatedFeed);
    } catch (e) {
      state = state.copyWith(error: 'Failed to delete Sparq');
    }
  }

  /// Handle socket event: sparq:new
  void onNewSparq(Map<String, dynamic> data) {
    // Refresh feed to include new Sparq
    refreshFeed();
  }

  // Track viewed Sparq IDs locally for ring color
  final Set<String> _viewedSparqIds = {};

  bool _isViewed(String sparqId) => _viewedSparqIds.contains(sparqId);

  void markLocalViewed(String sparqId) {
    _viewedSparqIds.add(sparqId);
  }
}

// ── Providers ────────────────────────────────────────────────────────

final sparqProvider = StateNotifierProvider<SparqNotifier, SparqState>((ref) {
  return SparqNotifier(ref);
});

/// Get Sparqs for a specific user
final userSparqsProvider = FutureProvider.family<List<SparqModel>, String>((ref, userId) async {
  final repo = ref.read(sparqRepositoryProvider);
  return repo.getUserSparqs(userId);
});

/// Get viewers for a specific Sparq
final sparqViewersProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, sparqId) async {
  final repo = ref.read(sparqRepositoryProvider);
  return repo.getViewers(sparqId);
});
