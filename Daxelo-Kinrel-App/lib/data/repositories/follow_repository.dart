// lib/data/repositories/follow_repository.dart
//
// DAXELO KINREL — Follow Repository
//
// Handles all follow/unfollow API interactions.
// Private accounts require request → accept/reject flow.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/networking/dio_client.dart';
import '../models/follow_model.dart';
import '../../features/profile/data/profile_provider.dart';

/// Abstract interface for follow operations.
abstract class FollowRepository {
  Future<void> followUser(String userId);
  Future<void> unfollowUser(String userId);
  Future<void> acceptFollowRequest(String userId);
  Future<void> rejectFollowRequest(String userId);
  Future<List<UserModel>> getFollowers({int page = 1, int limit = 20});
  Future<List<UserModel>> getFollowing({int page = 1, int limit = 20});
  Future<List<FollowModel>> getFollowRequests();
  Future<String> getFollowStatus(String userId);
  Future<Map<String, int>> getFollowCounts(String userId);
}

/// Concrete implementation using the Dio HTTP client.
class FollowRepositoryImpl implements FollowRepository {
  FollowRepositoryImpl(this._dio);

  final Dio _dio;

  @override
  Future<void> followUser(String userId) async {
    await _dio.post('/v1/follow/', data: {'followingId': userId});
  }

  @override
  Future<void> unfollowUser(String userId) async {
    await _dio.delete('/v1/follow/$userId');
  }

  @override
  Future<void> acceptFollowRequest(String userId) async {
    await _dio.patch('/v1/follow/$userId/accept');
  }

  @override
  Future<void> rejectFollowRequest(String userId) async {
    await _dio.patch('/v1/follow/$userId/reject');
  }

  @override
  Future<List<UserModel>> getFollowers({int page = 1, int limit = 20}) async {
    final response = await _dio.get(
      '/v1/follow/followers',
      queryParameters: {'page': page, 'limit': limit},
    );
    final list = _extractList(response.data);
    return list.map((e) => UserModel.fromJson(e)).toList();
  }

  @override
  Future<List<UserModel>> getFollowing({int page = 1, int limit = 20}) async {
    final response = await _dio.get(
      '/v1/follow/following',
      queryParameters: {'page': page, 'limit': limit},
    );
    final list = _extractList(response.data);
    return list.map((e) => UserModel.fromJson(e)).toList();
  }

  @override
  Future<List<FollowModel>> getFollowRequests() async {
    final response = await _dio.get('/v1/follow/requests');
    final list = _extractList(response.data);
    return list.map((e) => FollowModel.fromJson(e)).toList();
  }

  @override
  Future<String> getFollowStatus(String userId) async {
    final response = await _dio.get('/v1/follow/status/$userId');
    final data = response.data;
    if (data is Map<String, dynamic>) {
      return (data['status'] as String?) ?? 'none';
    }
    return 'none';
  }

  @override
  Future<Map<String, int>> getFollowCounts(String userId) async {
    final response = await _dio.get('/v1/follow/counts/$userId');
    final data = response.data;
    if (data is Map<String, dynamic>) {
      return {
        'followers': _parseInt(data['followers']),
        'following': _parseInt(data['following']),
      };
    }
    return {'followers': 0, 'following': 0};
  }

  // ── Helpers ────────────────────────────────────────────────────

  List<Map<String, dynamic>> _extractList(dynamic data) {
    if (data is List) {
      return data
          .map((e) {
            if (e is Map<String, dynamic>) return e;
            if (e is Map) {
              final converted = <String, dynamic>{};
              for (final entry in e.entries) {
                converted[entry.key.toString()] = entry.value;
              }
              return converted;
            }
            return <String, dynamic>{};
          })
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (data is Map<String, dynamic> && data.containsKey('data')) {
      return _extractList(data['data']);
    }
    return [];
  }

  int _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    if (value is num) return value.toInt();
    return 0;
  }
}

/// Lightweight user model for follow lists.
class UserModel {
  const UserModel({
    required this.id,
    this.name,
    this.username,
    this.avatarUrl,
    this.isPrivate = false,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String?,
      username: json['username'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      isPrivate: json['isPrivate'] as bool? ?? false,
    );
  }

  /// Construct from an existing [ProfileModel].
  factory UserModel.fromProfile(ProfileModel profile) {
    return UserModel(
      id: profile.id,
      name: profile.name,
      username: profile.username,
      avatarUrl: profile.avatarUrl,
    );
  }

  final String id;
  final String? name;
  final String? username;
  final String? avatarUrl;
  final bool isPrivate;

  String get displayName => name ?? username ?? 'User';

  String get initials {
    final source = displayName;
    if (source.isEmpty) return '?';
    final parts = source.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return source[0].toUpperCase();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'username': username,
        'avatarUrl': avatarUrl,
        'isPrivate': isPrivate,
      };
}

/// Provider for the follow repository.
final followRepositoryProvider = Provider<FollowRepository>((ref) {
  return FollowRepositoryImpl(ref.read(dioProvider));
});
