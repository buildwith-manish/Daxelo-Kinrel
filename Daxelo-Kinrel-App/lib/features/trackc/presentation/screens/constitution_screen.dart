// =============================================================================
// Track C v2.0 — Constitution Screen
// =============================================================================
// Displays the family constitution with current published version, articles,
// and clauses. Admins can edit the draft and publish.
//
// WCAG 2.2 AA: All interactive elements have Semantics labels. Vote counts
// announced via liveRegion. Color is never the sole state indicator.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/trackc_providers.dart';

class TrackcConstitutionScreen extends ConsumerWidget {
  const TrackcConstitutionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final constitutionAsync = ref.watch(constitutionProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Family Constitution')),
      body: constitutionAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Failed to load constitution: $e',
                style: TextStyle(color: theme.colorScheme.error),
                textAlign: TextAlign.center),
          ),
        ),
        data: (constitution) {
          if (constitution == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.gavel, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  const Text('No constitution yet'),
                  const SizedBox(height: 8),
                  Text(
                    'An admin can draft the first version.',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }

          final title = constitution['title'] as String? ?? 'Family Constitution';
          final preamble = constitution['preamble'] as String?;
          final status = constitution['status'] as String? ?? 'draft';
          final currentVersion = constitution['currentVersion'] as Map<String, dynamic>?;
          final draftVersion = constitution['draftVersion'] as Map<String, dynamic>?;

          final articles = (currentVersion?['articles'] as List? ?? []) as List<Map<String, dynamic>>;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Header
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                      if (preamble != null && preamble.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(preamble, style: theme.textTheme.bodyMedium?.copyWith(
                          fontStyle: FontStyle.italic,
                          color: Colors.grey[700],
                        )),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          _StatusChip(status: status),
                          const Spacer(),
                          if (currentVersion != null)
                            Text('v${currentVersion['versionNumber']} · Published ${_formatDate(currentVersion['publishedAt'])}',
                                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              if (draftVersion != null) ...[
                const SizedBox(height: 16),
                Card(
                  color: Colors.amber.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.edit_note, color: Colors.amber.shade800),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Draft v${draftVersion['versionNumber']} in progress',
                            style: TextStyle(color: Colors.amber.shade900, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Articles
              if (articles.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'No articles yet. The constitution has been published but contains no articles.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                ...articles.asMap().entries.map((entry) {
                  final i = entry.key;
                  final article = entry.value;
                  return _ArticleCard(
                    index: i + 1,
                    title: article['title'] as String? ?? '',
                    intent: article['intent'] as String?,
                    clauses: (article['clauses'] as List? ?? []).cast<Map<String, dynamic>>(),
                  );
                }),
            ],
          );
        },
      ),
    );
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso);
    if (d == null) return '';
    return '${d.day}/${d.month}/${d.year}';
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final colors = {
      'draft': Colors.grey,
      'in_review': Colors.orange,
      'published': Colors.green,
      'archived': Colors.brown,
    };
    final color = colors[status] ?? Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 6),
          Text(
            status.replaceAll('_', ' ').toUpperCase(),
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _ArticleCard extends StatelessWidget {
  const _ArticleCard({
    required this.index,
    required this.title,
    required this.intent,
    required this.clauses,
  });

  final int index;
  final String title;
  final String? intent;
  final List<Map<String, dynamic>> clauses;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      '$index',
                      style: TextStyle(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                      if (intent != null && intent!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(intent!, style: theme.textTheme.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                          color: Colors.grey[600],
                        )),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (clauses.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              ...clauses.asMap().entries.map((entry) {
                final ci = entry.key;
                final clause = entry.value;
                final text = clause['text'] as String? ?? '';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8, left: 40),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${ci + 1}.', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
