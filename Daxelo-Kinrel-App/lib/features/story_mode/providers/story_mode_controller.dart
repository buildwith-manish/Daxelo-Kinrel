// lib/features/story_mode/providers/story_mode_controller.dart
//
// P7.2 — Story Mode controller.
// Guides the user through a narrated tour of their family history.
// Uses spring physics (P3.1) for camera choreography and flutter_tts
// for narration.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A single chapter in the Story Mode tour.
@immutable
class StoryChapter {
  const StoryChapter({
    required this.id,
    required this.title,
    required this.narration,
    required this.focusPersonId,
    this.durationSeconds = 8,
  });

  final String id;
  final String title;
  final String narration;
  final String focusPersonId;
  final int durationSeconds;
}

/// State of the Story Mode playback.
@immutable
class StoryModeState {
  const StoryModeState({
    this.chapters = const [],
    this.currentIndex = 0,
    this.isPlaying = false,
    this.isPaused = false,
    this.subtitlesEnabled = true,
  });

  final List<StoryChapter> chapters;
  final int currentIndex;
  final bool isPlaying;
  final bool isPaused;
  final bool subtitlesEnabled;

  StoryChapter? get currentChapter =>
      chapters.isEmpty || currentIndex >= chapters.length
          ? null
          : chapters[currentIndex];

  bool get isLastChapter => currentIndex >= chapters.length - 1;
  bool get isFirstChapter => currentIndex == 0;

  StoryModeState copyWith({
    List<StoryChapter>? chapters,
    int? currentIndex,
    bool? isPlaying,
    bool? isPaused,
    bool? subtitlesEnabled,
  }) {
    return StoryModeState(
      chapters: chapters ?? this.chapters,
      currentIndex: currentIndex ?? this.currentIndex,
      isPlaying: isPlaying ?? this.isPlaying,
      isPaused: isPaused ?? this.isPaused,
      subtitlesEnabled: subtitlesEnabled ?? this.subtitlesEnabled,
    );
  }
}

/// Controller for Story Mode playback.
class StoryModeController extends StateNotifier<StoryModeState> {
  StoryModeController() : super(const StoryModeState());

  /// Loads chapters from the family chronicle.
  void loadChapters(List<StoryChapter> chapters) {
    state = StoryModeState(chapters: chapters);
  }

  /// Starts playback from the beginning (or current position).
  void play() {
    state = state.copyWith(isPlaying: true, isPaused: false);
  }

  /// Pauses playback.
  void pause() {
    state = state.copyWith(isPaused: true);
  }

  /// Advances to the next chapter.
  void next() {
    if (state.isLastChapter) {
      state = state.copyWith(isPlaying: false);
      return;
    }
    state = state.copyWith(currentIndex: state.currentIndex + 1);
  }

  /// Goes back to the previous chapter.
  void previous() {
    if (state.isFirstChapter) return;
    state = state.copyWith(currentIndex: state.currentIndex - 1);
  }

  /// Seeks to a specific chapter.
  void seekTo(int index) {
    if (index >= 0 && index < state.chapters.length) {
      state = state.copyWith(currentIndex: index);
    }
  }

  /// Toggles subtitles.
  void toggleSubtitles() {
    state = state.copyWith(subtitlesEnabled: !state.subtitlesEnabled);
  }

  /// Stops playback and resets to the beginning.
  void stop() {
    state = const StoryModeState();
  }
}

/// Provider for Story Mode.
final storyModeProvider =
    StateNotifierProvider<StoryModeController, StoryModeState>(
  (ref) => StoryModeController(),
);
