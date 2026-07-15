// lib/features/festival_theme/festival_theme_overlay.dart
//
// P8.2b — Festival theming overlay.
//
// Applies an optional, user-toggleable visual theme during festivals
// (e.g. Diwali, Eid, Christmas). The overlay is purely cosmetic and is
// OFF by default. It never auto-nags, never tracks whether the user
// "celebrated", and carries no engagement signal.
//
// Constitution / Copy-Audit: neutral, descriptive copy. No urgency
// ("last chance to celebrate"), no streaks, no FOMO.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A cosmetic festival theme. No behavioural payload.
@immutable
class FestivalTheme {
  const FestivalTheme({
    required this.id,
    required this.name,
    required this.accentColorValue,
    required this.motif,
    this.description = '',
  });

  final String id;
  final String name;
  /// 0xAARRGGBB accent.
  final int accentColorValue;
  /// Stable token the painter switches on (e.g. 'diya', 'crescent').
  final String motif;
  final String description;

  FestivalTheme copyWith({
    String? id,
    String? name,
    int? accentColorValue,
    String? motif,
    String? description,
  }) {
    return FestivalTheme(
      id: id ?? this.id,
      name: name ?? this.name,
      accentColorValue: accentColorValue ?? this.accentColorValue,
      motif: motif ?? this.motif,
      description: description ?? this.description,
    );
  }
}

const _defaultThemes = <FestivalTheme>[
  FestivalTheme(
    id: 'diwali',
    name: 'Diwali',
    accentColorValue: 0xFFFFB300,
    motif: 'diya',
    description: 'Warm gold accents for the festival of lights.',
  ),
  FestivalTheme(
    id: 'eid',
    name: 'Eid',
    accentColorValue: 0xFF2E8B57,
    motif: 'crescent',
    description: 'Green crescent motif.',
  ),
  FestivalTheme(
    id: 'christmas',
    name: 'Christmas',
    accentColorValue: 0xFFC62828,
    motif: 'pine',
    description: 'Pine red accents.',
  ),
  FestivalTheme(
    id: 'onam',
    name: 'Onam',
    accentColorValue: 0xFFFFA000,
    motif: 'pookalam',
    description: 'Flower-rangoli motif.',
  ),
];

@immutable
class FestivalThemeState {
  const FestivalThemeState({
    this.available = _defaultThemes,
    this.activeTheme,
    this.isOverlayEnabled = false,
  });

  final List<FestivalTheme> available;
  /// Currently chosen theme. Null means "no theme selected".
  final FestivalTheme? activeTheme;
  /// Master switch. The overlay is only rendered when this is true
  /// AND `activeTheme` is non-null.
  final bool isOverlayEnabled;

  bool get isOverlayActive => isOverlayEnabled && activeTheme != null;

  FestivalThemeState copyWith({
    List<FestivalTheme>? available,
    FestivalTheme? activeTheme,
    bool clearActive = false,
    bool? isOverlayEnabled,
  }) {
    return FestivalThemeState(
      available: available ?? this.available,
      activeTheme: clearActive ? null : (activeTheme ?? this.activeTheme),
      isOverlayEnabled: isOverlayEnabled ?? this.isOverlayEnabled,
    );
  }
}

class FestivalThemeController extends StateNotifier<FestivalThemeState> {
  FestivalThemeController() : super(const FestivalThemeState());

  /// Selects a theme by id. Does NOT auto-enable the overlay — the user
  /// opts in explicitly via `enableOverlay()` so we never surprise them
  /// with a visual change.
  void selectTheme(String id) {
    final match = state.available.where((t) => t.id == id).firstOrNull;
    if (match == null) return;
    state = state.copyWith(activeTheme: match);
  }

  void enableOverlay() =>
      state = state.copyWith(isOverlayEnabled: true);

  void disableOverlay() =>
      state = state.copyWith(isOverlayEnabled: false);

  void toggleOverlay() =>
      state = state.copyWith(isOverlayEnabled: !state.isOverlayEnabled);

  /// Clears the selection and turns the overlay off.
  void reset() => state = const FestivalThemeState();
}

final festivalThemeProvider =
    StateNotifierProvider<FestivalThemeController, FestivalThemeState>(
  (ref) => FestivalThemeController(),
);
