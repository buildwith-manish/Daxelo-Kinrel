// lib/features/chat/data/chat_media_service.dart
//
// DAXELO KINREL — Feature 4: Chat Media Upload Service
//
// Uploads images, voice notes, and videos to the NestJS backend
// (POST /api/families/:familyId/chat/media), which validates the file
// and stores it in Supabase Storage. Returns the public URL + messageId
// which the caller passes to chatProvider.sendMessageWithMedia().
//
// Why not upload directly to Supabase from the client?
//   1. The backend validates file size + MIME type (defense in depth).
//   2. The backend uses the service_role key (no public bucket write
//      access required from the client — more secure).
//   3. The backend can enforce per-family authorization before upload.
//
// The existing chat_screen.dart already has image_picker + record (voice)
// integrations that upload to Supabase Storage directly. This service is
// the NEW preferred path for media uploads via the NestJS backend. The
// old direct-to-Supabase path remains as a fallback for clients that
// haven't migrated yet.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;

import '../../../core/networking/dio_client.dart';
import '../../../core/services/supabase_service.dart';

/// Result of a media upload.
class MediaUploadResult {
  const MediaUploadResult({
    required this.messageId,
    required this.url,
    required this.mediaType,
    required this.mimeType,
    required this.size,
    this.durationSeconds,
  });

  /// The generated message ID to use when calling sendMessage.
  final String messageId;

  /// Public URL of the uploaded file in Supabase Storage.
  final String url;

  /// 'image' | 'voice' | 'video'
  final String mediaType;

  /// e.g. 'image/jpeg', 'audio/m4a'
  final String mimeType;

  /// File size in bytes.
  final int size;

  /// Duration in seconds (for voice/video). Null for images.
  final int? durationSeconds;
}

class ChatMediaService {
  ChatMediaService(this._ref);
  final Ref _ref;

  /// Upload a media file to the backend.
  ///
  /// [filePath] — local file path (from image_picker or record package).
  /// [mediaType] — 'image' | 'voice' | 'video'.
  /// [durationSeconds] — required for voice/video, null for images.
  Future<MediaUploadResult> upload({
    required String familyId,
    required String filePath,
    required String mediaType,
    int? durationSeconds,
  }) async {
    final dio = _ref.read(dioProvider);
    final client = _ref.read(supabaseProvider);
    final accessToken = client?.auth.currentSession?.accessToken ?? '';

    final fileName = p.basename(filePath);
    // Determine MIME type from extension.
    final ext = p.extension(filePath).toLowerCase();
    String mimeType;
    switch (ext) {
      case '.jpg':
      case '.jpeg':
        mimeType = 'image/jpeg';
        break;
      case '.png':
        mimeType = 'image/png';
        break;
      case '.webp':
        mimeType = 'image/webp';
        break;
      case '.gif':
        mimeType = 'image/gif';
        break;
      case '.m4a':
        mimeType = 'audio/m4a';
        break;
      case '.aac':
        mimeType = 'audio/aac';
        break;
      case '.mp3':
        mimeType = 'audio/mpeg';
        break;
      case '.mp4':
        mimeType = mediaType == 'video' ? 'video/mp4' : 'audio/mp4';
        break;
      case '.webm':
        mimeType = 'video/webm';
        break;
      default:
        mimeType = '$mediaType/octet-stream';
    }

    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        filePath,
        filename: fileName,
        contentType: MediaType.parse(mimeType),
      ),
      'mediaType': mediaType,
      if (durationSeconds != null) 'durationSeconds': durationSeconds.toString(),
    });

    final response = await dio.post(
      '/api/families/$familyId/chat/media',
      data: formData,
      options: Options(
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'multipart/form-data',
        },
        sendTimeout: const Duration(seconds: 60), // large files
        receiveTimeout: const Duration(seconds: 30),
      ),
    );

    final data = response.data;
    // The ResponseEnvelopeInterceptor wraps responses in {success, data, ...}.
    final payload = data is Map<String, dynamic> && data.containsKey('data')
        ? data['data'] as Map<String, dynamic>
        : (data is Map<String, dynamic> ? data : <String, dynamic>{});

    return MediaUploadResult(
      messageId: payload['messageId'] as String? ?? '',
      url: payload['url'] as String? ?? '',
      mediaType: payload['mediaType'] as String? ?? mediaType,
      mimeType: payload['mimeType'] as String? ?? mimeType,
      size: payload['size'] as int? ?? 0,
      durationSeconds: payload['durationSeconds'] as int?,
    );
  }
}

final chatMediaServiceProvider = Provider<ChatMediaService>((ref) {
  return ChatMediaService(ref);
});
