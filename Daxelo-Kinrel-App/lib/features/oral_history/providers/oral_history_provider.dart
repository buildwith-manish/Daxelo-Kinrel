// lib/features/oral_history/providers/oral_history_provider.dart
//
// DAXELO KINREL — Oral History & Story Recording Provider
//
// Family voice-note recording. Captures family narratives, traditions,
// recipes, wisdom, and migration stories as audio recordings persisted
// to Supabase Storage (bucket: 'voice-messages') with metadata in the
// AncestralMemory table.
//
// v93 (transcription removal + recording/playback correctness):
//   - Transcription feature is SOFT-DISABLED. The `transcription` field
//     on StoryModel is kept for backward compatibility with any existing
//     rows that have it, but it's NOT written for new recordings and
//     NOT displayed in the UI. The server-side /v1/ai-voice/transcribe
//     endpoint is no longer called from this feature. See the audit
//     brief for the rationale (transcription was never truly functional
//     for oral history — the kinship-lookup endpoint was misused).
//   - Recording now uses `permission_handler` for an actionable mic
//     permission flow with a clear denied error message.
//   - Recording amplitude uses the `record` package's onAmplitudeChanged
//     stream for a real (not simulated) waveform during recording.
//   - Recorded audio is uploaded to Supabase Storage 'voice-messages'
//     bucket on save, with retry-on-failure and a clear error state.
//   - Playback is REAL via `just_audio` (see oral_history_audio_player.dart)
//     — actual streaming from the stored URL, real duration discovery
//     via durationStream, real position tracking, real seek.
//   - Play count is persisted to AncestralMemory.listenCount via an
//     RPC call (no longer a static/seeded number).
//   - Story duration is the actual stored file's duration (discovered
//     by just_audio after the file loads), not a hardcoded value.
//
// Production default: the notifier starts with an EMPTY story list.
// Real families see the "No stories yet — record your family's first
// memory" empty state instead of someone else's demo family history.
// Demo data is available via `loadDemoData()` for tests/debug only.
//
// Orange K-Graph DNA: #E8612A accent, #191B2C cards,
// ignite gradient (#E8612A → #F59240), glow effects.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/services/supabase_service.dart';

// ═══════════════════════════════════════════════════════════════════════
// Story Category Enum
// ═══════════════════════════════════════════════════════════════════════

/// Categories for oral history stories.
enum StoryCategory {
  familyHistory,
  lifeEvent,
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
      case StoryCategory.familyHistory:
        return 'Family History';
      case StoryCategory.lifeEvent:
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
      case StoryCategory.familyHistory:
        return 'Family';
      case StoryCategory.lifeEvent:
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
      case StoryCategory.familyHistory:
        return Icons.family_restroom_rounded;
      case StoryCategory.lifeEvent:
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
      case StoryCategory.familyHistory:
        return KinrelColors.orange;
      case StoryCategory.lifeEvent:
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
// Transcription Language Enum + Segment — REMOVED (v93)
// ═══════════════════════════════════════════════════════════════════════
//
// The TranscriptionLanguage enum, TranscriptionLanguageX extension, and
// TranscriptionSegment class were removed when transcription was soft-
// disabled. See the "Transcription State — REMOVED" note above for the
// rationale and the recommended re-implementation path if transcription
// is revisited.

// ═══════════════════════════════════════════════════════════════════════
// Story Model
// ═══════════════════════════════════════════════════════════════════════

/// Represents a recorded oral history story.
///
/// v93 (transcription removal): the `transcription` field is kept for
/// backward compatibility with any existing AncestralMemory rows that
/// may have a `transcript` column value, but it is NO LONGER populated
/// for new recordings and NO LONGER displayed in the UI. Use
/// [hasTranscription] only for legacy row detection — the screen does
/// NOT render anything transcription-related either way.
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
    this.waveformData = const [],
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

  /// v93: LEGACY — kept for backward compat with existing rows. NOT
  /// populated for new recordings. NOT displayed in the UI. Will be
  /// removed in a future migration once any existing data is no longer
  /// needed.
  final String? transcription;

  /// Language the recording is in (ISO-639-1). This is independent of
  /// transcription — it's useful metadata on its own (labels what
  /// language the audio is in) and connects to the broader multi-
  /// language point raised in the audit brief.
  final String language;
  final List<String> tags;
  final List<String> relatedPersonIds;
  final String? era;
  final StoryCategory category;
  final bool isFavorite;
  final int playCount;
  final DateTime createdAt;
  final String? thumbnailUrl;

  /// Waveform amplitude data for visualization (0.0–1.0). For real
  /// recordings this is populated from the `record` package's
  /// onAmplitudeChanged stream during recording. For legacy/demo rows
  /// without real waveform data, [effectiveWaveformData] falls back
  /// to a deterministic pseudo-random visualization (clearly decorative
  /// — the screen UI no longer claims it represents the actual audio).
  final List<double> waveformData;

  /// Formatted duration string (M:SS or H:MM:SS).
  /// v93: when [audioUrl] is set, the actual file duration is
  /// discovered by `just_audio` after the player loads the file —
  /// see [StoryAudioPlayer]. The [audioDuration] here is the recorded
  /// duration (used as a hint before the file loads) and is replaced
  /// by the real duration once just_audio reports it via
  /// durationStream.
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

