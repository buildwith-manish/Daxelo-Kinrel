// lib/features/feed/providers/feed_provider.dart
//
// DAXELO KINREL — Feed Provider (Instagram-style Family Feed)
//
// Uses Supabase directly (following existing pattern).
// FamilyPost records are auto-generated when family events happen.

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/family/family_provider.dart';

// ── Table name constants ──────────────────────────────────────────
const _kFamilyPostTable = 'FamilyPost';

// ── Data Models ──────────────────────────────────────────────────

/// Post types for the family feed.
enum FeedPostType {
  relationshipDiscovered('relationship_discovered'),
  memberJoined('member_joined'),
  milestone('milestone'),
  connectionAdded('connection_added'),
  inviteShared('invite_shared');

  const FeedPostType(this.key);
  final String key;

  static FeedPostType fromKey(String key) {
    return FeedPostType.values.firstWhere(
      (e) => e.key == key,
      orElse: () => FeedPostType.memberJoined,
    );
  }
}

/// A family feed post — displayed as an Instagram-style card.
class FamilyPost {
  const FamilyPost({
    required this.id,
    required this.familyId,
    required this.authorId,
    required this.postType,
    required this.content,
    this.reactions = const {},
    this.createdAt,
    // Joined data
    this.familyName,
    this.familyUsername,
    this.authorName,
    this.authorUsername,
  });

  factory FamilyPost.fromJson(Map<String, dynamic> json) {
    return FamilyPost(
      id: json['id']?.toString() ?? '',
      familyId: json['familyId'] as String? ?? '',
      authorId: json['authorId'] as String? ?? '',
      postType: FeedPostType.fromKey(
        json['postType'] as String? ?? 'member_joined',
      ),
      content: json['content'] as Map<String, dynamic>? ?? {},
      reactions: json['reactions'] as Map<String, dynamic>? ?? {},
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      familyName: json['familyName'] as String?,
      familyUsername: json['familyUsername'] as String?,
      authorName: json['authorName'] as String?,
      authorUsername: json['authorUsername'] as String?,
    );
  }

  final String id;
  final String familyId;
  final String authorId;
  final FeedPostType postType;
  final Map<String, dynamic> content;
  final Map<String, dynamic> reactions;
  final DateTime? createdAt;

  // Joined fields (populated by query with foreign key joins)
  final String? familyName;
  final String? familyUsername;
  final String? authorName;
  final String? authorUsername;

  /// Heart reaction count
  int get heartCount => (reactions['heart'] as int?) ?? 0;

  /// Comment count
  int get commentCount => (reactions['comment'] as int?) ?? 0;

  /// Whether current user has hearted this post
  bool get isHearted => (reactions['isHearted'] as bool?) ?? false;

  /// Whether current user has saved this post
  bool get isSaved => (reactions['isSaved'] as bool?) ?? false;

  /// Relative time string
  String get timeAgo {
    if (createdAt == null) return '';
    final diff = DateTime.now().difference(createdAt!);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }

  FamilyPost copyWith({Map<String, dynamic>? reactions}) {
    return FamilyPost(
      id: id,
      familyId: familyId,
      authorId: authorId,
      postType: postType,
      content: content,
      reactions: reactions ?? this.reactions,
      createdAt: createdAt,
      familyName: familyName,
      familyUsername: familyUsername,
      authorName: authorName,
      authorUsername: authorUsername,
    );
  }
}

// ── Feed State ──────────────────────────────────────────────────

class FeedState {
  const FeedState({
    this.posts = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.page = 1,
    this.error,
  });

  final List<FamilyPost> posts;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final int page;
  final String? error;

  FeedState copyWith({
    List<FamilyPost>? posts,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    int? page,
    String? error,
  }) {
    return FeedState(
      posts: posts ?? this.posts,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      page: page ?? this.page,
      error: error,
    );
  }
}

// ── Feed Notifier ──────────────────────────────────────────────────

class FeedNotifier extends StateNotifier<FeedState> {
  FeedNotifier(this._ref) : super(const FeedState());

  final Ref _ref;
  static const int _pageSize = 10;

