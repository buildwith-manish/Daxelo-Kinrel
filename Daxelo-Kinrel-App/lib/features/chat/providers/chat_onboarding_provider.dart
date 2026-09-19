// lib/features/chat/providers/chat_onboarding_provider.dart
//
// DAXELO KINREL — Feature 7: Chat Onboarding Provider
//
// Fetches the user's onboarding status from the backend
// (GET /api/families/:id/chat/onboarding-status) + exposes it as
// Riverpod state. The chat_screen watches this to decide whether to
// show the coach-mark sequence after the user sends their first message.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/networking/dio_client.dart';
import '../presentation/chat_onboarding_coach_marks.dart';

/// Future provider that fetches the hasSentFirstMessage flag from the
/// backend. The chat_screen calls ref.invalidate() on this after a
/// sendMessage to refresh the status.
final chatOnboardingStatusProvider =
    FutureProvider.family<bool, String>((ref, familyId) async {
  try {
    final dio = ref.watch(dioProvider);
    final response = await dio.get('/api/families/$familyId/chat/onboarding-status');
    final data = response.data;
    final payload = data is Map<String, dynamic> && data.containsKey('data')
        ? data['data']
        : data;
    if (payload is Map<String, dynamic>) {
      return payload['hasSentFirstMessage'] as bool? ?? false;
    }
    return false;
  } catch (e) {
    return false;
  }
});

/// Convenience provider that combines the backend status + the local
/// hasSeenChatOnboarding flag. Returns true if the onboarding should be
/// shown (i.e. the user has sent their first message AND hasn't seen
/// the coach marks yet).
///
/// The chat_screen watches this + shows the ChatOnboardingCoachMarks
/// overlay when it flips to true.
final shouldShowChatOnboardingProvider = Provider.family<bool, String>((ref, familyId) {
  final hasSentFirstMessage = ref.watch(chatOnboardingStatusProvider(familyId)).valueOrNull ?? false;
  final hasSeenOnboarding = ref.watch(hasSeenChatOnboardingProvider);
  return hasSentFirstMessage && !hasSeenOnboarding;
});
