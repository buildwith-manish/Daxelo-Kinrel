// lib/features/grandparent_mode/grandparent_mode_profile.dart
//
// P12.6 Batch 4 — Grandparent Mode (accessibility presentation profile).
//
// Per kinrel_final_audited_prompt_v2.md §5.2:
//   - NOT a parallel set of screens or duplicate navigation/provider logic.
//   - A presentation-layer profile applied over existing screens.
//   - Scope: text scale, navigation density, icon+text pairing,
//     animation/motion reduction, information density, primary-action
//     visual prominence.
//   - Reuses existing reduced-motion infrastructure.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class GrandparentModeState {
  const GrandparentModeState({this.enabled = false});
  final bool enabled;

  static const double textScaleFactor = 1.3;
  static const bool alwaysPairIconWithText = true;
  static const int maxNavOptions = 5;
  static const double minTapTargetSize = 48.0;
  static const bool reduceAnimations = true;

  GrandparentModeState copyWith({bool? enabled}) {
    return GrandparentModeState(enabled: enabled ?? this.enabled);
  }
}

class GrandparentModeNotifier extends StateNotifier<GrandparentModeState> {
  GrandparentModeNotifier() : super(const GrandparentModeState());
  void enable() => state = const GrandparentModeState(enabled: true);
  void disable() => state = const GrandparentModeState(enabled: false);
  void toggle() => state = GrandparentModeState(enabled: !state.enabled);
}

final grandparentModeProvider =
    StateNotifierProvider<GrandparentModeNotifier, GrandparentModeState>(
      (ref) => GrandparentModeNotifier(),
    );
