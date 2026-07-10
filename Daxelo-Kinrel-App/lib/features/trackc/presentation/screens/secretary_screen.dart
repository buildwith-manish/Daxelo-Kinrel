// =============================================================================
// Track C v2.0 — Kinrel Secretary Screen
// =============================================================================
// Browse meeting artifacts. Draft → Reviewed → Published lifecycle.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/trackc_providers.dart';

class TrackcSecretaryScreen extends ConsumerWidget {
  const TrackcSecretaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final familyId = ref.watch(selectedFamilyIdProvider);
    final api = ref.watch(trackcApiClientProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Kinrel Secretary')),
      body: FutureBuilder<List<dynamic>>(
        future: familyId == null ? null : api.listArtifacts(familyId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Failed: ${snapshot.error}'));
          }
          final artifacts = snapshot.data ?? [];
          if (artifacts.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.description, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  const Text('No meeting artifacts yet'),
                  const SizedBox(height: 8),
                  Text(
                    'Create one to auto-generate draft minutes with AI.',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: artifacts.length,
            itemBuilder: (context, i) {
              final a = artifacts[i] as Map<String, dynamic>;
              return _ArtifactCard(artifact: a, api: api, familyId: familyId!);
            },
          );
        },
      ),
      floatingActionButton: familyId == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showCreateDialog(context, ref, familyId, api),
              icon: const Icon(Icons.add),
              label: const Text('New meeting'),
            ),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref, String familyId, dynamic api) {
    // Simplified — production would have a full form
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Meeting creation form — see secretary_create_screen.dart')),
    );
  }
}

class _ArtifactCard extends StatelessWidget {
  const _ArtifactCard({required this.artifact, required this.api, required this.familyId});

  final Map<String, dynamic> artifact;
  final dynamic api;
  final String familyId;

  @override
  Widget build(BuildContext context) {
    final title = artifact['title'] as String? ?? '';
    final heldAt = artifact['heldAt'] as String?;
    final status = artifact['status'] as String? ?? 'draft';
    final actionItems = (artifact['actionItems'] as List? ?? []);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Row(
          children: [
            Text(_formatDate(heldAt), style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const SizedBox(width: 8),
            _StatusChip(status: status),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (actionItems.isNotEmpty) ...[
                  const Text('Action Items', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 4),
                  for (final ai in actionItems.cast<Map<String, dynamic>>())
                    Padding(
                      padding: const EdgeInsets.only(left: 8, bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('☐ '),
                          Expanded(
                            child: Text(
                              '${ai['text'] ?? ''} (${ai['assigneeRole'] ?? 'all'}, due in ${ai['dueOffsetDays'] ?? 7}d)',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
                if (status == 'draft' || status == 'reviewed')
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonal(
                      onPressed: () => _publish(context),
                      child: const Text('Publish'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return '${d.day}/${d.month}/${d.year}';
  }

  Future<void> _publish(BuildContext context) async {
    try {
      await api.publishArtifact(familyId, artifact['id'] as String);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Artifact published')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Publish failed: $e')),
        );
      }
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final colors = {
      'draft': Colors.grey,
      'reviewed': Colors.orange,
      'published': Colors.green,
    };
    final color = colors[status] ?? Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }
}
