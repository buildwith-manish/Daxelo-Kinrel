// lib/data/repositories/sparq_repository.dart
//
// DAXELO KINREL — Sparq Repository
//
// Handles all Sparq (ephemeral story) API interactions.
// Supports creating, viewing, and managing sparqs.

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/networking/dio_client.dart';
import '../models/sparq_model.dart';
import 'follow_repository.dart'; // for UserModel

/// Abstract interface for Sparq operations.
abstract class SparqRepository {
  Future<List<UserSparqGroup>> getSparqFeed();
  Future<List<SparqModel>> getMySparqs();
  Future<SparqModel> createSparq({
    required String type,
    required String audience,
    File? mediaFile,
    String? text,
    String? bgColor,
  });
  Future<void> deleteSparq(String sparqId);
  Future<void> markViewed(String sparqId);
  Future<List<UserModel>> getSparqViewers(String sparqId);
}

/// Concrete implementation using the Dio HTTP client.
class SparqRepositoryImpl implements SparqRepository {
  SparqRepositoryImpl(this._dio);

  final Dio _dio;

  @override
  Future<List<UserSparqGroup>> getSparqFeed() async {
    final response = await _dio.get('/v1/sparqs/feed');
    final list = _extractList(response.data);
    return list
        .map((e) => UserSparqGroup.fromJson(e))
        .where((g) => g.sparqs.isNotEmpty)
        .toList();
  }

  @override
  Future<List<SparqModel>> getMySparqs() async {
    final response = await _dio.get('/v1/sparqs/mine');
    final list = _extractList(response.data);
    return list.map((e) => SparqModel.fromJson(e)).toList();
  }

  @override
  Future<SparqModel> createSparq({
    required String type,
    required String audience,
    File? mediaFile,
    String? text,
    String? bgColor,
  }) async {
    FormData formData;

    if (mediaFile != null) {
      final fileName = mediaFile.path.split('/').last;
      formData = FormData.fromMap({
        'type': type,
        'audience': audience,
        if (text != null) 'text': text,
        if (bgColor != null) 'bgColor': bgColor,
        'media': await MultipartFile.fromFile(mediaFile.path, filename: fileName),
      });
    } else {
      formData = FormData.fromMap({
        'type': type,
        'audience': audience,
        if (text != null) 'text': text,
        if (bgColor != null) 'bgColor': bgColor,
      });
    }

    final response = await _dio.post(
      '/v1/sparqs/',
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
    );

    final data = response.data;
    if (data is Map<String, dynamic> && data.containsKey('data')) {
      return SparqModel.fromJson(data['data'] as Map<String, dynamic>);
    }
    if (data is Map<String, dynamic>) {
      return SparqModel.fromJson(data);
    }
    throw Exception('Invalid response creating sparq');
  }

  @override
  Future<void> deleteSparq(String sparqId) async {
    await _dio.delete('/v1/sparqs/$sparqId');
  }

  @override
  Future<void> markViewed(String sparqId) async {
    await _dio.post('/v1/sparqs/$sparqId/view');
  }

  @override
  Future<List<UserModel>> getSparqViewers(String sparqId) async {
    final response = await _dio.get('/v1/sparqs/$sparqId/viewers');
    final list = _extractList(response.data);
    return list.map((e) => UserModel.fromJson(e)).toList();
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
}

/// Provider for the sparq repository.
final sparqRepositoryProvider = Provider<SparqRepository>((ref) {
  return SparqRepositoryImpl(ref.read(dioProvider));
});
