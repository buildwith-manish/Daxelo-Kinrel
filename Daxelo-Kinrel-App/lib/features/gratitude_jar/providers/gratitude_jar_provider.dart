// lib/features/gratitude_jar/providers/gratitude_jar_provider.dart
//
// P9.2a — Gratitude jar (local-only, NO streak).
//
// A simple, private place to drop short notes of gratitude for family
// members. Notes live only on this device (no sync, no server write in
// this minimal provider). There is deliberately NO streak counter, NO
// "you haven't added a note in N days" nudge, and NO daily-required
// framing — gratitude that is pressured stops being gratitude.
//
// Constitution / Copy-Audit: no guilt language, no manufactured
// urgency, no engagement metrics.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class GratitudeNote {
  const GratitudeNote({
    required this.id,
    required this.text,
    required this.createdAt,
    this.recipientName,
  });

  final String id;
  final String text;
  final DateTime createdAt;
  /// Optional: who the note is for. May be null for "the family".
  final String? recipientName;

  GratitudeNote copyWith({
    String? id,
    String? text,
    DateTime? createdAt,
    String? recipientName,
    bool clearRecipient = false,
  }) {
    return GratitudeNote(
      id: id ?? this.id,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      recipientName:
          clearRecipient ? null : (recipientName ?? this.recipientName),
    );
  }
}

@immutable
class GratitudeJarState {
  const GratitudeJarState({
    this.notes = const [],
    this.isSaving = false,
    this.error,
  });

  final List<GratitudeNote> notes;
  final bool isSaving;
  final String? error;

  /// Most-recent-first view for the UI. Does not mutate storage order.
  List<GratitudeNote> get chronological =>
      List<GratitudeNote>.of(notes)..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  GratitudeJarState copyWith({
    List<GratitudeNote>? notes,
    bool? isSaving,
    String? error,
    bool clearError = false,
  }) {
    return GratitudeJarState(
      notes: notes ?? this.notes,
      isSaving: isSaving ?? this.isSaving,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class GratitudeJarNotifier extends StateNotifier<GratitudeJarState> {
  GratitudeJarNotifier() : super(const GratitudeJarState());

  int _counter = 0;
  String _newId() => 'local-${DateTime.now().millisecondsSinceEpoch}-${_counter++}';

  /// Adds a note. Trims and rejects empty text with a clear, neutral
  /// error — no "you must be grateful every day" framing.
  void addNote(String text, {String? recipientName}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      state = state.copyWith(error: 'Note cannot be empty.', clearError: false);
      return;
    }
    final note = GratitudeNote(
      id: _newId(),
      text: trimmed,
      createdAt: DateTime.now(),
      recipientName: recipientName?.trim().isEmpty == true
          ? null
          : recipientName?.trim(),
    );
    state = state.copyWith(
      notes: [...state.notes, note],
      clearError: true,
    );
  }

  /// Edits an existing note's text in place.
  void editNote(String id, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    state = state.copyWith(
      notes: [
        for (final n in state.notes)
          if (n.id == id) n.copyWith(text: trimmed) else n,
      ],
    );
  }

  void removeNote(String id) {
    state = state.copyWith(notes: state.notes.where((n) => n.id != id).toList());
  }

  void clearError() => state = state.copyWith(clearError: true);
}

final gratitudeJarProvider =
    StateNotifierProvider<GratitudeJarNotifier, GratitudeJarState>(
  (ref) => GratitudeJarNotifier(),
);
