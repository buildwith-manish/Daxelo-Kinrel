// lib/features/community/services/community_service.dart
//
// DAXELO KINREL — Community API Service
//
// Calls the NestJS community backend endpoints.
// Uses the shared dioProvider for authenticated HTTP requests.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/networking/dio_client.dart';

// ═══════════════════════════════════════════════════════════════════════
// API Response Models
// ═══════════════════════════════════════════════════════════════════════

class CommunityModel {
  const CommunityModel({
    required this.id,
    required this.name,
    required this.type,
    this.description,
    this.avatarUrl,
    this.coverUrl,
    this.isPublic = true,
    this.memberCount = 0,
    this.postCount = 0,
    this.gotraName,
    this.villageName,
    this.surname,
    this.region,
    this.rules = const [],
    this.myRole,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String type; // gotra, village, surname, custom
  final String? description;
  final String? avatarUrl;
  final String? coverUrl;
  final bool isPublic;
  final int memberCount;
  final int postCount;
  final String? gotraName;
  final String? villageName;
  final String? surname;
  final String? region;
  final List<Map<String, dynamic>> rules;
  final String? myRole; // admin, moderator, member, null (not joined)
  final DateTime createdAt;

  bool get isJoined => myRole != null;
  bool get isAdmin => myRole == 'admin';
  bool get isModerator => myRole == 'moderator' || myRole == 'admin';

  factory CommunityModel.fromJson(Map<String, dynamic> json) {
    return CommunityModel(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String? ?? 'custom',
      description: json['description'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      coverUrl: json['coverUrl'] as String?,
      isPublic: json['isPublic'] as bool? ?? true,
      memberCount: json['memberCount'] as int? ?? 0,
      postCount: json['postCount'] as int? ?? 0,
      gotraName: json['gotraName'] as String?,
      villageName: json['villageName'] as String?,
      surname: json['surname'] as String?,
      region: json['region'] as String?,
      rules: (json['rules'] as List<dynamic>?)
              ?.map((e) => e as Map<String, dynamic>)
              .toList() ??
          [],
      myRole: json['myRole'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class CommunityPostModel {
  const CommunityPostModel({
    required this.id,
    required this.communityId,
    required this.authorId,
    required this.type,
    required this.body,
    this.title,
    this.mediaUrls = const [],
    this.visibility = 'members_only',
    this.isPinned = false,
    this.isLocked = false,
    this.createdAt,
  });

  final String id;
  final String communityId;
  final String authorId;
  final String type; // discussion, announcement, poll, media
  final String body;
  final String? title;
  final List<String> mediaUrls;
  final String visibility;
  final bool isPinned;
  final bool isLocked;
  final DateTime? createdAt;

  factory CommunityPostModel.fromJson(Map<String, dynamic> json) {
    return CommunityPostModel(
      id: json['id'] as String,
      communityId: json['communityId'] as String,
      authorId: json['authorId'] as String? ?? '',
      type: json['type'] as String? ?? 'discussion',
      body: json['body'] as String,
      title: json['title'] as String?,
      mediaUrls: (json['mediaUrls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      visibility: json['visibility'] as String? ?? 'members_only',
      isPinned: json['isPinned'] as bool? ?? false,
      isLocked: json['isLocked'] as bool? ?? false,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
    );
  }
}

class CommunityEventModel {
  const CommunityEventModel({
    required this.id,
    required this.communityId,
    required this.title,
    this.description,
    this.eventDate,
    this.location,
    this.myRsvp,
    this.attendeeCount = 0,
    required this.createdAt,
  });

  final String id;
  final String communityId;
  final String title;
  final String? description;
  final DateTime? eventDate;
  final String? location;
  final String? myRsvp; // attending, maybe, declined
  final int attendeeCount;
  final DateTime createdAt;

  factory CommunityEventModel.fromJson(Map<String, dynamic> json) {
    return CommunityEventModel(
      id: json['id'] as String,
      communityId: json['communityId'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      eventDate: json['eventDate'] != null
          ? DateTime.parse(json['eventDate'] as String)
          : null,
      location: json['location'] as String?,
      myRsvp: json['myRsvp'] as String?,
      attendeeCount: json['attendeeCount'] as int? ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// CommunityService — API calls
// ═══════════════════════════════════════════════════════════════════════

class CommunityService {
  CommunityService(this._ref);
  final Ref _ref;

  static const _basePath = '/v1/communities';

  /// Search/browse communities.
  Future<List<CommunityModel>> searchCommunities({
    String? type,
    String? search,
    int limit = 20,
    int page = 1,
  }) async {
    final dio = _ref.read(dioProvider);
    final query = <String, dynamic>{
      'limit': limit,
      'page': page,
      if (type != null) 'type': type,
      if (search != null) 'search': search,
    };
    final response = await dio.get(_basePath, queryParameters: query);
    final data = response.data;
    // Handle both paginated and array responses
    final list = data is List ? data : (data['items'] as List<dynamic>? ?? []);
    return list.map((e) => CommunityModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Create a new community.
  Future<CommunityModel> createCommunity({
    required String name,
    required String type,
    String? description,
    bool isPublic = true,
    String? gotraName,
    String? villageName,
    String? surname,
    String? region,
  }) async {
    final dio = _ref.read(dioProvider);
    final response = await dio.post(_basePath, data: {
      'name': name,
      'type': type,
      if (description != null) 'description': description,
      'isPublic': isPublic,
      if (gotraName != null) 'gotraName': gotraName,
      if (villageName != null) 'villageName': villageName,
      if (surname != null) 'surname': surname,
      if (region != null) 'region': region,
    });
    return CommunityModel.fromJson(response.data as Map<String, dynamic>);
  }

  /// Get community detail.
  Future<CommunityModel> getCommunity(String communityId) async {
    final dio = _ref.read(dioProvider);
    final response = await dio.get('$_basePath/$communityId');
    return CommunityModel.fromJson(response.data as Map<String, dynamic>);
  }

  /// Join a community.
  Future<Map<String, dynamic>> joinCommunity(String communityId) async {
    final dio = _ref.read(dioProvider);
    final response = await dio.post('$_basePath/$communityId/join');
    return response.data as Map<String, dynamic>;
  }

  /// Leave a community.
  Future<void> leaveCommunity(String communityId) async {
    final dio = _ref.read(dioProvider);
    await dio.post('$_basePath/$communityId/leave');
  }

  /// Get community posts.
  Future<List<CommunityPostModel>> getPosts(String communityId, {int limit = 20, int page = 1}) async {
    final dio = _ref.read(dioProvider);
    final response = await dio.get('$_basePath/$communityId/posts', queryParameters: {
      'limit': limit,
      'page': page,
    });
    final data = response.data;
    final list = data is List ? data : (data['items'] as List<dynamic>? ?? []);
    return list.map((e) => CommunityPostModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Create a community post.
  Future<CommunityPostModel> createPost(String communityId, {
    required String type,
    required String body,
    String? title,
    List<String>? mediaUrls,
    String visibility = 'members_only',
  }) async {
    final dio = _ref.read(dioProvider);
    final response = await dio.post('$_basePath/$communityId/posts', data: {
      'type': type,
      'body': body,
      if (title != null) 'title': title,
      if (mediaUrls != null) 'mediaUrls': mediaUrls,
      'visibility': visibility,
    });
    return CommunityPostModel.fromJson(response.data as Map<String, dynamic>);
  }

  /// Get community events.
  Future<List<CommunityEventModel>> getEvents(String communityId, {String? filter, int limit = 20, int page = 1}) async {
    final dio = _ref.read(dioProvider);
    final query = <String, dynamic>{
      'limit': limit,
      'page': page,
      if (filter != null) 'filter': filter,
    };
    final response = await dio.get('$_basePath/$communityId/events', queryParameters: query);
    final data = response.data;
    final list = data is List ? data : (data['items'] as List<dynamic>? ?? []);
    return list.map((e) => CommunityEventModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Create a community event.
  Future<CommunityEventModel> createEvent(String communityId, {
    required String title,
    String? description,
    DateTime? eventDate,
    String? location,
  }) async {
    final dio = _ref.read(dioProvider);
    final response = await dio.post('$_basePath/$communityId/events', data: {
      'title': title,
      if (description != null) 'description': description,
      if (eventDate != null) 'eventDate': eventDate.toIso8601String(),
      if (location != null) 'location': location,
    });
    return CommunityEventModel.fromJson(response.data as Map<String, dynamic>);
  }

  /// RSVP to an event.
  Future<Map<String, dynamic>> rsvpEvent(String communityId, String eventId, {required String status}) async {
    final dio = _ref.read(dioProvider);
    final response = await dio.post('$_basePath/$communityId/events/$eventId/rsvp', data: {
      'status': status,
    });
    return response.data as Map<String, dynamic>;
  }

  /// Get pending join requests (admin only).
  Future<List<Map<String, dynamic>>> getPendingRequests(String communityId) async {
    final dio = _ref.read(dioProvider);
    final response = await dio.get('$_basePath/$communityId/members/requests');
    return (response.data as List<dynamic>).map((e) => e as Map<String, dynamic>).toList();
  }

  /// Approve a join request.
  Future<void> approveRequest(String communityId, String userId) async {
    final dio = _ref.read(dioProvider);
    await dio.post('$_basePath/$communityId/members/$userId/approve');
  }

  /// Reject a join request.
  Future<void> rejectRequest(String communityId, String userId) async {
    final dio = _ref.read(dioProvider);
    await dio.post('$_basePath/$communityId/members/$userId/reject');
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Provider
// ═══════════════════════════════════════════════════════════════════════

final communityServiceProvider = Provider<CommunityService>((ref) {
  return CommunityService(ref);
});
