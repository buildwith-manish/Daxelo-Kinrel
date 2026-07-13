// lib/features/family_values/providers/family_values_provider.dart
//
// P9.2b — Family values manifesto.
//
// A short, editable list of values a family agrees to live by. This is
// a drafting surface, not a published contract (Track C governs the
// formal Family Constitution). Values here are intentionally lightweight
// and private to the family in this minimal provider.
//
// Constitution / Copy-Audit: neutral copy. No "live up to your values
// today" nudges, no compliance scoring, no streaks.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class FamilyValue {
  const FamilyValue({
    required this.id,
    required this.title,
    required this.description,
    required this.addedAt,
    this.orderIndex = 0,
  });

  final String id;
  final String title;
  final String description;
  final DateTime addedAt;
  final int orderIndex;

  FamilyValue copyWith({
    String? id,
    String? title,
    String? description,
    DateTime? addedAt,
    int? orderIndex,
  }) {
    return FamilyValue(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      addedAt: addedAt ?? this.addedAt,
      orderIndex: orderIndex ?? this.orderIndex,
    );
  }
}

@immutable
class FamilyValuesState {
  const FamilyValuesState({
    this.values = const [],
    this.isEditing = false,
    this.error,
  });

  final List<FamilyValue> values;
  final bool isEditing;
  final String? error;

  /// Values in their declared order.
  List<FamilyValue> get ordered =>
      List<FamilyValue>.of(values)..sort((a, b) {
        final byOrder = a.orderIndex.compareTo(b.orderIndex);
        if (byOrder != 0) return byOrder;
        return a.addedAt.compareTo(b.addedAt);
      });

  FamilyValuesState copyWith({
    List<FamilyValue>? values,
    bool? isEditing,
    String? error,
    bool clearError = false,
  }) {
    return FamilyValuesState(
      values: values ?? this.values,
      isEditing: isEditing ?? this.isEditing,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class FamilyValuesNotifier extends StateNotifier<FamilyValuesState> {
  FamilyValuesNotifier() : super(const FamilyValuesState());

  int _counter = 0;
  String _newId() => 'value-${DateTime.now().millisecondsSinceEpoch}-${_counter++}';

  /// Adds a value. Rejects empty titles with a neutral message.
  void addValue(String title, String description) {
    final t = title.trim();
    if (t.isEmpty) {
      state = state.copyWith(error: 'A value needs a short title.');
      return;
    }
    final value = FamilyValue(
      id: _newId(),
      title: t,
      description: description.trim(),
      addedAt: DateTime.now(),
      orderIndex: state.values.length,
    );
    state = state.copyWith(values: [...state.values, value], clearError: true);
  }

  void editValue(String id, {String? title, String? description}) {
    state = state.copyWith(
      values: [
        for (final v in state.values)
          if (v.id == id)
            v.copyWith(
              title: title?.trim().isEmpty == true ? v.title : title?.trim(),
              description: description?.trim() ?? v.description,
            )
          else
            v,
      ],
    );
  }

  void removeValue(String id) {
    state = state.copyWith(values: state.values.where((v) => v.id != id).toList());
  }

  /// Reorders by [oldIndex] → [newIndex] semantics used by ReorderableListView.
  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.values.length) return;
    final list = List<FamilyValue>.of(state.ordered);
    final adjusted = newIndex > oldIndex ? newIndex - 1 : newIndex;
    final item = list.removeAt(oldIndex);
    list.insert(adjusted.clamp(0, list.length), item);
    final renumbered = [
      for (var i = 0; i < list.length; i++) list[i].copyWith(orderIndex: i),
    ];
    state = state.copyWith(values: renumbered);
  }

  void beginEdit() => state = state.copyWith(isEditing: true);
  void endEdit() => state = state.copyWith(isEditing: false);
  void clearError() => state = state.copyWith(clearError: true);
}

final familyValuesProvider =
    StateNotifierProvider<FamilyValuesNotifier, FamilyValuesState>(
  (ref) => FamilyValuesNotifier(),
);
