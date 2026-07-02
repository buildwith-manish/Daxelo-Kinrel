import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:dio/dio.dart' as dio;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/networking/dio_client.dart';
import '../../../../core/services/supabase_service.dart';
import '../models/sparq_model.dart';

/// A text reply to a Sparq.
class SparqReply {
  const SparqReply({
    required this.id,
    required this.sparqId,
    required this.userId,
    required this.userName,
    this.userAvatarUrl,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String sparqId;
  final String userId;
  final String userName;
  final String? userAvatarUrl;
  final String content;
  final DateTime createdAt;

  factory SparqReply.fromJson(Map<String, dynamic> json) {
    return SparqReply(
      id: json['id'] as String? ?? '',
      sparqId: json['sparqId'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      userName: json['userName'] as String? ?? 'Member',
      userAvatarUrl: json['userAvatarUrl'] as String?,
      content: json['content'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class SparqRepository {
  SparqRepository(this._ref);
  final Ref _ref;

  /// Get the Sparq feed (grouped by user)
  Future<List<UserSparqGroup>> getFeed({int page = 1, int limit = 20}) async {
    final httpClient = _ref.read(dioProvider);
    final response = await httpClient.get('/sparq/feed', queryParameters: {'page': page, 'limit': limit});
    final list = response.data as List? ?? [];
    return list.map((e) => UserSparqGroup.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Get active Sparqs for a specific user
  Future<List<SparqModel>> getUserSparqs(String userId) async {
    final httpClient = _ref.read(dioProvider);
    final response = await httpClient.get('/sparq/user/$userId');
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
    final httpClient = _ref.read(dioProvider);
    final formData = dio.FormData.fromMap({
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
        'media': await dio.MultipartFile.fromFile(
          mediaFile.path,
          filename: mediaFile.path.split('/').last,
        ),
    });
    final response = await httpClient.post('/sparq', data: formData);
    return SparqModel.fromJson(response.data);
  }

  /// Mark a Sparq as viewed
  Future<void> markViewed(String sparqId) async {
    final httpClient = _ref.read(dioProvider);
    await httpClient.post('/sparq/$sparqId/view');
  }

  /// Get viewers for a Sparq (creator only)
  Future<List<Map<String, dynamic>>> getViewers(String sparqId) async {
    final httpClient = _ref.read(dioProvider);
    final response = await httpClient.get('/sparq/$sparqId/viewers');
    final list = response.data as List? ?? [];
    return list.cast<Map<String, dynamic>>();
  }

  /// Delete your own Sparq
  Future<void> deleteSparq(String sparqId) async {
    final httpClient = _ref.read(dioProvider);
    await httpClient.delete('/sparq/$sparqId');
  }

  /// Toggle echo on a Sparq — POST /sparq/$sparqId/echo
  /// Returns { echoCount, isEchoed }
  Future<Map<String, dynamic>> toggleEcho(String sparqId) async {
    final httpClient = _ref.read(dioProvider);
    final response = await httpClient.post('/sparq/$sparqId/echo');
    return response.data as Map<String, dynamic>;
  }

  /// Get the chain of Sparqs for a parent Sparq — GET /sparq/$sparqId/chain
  Future<List<SparqModel>> getChain(String sparqId) async {
    final httpClient = _ref.read(dioProvider);
    final response = await httpClient.get('/sparq/$sparqId/chain');
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
    final httpClient = _ref.read(dioProvider);
    final formData = dio.FormData.fromMap({
      'type': type,
      'mood': mood,
      'intensity': intensity,
      if (text != null) 'text': text,
      if (backgroundColor != null) 'backgroundColor': backgroundColor,
      if (duration != null) 'duration': duration,
      if (mediaFile != null)
        'media': await dio.MultipartFile.fromFile(
          mediaFile.path,
          filename: mediaFile.path.split('/').last,
        ),
    });
    final response = await httpClient.post('/sparq/$parentSparqId/chain', data: formData);
    return SparqModel.fromJson(response.data);
  }

  /// Send a text reply to a Sparq (v91).
  ///
  /// Inserts into the Supabase `SparqReply` table (created in migration
  /// `20260702120000_story_sparq_replies_chat_attachments.sql`).
  /// Returns the inserted reply on success, null on failure.
  Future<SparqReply?> replyToSparq({
    required String sparqId,
    required String userId,
    required String userName,
    String? userAvatarUrl,
    required String content,
  }) async {
    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) return null;

      final response = await client
          .from('SparqReply')
          .insert({
            'sparqId': sparqId,
            'userId': userId,
            'userName': userName,
            'userAvatarUrl': userAvatarUrl,
            'content': content,
          })
          .select()
          .single();

      return SparqReply.fromJson(response as Map<String, dynamic>);
    } catch (e) {
      return null;
    }
  }

  /// Fetch all replies for a Sparq, newest first.
  Future<List<SparqReply>> getReplies(String sparqId) async {
    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) return [];

      final response = await client
          .from('SparqReply')
          .select()
          .eq('sparqId', sparqId)
          .order('createdAt', ascending: false);

      return (response as List)
          .map((e) => SparqReply.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }
}

final sparqRepositoryProvider = Provider<SparqRepository>((ref) {
  return SparqRepository(ref);
});
