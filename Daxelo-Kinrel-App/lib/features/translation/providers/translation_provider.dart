// lib/features/translation/providers/translation_provider.dart
//
// P8.2c — Cross-generational translation.
//
// Translates a short phrase between family registers (e.g. formal
// grandparent address ↔ casual sibling address) and between languages
// using a small local phrase table. This is an OFFLINE, deterministic
// helper — there is no ML model and no engagement loop. The goal is to
// help a younger member address an elder correctly, nothing more.
//
// Constitution / Copy-Audit: honest copy. We never claim the output is
// "perfect" or "AI-written"; it is a phrasebook lookup. No streaks,
// no "translated N phrases today" counters.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Linguistic register the user is addressing the recipient in.
enum GenerationRegister { formal, neutral, casual }

@immutable
class TranslationPair {
  const TranslationPair({
    required this.source,
    required this.target,
    required this.targetLanguageCode,
    required this.register,
    this.note,
  });

  final String source;
  final String target;
  /// BCP-47-ish code, e.g. 'hi', 'ta', 'en'.
  final String targetLanguageCode;
  final GenerationRegister register;
  /// Optional honest caveat (e.g. "regional variant").
  final String? note;
}

/// Small offline phrasebook. In production this would be loaded from the
/// existing `assets/data/kinship_terms.json` — kept inline here so the
/// provider is self-contained and unit-testable without assets.
const _phrasebook = <TranslationPair>[
  TranslationPair(
    source: 'mother',
    target: 'Maa',
    targetLanguageCode: 'hi',
    register: GenerationRegister.casual,
  ),
  TranslationPair(
    source: 'mother',
    target: 'Mata ji',
    targetLanguageCode: 'hi',
    register: GenerationRegister.formal,
  ),
  TranslationPair(
    source: 'father',
    target: 'Papa',
    targetLanguageCode: 'hi',
    register: GenerationRegister.casual,
  ),
  TranslationPair(
    source: 'father',
    target: 'Pita ji',
    targetLanguageCode: 'hi',
    register: GenerationRegister.formal,
  ),
  TranslationPair(
    source: 'grandmother',
    target: 'Dadi',
    targetLanguageCode: 'hi',
    register: GenerationRegister.neutral,
    note: 'Paternal grandmother; maternal is Nani.',
  ),
  TranslationPair(
    source: 'grandfather',
    target: 'Dada',
    targetLanguageCode: 'hi',
    register: GenerationRegister.neutral,
    note: 'Paternal grandfather; maternal is Nana.',
  ),
];

@immutable
class TranslationState {
  const TranslationState({
    this.sourceText = '',
    this.targetLanguageCode = 'hi',
    this.register = GenerationRegister.neutral,
    this.results = const [],
    this.hasSearched = false,
  });

  final String sourceText;
  final String targetLanguageCode;
  final GenerationRegister register;
  final List<TranslationPair> results;
  final bool hasSearched;

  TranslationState copyWith({
    String? sourceText,
    String? targetLanguageCode,
    GenerationRegister? register,
    List<TranslationPair>? results,
    bool? hasSearched,
  }) {
    return TranslationState(
      sourceText: sourceText ?? this.sourceText,
      targetLanguageCode: targetLanguageCode ?? this.targetLanguageCode,
      register: register ?? this.register,
      results: results ?? this.results,
      hasSearched: hasSearched ?? this.hasSearched,
    );
  }
}

class TranslationNotifier extends StateNotifier<TranslationState> {
  TranslationNotifier() : super(const TranslationState());

  void setSourceText(String text) =>
      state = state.copyWith(sourceText: text, hasSearched: false);

  void setTargetLanguage(String code) =>
      state = state.copyWith(targetLanguageCode: code, hasSearched: false);

  void setRegister(GenerationRegister r) =>
      state = state.copyWith(register: r, hasSearched: false);

  /// Looks up the current source text in the phrasebook. Honest: returns
  /// an empty list when nothing matches rather than fabricating a guess.
  void translate() {
    final needle = state.sourceText.trim().toLowerCase();
    if (needle.isEmpty) {
      state = state.copyWith(results: const [], hasSearched: true);
      return;
    }
    final matches = _phrasebook.where((p) {
      if (p.source.toLowerCase() != needle) return false;
      if (p.targetLanguageCode != state.targetLanguageCode) return false;
      // When the user picked a specific register, honour it; otherwise
      // surface every matching register so they can choose.
      if (state.register != GenerationRegister.neutral &&
          p.register != state.register) {
        return false;
      }
      return true;
    }).toList();
    state = state.copyWith(results: matches, hasSearched: true);
  }

  void clear() => state = const TranslationState();
}

final translationProvider =
    StateNotifierProvider<TranslationNotifier, TranslationState>(
  (ref) => TranslationNotifier(),
);
