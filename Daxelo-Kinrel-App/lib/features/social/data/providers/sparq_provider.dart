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

  // ── New Sparq Enhancement State ──────────────────────────────────
  final String selectedMood; // happy/hype/love/sad/celebrate/angry
  final double selectedIntensity; // 0.0 to 1.0, maps to calm/warm/fire
  final bool isTimeCapsule;
  final DateTime? revealAt;
  final bool allowChain;
  final bool allowReplies;

  // ── Echo state: sparqId → isEchoed ──────────────────────────────
  final Map<String, bool> echoedSparqs;

  // ── Echo counts: sparqId → echoCount ────────────────────────────
  final Map<String, int> echoCounts;

  const SparqState({
    this.feed = const [],
    this.isLoading = false,
    this.error,
    this.isCreating = false,
    this.createProgress = 0.0,
    this.selectedMood = 'happy',
    this.selectedIntensity = 0.5,
    this.isTimeCapsule = false,
    this.revealAt,
    this.allowChain = false,
    this.allowReplies = true,
    this.echoedSparqs = const {},
    this.echoCounts = const {},
  });

  /// Maps intensity slider value (0.0-1.0) to string label
  String get intensityLabel {
    if (selectedIntensity <= 0.33) return 'calm';
    if (selectedIntensity <= 0.66) return 'warm';
    return 'fire';
  }

  SparqState copyWith({
    List<UserSparqGroup>? feed,
    bool? isLoading,
    String? error,
    bool? isCreating,
    double? createProgress,
    String? selectedMood,
    double? selectedIntensity,
    bool? isTimeCapsule,
    DateTime? revealAt,
    bool clearRevealAt = false,
    bool? allowChain,
    bool? allowReplies,
    Map<String, bool>? echoedSparqs,
    Map<String, int>? echoCounts,
  }) {
    return SparqState(
      feed: feed ?? this.feed,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      isCreating: isCreating ?? this.isCreating,
      createProgress: createProgress ?? this.createProgress,
      selectedMood: selectedMood ?? this.selectedMood,
      selectedIntensity: selectedIntensity ?? this.selectedIntensity,
      isTimeCapsule: isTimeCapsule ?? this.isTimeCapsule,
      revealAt: clearRevealAt ? null : (revealAt ?? this.revealAt),
      allowChain: allowChain ?? this.allowChain,
      allowReplies: allowReplies ?? this.allowReplies,
      echoedSparqs: echoedSparqs ?? this.echoedSparqs,
      echoCounts: echoCounts ?? this.echoCounts,
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

  /// Create a new Sparq with all enhancement fields
  Future<bool> createSparq({
    required String type,
    String? text,
    String? backgroundColor,
    String audience = 'PUBLIC',
    File? mediaFile,
    int? duration,
    String? mood,
    String? intensity,
    bool? allowChain,
    bool? allowReplies,
    bool? isTimeCapsule,
    DateTime? revealAt,
    String? parentSparqId,
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
        mood: mood ?? state.selectedMood,
        intensity: intensity ?? state.intensityLabel,
        allowChain: allowChain ?? state.allowChain,
        allowReplies: allowReplies ?? state.allowReplies,
        isTimeCapsule: isTimeCapsule ?? state.isTimeCapsule,
        revealAt: revealAt ?? state.revealAt,
        parentSparqId: parentSparqId,
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

  /// Toggle echo on a Sparq — calls API and updates local state
  Future<void> toggleEcho(String sparqId) async {
    // Optimistic update
    final wasEchoed = state.echoedSparqs[sparqId] ?? false;
    final currentCount = state.echoCounts[sparqId] ?? 0;

    state = state.copyWith(
      echoedSparqs: Map.from(state.echoedSparqs)..[sparqId] = !wasEchoed,
      echoCounts: Map.from(state.echoCounts)..[sparqId] = wasEchoed ? (currentCount - 1).clamp(0, 999999) : currentCount + 1,
    );

    try {
      final result = await _ref.read(sparqRepositoryProvider).toggleEcho(sparqId);
      // Update with server truth
      state = state.copyWith(
        echoedSparqs: Map.from(state.echoedSparqs)..[sparqId] = result['isEchoed'] as bool? ?? !wasEchoed,
        echoCounts: Map.from(state.echoCounts)..[sparqId] = result['echoCount'] as int? ?? currentCount,
      );
    } catch (e) {
      // Revert optimistic update
      state = state.copyWith(
        echoedSparqs: Map.from(state.echoedSparqs)..[sparqId] = wasEchoed,
        echoCounts: Map.from(state.echoCounts)..[sparqId] = currentCount,
      );
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

  // ── State setters for create screen ──────────────────────────────

  void setSelectedMood(String mood) {
    state = state.copyWith(selectedMood: mood);
  }

  void setSelectedIntensity(double value) {
    state = state.copyWith(selectedIntensity: value);
  }

  void setTimeCapsule(bool value) {
    state = state.copyWith(isTimeCapsule: value);
  }

  void setRevealAt(DateTime? dt) {
    if (dt == null) {
      state = state.copyWith(clearRevealAt: true);
    } else {
      state = state.copyWith(revealAt: dt);
    }
  }

  void setAllowChain(bool value) {
    state = state.copyWith(allowChain: value);
  }

  void setAllowReplies(bool value) {
    state = state.copyWith(allowReplies: value);
  }

  void clearError() {
    state = state.copyWith(error: null);
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

/// Get chain for a specific Sparq
final sparqChainProvider = FutureProvider.family<List<SparqModel>, String>((ref, sparqId) async {
  final repo = ref.read(sparqRepositoryProvider);
  return repo.getChain(sparqId);
});
