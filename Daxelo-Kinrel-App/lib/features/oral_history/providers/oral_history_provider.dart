// lib/features/oral_history/providers/oral_history_provider.dart
//
// DAXELO KINREL — Oral History & Story Recording Provider
//
// AI-powered story recording with transcription support.
// Captures family narratives, traditions, recipes, wisdom,
// and migration stories with multi-language transcription.
//
// Orange K-Graph DNA: #E8612A accent, #191B2C cards,
// ignite gradient (#E8612A → #F59240), glow effects.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';

// ═══════════════════════════════════════════════════════════════════════
// Story Category Enum
// ═══════════════════════════════════════════════════════════════════════

/// Categories for oral history stories.
enum StoryCategory {
  family_history,
  life_event,
  tradition,
  recipe,
  wisdom,
  migration,
  celebration,
  other,
}

extension StoryCategoryX on StoryCategory {
  String get label {
    switch (this) {
      case StoryCategory.family_history:
        return 'Family History';
      case StoryCategory.life_event:
        return 'Life Event';
      case StoryCategory.tradition:
        return 'Tradition';
      case StoryCategory.recipe:
        return 'Recipe';
      case StoryCategory.wisdom:
        return 'Wisdom';
      case StoryCategory.migration:
        return 'Migration';
      case StoryCategory.celebration:
        return 'Celebration';
      case StoryCategory.other:
        return 'Other';
    }
  }

  String get shortLabel {
    switch (this) {
      case StoryCategory.family_history:
        return 'Family';
      case StoryCategory.life_event:
        return 'Life';
      case StoryCategory.tradition:
        return 'Tradition';
      case StoryCategory.recipe:
        return 'Recipe';
      case StoryCategory.wisdom:
        return 'Wisdom';
      case StoryCategory.migration:
        return 'Migration';
      case StoryCategory.celebration:
        return 'Celebrate';
      case StoryCategory.other:
        return 'Other';
    }
  }

  IconData get icon {
    switch (this) {
      case StoryCategory.family_history:
        return Icons.family_restroom_rounded;
      case StoryCategory.life_event:
        return Icons.auto_stories_rounded;
      case StoryCategory.tradition:
        return Icons.temple_buddhist_rounded;
      case StoryCategory.recipe:
        return Icons.restaurant_rounded;
      case StoryCategory.wisdom:
        return Icons.lightbulb_rounded;
      case StoryCategory.migration:
        return Icons.flight_takeoff_rounded;
      case StoryCategory.celebration:
        return Icons.celebration_rounded;
      case StoryCategory.other:
        return Icons.bookmark_rounded;
    }
  }

