// lib/features/shared_list/presentation/shared_list_screen.dart
//
// DAXELO KINREL — Shared List / Errand Board Screen
//
// Collaborative checklist for groceries, chores, "someone pick up X".

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../shared_list_provider.dart';
import '../../family/presentation/family_space_floating_nav.dart';

class SharedListScreen extends ConsumerStatefulWidget {
  const SharedListScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<SharedListScreen> createState() => _SharedListScreenState();
}

class _SharedListScreenState extends ConsumerState<SharedListScreen> {
  final _newListController = TextEditingController();
  final _newItemControllers = <String, TextEditingController>{};

  @override
  void dispose() {
    _newListController.dispose();
    for (final c in _newItemControllers.values) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listsAsync = ref.watch(sharedListsProvider(widget.familyId));
    final theme = Theme.of(context);
    final notifier = SharedListNotifier(ref);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lists & Errands'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/family/${widget.familyId}');
            }
          },
        ),
      ),
      // Phase 27: extend body behind the floating dock so it floats.
      extendBody: true,
      bottomNavigationBar: FamilySpaceFloatingNav(familyId: widget.familyId),
      // Bug fix (FAB overlap): the global FAB theme previously forced
      // `shape: CircleBorder()` which clipped the extended FAB's icon +
      // label into a circle, causing overlap. That's fixed in the theme
      // (app_theme.dart). Here we also add explicit `icon` + `label`
      // with a sized gap and `isExtended: true` so the button is always
      // a pill shape with proper spacing, even on narrow split-screen
      // viewports where the FAB has limited horizontal room.
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateListDialog(notifier),
        icon: const Icon(Icons.add, size: 22),
        label: const Text(
          'New List',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        // Ensures the FAB stays a pill (stadium) shape regardless of
        // any inherited theme overrides. This is belt-and-suspenders
        // with the theme fix — the theme removes the global CircleBorder,
        // and this explicitly sets the extended FAB's shape.
        shape: const StadiumBorder(),
        // Material 3 extended FABs have a built-in 16px gap between
        // icon and label. We don't override it — the default spacing
        // is correct for all screen sizes (phone, tablet, web, split).
      ),
      body: listsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (lists) {
          if (lists.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.checklist_rounded, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  const Text('No lists yet'),
                  const SizedBox(height: 8),
                  Text('Create a grocery list, chore board, or errand list.',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: lists.length,
            itemBuilder: (context, i) => _ListCard(
              list: lists[i],
              familyId: widget.familyId,
              notifier: notifier,
              itemController: _newItemControllers.putIfAbsent(lists[i].id, () => TextEditingController()),
            ),
          );
        },
      ),
    );
  }

  void _showCreateListDialog(SharedListNotifier notifier) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New List'),
        content: TextField(
          controller: _newListController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g., Groceries, Chores, Pick up package',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (_newListController.text.trim().isNotEmpty) {
                await notifier.createList(widget.familyId, _newListController.text.trim());
                _newListController.clear();
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

class _ListCard extends ConsumerWidget {
  const _ListCard({
    required this.list,
    required this.familyId,
    required this.notifier,
    required this.itemController,
  });

  final SharedList list;
  final String familyId;
  final SharedListNotifier notifier;
  final TextEditingController itemController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(sharedListItemsProvider(list.id));
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Row(
          children: [
            Text(list.emoji ?? '📋', style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Expanded(child: Text(list.title, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
        subtitle: itemsAsync.whenOrNull(
          data: (items) {
            final done = items.where((i) => i.isDone).length;
            return Text('$done/${items.length} done', style: TextStyle(fontSize: 11, color: Colors.grey[600]));
          },
        ),
        children: [
          itemsAsync.when(
            loading: () => const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()),
            error: (_, __) => const ListTile(title: Text('Failed to load items')),
            data: (items) => Column(
              children: [
                ...items.map((item) => ListTile(
                  dense: true,
                  leading: Checkbox(
                    value: item.isDone,
                    onChanged: (_) => notifier.toggleItem(familyId, list.id, item.id, item.isDone),
                  ),
                  title: Text(
                    item.text,
                    style: TextStyle(
                      decoration: item.isDone ? TextDecoration.lineThrough : null,
                      color: item.isDone ? Colors.grey : null,
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => notifier.deleteItem(familyId, list.id, item.id),
                  ),
                )),
                // Add item row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: itemController,
                          decoration: const InputDecoration(
                            hintText: 'Add item...',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (text) async {
                            if (text.trim().isNotEmpty) {
                              await notifier.addItem(familyId, list.id, text.trim());
                              itemController.clear();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.add_circle),
                        onPressed: () async {
                          if (itemController.text.trim().isNotEmpty) {
                            await notifier.addItem(familyId, list.id, itemController.text.trim());
                            itemController.clear();
                          }
                        },
                      ),
                    ],
                  ),
                ),
                if (items.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, bottom: 4),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => notifier.deleteList(familyId, list.id),
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: const Text('Delete list', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