  /// Load initial feed for a family
  Future<void> loadFeed(String familyId) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) {
        state = state.copyWith(isLoading: false, error: 'Not connected');
        return;
      }

      // LOGIN BYPASSED: Guard against no valid session — RLS will deny queries
      final session = client.auth.currentSession;
      if (session == null) {
        state = state.copyWith(isLoading: false, posts: []);
        return;
      }

      final response = await withRetry(
        () => client
            .from(_kFamilyPostTable)
            .select('*, Family(name, username), Person(name, username)')
            .eq('familyId', familyId)
            .order('createdAt', ascending: false)
            .range(0, _pageSize - 1),
        operationName: 'Load feed',
      );

      final posts = (response as List)
          .map(
            (json) => FamilyPost.fromJson(
              _flattenJoins(json as Map<String, dynamic>),
            ),
          )
          .toList();

      state = state.copyWith(
        posts: posts,
        isLoading: false,
        hasMore: posts.length >= _pageSize,
        page: 1,
      );
    } catch (e) {
      debugPrint('⚠️ Feed load error: $e');
      // If the FamilyPost table doesn't exist yet in Supabase,
      // show empty feed instead of an error — this is expected for new setups
      final errMsg = e.toString();
      final isTableMissing = errMsg.contains('does not exist') ||
          errMsg.contains('not found') ||
          errMsg.contains('relation');
      state = state.copyWith(
        isLoading: false,
        error: isTableMissing ? null : errMsg,
        posts: [],
      );
    }
  }

  /// Load more posts (pagination)
  Future<void> loadMore(String familyId) async {
    if (state.isLoadingMore || !state.hasMore) return;

    state = state.copyWith(isLoadingMore: true);

    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) return;

      final nextPage = state.page + 1;
      final offset = state.page * _pageSize;

      final response = await withRetry(
        () => client
            .from(_kFamilyPostTable)
            .select('*, Family(name, username), Person(name, username)')
            .eq('familyId', familyId)
            .order('createdAt', ascending: false)
            .range(offset, offset + _pageSize - 1),
        operationName: 'Load more feed',
      );

      final newPosts = (response as List)
          .map(
            (json) => FamilyPost.fromJson(
              _flattenJoins(json as Map<String, dynamic>),
            ),
          )
          .toList();

      state = state.copyWith(
        posts: [...state.posts, ...newPosts],
        isLoadingMore: false,
        hasMore: newPosts.length >= _pageSize,
        page: nextPage,
      );
    } catch (e) {
      debugPrint('⚠️ Feed load more error: $e');
      state = state.copyWith(isLoadingMore: false);
    }
  }

  /// Toggle heart reaction on a post
  Future<void> toggleHeart(String postId) async {
    final postIndex = state.posts.indexWhere((p) => p.id == postId);
    if (postIndex == -1) return;

    final post = state.posts[postIndex];
    final newHeartCount = post.isHearted
        ? post.heartCount - 1
        : post.heartCount + 1;
    final newReactions = Map<String, dynamic>.from(post.reactions)
      ..['heart'] = newHeartCount
      ..['isHearted'] = !post.isHearted;

    // Optimistic update
    final updatedPosts = List<FamilyPost>.from(state.posts);
    updatedPosts[postIndex] = post.copyWith(reactions: newReactions);
    state = state.copyWith(posts: updatedPosts);

    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) return;

      await withRetry(
        () => client
            .from(_kFamilyPostTable)
            .update({'reactions': newReactions})
            .eq('id', postId),
        operationName: 'Toggle heart',
      );
    } catch (e) {
      debugPrint('⚠️ Toggle heart error: $e');
      // Revert on error
      final revertedPosts = List<FamilyPost>.from(state.posts);
      revertedPosts[postIndex] = post;
      state = state.copyWith(posts: revertedPosts);
    }
  }

  /// Toggle save/bookmark on a post
  Future<void> toggleSave(String postId) async {
    final postIndex = state.posts.indexWhere((p) => p.id == postId);
    if (postIndex == -1) return;

    final post = state.posts[postIndex];
    final newReactions = Map<String, dynamic>.from(post.reactions)
      ..['isSaved'] = !post.isSaved;

    final updatedPosts = List<FamilyPost>.from(state.posts);
    updatedPosts[postIndex] = post.copyWith(reactions: newReactions);
    state = state.copyWith(posts: updatedPosts);

    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) return;

      await withRetry(
        () => client
            .from(_kFamilyPostTable)
            .update({'reactions': newReactions})
            .eq('id', postId),
        operationName: 'Toggle save',
      );
    } catch (e) {
      debugPrint('⚠️ Toggle save error: $e');
      final revertedPosts = List<FamilyPost>.from(state.posts);
      revertedPosts[postIndex] = post;
      state = state.copyWith(posts: revertedPosts);
    }
  }

  /// Generate feed posts from existing family data (auto-populate)
  Future<void> generatePostsFromFamilyData(String familyId) async {
    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) return;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;

      // Check if posts already exist for this family
      final existing = await withRetry(
        () => client
            .from(_kFamilyPostTable)
            .select('id')
            .eq('familyId', familyId)
            .limit(1),
        operationName: 'Check existing posts',
      );

      if ((existing as List).isNotEmpty) return; // Posts already exist

      // Fetch family detail
      final detailAsync = _ref.read(familyDetailProvider(familyId));
      final detail = detailAsync.value;
      if (detail == null) return;

      final now = DateTime.now();
      final posts = <Map<String, dynamic>>[];

      // Generate "member_joined" posts for each member
      for (final member in detail.members) {
        posts.add({
          'id': _generateId(),
          'familyId': familyId,
          'authorId': member.id,
          'postType': 'member_joined',
          'content': {
            'memberName': member.name,
            'memberGender': member.gender,
            'familyUsername':
                detail.family.familyCode ??
                detail.family.name.toLowerCase().replaceAll(' ', '_'),
          },
          'reactions': {
            'heart': 0,
            'comment': 0,
            'isHearted': false,
            'isSaved': false,
          },
          'createdAt':
              member.createdAt?.toIso8601String() ??
              now
                  .subtract(Duration(hours: detail.members.indexOf(member) + 1))
                  .toIso8601String(),
        });
      }

      // Generate "connection_added" posts for each relationship
      for (final rel in detail.relationships) {
        final fromPerson = detail.members
            .where((m) => m.id == rel.fromPersonId)
            .firstOrNull;
        final toPerson = detail.members
            .where((m) => m.id == rel.toPersonId)
            .firstOrNull;
        if (fromPerson == null || toPerson == null) continue;

        posts.add({
          'id': _generateId(),
          'familyId': familyId,
          'authorId': userId,
          'postType': 'connection_added',
          'content': {
            'fromName': fromPerson.name,
            'fromGender': fromPerson.gender,
            'toName': toPerson.name,
            'toGender': toPerson.gender,
            'relationshipKey': rel.relationshipKey,
            'kinshipTerms': _getKinshipTerms(rel.relationshipKey),
          },
          'reactions': {
            'heart': 0,
            'comment': 0,
            'isHearted': false,
            'isSaved': false,
          },
          'createdAt':
              rel.createdAt?.toIso8601String() ??
              now
                  .subtract(
                    Duration(hours: detail.relationships.indexOf(rel) + 2),
                  )
                  .toIso8601String(),
        });
      }

      // Generate "milestone" post if significant
      if (detail.members.length >= 3) {
        posts.add({
          'id': _generateId(),
          'familyId': familyId,
          'authorId': userId,
          'postType': 'milestone',
          'content': {
            'milestoneType': 'generations',
            'milestoneValue': detail.family.generationCount,
            'memberCount': detail.members.length,
            'memberNames': detail.members.take(5).map((m) => m.name).toList(),
          },
          'reactions': {
            'heart': 0,
            'comment': 0,
            'isHearted': false,
            'isSaved': false,
          },
          'createdAt': now.subtract(const Duration(hours: 3)).toIso8601String(),
        });
      }

      // Batch insert posts
      if (posts.isNotEmpty) {
        await withRetry(
          () => client.from(_kFamilyPostTable).insert(posts),
          operationName: 'Generate feed posts',
        );
      }
    } catch (e) {
      debugPrint('⚠️ Generate posts error: $e');
    }
  }

  /// Flatten Supabase join results into the FamilyPost model fields
  static Map<String, dynamic> _flattenJoins(Map<String, dynamic> json) {
    final family = json['Family'] as Map<String, dynamic>?;
    final person = json['Person'] as Map<String, dynamic>?;

    return {
        ...json,
        'familyName': family?['name'] as String?,
        'familyUsername': family?['username'] as String?,
        'authorName': person?['name'] as String?,
        'authorUsername': person?['username'] as String?,
      }
      ..remove('Family')
      ..remove('Person');
  }

  /// Get kinship terms in multiple Indian languages for a relationship key
  static List<Map<String, String>> _getKinshipTerms(String key) {
    const termMap = <String, List<Map<String, String>>>{
      'father': [
        {'lang': 'hi', 'term': 'पिता'},
        {'lang': 'te', 'term': 'తండ్రి'},
        {'lang': 'bn', 'term': 'পিতা'},
      ],
      'mother': [
        {'lang': 'hi', 'term': 'माता'},
        {'lang': 'te', 'term': 'తల్లి'},
        {'lang': 'bn', 'term': 'মাতা'},
      ],
      'chacha': [
        {'lang': 'hi', 'term': 'चाचा'},
        {'lang': 'te', 'term': 'చాచా'},
        {'lang': 'bn', 'term': 'চাচা'},
      ],
      'brother': [
        {'lang': 'hi', 'term': 'भाई'},
        {'lang': 'te', 'term': 'సోదరుడు'},
        {'lang': 'bn', 'term': 'ভাই'},
      ],
      'sister': [
        {'lang': 'hi', 'term': 'बहन'},
        {'lang': 'te', 'term': 'సోదరి'},
        {'lang': 'bn', 'term': 'বোন'},
      ],
    };

    return termMap[key] ??
        [
          {'lang': 'hi', 'term': key},
        ];
  }
}

/// Generate a CUID-like ID for database inserts.
/// Uses Random to avoid duplicate IDs when generating in a tight loop
/// (DateTime.now().microsecond doesn't change between iterations).
String _generateId() {
  final timestamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final random = Random();
  final rand = List.generate(
    16,
    (_) => random.nextInt(36),
  ).map((v) => v.toRadixString(36)).join();
  return 'c$timestamp$rand'.substring(0, 25);
}

// ── Providers ──────────────────────────────────────────────────

/// Feed notifier provider
final feedProvider = StateNotifierProvider<FeedNotifier, FeedState>((ref) {
  return FeedNotifier(ref);
});

/// Convenience provider that returns feed for a specific family
final familyFeedProvider = Provider.family<FeedState, String>((ref, familyId) {
  return ref.watch(feedProvider);
});
