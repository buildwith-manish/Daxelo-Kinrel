// lib/features/shared_list/shared_list_provider.dart
//
// DAXELO KINREL — Shared List / Errand Board
//
// Collaborative checklist for groceries, chores, "someone pick up X".
// The unglamorous thing every family WhatsApp group actually uses daily.
// Uses Supabase 'SharedList' + 'SharedListItem' tables (created via migration).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/supabase_service.dart';

class SharedList {
  final String id;
  final String familyId;
  final String title;
  final String? emoji;
  final DateTime createdAt;
  final String createdBy;

  SharedList({
    required this.id,
    required this.familyId,
    required this.title,
    this.emoji,
    required this.createdAt,
    required this.createdBy,
  });

  factory SharedList.fromMap(Map<String, dynamic> m) => SharedList(
    id: m['id'] as String,
    familyId: m['familyId'] as String,
    title: m['title'] as String,
    emoji: m['emoji'] as String?,
    createdAt: DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now(),
    createdBy: m['createdBy'] as String,
  );
}

class SharedListItem {
  final String id;
  final String listId;
  final String text;
  final bool isDone;
  final String? doneBy;
  final DateTime createdAt;

  SharedListItem({
    required this.id,
    required this.listId,
    required this.text,
    required this.isDone,
    this.doneBy,
    required this.createdAt,
  });

  factory SharedListItem.fromMap(Map<String, dynamic> m) => SharedListItem(
    id: m['id'] as String,
    listId: m['listId'] as String,
    text: m['text'] as String,
    isDone: m['isDone'] as bool? ?? false,
    doneBy: m['doneBy'] as String?,
    createdAt: DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now(),
  );
}

/// All shared lists for a family.
final sharedListsProvider =
    FutureProvider.family<List<SharedList>, String>(
  (ref, familyId) async {
    final client = ref.read(supabaseProvider);
    if (client == null) return [];
    try {
      final result = await client
          .from('SharedList')
          .select()
          .eq('familyId', familyId)
          .order('createdAt', ascending: false);
      return result.map((e) => SharedList.fromMap(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  },
);

/// Items for a specific shared list.
final sharedListItemsProvider =
    FutureProvider.family<List<SharedListItem>, String>(
  (ref, listId) async {
    final client = ref.read(supabaseProvider);
    if (client == null) return [];
    try {
      final result = await client
          .from('SharedListItem')
          .select()
          .eq('listId', listId)
          .order('createdAt', ascending: true);
      return result.map((e) => SharedListItem.fromMap(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  },
);

class SharedListNotifier {
  final WidgetRef _ref;
  SharedListNotifier(this._ref);

  Future<void> createList(String familyId, String title, {String? emoji}) async {
    final client = _ref.read(supabaseProvider);
    if (client == null) return;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await client.from('SharedList').insert({
        'familyId': familyId,
        'title': title,
        'emoji': emoji ?? '📋',
        'createdBy': userId,
      });
      _ref.invalidate(sharedListsProvider(familyId));
    } catch (_) {}
  }

  Future<void> addItem(String familyId, String listId, String text) async {
    final client = _ref.read(supabaseProvider);
    if (client == null) return;
    try {
      await client.from('SharedListItem').insert({
        'listId': listId,
        'text': text,
        'isDone': false,
      });
      _ref.invalidate(sharedListItemsProvider(listId));
      _ref.invalidate(sharedListsProvider(familyId));
    } catch (_) {}
  }

  Future<void> toggleItem(String familyId, String listId, String itemId, bool currentDone) async {
    final client = _ref.read(supabaseProvider);
    if (client == null) return;
    final userId = client.auth.currentUser?.id;
    try {
      await client.from('SharedListItem').update({
        'isDone': !currentDone,
        'doneBy': !currentDone ? userId : null,
      }).eq('id', itemId);
      _ref.invalidate(sharedListItemsProvider(listId));
    } catch (_) {}
  }

  Future<void> deleteItem(String familyId, String listId, String itemId) async {
    final client = _ref.read(supabaseProvider);
    if (client == null) return;
    try {
      await client.from('SharedListItem').delete().eq('id', itemId);
      _ref.invalidate(sharedListItemsProvider(listId));
    } catch (_) {}
  }

  Future<void> deleteList(String familyId, String listId) async {
    final client = _ref.read(supabaseProvider);
    if (client == null) return;
    try {
      await client.from('SharedListItem').delete().eq('listId', listId);
      await client.from('SharedList').delete().eq('id', listId);
      _ref.invalidate(sharedListsProvider(familyId));
    } catch (_) {}
  }
}
