// lib/features/presence/presentation/presence_widget.dart
//
// Compact presence row for the family hub. Shows all family members'
// current status as colored avatar dots. Tapping opens a status picker.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../presence_provider.dart';
import '../../../core/constants/brand_colors.dart';

class PresenceRow extends ConsumerWidget {
  const PresenceRow({super.key, required this.familyId});
  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presenceAsync = ref.watch(familyPresenceProvider(familyId));
    final myStatus = ref.watch(myPresenceProvider);
    final theme = Theme.of(context);

    return presenceAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (members) {
        if (members.isEmpty) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              // My status toggle
              GestureDetector(
                onTap: () => _showStatusPicker(context, ref),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Color(myStatus.colorValue).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Color(myStatus.colorValue), width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(myStatus.emoji, style: const TextStyle(fontSize: 12)),
                      const SizedBox(width: 4),
                      Text(
                        myStatus.label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Color(myStatus.colorValue),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Family members presence dots
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: members.take(10).map((m) {
                      final color = Color(m.status.colorValue);
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Tooltip(
                          message: '${m.displayName ?? 'Member'} — ${m.status.label}',
                          child: Stack(
                            children: [
                              CircleAvatar(
                                radius: 12,
                                backgroundColor: color.withOpacity(0.2),
                                backgroundImage: m.avatarUrl != null && m.avatarUrl!.isNotEmpty
                                    ? NetworkImage(m.avatarUrl!)
                                    : null,
                                child: (m.avatarUrl == null || m.avatarUrl!.isEmpty)
                                    ? Text(
                                        (m.displayName ?? '?')[0].toUpperCase(),
                                        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
                                      )
                                    : null,
                              ),
                              Positioned(
                                right: 0, bottom: 0,
                                child: Container(
                                  width: 8, height: 8,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: theme.colorScheme.surface, width: 1.5),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showStatusPicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Set your status', style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            ),
            ...PresenceStatus.values.map((s) => ListTile(
              leading: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: Color(s.colorValue).withOpacity(0.15), shape: BoxShape.circle),
                child: Center(child: Text(s.emoji, style: const TextStyle(fontSize: 16))),
              ),
              title: Text(s.label),
              trailing: ref.read(myPresenceProvider) == s
                  ? Icon(Icons.check, color: Color(s.colorValue))
                  : null,
              onTap: () {
                ref.read(myPresenceProvider.notifier).update(s);
                Navigator.pop(ctx);
              },
            )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
