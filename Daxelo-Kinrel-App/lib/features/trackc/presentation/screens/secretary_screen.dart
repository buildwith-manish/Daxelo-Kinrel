// =============================================================================
// Track C v2.0 — Kinrel Secretary Screen
// =============================================================================
// Browse meeting artifacts. Draft → Reviewed → Published lifecycle.
//
// CONSOLIDATION: This screen now supports an `embedded` mode for use as a
// tab inside the Decisions screen. When embedded=true, it renders without
// its own Scaffold/AppBar (the parent Decisions screen provides the chrome).
// When embedded=false (standalone), it renders a full Scaffold.
// =============================================================================

import 'package:flutter/material.dart';
import '../../../../core/constants/brand_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/trackc_providers.dart';

class TrackcSecretaryScreen extends ConsumerWidget {
  const TrackcSecretaryScreen({super.key, this.embedded = false});

  /// When true, renders as a tab content (no Scaffold/AppBar).
  /// When false, renders as a standalone screen with its own Scaffold.
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final familyId = ref.watch(selectedFamilyIdProvider);
    final api = ref.watch(trackcApiClientProvider);
    final theme = Theme.of(context);

    final body = FutureBuilder<List<dynamic>>(
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
                const Text('No meeting minutes yet'),
                const SizedBox(height: 8),
                Text(
                  'Tap "New meeting" to auto-generate draft minutes with AI.',
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
    );

    // In embedded mode, render as a plain widget (no Scaffold).
    // The parent Decisions screen provides the FAB and AppBar.
    if (embedded) {
      return body;
    }

    // Standalone mode: full Scaffold with AppBar + FAB
    return Scaffold(
      backgroundColor: KinrelColors.darkBackground,
      appBar: AppBar(title: const Text('Meeting Minutes')),
      body: body,
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
            Icon(Icons.circle, size: 8, color: _statusColor(status)),
            const SizedBox(width: 6),
            Text(_statusLabel(status), style: TextStyle(fontSize: 12, color: _statusColor(status))),
            if (heldAt != null) ...[
              const SizedBox(width: 12),
              Icon(Icons.calendar_today, size: 12, color: Colors.grey[500]),
              const SizedBox(width: 4),
              Text(
                _formatDate(heldAt),
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (actionItems.isNotEmpty) ...[
                  Text('Action Items', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  ...actionItems.map((item) {
                    final map = item as Map<String, dynamic>;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.check_circle_outline, size: 16, color: Colors.grey[500]),
                          const SizedBox(width: 8),
                          Expanded(child: Text(map['text'] as String? ?? '')),
                        ],
                      ),
                    );
                  }),
                ],
                if (artifact['draftMinutesMd'] != null &&
                    (artifact['draftMinutesMd'] as String).isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('Draft Minutes', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      artifact['draftMinutesMd'] as String,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return '${d.day}/${d.month}/${d.year}';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'published':
        return Colors.green;
      case 'reviewed':
        return Colors.blue;
      case 'draft':
      default:
        return Colors.orange;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'published':
        return 'Published';
      case 'reviewed':
        return 'Reviewed';
      case 'draft':
      default:
        return 'Draft';
    }
  }
}
