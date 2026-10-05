import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart' as dio;
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

  final String id;
  final String sparqId;
  final String userId;
  final String userName;
  final String? userAvatarUrl;
  final String content;
  final DateTime createdAt;
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
  ///
  /// [mediaFile] is an [XFile] (from `cross_file`) — works on both web
  /// (blob URL path) and native (real file path). The bytes are read
  /// via `mediaFile.readAsBytes()` (cross-platform) and uploaded via
  /// `MultipartFile.fromBytes` (rather than `fromFile`, which only
  /// works on native filesystem paths).
  Future<SparqModel> createSparq({
    required String type,
    String? text,
    String? backgroundColor,
    String audience = 'PUBLIC',
    XFile? mediaFile,
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
        'media': dio.MultipartFile.fromBytes(
          await mediaFile.readAsBytes(),
          filename: mediaFile.name.isNotEmpty
              ? mediaFile.name
              : 'media-${DateTime.now().millisecondsSinceEpoch}',
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
  ///
  /// [mediaFile] is an [XFile] — works on web blob URLs AND native file
  /// paths (uses readAsBytes + MultipartFile.fromBytes).
  Future<SparqModel> addToChain({
    required String parentSparqId,
    required String type,
    String? text,
    String? backgroundColor,
    XFile? mediaFile,
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
        'media': dio.MultipartFile.fromBytes(
          await mediaFile.readAsBytes(),
          filename: mediaFile.name.isNotEmpty
              ? mediaFile.name
              : 'media-${DateTime.now().millisecondsSinceEpoch}',
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

      return SparqReply.fromJson(response);
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
