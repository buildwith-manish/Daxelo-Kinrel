// lib/features/feed/providers/post_create_provider.dart
// DAXELO KINREL — Post Creation Provider
//
// Manages state for the post creation screen:
// text, media file, family selection, audience, occasion, submission.

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/family/family_provider.dart';

// ── Audience enum ──────────────────────────────────────────────

enum PostAudience { familyOnly, public }

// ── Occasion enum ──────────────────────────────────────────────

enum PostOccasion {
  birthday('Birthday'),
  anniversary('Anniversary'),
  festival('Festival'),
  achievement('Achievement'),
  other('Other');

  const PostOccasion(this.label);
  final String label;
}

// ── Post Create State ──────────────────────────────────────────

class PostCreateState {
  const PostCreateState({
    this.text = '',
    this.selectedFamilyId,
    this.mediaFile,
    this.mediaUrl,
    this.audience = PostAudience.familyOnly,
    this.occasion,
    this.location,
    this.isSubmitting = false,
    this.error,
  });

  final String text;
  final String? selectedFamilyId;
  final File? mediaFile;
  final String? mediaUrl;
  final PostAudience audience;
  final PostOccasion? occasion;
  final String? location;
  final bool isSubmitting;
  final String? error;

  bool get hasContent => text.trim().isNotEmpty || mediaFile != null;

  PostCreateState copyWith({
    String? text,
    String? selectedFamilyId,
    File? mediaFile,
    String? mediaUrl,
    bool clearMedia = false,
    PostAudience? audience,
    PostOccasion? occasion,
    String? location,
    bool? isSubmitting,
    String? error,
    bool clearError = false,
  }) {
    return PostCreateState(
      text: text ?? this.text,
      selectedFamilyId: selectedFamilyId ?? this.selectedFamilyId,
      mediaFile: clearMedia ? null : (mediaFile ?? this.mediaFile),
      mediaUrl: clearMedia ? null : (mediaUrl ?? this.mediaUrl),
      audience: audience ?? this.audience,
      occasion: occasion ?? this.occasion,
      location: location ?? this.location,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

// ── Post Create Notifier ───────────────────────────────────────

class PostCreateNotifier extends StateNotifier<PostCreateState> {
  PostCreateNotifier(this._ref) : super(const PostCreateState());

  final Ref _ref;

  void setText(String value) {
    state = state.copyWith(text: value);
  }

  void setSelectedFamilyId(String? familyId) {
    state = state.copyWith(selectedFamilyId: familyId);
  }

  void setMediaFile(File? file) {
    if (file == null) {
      state = state.copyWith(clearMedia: true);
    } else {
      state = state.copyWith(mediaFile: file);
    }
  }

  void setAudience(PostAudience audience) {
    state = state.copyWith(audience: audience);
  }

  void setOccasion(PostOccasion? occasion) {
    state = state.copyWith(occasion: occasion);
  }

  void setLocation(String? location) {
    state = state.copyWith(location: location);
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// Submit the post to the backend
  Future<bool> submit() async {
    if (!state.hasContent || state.selectedFamilyId == null) return false;

    state = state.copyWith(isSubmitting: true, clearError: true);

    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) {
        state = state.copyWith(isSubmitting: false, error: 'Not connected');
        return false;
      }

      final userId = client.auth.currentUser?.id;
      if (userId == null) {
        state = state.copyWith(isSubmitting: false, error: 'Not authenticated');
        return false;
      }

      String? mediaUrl;

      // Upload media to Supabase Storage if present
      if (state.mediaFile != null) {
        try {
          final fileBytes = await state.mediaFile!.readAsBytes();
          final fileName =
              'post-${DateTime.now().millisecondsSinceEpoch}-${state.mediaFile!.path.split('/').last}';
          await client.storage.from('post-media').uploadBinary(
                fileName,
                fileBytes,
                fileOptions: const FileOptions(upsert: true),
              );
          mediaUrl = client.storage.from('post-media').getPublicUrl(fileName);
        } catch (e) {
          debugPrint('⚠️ Media upload error: $e');
          // Continue without media rather than failing
        }
      }

      // Determine post type
      final postType = state.mediaFile != null ? 'photo' : 'text';

      // Build content map
      final content = <String, dynamic>{
        'text': state.text.trim(),
      };
      if (mediaUrl != null) content['mediaUrl'] = mediaUrl;
      if (state.occasion != null) {
        content['occasion'] = state.occasion!.label;
      }
      if (state.location != null && state.location!.isNotEmpty) {
        content['location'] = state.location;
      }

      // Submit via Supabase direct insert
      await client.from('FamilyPost').insert({
        'familyId': state.selectedFamilyId,
        'authorId': userId,
        'postType': postType,
        'content': content,
        'reactions': {
          'heart': 0,
          'comment': 0,
          'isHearted': false,
          'isSaved': false,
        },
        'audience': state.audience == PostAudience.public ? 'PUBLIC' : 'FAMILY_ONLY',
      });

      state = const PostCreateState(); // Reset on success
      return true;
    } catch (e) {
      debugPrint('⚠️ Post create error: $e');
      state = state.copyWith(
        isSubmitting: false,
        error: 'Failed to share post. Please try again.',
      );
      return false;
    }
  }
}

// ── Provider ───────────────────────────────────────────────────

final postCreateProvider =
    StateNotifierProvider<PostCreateNotifier, PostCreateState>((ref) {
  return PostCreateNotifier(ref);
});