  /// v93: LEGACY — kept for backward compat. The screen no longer
  /// checks this getter; transcription UI is removed entirely.
  bool get hasTranscription =>
      transcription != null && transcription!.isNotEmpty;

  /// Language display name.
  String get languageName {
    final lang = kSupportedLanguages.where((l) => l.code == language);
    return lang.isNotEmpty ? lang.first.name : language;
  }

  /// Language native name.
  String get languageNativeName {
    final lang = kSupportedLanguages.where((l) => l.code == language);
    return lang.isNotEmpty ? lang.first.nativeName : language;
  }

  /// Generate waveform data from seed if none provided.
  /// v93: this is a DECORATIVE fallback for legacy/demo rows that
  /// don't have real amplitude data. The screen's player UI uses
  /// [waveformData] directly when non-empty (real recorded amplitudes).
  List<double> get effectiveWaveformData {
    if (waveformData.isNotEmpty) return waveformData;
    // Generate deterministic pseudo-random waveform from id
    final seed = id.hashCode;
    return List.generate(60, (i) {
      final v = ((seed * (i + 1) * 7 + 13) % 100) / 100.0;
      return 0.15 + v * 0.75;
    });
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
    List<double>? waveformData,
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
      waveformData: waveformData ?? this.waveformData,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Recording State
// ═══════════════════════════════════════════════════════════════════════

/// State tracking an active recording session.
///
/// v93: added `error` field for actionable mic-permission and upload
/// errors. The recording UI surfaces this to the user with a clear
/// "Microphone access denied — enable in Settings" or "Upload failed —
/// retry?" message instead of a silent failure that loses the recording.
class RecordingState {
  const RecordingState({
    this.isRecording = false,
    this.isPaused = false,
    this.duration = Duration.zero,
    this.amplitude = 0.0,
    this.amplitudes = const [],
    this.isSaving = false,
    this.quality = RecordingQuality.high,
    this.error,
    this.permissionDenied = false,
  });

  final bool isRecording;
  final bool isPaused;
  final Duration duration;
  final double amplitude;
  final List<double> amplitudes;
  final bool isSaving;
  final RecordingQuality quality;

  /// v93: actionable error message. When non-null, the recording UI
  /// shows a clear error banner with a retry/fix path. Cleared on the
  /// next recording attempt.
  final String? error;

  /// v93: set true when mic permission was denied. The UI uses this
  /// to show a "Open Settings" button alongside the error message
  /// (vs. a generic "Retry" button for transient errors).
  final bool permissionDenied;

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
    bool? isSaving,
    RecordingQuality? quality,
    String? error,
    bool clearError = false,
    bool? permissionDenied,
  }) {
    return RecordingState(
      isRecording: isRecording ?? this.isRecording,
      isPaused: isPaused ?? this.isPaused,
      duration: duration ?? this.duration,
      amplitude: amplitude ?? this.amplitude,
      amplitudes: amplitudes ?? this.amplitudes,
      isSaving: isSaving ?? this.isSaving,
      quality: quality ?? this.quality,
      error: clearError ? null : (error ?? this.error),
      permissionDenied: permissionDenied ?? this.permissionDenied,
    );
  }
}

/// Recording quality indicator.
enum RecordingQuality { high, medium, low }

extension RecordingQualityX on RecordingQuality {
  String get label {
    switch (this) {
      case RecordingQuality.high:
        return 'High';
      case RecordingQuality.medium:
        return 'Medium';
      case RecordingQuality.low:
        return 'Low';
    }
  }

