import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../core/networking/dio_client.dart';
import '../../../core/constants/supported_languages.dart';

// ── State Models ────────────────────────────────────────────────

class FestivalTemplate {
  factory FestivalTemplate.fromJson(Map<String, dynamic> json) {
    return FestivalTemplate(
      name: json['name'] as String? ?? '',
      icon: json['icon'] as String? ?? '',
      colorTheme: json['colorTheme'] as String? ?? '#FFD700',
      defaultMessageTemplates:
          (json['defaultMessageTemplates'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
          [],
    );
  }

  final String name;
  final String icon;
  final String colorTheme;
  final List<String> defaultMessageTemplates;

  const FestivalTemplate({
    required this.name,
    required this.icon,
    required this.colorTheme,
    required this.defaultMessageTemplates,
  });

}

enum CardStyle { traditional, modern, elegant }

class FestivalCardsState {
  const FestivalCardsState({
    this.isGenerating = false,
    this.imageBase64,
    this.festival,
    this.kinshipTerm,
    this.error,
    this.selectedFestival,
    this.selectedLanguage = SupportedLanguage.hindi,
    this.selectedStyle = CardStyle.traditional,
    this.kinshipTermInput = '',
    this.relationshipKeyInput = '',
  });

  final bool isGenerating;
  final String? imageBase64;
  final String? festival;
  final String? kinshipTerm;
  final String? error;
  final FestivalTemplate? selectedFestival;
  final SupportedLanguage selectedLanguage;
  final CardStyle selectedStyle;
  final String kinshipTermInput;
  final String relationshipKeyInput;


  FestivalCardsState copyWith({
    bool? isGenerating,
    String? imageBase64,
    String? festival,
    String? kinshipTerm,
    String? error,
    FestivalTemplate? selectedFestival,
    SupportedLanguage? selectedLanguage,
    CardStyle? selectedStyle,
    String? kinshipTermInput,
    String? relationshipKeyInput,
  }) {
    return FestivalCardsState(
      isGenerating: isGenerating ?? this.isGenerating,
      imageBase64: imageBase64 ?? this.imageBase64,
      festival: festival ?? this.festival,
      kinshipTerm: kinshipTerm ?? this.kinshipTerm,
      error: error ?? this.error,
      selectedFestival: selectedFestival ?? this.selectedFestival,
      selectedLanguage: selectedLanguage ?? this.selectedLanguage,
      selectedStyle: selectedStyle ?? this.selectedStyle,
      kinshipTermInput: kinshipTermInput ?? this.kinshipTermInput,
      relationshipKeyInput: relationshipKeyInput ?? this.relationshipKeyInput,
    );
  }
}

// ── Providers ───────────────────────────────────────────────────

/// Festival templates provider
final festivalTemplatesProvider =
    FutureProvider<List<FestivalTemplate>>((ref) async {
  final dio = ref.watch(dioProvider);
  try {
    final response = await dio.get('/v1/ai-cards/templates');
    final data = response.data as List<dynamic>;
    return data
        .map((e) => FestivalTemplate.fromJson(e as Map<String, dynamic>))
        .toList();
  } on DioException {
    // Return hardcoded fallback templates if API is unavailable
    return _fallbackTemplates;
  } catch (_) {
    return _fallbackTemplates;
  }
});

/// Festival cards state notifier
class FestivalCardsNotifier extends StateNotifier<FestivalCardsState> {
  FestivalCardsNotifier(this._dio) : super(const FestivalCardsState());

  final Dio _dio;


  /// Select a festival
  void selectFestival(FestivalTemplate? template) {
    state = state.copyWith(
      selectedFestival: template,
      imageBase64: null,
      error: null,
    );
  }

  /// Set language
  void setLanguage(SupportedLanguage language) {
    state = state.copyWith(selectedLanguage: language);
  }

  /// Set card style
  void setStyle(CardStyle style) {
    state = state.copyWith(selectedStyle: style);
  }

  /// Update kinship term input
  void setKinshipTermInput(String value) {
    state = state.copyWith(kinshipTermInput: value);
  }

  /// Update relationship key input
  void setRelationshipKeyInput(String value) {
    state = state.copyWith(relationshipKeyInput: value);
  }

  /// Generate festival card
  Future<void> generateFestivalCard() async {
    if (state.selectedFestival == null) return;
    if (state.kinshipTermInput.trim().isEmpty) return;

    state = state.copyWith(isGenerating: true, error: null);

    try {
      final styleName = state.selectedStyle.name;
      final response = await _dio.post(
        '/v1/ai-cards/festival',
        data: {
          'festival': state.selectedFestival!.name,
          'kinshipTerm': state.kinshipTermInput.trim(),
          'language': state.selectedLanguage.code,
          'style': styleName,
        },
      );

      final data = response.data as Map<String, dynamic>;
      state = state.copyWith(
        isGenerating: false,
        imageBase64: data['imageBase64'] as String? ?? '',
        festival: data['festival'] as String?,
        kinshipTerm: data['kinshipTerm'] as String?,
      );
    } on DioException catch (e) {
      final message = e.response?.data?['message'] as String? ??
          'Failed to generate card. Please try again.';
      state = state.copyWith(isGenerating: false, error: message);
    } catch (e) {
      state = state.copyWith(
        isGenerating: false,
        error: 'An unexpected error occurred.',
      );
    }
  }

  /// Generate kinship card
  Future<void> generateKinshipCard() async {
    if (state.relationshipKeyInput.trim().isEmpty) return;

    state = state.copyWith(isGenerating: true, error: null);

    try {
      final styleName = state.selectedStyle.name;
      final response = await _dio.post(
        '/v1/ai-cards/kinship',
        data: {
          'relationshipKey': state.relationshipKeyInput.trim(),
          'language': state.selectedLanguage.code,
          'style': styleName,
        },
      );

      final data = response.data as Map<String, dynamic>;
      state = state.copyWith(
        isGenerating: false,
        imageBase64: data['imageBase64'] as String? ?? '',
      );
    } on DioException catch (e) {
      final message = e.response?.data?['message'] as String? ??
          'Failed to generate card. Please try again.';
      state = state.copyWith(isGenerating: false, error: message);
    } catch (e) {
      state = state.copyWith(
        isGenerating: false,
        error: 'An unexpected error occurred.',
      );
    }
  }

  /// Clear the generated card
  void clearCard() {
    state = state.copyWith(
      imageBase64: null,
      festival: null,
      kinshipTerm: null,
      error: null,
    );
  }

  /// Reset to template selection
  void resetToTemplates() {
    state = const FestivalCardsState();
  }
}

/// Festival cards provider
final festivalCardsProvider =
    StateNotifierProvider<FestivalCardsNotifier, FestivalCardsState>((ref) {
  final dio = ref.watch(dioProvider);
  return FestivalCardsNotifier(dio);
});

// ── Fallback Templates ──────────────────────────────────────────

const _fallbackTemplates = <FestivalTemplate>[
  FestivalTemplate(
    name: 'Diwali',
    icon: '🪔',
    colorTheme: '#FFD700',
    defaultMessageTemplates: [
      'Happy Diwali, dear {term}!',
      'May the festival of lights bring joy, {term}!',
    ],
  ),
  FestivalTemplate(
    name: 'Raksha Bandhan',
    icon: '🧵',
    colorTheme: '#FF69B4',
    defaultMessageTemplates: [
      'Happy Raksha Bandhan, {term}!',
      'The bond we share is unbreakable, {term}!',
    ],
  ),
  FestivalTemplate(
    name: 'Bhai Dooj',
    icon: '🙏',
    colorTheme: '#FF8C00',
    defaultMessageTemplates: [
      'Happy Bhai Dooj, {term}!',
      'Blessings and love always, {term}!',
    ],
  ),
  FestivalTemplate(
    name: 'Holi',
    icon: '🎨',
    colorTheme: '#FF69B4',
    defaultMessageTemplates: [
      'Happy Holi, {term}!',
      'May your life be colorful, {term}!',
    ],
  ),
  FestivalTemplate(
    name: 'Eid',
    icon: '🌙',
    colorTheme: '#2E8B57',
    defaultMessageTemplates: [
      'Eid Mubarak, {term}!',
      'May blessings be with you, {term}!',
    ],
  ),
  FestivalTemplate(
    name: 'Navratri',
    icon: '🪘',
    colorTheme: '#DC143C',
    defaultMessageTemplates: [
      'Happy Navratri, {term}!',
      'May the divine bless you, {term}!',
    ],
  ),
  FestivalTemplate(
    name: 'Pongal',
    icon: '🌾',
    colorTheme: '#8B4513',
    defaultMessageTemplates: [
      'Happy Pongal, {term}!',
      'May the harvest bring prosperity, {term}!',
    ],
  ),
  FestivalTemplate(
    name: 'Onam',
    icon: '🌺',
    colorTheme: '#FFC107',
    defaultMessageTemplates: [
      'Happy Onam, {term}!',
      'May the king visit your home, {term}!',
    ],
  ),
  FestivalTemplate(
    name: 'Baisakhi',
    icon: '🌽',
    colorTheme: '#FF8C00',
    defaultMessageTemplates: [
      'Happy Baisakhi, {term}!',
      'New year, new beginnings, {term}!',
    ],
  ),
  FestivalTemplate(
    name: 'Durga Puja',
    icon: '🔱',
    colorTheme: '#8B008B',
    defaultMessageTemplates: [
      'Happy Durga Puja, {term}!',
      'May Maa Durga bless you, {term}!',
    ],
  ),
];
