// lib/features/kinship_pronunciation/providers/kinship_pronunciation_provider.dart
//
// P9.2c — Kinship pronunciation.
//
// Helps a learner hear/see how a kinship term (e.g. "Dadi", "Chitappa")
// is pronounced. Holds the currently-selected term, a phonetic guide,
// and an `isPlaying` flag. No audio bytes are bundled here — the caller
// supplies an `audioUrl` (or null when only the phonetic guide is
// available, which we state honestly).
//
// Constitution / Copy-Audit: honest copy. We never claim a "perfect
// accent"; the phonetic guide is labelled as approximate. No streaks,
// no "pronounce 5 terms today" engagement.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class KinshipPronunciation {
  const KinshipPronunciation({
    required this.term,
    required this.phonetic,
    required this.languageCode,
    this.audioUrl,
    this.note,
  });

  final String term;
  /// Approximate phonetic spelling, e.g. "DAA-dee".
  final String phonetic;
  final String languageCode;
  /// Null when no recording is available (state this honestly to the user).
  final String? audioUrl;
  /// Optional honest caveat, e.g. "regional variant".
  final String? note;

  bool get hasAudio => audioUrl != null && audioUrl!.isNotEmpty;
}

@immutable
class PronunciationState {
  const PronunciationState({
    this.current,
    this.isPlaying = false,
    this.playbackError,
    this.recentlyPlayed = const [],
  });

  final KinshipPronunciation? current;
  final bool isPlaying;
  final String? playbackError;
  /// Bounded, most-recent-first log of what the user played. Used only
  /// to render a small "recently heard" list. NOT a streak / NOT a
  /// count surfaced to the user as a metric.
  final List<KinshipPronunciation> recentlyPlayed;

  PronunciationState copyWith({
    KinshipPronunciation? current,
    bool? isPlaying,
    String? playbackError,
    bool clearError = false,
    List<KinshipPronunciation>? recentlyPlayed,
  }) {
    return PronunciationState(
      current: current ?? this.current,
      isPlaying: isPlaying ?? this.isPlaying,
      playbackError:
          clearError ? null : (playbackError ?? this.playbackError),
      recentlyPlayed: recentlyPlayed ?? this.recentlyPlayed,
    );
  }
}

class KinshipPronunciationNotifier
    extends StateNotifier<PronunciationState> {
  KinshipPronunciationNotifier() : super(const PronunciationState());

  /// Selects a term to view / play. Does NOT auto-play.
  void select(KinshipPronunciation pron) {
    state = state.copyWith(current: pron, clearError: true, isPlaying: false);
  }

  /// Marks playback as started. Honest: if there is no audio asset, we
  /// surface a neutral message rather than silently faking playback.
  void play() {
    final c = state.current;
    if (c == null) return;
    if (!c.hasAudio) {
      state = state.copyWith(
        isPlaying: false,
        playbackError: 'No audio available — showing the phonetic guide only.',
      );
      return;
    }
    state = state.copyWith(isPlaying: true, clearError: true);
  }

  /// Marks playback as finished and records the term in the recent list.
  void stop() {
    final c = state.current;
    if (c == null) {
      state = state.copyWith(isPlaying: false);
      return;
    }
    final recent = [c, ...state.recentlyPlayed.where((p) => p.term != c.term)]
        .take(8)
        .toList(growable: false);
    state = state.copyWith(isPlaying: false, recentlyPlayed: recent);
  }

  void clearError() => state = state.copyWith(clearError: true);

  void clear() => state = const PronunciationState();
}

final kinshipPronunciationProvider =
    StateNotifierProvider<KinshipPronunciationNotifier, PronunciationState>(
  (ref) => KinshipPronunciationNotifier(),
);
