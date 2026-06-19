// lib/features/community/providers/community_provider.dart
//
// DAXELO KINREL — Community State Management
//
// Manages community discovery, detail, posts, events, and membership
// using Riverpod StateNotifierProvider. Wired to NestJS backend.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/community_service.dart';

// ═══════════════════════════════════════════════════════════════════════
// Community Discovery Provider
// ═══════════════════════════════════════════════════════════════════════

/// Search/browse communities.
final communitySearchProvider = FutureProvider.family<List<CommunityModel>, CommunitySearchParams>(
  (ref, params) async {
    final service = ref.read(communityServiceProvider);
    return service.searchCommunities(
      type: params.type,
      search: params.search,
      limit: params.limit,
      page: params.page,
    );
  },
);

class CommunitySearchParams {
  const CommunitySearchParams({this.type, this.search, this.limit = 20, this.page = 1});
  final String? type;
  final String? search;
  final int limit;
  final int page;
}

// ═══════════════════════════════════════════════════════════════════════
// Community Detail Provider
// ═══════════════════════════════════════════════════════════════════════

/// Get a single community's detail.
final communityDetailProvider = FutureProvider.family<CommunityModel, String>(
  (ref, communityId) async {
    final service = ref.read(communityServiceProvider);
    return service.getCommunity(communityId);
  },
);

// ═══════════════════════════════════════════════════════════════════════
// Community Posts Provider
// ═══════════════════════════════════════════════════════════════════════

/// Get posts for a community.
final communityPostsProvider = FutureProvider.family<List<CommunityPostModel>, String>(
  (ref, communityId) async {
    final service = ref.read(communityServiceProvider);
    return service.getPosts(communityId);
  },
);

// ═══════════════════════════════════════════════════════════════════════
// Community Events Provider
// ═══════════════════════════════════════════════════════════════════════

/// Get events for a community.
final communityEventsProvider = FutureProvider.family<List<CommunityEventModel>, CommunityEventsParams>(
  (ref, params) async {
    final service = ref.read(communityServiceProvider);
    return service.getEvents(params.communityId, filter: params.filter);
  },
);

class CommunityEventsParams {
  const CommunityEventsParams({required this.communityId, this.filter});
  final String communityId;
  final String? filter; // upcoming, past
}

// ═══════════════════════════════════════════════════════════════════════
// Community Actions Notifier
// ═══════════════════════════════════════════════════════════════════════

class CommunityActionState {
  const CommunityActionState({
    this.isJoining = false,
    this.isLeaving = false,
    this.isCreatingPost = false,
    this.isCreatingEvent = false,
    this.isRsvping = false,
    this.error,
  });

  final bool isJoining;
  final bool isLeaving;
  final bool isCreatingPost;
  final bool isCreatingEvent;
  final bool isRsvping;
  final String? error;

  CommunityActionState copyWith({
    bool? isJoining,
    bool? isLeaving,
    bool? isCreatingPost,
    bool? isCreatingEvent,
    bool? isRsvping,
    String? error,
  }) {
    return CommunityActionState(
      isJoining: isJoining ?? this.isJoining,
      isLeaving: isLeaving ?? this.isLeaving,
      isCreatingPost: isCreatingPost ?? this.isCreatingPost,
      isCreatingEvent: isCreatingEvent ?? this.isCreatingEvent,
      isRsvping: isRsvping ?? this.isRsvping,
      error: error,
    );
  }
}

class CommunityActionNotifier extends StateNotifier<CommunityActionState> {
  CommunityActionNotifier(this._ref) : super(const CommunityActionState());

  final Ref _ref;

  /// Join a community.
  Future<bool> joinCommunity(String communityId) async {
    state = state.copyWith(isJoining: true, error: null);
    try {
      await _ref.read(communityServiceProvider).joinCommunity(communityId);
      // Invalidate related providers to refresh
      _ref.invalidate(communityDetailProvider(communityId));
      _ref.invalidate(communitySearchProvider);
      state = state.copyWith(isJoining: false);
      return true;
    } catch (e) {
      state = state.copyWith(isJoining: false, error: e.toString());
      return false;
    }
  }

  /// Leave a community.
  Future<bool> leaveCommunity(String communityId) async {
    state = state.copyWith(isLeaving: true, error: null);
    try {
      await _ref.read(communityServiceProvider).leaveCommunity(communityId);
      _ref.invalidate(communityDetailProvider(communityId));
      _ref.invalidate(communitySearchProvider);
      state = state.copyWith(isLeaving: false);
      return true;
    } catch (e) {
      state = state.copyWith(isLeaving: false, error: e.toString());
      return false;
    }
  }

  /// Create a post in a community.
  Future<CommunityPostModel?> createPost(String communityId, {
    required String type,
    required String body,
    String? title,
    List<String>? mediaUrls,
  }) async {
    state = state.copyWith(isCreatingPost: true, error: null);
    try {
      final post = await _ref.read(communityServiceProvider).createPost(
        communityId,
        type: type,
        body: body,
        title: title,
        mediaUrls: mediaUrls,
      );
      _ref.invalidate(communityPostsProvider(communityId));
      state = state.copyWith(isCreatingPost: false);
      return post;
    } catch (e) {
      state = state.copyWith(isCreatingPost: false, error: e.toString());
      return null;
    }
  }

  /// Create an event in a community.
  Future<CommunityEventModel?> createEvent(String communityId, {
    required String title,
    String? description,
    DateTime? eventDate,
    String? location,
  }) async {
    state = state.copyWith(isCreatingEvent: true, error: null);
    try {
      final event = await _ref.read(communityServiceProvider).createEvent(
        communityId,
        title: title,
        description: description,
        eventDate: eventDate,
        location: location,
      );
      _ref.invalidate(communityEventsProvider(CommunityEventsParams(communityId: communityId)));
      state = state.copyWith(isCreatingEvent: false);
      return event;
    } catch (e) {
      state = state.copyWith(isCreatingEvent: false, error: e.toString());
      return null;
    }
  }

  /// RSVP to an event.
  Future<bool> rsvpEvent(String communityId, String eventId, {required String status}) async {
    state = state.copyWith(isRsvping: true, error: null);
    try {
      await _ref.read(communityServiceProvider).rsvpEvent(communityId, eventId, status: status);
      _ref.invalidate(communityEventsProvider(CommunityEventsParams(communityId: communityId)));
      state = state.copyWith(isRsvping: false);
      return true;
    } catch (e) {
      state = state.copyWith(isRsvping: false, error: e.toString());
      return false;
    }
  }
}

final communityActionProvider = StateNotifierProvider<CommunityActionNotifier, CommunityActionState>(
  (ref) => CommunityActionNotifier(ref),
);