  Color get accentColor {
    switch (this) {
      case StoryCategory.family_history:
        return KinrelColors.orange;
      case StoryCategory.life_event:
        return KinrelColors.amber;
      case StoryCategory.tradition:
        return KinrelColors.gold;
      case StoryCategory.recipe:
        return KinrelColors.success;
      case StoryCategory.wisdom:
        return KinrelColors.info;
      case StoryCategory.migration:
        return KinrelColors.coral;
      case StoryCategory.celebration:
        return KinrelColors.brightGold;
      case StoryCategory.other:
        return KinrelColors.textDim;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Supported Languages
// ═══════════════════════════════════════════════════════════════════════

/// Supported transcription/recording languages.
class SupportedLanguage {
  const SupportedLanguage({
    required this.code,
    required this.name,
    required this.nativeName,
  });

  final String code;
  final String name;
  final String nativeName;
}

const kSupportedLanguages = <SupportedLanguage>[
  SupportedLanguage(code: 'hi', name: 'Hindi', nativeName: 'हिन्दी'),
  SupportedLanguage(code: 'bn', name: 'Bengali', nativeName: 'বাংলা'),
  SupportedLanguage(code: 'ta', name: 'Tamil', nativeName: 'தமிழ்'),
  SupportedLanguage(code: 'te', name: 'Telugu', nativeName: 'తెలుగు'),
  SupportedLanguage(code: 'mr', name: 'Marathi', nativeName: 'मराठी'),
  SupportedLanguage(code: 'gu', name: 'Gujarati', nativeName: 'ગુજરાતી'),
  SupportedLanguage(code: 'kn', name: 'Kannada', nativeName: 'ಕನ್ನಡ'),
  SupportedLanguage(code: 'ml', name: 'Malayalam', nativeName: 'മലയാളം'),
  SupportedLanguage(code: 'pa', name: 'Punjabi', nativeName: 'ਪੰਜਾਬੀ'),
  SupportedLanguage(code: 'ur', name: 'Urdu', nativeName: 'اردو'),
  SupportedLanguage(code: 'en', name: 'English', nativeName: 'English'),
  SupportedLanguage(code: 'es', name: 'Spanish', nativeName: 'Español'),
  SupportedLanguage(code: 'ar', name: 'Arabic', nativeName: 'العربية'),
  SupportedLanguage(code: 'zh', name: 'Mandarin', nativeName: '中文'),
  SupportedLanguage(code: 'ja', name: 'Japanese', nativeName: '日本語'),
];

// ═══════════════════════════════════════════════════════════════════════
// TranscriptionSegment Model
// ═══════════════════════════════════════════════════════════════════════

/// A timestamped segment within a transcription.
class TranscriptionSegment {
  const TranscriptionSegment({
    required this.text,
    required this.startTime,
    required this.endTime,
    required this.confidence,
  });

  final String text;
  final Duration startTime;
  final Duration endTime;
  final double confidence;

  /// Formatted start time string (MM:SS).
  String get startTimeLabel {
    final m = startTime.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = startTime.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// Formatted end time string (MM:SS).
  String get endTimeLabel {
    final m = endTime.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = endTime.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  TranscriptionSegment copyWith({
    String? text,
    Duration? startTime,
    Duration? endTime,
    double? confidence,
  }) {
    return TranscriptionSegment(
      text: text ?? this.text,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      confidence: confidence ?? this.confidence,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Story Model
// ═══════════════════════════════════════════════════════════════════════

/// Represents a recorded oral history story.
class StoryModel {
  const StoryModel({
    required this.id,
    required this.title,
    this.description,
    required this.narratorId,
    required this.narratorName,
    required this.familyId,
    required this.audioDuration,
    this.audioPath,
    this.audioUrl,
    this.transcription,
    required this.language,
    this.tags = const [],
    this.relatedPersonIds = const [],
    this.era,
    required this.category,
    this.isFavorite = false,
    this.playCount = 0,
    required this.createdAt,
    this.thumbnailUrl,
  });

  final String id;
  final String title;
  final String? description;
  final String narratorId;
  final String narratorName;
  final String familyId;
  final Duration audioDuration;
  final String? audioPath;
  final String? audioUrl;
  final String? transcription;
  final String language;
  final List<String> tags;
  final List<String> relatedPersonIds;
  final String? era;
  final StoryCategory category;
  final bool isFavorite;
  final int playCount;
  final DateTime createdAt;
  final String? thumbnailUrl;

  /// Formatted duration string (M:SS or H:MM:SS).
  String get durationLabel {
    final h = audioDuration.inHours;
    final m = audioDuration.inMinutes.remainder(60);
    final s = audioDuration.inSeconds.remainder(60);
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// Narrator initials for avatar.
  String get narratorInitials {
    final parts = narratorName.split(' ').where((s) => s.isNotEmpty).take(2);
    return parts.map((s) => s[0].toUpperCase()).join();
  }

  /// Whether the story has been transcribed.
  bool get hasTranscription => transcription != null && transcription!.isNotEmpty;

  /// Language display name.
  String get languageName {
    final lang = kSupportedLanguages.where((l) => l.code == language);
    return lang.isNotEmpty ? lang.first.name : language;
  }

  StoryModel copyWith({
    String? id,
    String? title,
    String? description,
    String? narratorId,
    String? narratorName,
    String? familyId,
    Duration? audioDuration,
    String? audioPath,
    String? audioUrl,
    String? transcription,
    String? language,
    List<String>? tags,
    List<String>? relatedPersonIds,
    String? era,
    StoryCategory? category,
    bool? isFavorite,
    int? playCount,
    DateTime? createdAt,
    String? thumbnailUrl,
  }) {
    return StoryModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      narratorId: narratorId ?? this.narratorId,
      narratorName: narratorName ?? this.narratorName,
      familyId: familyId ?? this.familyId,
      audioDuration: audioDuration ?? this.audioDuration,
      audioPath: audioPath ?? this.audioPath,
      audioUrl: audioUrl ?? this.audioUrl,
      transcription: transcription ?? this.transcription,
      language: language ?? this.language,
      tags: tags ?? this.tags,
      relatedPersonIds: relatedPersonIds ?? this.relatedPersonIds,
      era: era ?? this.era,
      category: category ?? this.category,
      isFavorite: isFavorite ?? this.isFavorite,
      playCount: playCount ?? this.playCount,
      createdAt: createdAt ?? this.createdAt,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Recording State
// ═══════════════════════════════════════════════════════════════════════

/// State tracking an active recording session.
class RecordingState {
  const RecordingState({
    this.isRecording = false,
    this.isPaused = false,
    this.duration = Duration.zero,
    this.amplitude = 0.0,
    this.amplitudes = const [],
  });

  final bool isRecording;
  final bool isPaused;
  final Duration duration;
  final double amplitude;
  final List<double> amplitudes;

  /// Formatted duration string.
  String get durationLabel {
    final m = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// Whether recording is currently active (not stopped).
  bool get isActive => isRecording || isPaused;

  RecordingState copyWith({
    bool? isRecording,
    bool? isPaused,
    Duration? duration,
    double? amplitude,
    List<double>? amplitudes,
  }) {
    return RecordingState(
      isRecording: isRecording ?? this.isRecording,
      isPaused: isPaused ?? this.isPaused,
      duration: duration ?? this.duration,
      amplitude: amplitude ?? this.amplitude,
      amplitudes: amplitudes ?? this.amplitudes,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Transcription State
// ═══════════════════════════════════════════════════════════════════════

/// State tracking an active AI transcription session.
class TranscriptionState {
  const TranscriptionState({
    this.isTranscribing = false,
    this.progress = 0.0,
    this.text = '',
    this.language = '',
    this.segments = const [],
    this.error,
  });

  final bool isTranscribing;
  final double progress;
  final String text;
  final String language;
  final List<TranscriptionSegment> segments;
  final String? error;

  /// Whether transcription has completed with results.
  bool get hasResults => text.isNotEmpty && !isTranscribing;

  /// Detected language display name.
  String get languageName {
    final lang = kSupportedLanguages.where((l) => l.code == language);
    return lang.isNotEmpty ? lang.first.name : language;
  }

  TranscriptionState copyWith({
    bool? isTranscribing,
    double? progress,
    String? text,
    String? language,
    List<TranscriptionSegment>? segments,
    String? error,
  }) {
    return TranscriptionState(
      isTranscribing: isTranscribing ?? this.isTranscribing,
      progress: progress ?? this.progress,
      text: text ?? this.text,
      language: language ?? this.language,
      segments: segments ?? this.segments,
      error: error,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Oral History State
// ═══════════════════════════════════════════════════════════════════════

/// Combined state for the oral history feature.
class OralHistoryState {
  const OralHistoryState({
    this.stories = const [],
    this.recordingState = const RecordingState(),
    this.transcriptionState = const TranscriptionState(),
    this.filter,
    this.searchQuery = '',
    this.selectedLanguage = 'en',
  });

  final List<StoryModel> stories;
  final RecordingState recordingState;
  final TranscriptionState transcriptionState;
  final StoryCategory? filter;
  final String searchQuery;
  final String selectedLanguage;

  /// Stories filtered by category and search query.
  List<StoryModel> get filteredStories {
    var result = stories.toList();

    // Filter by category
    if (filter != null) {
      result = result.where((s) => s.category == filter).toList();
    }

    // Filter by search query
    if (searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      result = result.where((s) {
        return s.title.toLowerCase().contains(query) ||
            s.narratorName.toLowerCase().contains(query) ||
            (s.description?.toLowerCase().contains(query) ?? false) ||
            (s.era?.toLowerCase().contains(query) ?? false) ||
            s.tags.any((t) => t.toLowerCase().contains(query));
      }).toList();
    }

    // Sort: favorites first, then newest
    result.sort((a, b) {
      if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
      return b.createdAt.compareTo(a.createdAt);
    });

    return result;
  }

  /// All unique categories present in the stories.
  List<StoryCategory> get availableCategories {
    final cats = stories.map((s) => s.category).toSet().toList();
    cats.sort((a, b) => a.index.compareTo(b.index));
    return cats;
  }

  /// Total duration of all stories.
  Duration get totalDuration {
    return stories.fold<Duration>(
      Duration.zero,
      (prev, s) => prev + s.audioDuration,
    );
  }

  /// Total number of stories.
  int get storyCount => stories.length;

  /// Number of favorite stories.
  int get favoriteCount => stories.where((s) => s.isFavorite).length;

  /// Number of transcribed stories.
  int get transcribedCount => stories.where((s) => s.hasTranscription).length;

  OralHistoryState copyWith({
    List<StoryModel>? stories,
    RecordingState? recordingState,
    TranscriptionState? transcriptionState,
    StoryCategory? Function()? filter,
    String? searchQuery,
    String? selectedLanguage,
  }) {
    return OralHistoryState(
      stories: stories ?? this.stories,
      recordingState: recordingState ?? this.recordingState,
      transcriptionState: transcriptionState ?? this.transcriptionState,
      filter: filter != null ? filter() : this.filter,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedLanguage: selectedLanguage ?? this.selectedLanguage,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Oral History Notifier
// ═══════════════════════════════════════════════════════════════════════

/// State notifier managing oral history stories and recording.
class OralHistoryNotifier extends StateNotifier<OralHistoryState> {
  OralHistoryNotifier() : super(OralHistoryState(stories: _demoStories));

  Timer? _recordingTimer;
  Timer? _amplitudeTimer;

  // ── Recording Methods ──────────────────────────────────────────────

  /// Start a new recording session.
  void startRecording() {
    _recordingTimer?.cancel();
    _amplitudeTimer?.cancel();

    state = state.copyWith(
      recordingState: const RecordingState(
        isRecording: true,
        isPaused: false,
        duration: Duration.zero,
        amplitude: 0.0,
        amplitudes: [],
      ),
    );

    // Simulate recording timer
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.recordingState.isRecording && !state.recordingState.isPaused) {
        final newDuration = state.recordingState.duration + const Duration(seconds: 1);
        state = state.copyWith(
          recordingState: state.recordingState.copyWith(duration: newDuration),
        );
      }
    });

    // Simulate amplitude visualization
    _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (state.recordingState.isRecording && !state.recordingState.isPaused) {
        final randomAmplitude = 0.2 + (DateTime.now().millisecond % 80) / 100.0;
        final newAmplitudes = [...state.recordingState.amplitudes, randomAmplitude];
        // Keep only last 50 amplitudes for waveform
        if (newAmplitudes.length > 50) {
          newAmplitudes.removeAt(0);
        }
        state = state.copyWith(
          recordingState: state.recordingState.copyWith(
            amplitude: randomAmplitude,
            amplitudes: newAmplitudes,
          ),
        );
      }
    });
  }

  /// Pause the current recording.
  void pauseRecording() {
    state = state.copyWith(
      recordingState: state.recordingState.copyWith(isPaused: true),
    );
  }

  /// Resume a paused recording.
  void resumeRecording() {
    state = state.copyWith(
      recordingState: state.recordingState.copyWith(isPaused: false),
    );
  }

  /// Stop the current recording and return the recorded duration.
  Duration stopRecording() {
    _recordingTimer?.cancel();
    _amplitudeTimer?.cancel();

    final recordedDuration = state.recordingState.duration;

    state = state.copyWith(
      recordingState: state.recordingState.copyWith(
        isRecording: false,
        isPaused: false,
      ),
    );

    return recordedDuration;
  }

  // ── Transcription Methods ──────────────────────────────────────────

  /// Transcribe the current recording using AI.
  Future<void> transcribeRecording() async {
    state = state.copyWith(
      transcriptionState: const TranscriptionState(
        isTranscribing: true,
        progress: 0.0,
      ),
    );

    // Simulate AI transcription with progress
    for (var i = 0; i < 10; i++) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!state.transcriptionState.isTranscribing) return;
      state = state.copyWith(
        transcriptionState: state.transcriptionState.copyWith(
          progress: (i + 1) / 10,
        ),
      );
    }

    // Simulate transcription result based on selected language
    final lang = state.selectedLanguage;
    final transcriptionTexts = {
      'hi': 'यह हमारे परिवार की कहानी है। हमारे दादा जी ने इस घर को बहुत मेहनत से बनाया था। वे हमेशा कहते थे कि परिवार सबसे बड़ा धन है।',
      'bn': 'এটি আমাদের পরিবারের গল্প। আমাদের দাদা অনেক কঠোর পরিশ্রম করে এই বাড়িটি তৈরি করেছিলেন।',
      'ta': 'இது எங்கள் குடும்பத்தின் கதை. எங்கள் தாத்தா இந்த வீட்டை நிறைய கடினமாக கட்டினார்கள்.',
      'en': 'This is our family story. Our grandfather built this house with great effort. He always said that family is the greatest wealth.',
    };

    final demoSegments = [
      TranscriptionSegment(
        text: transcriptionTexts[lang] ?? transcriptionTexts['en']!,
        startTime: Duration.zero,
        endTime: state.recordingState.duration,
        confidence: 0.95,
      ),
    ];

    state = state.copyWith(
      transcriptionState: TranscriptionState(
        isTranscribing: false,
        progress: 1.0,
        text: transcriptionTexts[lang] ?? transcriptionTexts['en']!,
        language: lang,
        segments: demoSegments,
      ),
    );
  }

  // ── Story CRUD Methods ─────────────────────────────────────────────

  /// Add a new story.
  void addStory(StoryModel story) {
    state = state.copyWith(
      stories: [...state.stories, story],
      transcriptionState: const TranscriptionState(),
    );
  }

  /// Delete a story by ID.
  void deleteStory(String storyId) {
    state = state.copyWith(
      stories: state.stories.where((s) => s.id != storyId).toList(),
    );
  }

  /// Toggle the favorite status of a story.
  void toggleFavorite(String storyId) {
    final updatedStories = state.stories.map((s) {
      if (s.id == storyId) {
        return s.copyWith(isFavorite: !s.isFavorite);
      }
      return s;
    }).toList();
    state = state.copyWith(stories: updatedStories);
  }

  // ── Filter / Search Methods ────────────────────────────────────────

  /// Set the category filter (null for all).
  void setFilter(StoryCategory? category) {
    state = state.copyWith(filter: () => category);
  }

  /// Set the search query string.
  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  /// Set the selected language for recording/transcription.
  void setSelectedLanguage(String languageCode) {
    state = state.copyWith(selectedLanguage: languageCode);
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _amplitudeTimer?.cancel();
    super.dispose();
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Providers
// ═══════════════════════════════════════════════════════════════════════

/// Main oral history provider.
final oralHistoryProvider =
    StateNotifierProvider<OralHistoryNotifier, OralHistoryState>((ref) {
  return OralHistoryNotifier();
});

/// Computed provider: filtered stories based on current filter and search.
final filteredStoriesProvider = Provider<List<StoryModel>>((ref) {
  final state = ref.watch(oralHistoryProvider);
  return state.filteredStories;
});

/// Computed provider: all unique story categories.
final storyCategoriesProvider = Provider<List<StoryCategory>>((ref) {
  final state = ref.watch(oralHistoryProvider);
  return state.availableCategories;
});

// ═══════════════════════════════════════════════════════════════════════
// Demo Stories — Realistic Indian Family Oral History
// ═══════════════════════════════════════════════════════════════════════

final _demoStories = <StoryModel>[
  StoryModel(
    id: 'story-1',
    title: 'How Dada Built Sharma Haveli',
    description: 'Dada Suresh Kumar Sharma recounts the three-year journey of building the family haveli in Jaipur, from laying the foundation stone in 1965 to the Griha Pravesh in 1968.',
    narratorId: 'm15',
    narratorName: 'Suresh Kumar Sharma',
    familyId: 'fam-sharma',
    audioDuration: const Duration(minutes: 12, seconds: 34),
    transcription: 'यह हमारे परिवार की कहानी है। हमारे दादा जी ने इस घर को बहुत मेहनत से बनाया था। 1965 में जब नींव रखी गई थी, तो पूरे मोहल्ले के लोग आए थे। हर ईंट हमने अपने हाथों से लगाई। तीन साल लगे, लेकिन जब घर बनकर तैयार हुआ, तो वो दिन कभी नहीं भूलूंगा।',
    language: 'hi',
    tags: ['haveli', 'Jaipur', 'construction', '1960s', 'Dada'],
    relatedPersonIds: ['m6', 'm7', 'm15'],
    era: '1960s',
    category: StoryCategory.family_history,
    isFavorite: true,
    playCount: 47,
    createdAt: DateTime(2024, 10, 15),
  ),

  StoryModel(
    id: 'story-2',
    title: 'Dadi\'s Secret Ghevar Recipe',
    description: 'Kamla Sharma shares her legendary ghevar recipe that has been passed down through four generations of Sharma women. The secret is in the rabdi temperature!',
    narratorId: 'm6',
    narratorName: 'Kamla Sharma',
    familyId: 'fam-sharma',
    audioDuration: const Duration(minutes: 8, seconds: 22),
    transcription: 'बेटा, घेवर बनाने का सबसे जरूरी बात यह है कि रबड़ी का तापमान सही होना चाहिए। मेरी सास ने मुझे सिखाया था, उनकी सास ने उन्हें। यह रेसिपी चार पीढ़ियों से चली आ रही है।',
    language: 'hi',
    tags: ['recipe', 'ghevar', 'Rajasthani', 'sweet', 'Dadi'],
    relatedPersonIds: ['m6', 'm8', 'm14'],
    era: 'Traditional',
    category: StoryCategory.recipe,
    isFavorite: true,
    playCount: 89,
    createdAt: DateTime(2024, 9, 20),
  ),

  StoryModel(
    id: 'story-3',
    title: 'The Night We Left Lahore',
    description: 'Saroj Devi recounts her family\'s journey from Lahore to Amritsar during Partition in 1947. A story of courage, loss, and new beginnings.',
    narratorId: 'm9',
    narratorName: 'Saroj Devi',
    familyId: 'fam-sharma',
    audioDuration: const Duration(minutes: 23, seconds: 15),
    transcription: 'It was August 1947. We had only one night to pack everything. My father said we could only take what we could carry. We left our home, our shop, everything. The train journey took three days. We lost count of the stops. But we found each other again in Amritsar.',
    language: 'en',
    tags: ['Partition', 'Lahore', 'migration', '1947', 'freedom'],
    relatedPersonIds: ['m9', 'm4'],
    era: 'Partition Era',
    category: StoryCategory.migration,
    isFavorite: false,
    playCount: 156,
    createdAt: DateTime(2024, 8, 14),
  ),

  StoryModel(
    id: 'story-4',
    title: 'Why We Light the Akhand Jyot on Diwali',
    description: 'Ravi Sharma explains the family tradition of keeping an eternal flame burning for 48 hours during Diwali, a practice started by his great-grandfather in 1920.',
    narratorId: 'm7',
    narratorName: 'Ravi Sharma',
    familyId: 'fam-sharma',
    audioDuration: const Duration(minutes: 6, seconds: 45),
    transcription: 'Every Diwali, we light the Akhand Jyot and it burns for 48 hours without going out. My great-grandfather Pandit Raghunath Sharma started this in 1920. He believed that as long as the flame burns, the family stays united. So far, it never has gone out.',
    language: 'en',
    tags: ['Diwali', 'tradition', 'Akhand Jyot', '1920', 'puja'],
    relatedPersonIds: ['m7', 'm6', 'm15'],
    era: 'Since 1920',
    category: StoryCategory.tradition,
    isFavorite: false,
    playCount: 34,
    createdAt: DateTime(2024, 11, 1),
  ),

  StoryModel(
    id: 'story-5',
    title: 'Nani Ma\'s Wisdom on Raising Children',
    description: 'Saroj Devi shares her philosophy on raising children with kindness, patience, and the importance of family stories. "Every child needs to know where they come from."',
    narratorId: 'm9',
    narratorName: 'Saroj Devi',
    familyId: 'fam-sharma',
    audioDuration: const Duration(minutes: 15, seconds: 8),
    transcription: 'बच्चों को प्यार से बड़ा करो, डर से नहीं। हर बच्चे को अपनी जड़ें पता होनी चाहिए। जब वो जानेंगे कि वो कहाँ से आए हैं, तभी वो सही दिशा में जा सकेंगे।',
    language: 'hi',
    tags: ['wisdom', 'parenting', 'children', 'values', 'Nani'],
    relatedPersonIds: ['m9', 'm4', 'm8'],
    era: 'Timeless',
    category: StoryCategory.wisdom,
    isFavorite: true,
    playCount: 72,
    createdAt: DateTime(2024, 7, 10),
  ),

  StoryModel(
    id: 'story-6',
    title: 'Arjun & Priya\'s Wedding — The Full Story',
    description: 'Sunita Sharma narrates the complete story of Arjun and Priya\'s wedding — from the first meeting arranged through family to the intimate pandemic-era ceremony at Jai Mahal Palace.',
    narratorId: 'm8',
    narratorName: 'Sunita Sharma',
    familyId: 'fam-sharma',
    audioDuration: const Duration(minutes: 19, seconds: 42),
    transcription: 'When we first heard about Priya\'s family, I knew she was perfect for Arjun. But 2020 was such a difficult year. We had planned a 500-guest wedding, but ended up with just 50. The pheras were livestreamed for relatives abroad. It was intimate, emotional, and absolutely beautiful.',
    language: 'en',
    tags: ['wedding', 'Arjun', 'Priya', 'pandemic', '2020'],
    relatedPersonIds: ['m8', 'm7', 'm1', 'm2'],
    era: '2020s',
    category: StoryCategory.celebration,
    isFavorite: false,
    playCount: 63,
    createdAt: DateTime(2024, 12, 8),
  ),
];
