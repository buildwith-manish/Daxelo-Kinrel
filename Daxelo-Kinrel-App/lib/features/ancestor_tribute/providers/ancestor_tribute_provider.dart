// lib/features/ancestor_tribute/providers/ancestor_tribute_provider.dart
//
// P9.2k — Ancestor tribute wall.
//
// A simple, respectful wall where family members leave short text
// tributes to ancestors. This minimal provider holds an in-memory list
// (in production, backed by Supabase with RLS). There is deliberately
// NO "most-loved tribute" surface, NO like count, and NO time-pressure
// ("tribute of the day"). Tributes are listed in chronological order.
//
// Constitution / Copy-Audit: reverent, neutral copy. No engagement
// metrics, no streaks, no manufactured urgency around remembrance.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class AncestorTribute {
  const AncestorTribute({
    required this.id,
    required this.ancestorName,
    required this.tribute,
    required this.createdAt,
    this.authorName,
  });

  final String id;
  final String ancestorName;
  final String tribute;
  final DateTime createdAt;
  /// Optional author. May be null for an anonymous tribute.
  final String? authorName;

  AncestorTribute copyWith({
    String? id,
    String? ancestorName,
    String? tribute,
    DateTime? createdAt,
    String? authorName,
    bool clearAuthor = false,
  }) {
    return AncestorTribute(
      id: id ?? this.id,
      ancestorName: ancestorName ?? this.ancestorName,
      tribute: tribute ?? this.tribute,
      createdAt: createdAt ?? this.createdAt,
      authorName:
          clearAuthor ? null : (authorName ?? this.authorName),
    );
  }
}

@immutable
class AncestorTributeState {
  const AncestorTributeState({
    this.tributes = const [],
    this.isSaving = false,
    this.error,
  });

  final List<AncestorTribute> tributes;
  final bool isSaving;
  final String? error;

  /// Chronological (oldest first) — the wall reads top-to-bottom in the
  /// order tributes were left.
  List<AncestorTribute> get chronological =>
      List<AncestorTribute>.of(tributes)
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  AncestorTributeState copyWith({
    List<AncestorTribute>? tributes,
    bool? isSaving,
    String? error,
    bool clearError = false,
  }) {
    return AncestorTributeState(
      tributes: tributes ?? this.tributes,
      isSaving: isSaving ?? this.isSaving,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class AncestorTributeNotifier
    extends StateNotifier<AncestorTributeState> {
  AncestorTributeNotifier() : super(const AncestorTributeState());

  int _counter = 0;
  String _newId() =>
      'tribute-${DateTime.now().millisecondsSinceEpoch}-${_counter++}';

  /// Adds a tribute. Rejects empty name or body with a neutral message.
  void addTribute({
    required String ancestorName,
    required String tribute,
    String? authorName,
  }) {
    final name = ancestorName.trim();
    final body = tribute.trim();
    if (name.isEmpty) {
      state = state.copyWith(error: 'Please name the ancestor being remembered.');
      return;
    }
    if (body.isEmpty) {
      state = state.copyWith(error: 'The tribute cannot be empty.');
      return;
    }
    final t = AncestorTribute(
      id: _newId(),
      ancestorName: name,
      tribute: body,
      createdAt: DateTime.now(),
      authorName: authorName?.trim().isEmpty == true ? null : authorName?.trim(),
    );
    state = state.copyWith(
      tributes: [...state.tributes, t],
      clearError: true,
    );
  }

  void editTribute(String id, {String? tribute, String? authorName}) {
    state = state.copyWith(
      tributes: [
        for (final t in state.tributes)
          if (t.id == id)
            t.copyWith(
              tribute: tribute?.trim().isEmpty == true ? t.tribute : tribute?.trim(),
              authorName: authorName?.trim().isEmpty == true
                  ? t.authorName
                  : authorName?.trim(),
            )
          else
            t,
      ],
    );
  }

  void removeTribute(String id) {
    state = state.copyWith(
      tributes: state.tributes.where((t) => t.id != id).toList(),
    );
  }

  void clearError() => state = state.copyWith(clearError: true);
}

final ancestorTributeProvider =
    StateNotifierProvider<AncestorTributeNotifier, AncestorTributeState>(
  (ref) => AncestorTributeNotifier(),
);
