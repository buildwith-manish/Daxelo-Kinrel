import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../core/networking/dio_client.dart';
import '../../../core/constants/supported_languages.dart';

// ── State Models ────────────────────────────────────────────────

class VoiceSearchState {
  const VoiceSearchState({
    this.isRecording = false,
    this.isLoading = false,
    this.transcription,
    this.results,
    this.error,
    this.selectedLanguage = SupportedLanguage.hindi,
  });

  final bool isRecording;
  final bool isLoading;
  final String? transcription;
  final List<KinshipVoiceResult>? results;
  final String? error;
  final SupportedLanguage selectedLanguage;

  VoiceSearchState copyWith({
    bool? isRecording,
    bool? isLoading,
    String? transcription,
    List<KinshipVoiceResult>? results,
    String? error,
    SupportedLanguage? selectedLanguage,
  }) {
    return VoiceSearchState(
      isRecording: isRecording ?? this.isRecording,
      isLoading: isLoading ?? this.isLoading,
      transcription: transcription ?? this.transcription,
      results: results ?? this.results,
      error: error ?? this.error,
      selectedLanguage: selectedLanguage ?? this.selectedLanguage,
    );
  }
}

class KinshipVoiceResult {
  const KinshipVoiceResult({
    required this.relationshipKey,
    required this.englishTerm,
    required this.gender,
    required this.lineage,
    required this.generation,
    required this.relationshipCategory,
    required this.searchKeywords,
    required this.translations,
  });

  factory KinshipVoiceResult.fromJson(Map<String, dynamic> json) {
    return KinshipVoiceResult(
      relationshipKey: json['relationshipKey'] as String? ?? '',
      englishTerm: json['englishTerm'] as String? ?? '',
      gender: json['gender'] as String? ?? '',
      lineage: json['lineage'] as String? ?? '',
      generation: json['generation']?.toString() ?? '',
      relationshipCategory: json['relationshipCategory'] as String? ?? '',
      searchKeywords:
          (json['searchKeywords'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      translations: (json['translations'] as Map<String, dynamic>?) ?? {},
    );
  }

  final String relationshipKey;
  final String englishTerm;
  final String gender;
  final String lineage;
  final String generation;
  final String relationshipCategory;
  final List<String> searchKeywords;
  final Map<String, dynamic> translations;
}

class VoiceLookupResult {
  const VoiceLookupResult({required this.transcription, required this.term});

  factory VoiceLookupResult.fromJson(Map<String, dynamic> json) {
    return VoiceLookupResult(
      transcription: json['transcription'] as String? ?? '',
      term: (json['term'] as Map<String, dynamic>?) ?? {},
    );
  }

  final String transcription;
  final Map<String, dynamic> term;
}

// ── Providers ───────────────────────────────────────────────────

/// Voice search state notifier
class VoiceSearchNotifier extends StateNotifier<VoiceSearchState> {
  VoiceSearchNotifier(this._dio) : super(VoiceSearchState());

  final Dio _dio;

  /// Set recording state
  void setRecording(bool isRecording) {
    state = state.copyWith(isRecording: isRecording);
  }

  /// Set selected language
  void setLanguage(SupportedLanguage language) {
    state = state.copyWith(selectedLanguage: language);
  }

  /// Clear current results
  void clearResults() {
    state = VoiceSearchState();
  }

  /// Transcribe audio and search kinship terms
  Future<void> transcribeAndSearch(String base64Audio) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final response = await _dio.post(
        '/v1/ai-voice/transcribe',
        data: {'audio': base64Audio, 'language': state.selectedLanguage.code},
      );

      final data = response.data as Map<String, dynamic>;
      final transcription = data['transcription'] as String? ?? '';
      final resultsList =
          (data['results']?['results'] as List<dynamic>?)
              ?.map(
                (e) => KinshipVoiceResult.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [];

      state = state.copyWith(
        isLoading: false,
        transcription: transcription,
        results: resultsList,
      );
    } on DioException catch (e) {
      final message =
          e.response?.data?['message'] as String? ??
          'Voice search failed. Please try again.';
      state = state.copyWith(isLoading: false, error: message);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'An unexpected error occurred.',
      );
    }
  }

  /// Quick lookup for exact kinship term
  Future<void> quickLookup(String base64Audio) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final response = await _dio.post(
        '/v1/ai-voice/lookup',
        data: {'audio': base64Audio, 'language': state.selectedLanguage.code},
      );

      final lookupResult = VoiceLookupResult.fromJson(
        response.data as Map<String, dynamic>,
      );
      state = state.copyWith(
        isLoading: false,
        transcription: lookupResult.transcription,
        results: [],
      );
    } on DioException catch (e) {
      final message =
          e.response?.data?['message'] as String? ??
          'Voice lookup failed. Please try again.';
      state = state.copyWith(isLoading: false, error: message);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'An unexpected error occurred.',
      );
    }
  }
}

/// Voice search provider
final voiceSearchProvider =
    StateNotifierProvider<VoiceSearchNotifier, VoiceSearchState>((ref) {
      final dio = ref.watch(dioProvider);
      return VoiceSearchNotifier(dio);
    });
