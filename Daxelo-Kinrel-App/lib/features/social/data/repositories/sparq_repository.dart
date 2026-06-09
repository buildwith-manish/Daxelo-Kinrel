import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:dio/dio.dart';
import '../../../../core/networking/dio_client.dart';
import '../models/sparq_model.dart';

class SparqRepository {
  SparqRepository(this._ref);
  final Ref _ref;

  /// Get the Sparq feed (grouped by user)
  Future<List<UserSparqGroup>> getFeed({int page = 1, int limit = 20}) async {
    final dio = _ref.read(dioProvider);
    final response = await dio.get('/sparq/feed', queryParameters: {'page': page, 'limit': limit});
    final list = response.data as List? ?? [];
    return list.map((e) => UserSparqGroup.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Get active Sparqs for a specific user
  Future<List<SparqModel>> getUserSparqs(String userId) async {
    final dio = _ref.read(dioProvider);
    final response = await dio.get('/sparq/user/$userId');
    final list = response.data as List? ?? [];
    return list.map((e) => SparqModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Create a new Sparq with file upload
  Future<SparqModel> createSparq({
    required String type,
    String? text,
    String? backgroundColor,
    String audience = 'PUBLIC',
    File? mediaFile,
    int? duration,
    String mood = 'happy',
    String intensity = 'warm',
    bool allowChain = false,
    bool allowReplies = true,
    bool isTimeCapsule = false,
    DateTime? revealAt,
    String? parentSparqId,
  }) async {
    final dio = _ref.read(dioProvider);
    final formData = FormData.fromMap({
      'type': type,
      'audience': audience,
      'mood': mood,
      'intensity': intensity,
      'allowChain': allowChain,
      'allowReplies': allowReplies,
      'isTimeCapsule': isTimeCapsule,
      if (text != null) 'text': text,
      if (backgroundColor != null) 'backgroundColor': backgroundColor,
      if (duration != null) 'duration': duration,
      if (revealAt != null) 'revealAt': revealAt.toIso8601String(),
      if (parentSparqId != null) 'parentSparqId': parentSparqId,
      if (mediaFile != null)
        'media': await MultipartFile.fromFile(
          mediaFile.path,
          filename: mediaFile.path.split('/').last,
        ),
    });
    final response = await dio.post('/sparq', data: formData);
    return SparqModel.fromJson(response.data);
  }

  /// Mark a Sparq as viewed
  Future<void> markViewed(String sparqId) async {
    final dio = _ref.read(dioProvider);
    await dio.post('/sparq/$sparqId/view');
  }

  /// Get viewers for a Sparq (creator only)
  Future<List<Map<String, dynamic>>> getViewers(String sparqId) async {
    final dio = _ref.read(dioProvider);
    final response = await dio.get('/sparq/$sparqId/viewers');
    final list = response.data as List? ?? [];
    return list.cast<Map<String, dynamic>>();
  }

  /// Delete your own Sparq
  Future<void> deleteSparq(String sparqId) async {
    final dio = _ref.read(dioProvider);
    await dio.delete('/sparq/$sparqId');
  }

  /// Toggle echo on a Sparq — POST /sparq/$sparqId/echo
  /// Returns { echoCount, isEchoed }
  Future<Map<String, dynamic>> toggleEcho(String sparqId) async {
    final dio = _ref.read(dioProvider);
    final response = await dio.post('/sparq/$sparqId/echo');
    return response.data as Map<String, dynamic>;
  }

  /// Get the chain of Sparqs for a parent Sparq — GET /sparq/$sparqId/chain
  Future<List<SparqModel>> getChain(String sparqId) async {
    final dio = _ref.read(dioProvider);
    final response = await dio.get('/sparq/$sparqId/chain');
    final list = response.data as List? ?? [];
    return list.map((e) => SparqModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Add to chain — POST /sparq/$parentSparqId/chain
  Future<SparqModel> addToChain({
    required String parentSparqId,
    required String type,
    String? text,
    String? backgroundColor,
    File? mediaFile,
    int? duration,
    String mood = 'happy',
    String intensity = 'warm',
  }) async {
    final dio = _ref.read(dioProvider);
    final formData = FormData.fromMap({
      'type': type,
      'mood': mood,
      'intensity': intensity,
      if (text != null) 'text': text,
      if (backgroundColor != null) 'backgroundColor': backgroundColor,
      if (duration != null) 'duration': duration,
      if (mediaFile != null)
        'media': await MultipartFile.fromFile(
          mediaFile.path,
          filename: mediaFile.path.split('/').last,
        ),
    });
    final response = await dio.post('/sparq/$parentSparqId/chain', data: formData);
    return SparqModel.fromJson(response.data);
  }
}

final sparqRepositoryProvider = Provider<SparqRepository>((ref) {
  return SparqRepository(ref);
});
