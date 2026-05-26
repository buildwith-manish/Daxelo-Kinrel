import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/networking/dio_client.dart';
import '../../../core/config/env_config.dart';

// ── Models ──────────────────────────────────────────────────────────

class ChatMessage {
  const ChatMessage({
    required this.content,
    required this.isUser,
    required this.timestamp,
    this.kinshipData,
  });

  final String content;
  final bool isUser;
  final DateTime timestamp;
  final List<KinshipCardData>? kinshipData;

}

class KinshipCardData {
  const KinshipCardData({
    required this.relationshipKey,
    required this.englishTerm,
    required this.gender,
    required this.lineage,
    required this.relationshipCategory,
    required this.translations,
  });

  factory KinshipCardData.fromJson(Map<String, dynamic> json) {
    final rawTranslations = json['translations'] as Map<String, dynamic>? ?? {};
    final parsedTranslations = <String, TranslationEntry>{};
    rawTranslations.forEach((lang, value) {
      if (value is Map<String, dynamic>) {
        parsedTranslations[lang] = TranslationEntry(
          native: value['native'] as String? ?? '',
          latin: value['latin'] as String? ?? '',
        );
      }
    });

    return KinshipCardData(
      relationshipKey: json['relationshipKey'] as String? ?? '',
      englishTerm: json['englishTerm'] as String? ?? '',
      gender: json['gender'] as String? ?? '',
      lineage: json['lineage'] as String? ?? '',
      relationshipCategory: json['relationshipCategory'] as String? ?? '',
      translations: parsedTranslations,
    );
  }

  final String relationshipKey;
  final String englishTerm;
  final String gender;
  final String lineage;
  final String relationshipCategory;
  final Map<String, TranslationEntry> translations;

}

class TranslationEntry {
  TranslationEntry({required this.native, required this.latin});

  final String native;
  final String latin;

}

// ── State Providers ─────────────────────────────────────────────────

final aiChatMessagesProvider =
    StateProvider<List<ChatMessage>>((ref) => []);

final aiChatLoadingProvider = StateProvider<bool>((ref) => false);

final aiChatSessionIdProvider = StateProvider<String>((ref) {
  return 'session_${DateTime.now().millisecondsSinceEpoch}';
});

// ── Suggestions Provider ────────────────────────────────────────────

final aiChatSuggestionsProvider = FutureProvider<List<String>>((ref) async {
  final dio = ref.watch(dioProvider);
  try {
    final response = await dio.get(
      '${EnvConfig.apiBaseUrl}/v1/ai-chat/suggestions',
    );
    final data = response.data;
    if (data is Map<String, dynamic> && data['suggestions'] is List) {
      return (data['suggestions'] as List)
          .map((s) => s.toString())
          .toList();
    }
    return [];
  } catch (e) {
    return [
      "What do I call my mother's brother?",
      'Who is Chacha?',
      'What is the difference between Tau and Chacha?',
      'Who is Nanad?',
      "What do I call my husband's younger brother?",
      'Who is Samdhi?',
      'What is the Hindi term for father-in-law?',
    ];
  }
});

// ── Send Message Provider ───────────────────────────────────────────

final aiChatSendMessageProvider = Provider<Future<void> Function(String)>(
  (ref) {
    return (String message) async {
      final dio = ref.watch(dioProvider);
      final messages = ref.read(aiChatMessagesProvider.notifier);
      final loading = ref.read(aiChatLoadingProvider.notifier);
      final sessionId = ref.read(aiChatSessionIdProvider);

      // Add user message
      messages.state = [
        ...messages.state,
        ChatMessage(
          content: message,
          isUser: true,
          timestamp: DateTime.now(),
        ),
      ];

      // Set loading
      loading.state = true;

      try {
        final response = await dio.post(
          '${EnvConfig.apiBaseUrl}/v1/ai-chat',
          data: {
            'sessionId': sessionId,
            'message': message,
          },
        );

        final data = response.data as Map<String, dynamic>;
        final aiResponse = data['response'] as String? ?? 'No response';
        final rawKinship = data['kinshipData'] as List<dynamic>?;

        List<KinshipCardData>? kinshipCards;
        if (rawKinship != null && rawKinship.isNotEmpty) {
          kinshipCards = rawKinship
              .map((k) => KinshipCardData.fromJson(k as Map<String, dynamic>))
              .toList();
        }

        messages.state = [
          ...messages.state,
          ChatMessage(
            content: aiResponse,
            isUser: false,
            timestamp: DateTime.now(),
            kinshipData: kinshipCards,
          ),
        ];
      } catch (e) {
        messages.state = [
          ...messages.state,
          ChatMessage(
            content:
                'Sorry, I couldn\'t process your request. Please try again.',
            isUser: false,
            timestamp: DateTime.now(),
          ),
        ];
      } finally {
        loading.state = false;
      }
    };
  },
);

// ── Clear Session Provider ──────────────────────────────────────────

final aiChatClearSessionProvider = Provider<Future<void> Function()>(
  (ref) {
    return () async {
      final dio = ref.watch(dioProvider);
      final sessionId = ref.read(aiChatSessionIdProvider);

      try {
        await dio.delete(
          '${EnvConfig.apiBaseUrl}/v1/ai-chat/$sessionId',
        );
      } catch (_) {
        // Silently fail - session might not exist on server
      }

      // Reset local state
      ref.read(aiChatMessagesProvider.notifier).state = [];
      ref.read(aiChatSessionIdProvider.notifier).state =
          'session_${DateTime.now().millisecondsSinceEpoch}';
    };
  },
);
