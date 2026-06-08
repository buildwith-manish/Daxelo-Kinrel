import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/networking/dio_client.dart';
import '../models/follow_model.dart';

class FollowRepository {
  FollowRepository(this._ref);
  final Ref _ref;

  /// Follow a user
  Future<FollowModel> followUser(String userId) async {
    final dio = _ref.read(dioProvider);
    final response = await dio.post('/follow', data: {'userId': userId});
    return FollowModel.fromJson(response.data);
  }

  /// Unfollow a user
  Future<void> unfollowUser(String userId) async {
    final dio = _ref.read(dioProvider);
    await dio.delete('/follow/$userId');
  }

  /// Accept a follow request
  Future<void> acceptRequest(String followId) async {
    final dio = _ref.read(dioProvider);
    await dio.post('/follow/$followId/accept');
  }

  /// Reject a follow request
  Future<void> rejectRequest(String followId) async {
    final dio = _ref.read(dioProvider);
    await dio.post('/follow/$followId/reject');
  }

  /// Get follow status with a specific user: 'none', 'pending', 'following', 'self'
  Future<String> getFollowStatus(String userId) async {
    final dio = _ref.read(dioProvider);
    final response = await dio.get('/follow/status', queryParameters: {'userId': userId});
    return response.data['status'] as String? ?? 'none';
  }

  /// Get followers list (paginated)
  Future<List<FollowModel>> getFollowers({int page = 1, int limit = 20}) async {
    final dio = _ref.read(dioProvider);
    final response = await dio.get('/follow/followers', queryParameters: {
      'page': page,
      'limit': limit,
    });
    final list = response.data as List? ?? [];
    return list.map((e) => FollowModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Get following list (paginated)
  Future<List<FollowModel>> getFollowing({int page = 1, int limit = 20}) async {
    final dio = _ref.read(dioProvider);
    final response = await dio.get('/follow/following', queryParameters: {
      'page': page,
      'limit': limit,
    });
    final list = response.data as List? ?? [];
    return list.map((e) => FollowModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Get pending follow requests
  Future<List<FollowModel>> getPendingRequests() async {
    final dio = _ref.read(dioProvider);
    final response = await dio.get('/follow/requests');
    final list = response.data as List? ?? [];
    return list.map((e) => FollowModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Get follower and following counts for a user
  Future<Map<String, int>> getFollowCounts(String userId) async {
    final dio = _ref.read(dioProvider);
    final response = await dio.get('/users/$userId/follow-counts');
    return {
      'followers': response.data['followers'] as int? ?? 0,
      'following': response.data['following'] as int? ?? 0,
    };
  }
}

final followRepositoryProvider = Provider<FollowRepository>((ref) {
  return FollowRepository(ref);
});