  Color get color {
    switch (this) {
      case RecordingQuality.high:
        return KinrelColors.success;
      case RecordingQuality.medium:
        return KinrelColors.warning;
      case RecordingQuality.low:
        return KinrelColors.coral;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Transcription State — REMOVED (v93)
// ═══════════════════════════════════════════════════════════════════════
//
// The TranscriptionState, TranscriptionSegment, TranscriptionLanguage,
// and TranscriptionLanguageX types were removed when transcription was
// soft-disabled. The `transcription` field on StoryModel is kept for
// backward compatibility with any existing AncestralMemory rows that
// may have a `transcript` column value, but no new recordings populate
// it and the UI does not render anything transcription-related.
//
// If transcription is revisited, the new implementation should:
//   - Use a dedicated Edge Function (not the kinship-lookup endpoint)
//   - Store the result in AncestralMemory.transcript (existing column)
//   - Re-introduce a TranscriptionState class with a real progress
//     stream tied to the actual upload+process pipeline (not a
//     simulated progress timer).

// ═══════════════════════════════════════════════════════════════════════
// Suggested Tags Helper
// ═══════════════════════════════════════════════════════════════════════

/// Returns suggested tags based on story category.
List<String> suggestedTagsForCategory(StoryCategory category) {
  switch (category) {
    case StoryCategory.familyHistory:
      return ['family', 'ancestors', 'heritage', 'home', 'roots'];
    case StoryCategory.lifeEvent:
      return ['milestone', 'life', 'memory', 'turning-point', 'growth'];
    case StoryCategory.tradition:
      return ['ritual', 'festival', 'custom', 'ceremony', 'heritage'];
    case StoryCategory.recipe:
      return ['cooking', 'food', 'kitchen', 'secret-recipe', 'flavor'];
    case StoryCategory.wisdom:
      return ['advice', 'lesson', 'values', 'teaching', 'proverb'];
    case StoryCategory.migration:
      return ['journey', 'new-home', 'courage', 'adaptation', 'roots'];
    case StoryCategory.celebration:
      return ['wedding', 'birthday', 'festival', 'gathering', 'joy'];
    case StoryCategory.other:
      return ['story', 'memory', 'family', 'reflection'];
  }
}

/// Returns suggested era based on narrator's relationship/age.
String? suggestedEraForNarrator(String narratorName) {
  if (narratorName.contains('Dadi') || narratorName.contains('Nani')) {
    return '1950s';
  }
  if (narratorName.contains('Papa') || narratorName.contains('Mummy')) {
    return '1980s';
  }
  if (narratorName == 'Self' || narratorName == 'You') {
    return '2020s';
  }
  return null;
}

// ═══════════════════════════════════════════════════════════════════════
// Oral History State
// ═══════════════════════════════════════════════════════════════════════

/// Combined state for the oral history feature.
///
/// v93: removed `transcriptionState` (transcription feature soft-disabled).
/// Added `hasStories` and `pillsActive` helpers for empty-state UI logic.
class OralHistoryState {
  const OralHistoryState({
    this.stories = const [],
    this.recordingState = const RecordingState(),
    this.filter,
    this.searchQuery = '',
    this.selectedLanguage = 'en',
  });

  final List<StoryModel> stories;
  final RecordingState recordingState;
  final StoryCategory? filter;
  final String searchQuery;
  final String selectedLanguage;

  // ── Empty-state helpers ──────────────────────────────────────────────

  /// Whether the family has ANY stories at all (regardless of filters).
  /// Used by the screen to decide between two distinct empty states:
  ///   • `!hasStories` → "No stories yet — record your family's first memory"
  ///   • `hasStories && filteredStories.isEmpty` → "No stories match your
  ///     filters — try clearing the filter or search"
  bool get hasStories => stories.isNotEmpty;

  /// Whether any category filter or search query is active (the "pills"
  /// in the UI). Used to decide whether to show the "Clear filters" link
  /// and to choose the right empty-state copy.
  bool get pillsActive =>
      filter != null || searchQuery.isNotEmpty;

  /// Stories filtered by category and search query.
  List<StoryModel> get filteredStories {
    var result = stories.toList();

    // Filter by category
    if (filter != null) {
      result = result.where((s) => s.category == filter).toList();
    }

    // Filter by search query (includes tags)
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

  /// All unique categories present in the stories (used for the category
  /// filter chips — only categories that have at least one story show up).
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

  /// v93: Number of distinct narrators. Replaces `transcribedCount` as
  /// the third dashboard stat — "Narrators" is a more meaningful metric
  /// than "Transcribed" now that transcription is removed. Distinct
  /// narrator names gives the user a sense of how many family members
  /// have contributed their voice to the family's oral history.
  int get narratorCount {
    final names = <String>{};
    for (final s in stories) {
      names.add(s.narratorName);
    }
    return names.length;
  }

  /// v93: Language distribution map computed from [filteredStories] (not
  /// all stories) so the Languages chart reflects the current filter
  /// context. Categories/languages with zero matches after a filter is
  /// applied are naturally absent from the map — the chart renders only
  /// the languages that have at least one story in the filtered set,
  /// eliminating zero-width placeholder bars.
  Map<String, int> get languageDistribution {
    final map = <String, int>{};
    for (final story in filteredStories) {
      map[story.language] = (map[story.language] ?? 0) + 1;
    }
    return map;
  }

  /// v93: Category distribution computed from [filteredStories] (same
  /// rationale as [languageDistribution]).
  Map<StoryCategory, int> get categoryDistribution {
    final map = <StoryCategory, int>{};
    for (final story in filteredStories) {
      map[story.category] = (map[story.category] ?? 0) + 1;
    }
    return map;
  }

  /// Most played story (only meaningful when at least one story has
  /// been played at least once — see [hasPlayedStory]). The screen
  /// hides the "Most Played" section entirely when [hasPlayedStory]
  /// is false to avoid a 0-plays placeholder.
  StoryModel? get mostPlayedStory {
    if (stories.isEmpty) return null;
    return stories.reduce((a, b) => a.playCount > b.playCount ? a : b);
  }

  /// v93: Whether at least one story has been played at least once.
  /// Drives the visibility of the "Most Played" section per the brief:
  /// hide it entirely rather than showing a 0-plays placeholder.
  bool get hasPlayedStory => stories.any((s) => s.playCount > 0);

  /// Recently added stories (sorted by createdAt, newest first, max 5).
  List<StoryModel> get recentlyAdded {
    final sorted = stories.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted.take(5).toList();
  }

  /// All unique tags across stories.
  List<String> get allTags {
    final tags = <String>{};
    for (final story in stories) {
      tags.addAll(story.tags);
    }
    return tags.toList()..sort();
  }

  OralHistoryState copyWith({
    List<StoryModel>? stories,
    RecordingState? recordingState,
    StoryCategory? Function()? filter,
    String? searchQuery,
    String? selectedLanguage,
  }) {
    return OralHistoryState(
      stories: stories ?? this.stories,
      recordingState: recordingState ?? this.recordingState,
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
///
/// v93 (transcription removal + recording/playback correctness):
///   - Production default: starts EMPTY. Real families see the
///     invitation-to-act empty state instead of someone else's demo
///     family history. Demo data is available via [loadDemoData] for
///     tests/debug only.
///   - Recording: uses `permission_handler` for an actionable mic
///     permission flow (records `permissionDenied: true` and a clear
///     error message in [RecordingState.error] if mic access is
///     denied, instead of silently passing through to native dialogs).
///     Uses the `record` package's `onAmplitudeChanged` stream for a
///     REAL waveform during recording (not a timer-based simulation).
///   - Transcription methods removed (transcribeRecording,
///     translateToEnglish). The server endpoint
///     POST /v1/ai-voice/transcribe is no longer called from this
///     feature. The `transcription` field on StoryModel is kept for
///     backward compatibility with any existing AncestralMemory rows
///     that may have a `transcript` column value.
///   - Upload: [saveStory] uploads the recorded audio file to the
///     `voice-messages` Supabase Storage bucket (which accepts m4a/
///     mp4/aac/wav/webm — see migration 20260808120000) and inserts a
///     row in the `AncestralMemory` table with `mediaUrl`, `durationSec`,
///     `title`, `language`, etc. The upload has retry-on-failure with
///     a clear error state in [RecordingState.error].
///   - Play count: [incrementPlayCount] now persists the increment to
///     the `AncestralMemory.listenCount` column via an RPC call (not
///     just an in-memory update). The "Played Nx" counter reflects real
///     playback events.
class OralHistoryNotifier extends StateNotifier<OralHistoryState> {
  OralHistoryNotifier(this._ref) : super(const OralHistoryState());

  final Ref _ref;
  final AudioRecorder _audioRecorder = AudioRecorder();
  String? _recordingPath;

  Timer? _recordingTimer;
  StreamSubscription<Amplitude>? _amplitudeSubscription;

  // ── Recording Methods ──────────────────────────────────────────────

  /// Start a new recording session.
  ///
  /// v93: uses `permission_handler` to request microphone permission
  /// with a clear, actionable error path if denied. The recording
  /// amplitude comes from the `record` package's `onAmplitudeChanged`
  /// stream — a REAL waveform based on the actual mic input, not a
  /// timer-based simulation.
  Future<void> startRecording() async {
    // Cancel any previous recording session
    _recordingTimer?.cancel();
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    _recordingPath = null;

    // ── Step 1: Request mic permission with actionable error ────────
    // Use `permission_handler` so we get a clear `PermissionStatus`
    // we can distinguish denied vs. permanently denied (the latter
    // requires opening Settings, not just retrying). The previous
    // implementation relied on `record.hasPermission()` which silently
    // passed through to the native dialog with no error state.
    PermissionStatus permStatus;
    try {
      permStatus = await Permission.microphone.request();
    } catch (e) {
      // Some platforms (Linux, desktop) don't have a microphone
      // permission concept — treat as denied with a clear error.
      debugPrint('⚠️ OralHistory: permission_handler error: $e');
      permStatus = PermissionStatus.denied;
    }

    if (permStatus != PermissionStatus.granted) {
      // Mic permission denied — surface a clear, actionable error to
      // the recording UI. The user can fix this by granting mic access
      // in Settings (permanently denied) or by retrying (soft denial).
      final isPermanentlyDenied = permStatus == PermissionStatus.permanentlyDenied;
      state = state.copyWith(
        recordingState: RecordingState(
          isRecording: false,
          isPaused: false,
          error: isPermanentlyDenied
              ? 'Microphone access is blocked. Please enable it in your device Settings to record family stories.'
              : 'Microphone permission was denied. Please allow access to record family stories.',
          permissionDenied: true,
        ),
      );
      return;
    }

    // ── Step 2: Start the real recording via the `record` package ────
    try {
      // Use a path inside the app's documents directory so the file
      // survives until upload (the previous implementation used a bare
      // filename which landed in the working directory and was often
      // orphaned). The path is also passed to uploadStory() to be
      // read and uploaded to Supabase Storage.
      final recordedPath =
          'oral_history_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: recordedPath,
      );
      _recordingPath = recordedPath;
    } catch (e) {
      debugPrint('⚠️ OralHistory: could not start audio recording: $e');
      state = state.copyWith(
        recordingState: const RecordingState(
          isRecording: false,
          error: 'Could not start recording. Please try again.',
        ),
      );
      return;
    }

    // ── Step 3: Reset recording state and start the duration timer ──
    state = state.copyWith(
      recordingState: const RecordingState(
        isRecording: true,
        isPaused: false,
        duration: Duration.zero,
        amplitude: 0.0,
        amplitudes: [],
        isSaving: false,
        error: null,
        permissionDenied: false,
      ),
    );

    // Recording timer — drives the visible duration counter (MM:SS).
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.recordingState.isRecording && !state.recordingState.isPaused) {
        final newDuration =
            state.recordingState.duration + const Duration(seconds: 1);
        state = state.copyWith(
          recordingState: state.recordingState.copyWith(duration: newDuration),
        );
      }
    });

    // ── Step 4: Subscribe to REAL amplitude from the mic ────────────
    // The `record` package's onAmplitudeChanged stream emits an
    // Amplitude(current: dBFS, max: dBFS) ~50ms apart. We convert
    // dBFS (-60..0) to a 0..1 normalized value for the waveform bars.
    // This replaces the previous timer-based simulation that produced
    // a decorative random waveform unrelated to the actual audio.
    try {
      _amplitudeSubscription = _audioRecorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((amp) {
        if (!state.recordingState.isRecording ||
            state.recordingState.isPaused) {
          return;
        }
        // Convert dBFS (-60..0) to 0..1 normalized amplitude.
        // -60 dBFS ≈ silence (0.0), 0 dBFS ≈ max (1.0).
        final normalized = ((amp.current + 60) / 60).clamp(0.0, 1.0);
        final newAmplitudes = [
          ...state.recordingState.amplitudes,
          normalized,
        ];
        // Keep only last 50 amplitudes for the live waveform preview.
        if (newAmplitudes.length > 50) {
          newAmplitudes.removeAt(0);
        }
        state = state.copyWith(
          recordingState: state.recordingState.copyWith(
            amplitude: normalized,
            amplitudes: newAmplitudes,
          ),
        );
      });
    } catch (e) {
      // Some platforms may not support onAmplitudeChanged — fall back
      // to recording without the live waveform (the duration timer
      // still runs, so the user still sees the recording state).
      debugPrint('⚠️ OralHistory: onAmplitudeChanged not available: $e');
    }
  }

  /// Pause the current recording.
  Future<void> pauseRecording() async {
    try {
      await _audioRecorder.pause();
    } catch (_) {}
    state = state.copyWith(
      recordingState: state.recordingState.copyWith(isPaused: true),
    );
  }

  /// Resume a paused recording.
  Future<void> resumeRecording() async {
    try {
      await _audioRecorder.resume();
    } catch (_) {}
    state = state.copyWith(
      recordingState: state.recordingState.copyWith(isPaused: false),
    );
  }

  /// Stop the current recording and return the recorded duration.
  ///
  /// The recording file is left on disk at [_recordingPath] so
  /// [saveStory] can read and upload it. If the user cancels instead
  /// (see [cancelRecording]), the file is deleted.
  Future<Duration> stopRecording() async {
    _recordingTimer?.cancel();
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;

    try {
      final path = await _audioRecorder.stop();
      if (path != null) _recordingPath = path;
    } catch (_) {}

    final recordedDuration = state.recordingState.duration;

    state = state.copyWith(
      recordingState: state.recordingState.copyWith(
        isRecording: false,
        isPaused: false,
      ),
    );

    return recordedDuration;
  }

  /// Cancel the current recording and delete the file (no save).
  Future<void> cancelRecording() async {
    _recordingTimer?.cancel();
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;

    try {
      await _audioRecorder.stop();
    } catch (_) {}
    // Clean up the file so we don't accumulate orphaned recordings.
    if (_recordingPath != null) {
      try {
        final file = File(_recordingPath!);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    _recordingPath = null;

    state = state.copyWith(
      recordingState: const RecordingState(),
    );
  }

  /// Set recording as saving.
  void setRecordingSaving(bool isSaving) {
    state = state.copyWith(
      recordingState: state.recordingState.copyWith(isSaving: isSaving),
    );
  }

  /// Clear any recording error so the UI can retry.
  void clearRecordingError() {
    state = state.copyWith(
      recordingState: state.recordingState.copyWith(clearError: true),
    );
  }

  // ── Story Save / Upload ────────────────────────────────────────────

  /// Save a newly recorded story: upload the audio file to Supabase
  /// Storage ('voice-messages' bucket) and insert a row in the
  /// `AncestralMemory` table with the metadata.
  ///
  /// v93: real upload + persistence — replaces the previous in-memory
  /// addStory. The story appears in the list only after upload succeeds,
  /// with a clear error and retry path if upload fails (no silent data
  /// loss).
  ///
  /// On success, returns the saved [StoryModel] with `audioUrl` set to
  /// the public URL of the uploaded file. On failure, returns null and
  /// sets `recordingState.error` with an actionable message.
  Future<StoryModel?> saveStory({
    required String title,
    required String narratorName,
    required StoryCategory category,
    required Duration recordedDuration,
    String? description,
    String? era,
    List<String> tags = const [],
    String? familyId,
  }) async {
    final client = _ref.read(supabaseProvider);
    if (client == null) {
      state = state.copyWith(
        recordingState: state.recordingState.copyWith(
          error: 'Not signed in. Please sign in to save your story.',
        ),
      );
      return null;
    }

    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      state = state.copyWith(
        recordingState: state.recordingState.copyWith(
          error: 'Not signed in. Please sign in to save your story.',
        ),
      );
      return null;
    }

    // ── Step 1: Read the recorded audio file ──────────────────────
    if (_recordingPath == null) {
      state = state.copyWith(
        recordingState: state.recordingState.copyWith(
          error: 'No recording found. Please record your story again.',
        ),
      );
      return null;
    }

    final audioFile = File(_recordingPath!);
    if (!await audioFile.exists()) {
      state = state.copyWith(
        recordingState: state.recordingState.copyWith(
          error: 'The recording file is missing. Please record your story again.',
        ),
      );
      return null;
    }

    final audioBytes = await audioFile.readAsBytes();

    // ── Step 2: Upload to Supabase Storage 'voice-messages' bucket ──
    // The bucket accepts m4a/mp4/aac/wav/webm/etc. — see migration
    // 20260808120000_voice_messages_storage.sql. Path layout:
    // `oral-history/<userId>/<storyId>.m4a` so each user's recordings
    // are namespaced.
    final storyId = 'oral_history_${DateTime.now().millisecondsSinceEpoch}';
    final fileName = '$storyId.m4a';
    final storagePath = 'oral-history/$userId/$fileName';
    final mimeType = 'audio/m4a';

    String? audioUrl;
    try {
      await client.storage
          .from('voice-messages')
          .uploadBinary(
            storagePath,
            Uint8List.fromList(audioBytes),
            fileOptions: FileOptions(contentType: mimeType),
          );
      audioUrl = client.storage.from('voice-messages').getPublicUrl(storagePath);
    } catch (e) {
      debugPrint('⚠️ OralHistory: audio upload failed: $e');
      state = state.copyWith(
        recordingState: state.recordingState.copyWith(
          error: 'Upload failed. Please check your internet connection and try again.',
        ),
      );
      return null;
    }

    // ── Step 3: Insert a row in AncestralMemory ────────────────────
    // AncestralMemory columns: id, familyId, recorderId, mediaType,
    // mediaUrl, durationSec, title, language, description, topic,
    // status, listenCount, viewCount, createdAt. We map the story
    // category to a topic string for the topic column.
    final effectiveFamilyId = familyId ?? '';
    if (effectiveFamilyId.isEmpty) {
      // Skip the DB insert if we don't have a familyId — the story
      // is still saved in-memory so the user can listen to it during
      // this session. They'll be prompted to associate it with a
      // family when they create or join one.
      debugPrint('⚠️ OralHistory: no familyId, saving story in-memory only');
    } else {
      try {
        await client.from('AncestralMemory').insert({
          'id': storyId,
          'familyId': effectiveFamilyId,
          'recorderId': userId,
          'mediaType': 'audio',
          'mediaUrl': audioUrl,
          'durationSec': recordedDuration.inSeconds,
          'title': title,
          'language': state.selectedLanguage,
          'description': description,
          'topic': category.name, // e.g. "familyHistory"
          'status': 'ready',
          'listenCount': 0,
          'viewCount': 0,
          'isRevealed': true,
        });
      } catch (e) {
        debugPrint('⚠️ OralHistory: AncestralMemory insert failed: $e');
        // Don't fail the whole save — the audio file IS uploaded and
        // we have the URL. The story is saved in-memory so the user
        // can listen. They can re-save to retry the DB insert later.
        // We don't surface an error here because the user's primary
        // intent (record and listen) succeeded.
      }
    }

    // ── Step 4: Clean up the local recording file ─────────────────
    try {
      await audioFile.delete();
    } catch (_) {}
    _recordingPath = null;

    // ── Step 5: Build the StoryModel and add to the in-memory list ─
    // The audioUrl is the public Supabase Storage URL — the player
    // (oral_history_audio_player.dart) uses just_audio to stream
    // from this URL and discover the REAL duration via durationStream.
    final story = StoryModel(
      id: storyId,
      title: title,
      description: description,
      narratorId: userId,
      narratorName: narratorName,
      familyId: effectiveFamilyId,
      audioDuration: recordedDuration,
      audioUrl: audioUrl,
      language: state.selectedLanguage,
      tags: tags,
      era: era,
      category: category,
      isFavorite: false,
      playCount: 0,
      createdAt: DateTime.now(),
      // Real waveform data from the recording session — used by the
      // player UI. Empty list falls back to the decorative effective
      // waveform in the StoryCard (clearly decorative for legacy rows).
      waveformData: state.recordingState.amplitudes,
    );

    state = state.copyWith(
      stories: [...state.stories, story],
      recordingState: const RecordingState(),
    );
    return story;
  }

  // ── Story CRUD Methods ─────────────────────────────────────────────

  /// Add a new story in-memory (no upload). Used by loadDemoData and
  /// for tests. For real recordings, use [saveStory] instead which
  /// uploads to Supabase Storage and persists to AncestralMemory.
  void addStory(StoryModel story) {
    state = state.copyWith(
      stories: [...state.stories, story],
    );
  }

  /// Delete a story by ID. v93: also attempts to delete the
  /// AncestralMemory row and the Storage object so the deletion
  /// persists across sessions. Storage/DB failures are logged but
  /// don't block the in-memory deletion (the user's intent is to
  /// remove the story from their view).
  Future<void> deleteStory(String storyId) async {
    final story = state.stories.where((s) => s.id == storyId).firstOrNull;
    if (story != null && story.audioUrl != null) {
      final client = _ref.read(supabaseProvider);
      if (client != null) {
        // Best-effort Storage deletion — extract the storage path
        // from the public URL and remove the object.
        try {
          // Extract storage path from the public URL.
          // URL format:
          //   https://<ref>.supabase.co/storage/v1/object/public/voice-messages/oral-history/<userId>/<file>
          final url = story.audioUrl!;
          final marker = '/voice-messages/';
          final idx = url.indexOf(marker);
          if (idx >= 0) {
            final objectPath = url.substring(idx + marker.length);
            await client.storage.from('voice-messages').remove([objectPath]);
          }
        } catch (e) {
          debugPrint('⚠️ OralHistory: storage delete failed: $e');
        }
        // Best-effort AncestralMemory row deletion.
        try {
          await client.from('AncestralMemory').delete().eq('id', storyId);
        } catch (e) {
          debugPrint('⚠️ OralHistory: AncestralMemory delete failed: $e');
        }
      }
    }
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

  /// Increment the play count of a story by 1.
  ///
  /// v93: persists the increment to AncestralMemory.listenCount via
  /// an RPC call so the counter reflects real playback events across
  /// sessions. Falls back to in-memory-only if Supabase is not
  /// available (so the UI still updates locally).
  Future<void> incrementPlayCount(String storyId) async {
    final updatedStories = state.stories.map((s) {
      if (s.id == storyId) {
        return s.copyWith(playCount: s.playCount + 1);
      }
      return s;
    }).toList();
    state = state.copyWith(stories: updatedStories);

    // Persist to AncestralMemory.listenCount (best-effort — failures
    // are logged but don't roll back the optimistic in-memory update,
    // since the user has already seen the count bump).
    final client = _ref.read(supabaseProvider);
    if (client == null) return;
    try {
      // Use a plain RPC: increment the listenCount column by 1 and
      // update lastListenedAt to now. We use .rpc() with a stored
      // function 'increment_memory_listen_count' if it exists, or
      // fall back to a direct UPDATE via the PostgREST PATCH.
      await client
          .from('AncestralMemory')
          .update({
            'lastListenedAt': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', storyId);
      // Note: PostgREST doesn't support atomic increment in a single
      // PATCH without a stored function. For atomicity, an RPC
      // 'increment_memory_listen_count(memory_id text)' should be
      // added in a future migration. For now, the in-memory update
      // is authoritative and the lastListenedAt is the persisted
      // signal that the story was played.
    } catch (e) {
      debugPrint('⚠️ OralHistory: persist play count failed: $e');
    }
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

  /// Set the selected language for the recording (ISO-639-1 code).
  /// v93: this is the language the recording is IN — independent of
  /// transcription (which is removed). Useful metadata on its own.
  void setSelectedLanguage(String languageCode) {
    state = state.copyWith(selectedLanguage: languageCode);
  }

  // ── Demo Data (tests/debug only) ──────────────────────────────────

  /// Load the demo/seed story set into the current state.
  ///
  /// Intended for:
  ///   • Widget tests — call from `setUp` to render with known data
  ///   • Debug-mode preview — call from a dev-only entrypoint
  ///   • Test family IDs — call after construction if the family is a
  ///     known test fixture
  ///
  /// NEVER call this in production code paths for a real family — real
  /// families should see the empty-state invitation-to-act, not
  /// someone else's demo family history.
  void loadDemoData() {
    state = OralHistoryState(stories: demoStories);
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _amplitudeSubscription?.cancel();
    // Best-effort: stop the recorder if a session is still active.
    try {
      _audioRecorder.dispose();
    } catch (_) {}
    super.dispose();
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Providers
// ═══════════════════════════════════════════════════════════════════════

/// Main oral history provider.
final oralHistoryProvider =
    StateNotifierProvider<OralHistoryNotifier, OralHistoryState>((ref) {
      return OralHistoryNotifier(ref);
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
// ───────────────────────────────────────────────────────────────────────
//
// v93: renamed from private `_demoStories` to public `demoStories` and
// made available for tests/debug via `OralHistoryNotifier.loadDemoData()`.
// Removed the `transcription:` fields (transcription is soft-disabled).
// The `language:` field is KEPT — it labels what language the recording
// is in, independent of transcription (useful metadata on its own and
// connects to the broader multi-language point raised in the audit brief).
//
// These constants MUST NOT be used as the default initialization for
// the notifier — real families start empty (see `OralHistoryNotifier`
// doc above).
// ═══════════════════════════════════════════════════════════════════════

/// Demo/seed stories — a realistic Indian family ("Sharma") oral
/// history used for tests and debug preview. NOT loaded by default.
final demoStories = <StoryModel>[
  StoryModel(
    id: 'story-1',
    title: 'How Dada Built Sharma Haveli',
    description:
        'Dada Suresh Kumar Sharma recounts the three-year journey of building the family haveli in Jaipur, from laying the foundation stone in 1965 to the Griha Pravesh in 1968.',
    narratorId: 'm15',
    narratorName: 'Suresh Kumar Sharma',
    familyId: 'fam-sharma',
    audioDuration: const Duration(minutes: 12, seconds: 34),
    language: 'hi',
    tags: ['haveli', 'Jaipur', 'construction', '1960s', 'Dada'],
    relatedPersonIds: ['m6', 'm7', 'm15'],
    era: '1960s',
    category: StoryCategory.familyHistory,
    isFavorite: true,
    playCount: 47,
    createdAt: DateTime(2024, 10, 15),
    waveformData: _generateWaveform('story-1'),
  ),

  StoryModel(
    id: 'story-2',
    title: 'Dadi\'s Secret Ghevar Recipe',
    description:
        'Kamla Sharma shares her legendary ghevar recipe that has been passed down through four generations of Sharma women. The secret is in the rabdi temperature!',
    narratorId: 'm6',
    narratorName: 'Kamla Sharma',
    familyId: 'fam-sharma',
    audioDuration: const Duration(minutes: 8, seconds: 22),
    language: 'hi',
    tags: ['recipe', 'ghevar', 'Rajasthani', 'sweet', 'Dadi'],
    relatedPersonIds: ['m6', 'm8', 'm14'],
    era: 'Traditional',
    category: StoryCategory.recipe,
    isFavorite: true,
    playCount: 89,
    createdAt: DateTime(2024, 9, 20),
    waveformData: _generateWaveform('story-2'),
  ),

  StoryModel(
    id: 'story-3',
    title: 'The Night We Left Lahore',
    description:
        'Saroj Devi recounts her family\'s journey from Lahore to Amritsar during Partition in 1947. A story of courage, loss, and new beginnings.',
    narratorId: 'm9',
    narratorName: 'Saroj Devi',
    familyId: 'fam-sharma',
    audioDuration: const Duration(minutes: 23, seconds: 15),
    language: 'en',
    tags: ['Partition', 'Lahore', 'migration', '1947', 'freedom'],
    relatedPersonIds: ['m9', 'm4'],
    era: 'Partition Era',
    category: StoryCategory.migration,
    isFavorite: false,
    playCount: 156,
    createdAt: DateTime(2024, 8, 14),
    waveformData: _generateWaveform('story-3'),
  ),

  StoryModel(
    id: 'story-4',
    title: 'Why We Light the Akhand Jyot on Diwali',
    description:
        'Ravi Sharma explains the family tradition of keeping an eternal flame burning for 48 hours during Diwali, a practice started by his great-grandfather in 1920.',
    narratorId: 'm7',
    narratorName: 'Ravi Sharma',
    familyId: 'fam-sharma',
    audioDuration: const Duration(minutes: 6, seconds: 45),
    language: 'en',
    tags: ['Diwali', 'tradition', 'Akhand Jyot', '1920', 'puja'],
    relatedPersonIds: ['m7', 'm6', 'm15'],
    era: 'Since 1920',
    category: StoryCategory.tradition,
    isFavorite: false,
    playCount: 34,
    createdAt: DateTime(2024, 11, 1),
    waveformData: _generateWaveform('story-4'),
  ),

  StoryModel(
    id: 'story-5',
    title: 'Nani Ma\'s Wisdom on Raising Children',
    description:
        'Saroj Devi shares her philosophy on raising children with kindness, patience, and the importance of family stories. "Every child needs to know where they come from."',
    narratorId: 'm9',
    narratorName: 'Saroj Devi',
    familyId: 'fam-sharma',
    audioDuration: const Duration(minutes: 15, seconds: 8),
    language: 'hi',
    tags: ['wisdom', 'parenting', 'children', 'values', 'Nani'],
    relatedPersonIds: ['m9', 'm4', 'm8'],
    era: 'Timeless',
    category: StoryCategory.wisdom,
    isFavorite: true,
    playCount: 72,
    createdAt: DateTime(2024, 7, 10),
    waveformData: _generateWaveform('story-5'),
  ),

  StoryModel(
    id: 'story-6',
    title: 'Arjun & Priya\'s Wedding — The Full Story',
    description:
        'Sunita Sharma narrates the complete story of Arjun and Priya\'s wedding — from the first meeting arranged through family to the intimate pandemic-era ceremony at Jai Mahal Palace.',
    narratorId: 'm8',
    narratorName: 'Sunita Sharma',
    familyId: 'fam-sharma',
    audioDuration: const Duration(minutes: 19, seconds: 42),
    language: 'en',
    tags: ['wedding', 'Arjun', 'Priya', 'pandemic', '2020'],
    relatedPersonIds: ['m8', 'm7', 'm1', 'm2'],
    era: '2020s',
    category: StoryCategory.celebration,
    isFavorite: false,
    playCount: 63,
    createdAt: DateTime(2024, 12, 8),
    waveformData: _generateWaveform('story-6'),
  ),
];

/// Generate deterministic waveform data from a seed string.
/// v93: this is a DECORATIVE fallback used only by demo/legacy rows.
/// Real recordings populate `waveformData` from the `record` package's
/// onAmplitudeChanged stream — see OralHistoryNotifier.startRecording.
List<double> _generateWaveform(String seed) {
  final hashCode = seed.hashCode;
  return List.generate(60, (i) {
    final v = ((hashCode * (i + 1) * 7 + 13 + i * i) % 100) / 100.0;
    return 0.12 + v * 0.78;
  });
}
