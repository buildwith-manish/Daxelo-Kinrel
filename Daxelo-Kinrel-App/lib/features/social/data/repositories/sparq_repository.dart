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
  }) async {
    final dio = _ref.read(dioProvider);
    final formData = FormData.fromMap({
      'type': type,
      'audience': audience,
      if (text != null) 'text': text,
      if (backgroundColor != null) 'backgroundColor': backgroundColor,
      if (duration != null) 'duration': duration,
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
}

final sparqRepositoryProvider = Provider<SparqRepository>((ref) {
  return SparqRepository(ref);
});
