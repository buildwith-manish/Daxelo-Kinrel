// lib/features/rtl/providers/rtl_check.dart
//
// P8.2a — RTL check helper.
//
// Detects whether a piece of user-facing text contains right-to-left
// (RTL) characters so the UI can mirror layout and set the correct
// `TextDirection`. This is a layout/a11y helper — it stores no user
// content and sends nothing to the network.
//
// Constitution note: neutral, descriptive copy only. No engagement,
// no scoring, no telemetry.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Coarse directionality classification for a run of text.
enum RtlDirectionality { ltr, rtl, mixed, empty }

/// Pure helper. No state, no side-effects — safe to unit-test in isolation.
class RtlCheck {
  const RtlCheck._();

  /// True when [codeUnit] belongs to an RTL script block
  /// (Arabic, Hebrew, Syriac, Thaana, N'Ko, etc.).
  static bool isRtlCodeUnit(int codeUnit) {
    // Hebrew block: U+0590 – U+05FF
    if (codeUnit >= 0x0590 && codeUnit <= 0x05FF) return true;
    // Arabic block: U+0600 – U+06FF
    if (codeUnit >= 0x0600 && codeUnit <= 0x06FF) return true;
    // Arabic Supplement: U+0750 – U+077F
    if (codeUnit >= 0x0750 && codeUnit <= 0x077F) return true;
    // Syriac: U+0700 – U+074F
    if (codeUnit >= 0x0700 && codeUnit <= 0x074F) return true;
    // Thaana: U+0780 – U+07BF
    if (codeUnit >= 0x0780 && codeUnit <= 0x07BF) return true;
    // N'Ko: U+07C0 – U+07FF
    if (codeUnit >= 0x07C0 && codeUnit <= 0x07FF) return true;
    // Arabic Presentation Forms-A/B
    if (codeUnit >= 0xFB50 && codeUnit <= 0xFDFF) return true;
    if (codeUnit >= 0xFE70 && codeUnit <= 0xFEFF) return true;
    // RLM (U+200F) and ALM (U+061C)
    if (codeUnit == 0x200F || codeUnit == 0x061C) return true;
    return false;
  }

  /// Classifies [text] into one directionality bucket.
  static RtlDirectionality detect(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return RtlDirectionality.empty;

    var hasRtl = false;
    var hasLtr = false;
    for (final codeUnit in trimmed.codeUnits) {
      if (codeUnit <= 0x0020) continue; // whitespace
      if (codeUnit >= 0x2000 && codeUnit <= 0x206F) continue; // punct
      if (codeUnit >= 0x0021 && codeUnit <= 0x0040) continue;
      if (codeUnit >= 0x005B && codeUnit <= 0x0060) continue;
      if (codeUnit >= 0x007B && codeUnit <= 0x007E) continue;
      if (codeUnit >= 0x0660 && codeUnit <= 0x0669) continue; // digits
      if (isRtlCodeUnit(codeUnit)) {
        hasRtl = true;
      } else {
        hasLtr = true;
      }
      if (hasRtl && hasLtr) return RtlDirectionality.mixed;
    }
    if (hasRtl) return RtlDirectionality.rtl;
    if (hasLtr) return RtlDirectionality.ltr;
    return RtlDirectionality.empty;
  }

  /// A human-readable, neutral label for accessibility / debug overlays.
  static String describe(RtlDirectionality d) {
    switch (d) {
      case RtlDirectionality.ltr:
        return 'Left-to-right text';
      case RtlDirectionality.rtl:
        return 'Right-to-left text';
      case RtlDirectionality.mixed:
        return 'Mixed-direction text';
      case RtlDirectionality.empty:
        return 'No text';
    }
  }
}

/// Immutable snapshot of the RTL check for a single text input.
@immutable
class RtlCheckState {
  const RtlCheckState({
    this.input = '',
    this.directionality = RtlDirectionality.empty,
  });

  final String input;
  final RtlDirectionality directionality;

  /// True when the UI should mirror for an RTL reader.
  bool get shouldMirror =>
      directionality == RtlDirectionality.rtl ||
      directionality == RtlDirectionality.mixed;

  RtlCheckState copyWith({String? input, RtlDirectionality? directionality}) {
    return RtlCheckState(
      input: input ?? this.input,
      directionality: directionality ?? this.directionality,
    );
  }
}

/// Recomputes directionality whenever a new input string is supplied.
/// Kept `autoDispose` because it is transient per screen/form.
class RtlCheckNotifier extends StateNotifier<RtlCheckState> {
  RtlCheckNotifier() : super(const RtlCheckState());

  void evaluate(String text) {
    state = RtlCheckState(
      input: text,
      directionality: RtlCheck.detect(text),
    );
  }

  void clear() => state = const RtlCheckState();
}

final rtlCheckProvider =
    StateNotifierProvider.autoDispose<RtlCheckNotifier, RtlCheckState>(
  (ref) => RtlCheckNotifier(),
);
