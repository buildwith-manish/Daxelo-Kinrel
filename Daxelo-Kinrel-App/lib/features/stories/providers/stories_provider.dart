// lib/features/stories/providers/stories_provider.dart
//
// DAXELO KINREL — Stories Provider
//
// Instagram-like stories for families:
//   • Story model with fromJson/toJson
//   • StoryGroup model (user info + list of stories + hasUnviewed flag)
//   • storiesProvider — fetches GET /stories?familyId=xxx
//   • myStoriesProvider — current user's stories
//   • createStoryProvider — posts new stories
//   • markStoryViewedProvider — marks a story as viewed

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/auth_config.dart';
import '../../../core/networking/dio_client.dart';
import '../../../core/services/supabase_service.dart';

// ── Data Models ──────────────────────────────────────────────────

/// A single story item (image/video/text).
class Story {
  const Story({
    required this.id,
    required this.userId,
    required this.familyId,
    required this.type,
    this.caption,
    this.mediaUrl,
    this.gradientColors,
    this.viewers = const [],
    this.createdAt,
    this.expiresAt,
  });

  factory Story.fromJson(Map<String, dynamic> json) {
    return Story(
      id: json['id']?.toString() ?? '',
      userId: json['userId'] as String? ?? '',
      familyId: json['familyId'] as String? ?? '',
      type: json['type'] as String? ?? 'text',
      caption: json['caption'] as String?,
      mediaUrl: json['mediaUrl'] as String?,
      gradientColors: json['gradientColors'] != null
          ? List<String>.from(json['gradientColors'] as List)
          : null,
      viewers: json['viewers'] != null
          ? List<String>.from(
              (json['viewers'] as List).map((v) => v.toString()),
            )
          : [],
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      expiresAt: json['expiresAt'] != null
          ? DateTime.tryParse(json['expiresAt'].toString())
          : null,
    );
  }

  final String id;
  final String userId;
  final String familyId;

  /// Story type: 'text', 'image', 'video'
  final String type;

  /// Caption text for the story
  final String? caption;

  /// URL for image/video stories
  final String? mediaUrl;

  /// Gradient color hex strings for text stories (e.g. ['#E8612A', '#C44A18'])
  final List<String>? gradientColors;

  /// User IDs who have viewed this story
  final List<String> viewers;

  final DateTime? createdAt;
  final DateTime? expiresAt;

  /// Whether a specific user has viewed this story
  bool isViewedBy(String userId) => viewers.contains(userId);

  /// Relative time string
  String get timeAgo {
    if (createdAt == null) return '';
    final diff = DateTime.now().difference(createdAt!);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  /// Whether this story has expired (24-hour default)
  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'familyId': familyId,
        'type': type,
        'caption': caption,
        'mediaUrl': mediaUrl,
        'gradientColors': gradientColors,
        'viewers': viewers,
        'createdAt': createdAt?.toIso8601String(),
        'expiresAt': expiresAt?.toIso8601String(),
      };
}

/// A group of stories from the same user.
/// Analogous to Instagram's story circle per user.
class StoryGroup {
  const StoryGroup({
    required this.userId,
    required this.userName,
    this.userAvatarUrl,
    required this.stories,
    this.hasUnviewed = false,
  });

  factory StoryGroup.fromJson(Map<String, dynamic> json) {
    return StoryGroup(
      userId: json['userId'] as String? ?? '',
      userName: json['userName'] as String? ?? 'Unknown',
      userAvatarUrl: json['userAvatarUrl'] as String?,
      stories: (json['stories'] as List?)
              ?.map((s) => Story.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
      hasUnviewed: json['hasUnviewed'] as bool? ?? false,
    );
  }

  final String userId;
  final String userName;
  final String? userAvatarUrl;
  final List<Story> stories;
  final bool hasUnviewed;

  /// User initials for avatar fallback
  String get initials {
    if (userName.isEmpty) return '?';
    final parts = userName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return userName[0].toUpperCase();
  }

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'userName': userName,
        'userAvatarUrl': userAvatarUrl,
        'stories': stories.map((s) => s.toJson()).toList(),
        'hasUnviewed': hasUnviewed,
      };
}

// ── Providers ──────────────────────────────────────────────────

/// Fetches story groups for a specific family.
/// GET /stories?familyId=xxx
final storiesProvider =
    FutureProvider.family<List<StoryGroup>, String>((ref, familyId) async {
  final dio = ref.read(dioProvider);

  try {
    final response = await dio.get(
      '/stories',
      queryParameters: {'familyId': familyId},
    );

    final data = response.data;

    // Handle response envelope: { data: [...] } or direct list
    List<dynamic> list;
    if (data is Map && data.containsKey('data')) {
      list = data['data'] as List;
    } else if (data is List) {
      list = data;
    } else {
      return [];
    }

    return list
        .map((json) => StoryGroup.fromJson(json as Map<String, dynamic>))
        .where((group) => group.stories.isNotEmpty)
        .toList();
  } on DioException catch (e) {
    // If the stories endpoint doesn't exist yet on the backend (404),
    // return empty list instead of crashing
    if (e.response?.statusCode == 404) {
      debugPrint('ℹ️ Stories endpoint not available yet — returning empty');
      return [];
    }
    debugPrint('⚠️ storiesProvider error: $e');
    return [];
  } catch (e) {
    debugPrint('⚠️ storiesProvider error: $e');
    return [];
  }
});

