// lib/features/family_journey/providers/journey_provider.dart
//
// P7.3 — Family Journey Replay provider.
// Filters the graph by year — who was alive, who had valid relationships.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// State of the journey replay.
@immutable
class JourneyState {
  const JourneyState({
    this.selectedYear = 2026,
    this.minYear = 1900,
    this.maxYear = 2026,
    this.isPlaying = false,
    this.playbackSpeedYearsPerSecond = 0.5,
    this.alivePersonIds = const {},
    this.memoryMarkers = const {},
  });

  final int selectedYear;
  final int minYear;
  final int maxYear;
  final bool isPlaying;
  final double playbackSpeedYearsPerSecond;
  final Set<String> alivePersonIds;
  final Map<int, String> memoryMarkers;

  JourneyState copyWith({
    int? selectedYear,
    int? minYear,
    int? maxYear,
    bool? isPlaying,
    double? playbackSpeedYearsPerSecond,
    Set<String>? alivePersonIds,
    Map<int, String>? memoryMarkers,
  }) {
    return JourneyState(
      selectedYear: selectedYear ?? this.selectedYear,
      minYear: minYear ?? this.minYear,
      maxYear: maxYear ?? this.maxYear,
      isPlaying: isPlaying ?? this.isPlaying,
      playbackSpeedYearsPerSecond:
          playbackSpeedYearsPerSecond ?? this.playbackSpeedYearsPerSecond,
      alivePersonIds: alivePersonIds ?? this.alivePersonIds,
      memoryMarkers: memoryMarkers ?? this.memoryMarkers,
    );
  }
}

/// Controller for the journey replay.
class JourneyController extends StateNotifier<JourneyState> {
  JourneyController() : super(JourneyState(maxYear: DateTime.now().year, selectedYear: DateTime.now().year));

  /// Sets the selected year.
  void setYear(int year) {
    state = state.copyWith(selectedYear: year.clamp(state.minYear, state.maxYear));
  }

  /// Starts auto-advance playback.
  void play() => state = state.copyWith(isPlaying: true);

  /// Pauses playback.
  void pause() => state = state.copyWith(isPlaying: false);

  /// Sets the year range.
  void setYearRange(int min, int max) {
    state = state.copyWith(minYear: min, maxYear: max);
  }

  /// Sets which persons were alive at the selected year.
  void setAlivePersons(Set<String> ids) {
    state = state.copyWith(alivePersonIds: ids);
  }

  /// Sets memory markers (year → memory description).
  void setMemoryMarkers(Map<int, String> markers) {
    state = state.copyWith(memoryMarkers: markers);
  }
}

final journeyProvider =
    StateNotifierProvider<JourneyController, JourneyState>(
  (ref) => JourneyController(),
);

/// Checks if a person was alive at [year].
/// Returns true if the person was born before or during [year] and
/// (if deceased) died after [year].
bool wasAliveAt({
  required int year,
  DateTime? dateOfBirth,
  DateTime? dateOfDeath,
}) {
  if (dateOfBirth == null) return true; // unknown birth = assume alive
  if (dateOfBirth.year > year) return false; // not born yet
  if (dateOfDeath != null && dateOfDeath.year < year) return false; // already deceased
  return true;
}