/// Fetches stories for the current user in a specific family.
final myStoriesProvider =
    FutureProvider.family<List<Story>, String>((ref, familyId) async {
  final dio = ref.read(dioProvider);
  final client = ref.read(supabaseProvider);
  if (client == null) return [];

  final userId = client.auth.currentUser?.id ??
      (kAuthDisabled ? MockUser.id : null);
  if (userId == null) return [];

  try {
    final response = await dio.get(
      '/stories',
      queryParameters: {'familyId': familyId, 'userId': userId},
    );

    final data = response.data;
    List<dynamic> list;
    if (data is Map && data.containsKey('data')) {
      list = data['data'] as List;
    } else if (data is List) {
      list = data;
    } else {
      return [];
    }

    return list
        .map((json) => Story.fromJson(json as Map<String, dynamic>))
        .where((story) => story.userId == userId)
        .toList();
  } on DioException catch (e) {
    if (e.response?.statusCode == 404) return [];
    debugPrint('⚠️ myStoriesProvider error: $e');
    return [];
  } catch (e) {
    debugPrint('⚠️ myStoriesProvider error: $e');
    return [];
  }
});

/// Creates a new story and invalidates the stories list.
final createStoryProvider =
    FutureProvider.family<Story?, CreateStoryParams>((ref, params) async {
  final dio = ref.read(dioProvider);

  try {
    final response = await dio.post(
      '/stories',
      data: params.toJson(),
    );

    final data = response.data;
    if (data is Map && data.containsKey('data')) {
      final story = Story.fromJson(data['data'] as Map<String, dynamic>);
      ref.invalidate(storiesProvider(params.familyId));
      return story;
    } else if (data is Map) {
      final story = Story.fromJson(data as Map<String, dynamic>);
      ref.invalidate(storiesProvider(params.familyId));
      return story;
    }

    ref.invalidate(storiesProvider(params.familyId));
    return null;
  } on DioException catch (e) {
    debugPrint('⚠️ createStoryProvider error: $e');
    return null;
  } catch (e) {
    debugPrint('⚠️ createStoryProvider error: $e');
    return null;
  }
});

/// Marks a story as viewed by the current user.
final markStoryViewedProvider =
    FutureProvider.family<bool, MarkViewedParams>((ref, params) async {
  final dio = ref.read(dioProvider);

  try {
    await dio.post(
      '/stories/${params.storyId}/view',
      data: {'userId': params.userId},
    );
    // Refresh stories so hasUnviewed flags update
    ref.invalidate(storiesProvider(params.familyId));
    return true;
  } on DioException catch (e) {
    debugPrint('⚠️ markStoryViewedProvider error: $e');
    return false;
  } catch (e) {
    debugPrint('⚠️ markStoryViewedProvider error: $e');
    return false;
  }
});

/// Parameters for creating a new story.
class CreateStoryParams {
  const CreateStoryParams({
    required this.familyId,
    required this.type,
    this.caption,
    this.mediaUrl,
    this.gradientColors,
    this.audience,
  });

  final String familyId;

  /// 'text', 'image', or 'video'
  final String type;
  final String? caption;
  final String? mediaUrl;
  final List<String>? gradientColors;

  /// 'PUBLIC' or 'FAMILY_ONLY'
  final String? audience;

  Map<String, dynamic> toJson() => {
        'familyId': familyId,
        'type': type,
        if (caption != null) 'caption': caption,
        if (mediaUrl != null) 'mediaUrl': mediaUrl,
        if (gradientColors != null) 'gradientColors': gradientColors,
        if (audience != null) 'audience': audience,
      };
}

/// Parameters for marking a story as viewed.
class MarkViewedParams {
  const MarkViewedParams({
    required this.storyId,
    required this.userId,
    required this.familyId,
  });

  final String storyId;
  final String userId;
  final String familyId;
}

/// Story gradients for text stories — curated Kinrel-themed presets.
const storyGradients = <List<String>>[
  ['#E8612A', '#C44A18'], // Ignite
  ['#E8612A', '#F59240'], // Sunrise
  ['#C44A18', '#F59240'], // Ember
  ['#131416', '#E8612A'], // Dark Fire
  ['#191B2C', '#E8612A'], // Card to Orange
  ['#202338', '#F59240'], // Elevated to Amber
  ['#D4AF37', '#E8612A'], // Gold to Orange
  ['#2E8B57', '#131416'], // Festival Green
  ['#DC143C', '#F59240'], // Festival Red
  ['#4CAF7A', '#131416'], // Success to Dark
];
