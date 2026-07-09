// =============================================================================
// Track C v2.0 — AURA Timeline Screen
// =============================================================================
// Append-only family history. Filter by kind. Tap for detail + corrections.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/trackc_providers.dart';

class TrackcTimelineScreen extends ConsumerStatefulWidget {
  const TrackcTimelineScreen({super.key});

  @override
  ConsumerState<TrackcTimelineScreen> createState() => _TrackcTimelineScreenState();
}

class _TrackcTimelineScreenState extends ConsumerState<TrackcTimelineScreen> {
  String? _filterKind;

  static const _kinds = <String?>[
    null,
    'constitution_created',
    'constitution_amended',
    'decision_created',
    'decision_voted',
    'decision_resolved',
    'decision_expired',
    'decision_lifecycle_changed',
    'member_joined',
    'member_left',
    'meeting_artifact_published',
    'learning_profile_reset',
    'correction',
  ];

  @override
  Widget build(BuildContext context) {
    final timelineAsync = ref.watch(timelineProvider(_filterKind));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AURA Timeline'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Export',
            onPressed: () => _export(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter chips
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: _kinds.map((kind) {
                final selected = _filterKind == kind;
                final label = kind == null ? 'All' : _kindLabel(kind);
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(label),
                    selected: selected,
                    onSelected: (_) => setState(() => _filterKind = kind),
                  ),
                );
              }).toList(),
            ),
          ),
          // Timeline list
          Expanded(
            child: timelineAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Failed to load: $e')),
              data: (events) {
                if (events.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history_edu, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        const Text('No timeline events yet'),
                        const SizedBox(height: 8),
                        Text(
                          'Governance events will appear here as your family uses AURA.',
                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: events.length,
                  itemBuilder: (context, i) {
                    final e = events[i];
                    return _TimelineTile(event: e);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _kindLabel(String kind) {
    return kind.split('_').map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
  }

  Future<void> _export(BuildContext context) async {
    final familyId = ref.read(selectedFamilyIdProvider);
    if (familyId == null) return;
    final api = ref.read(trackcApiClientProvider);
    try {
      final html = await api.exportTimelineHtml(familyId, year: DateTime.now().year);
      if (context.mounted) {
        // For simplicity, show a snackbar; in production, open in WebView or print
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Timeline HTML ready (${html.length} chars). Print from web view.'),
            action: SnackBarAction(label: 'OK', onPressed: () {}),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({required this.event});

  final Map<String, dynamic> event;

  @override
  Widget build(BuildContext context) {
    final kind = event['kind'] as String? ?? '';
    final title = event['title'] as String? ?? '';
    final description = event['description'] as String?;
    final occurredAt = event['occurredAt'] as String?;
    final actorId = event['actorId'] as String?;

    final (icon, color) = _kindVisual(kind);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: Colors.grey[300],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                        ),
                        Text(
                          _formatRelative(occurredAt),
                          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                    if (description != null && description!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(description, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                    ],
                    if (actorId != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'by ${actorId.length > 8 ? '${actorId.substring(0, 8)}…' : actorId}',
                        style: TextStyle(fontSize: 11, color: Colors.grey[500], fontStyle: FontStyle.italic),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  (IconData, Color) _kindVisual(String kind) {
    return {
      'constitution_created': (Icons.gavel, Colors.green),
      'constitution_amended': (Icons.edit, Colors.orange),
      'constitution_version_published': (Icons.publish, Colors.green),
      'decision_created': (Icons.add_circle, Colors.blue),
      'decision_voted': (Icons.how_to_vote, Colors.indigo),
      'decision_resolved': (Icons.check_circle, Colors.teal),
      'decision_expired': (Icons.timer_off, Colors.grey),
      'decision_lifecycle_changed': (Icons.update, Colors.purple),
      'member_joined': (Icons.person_add, Colors.blue),
      'member_left': (Icons.person_remove, Colors.red),
      'role_changed': (Icons.swap_horiz, Colors.amber),
      'meeting_artifact_published': (Icons.description, Colors.deepOrange),
      'learning_profile_reset': (Icons.refresh, Colors.pink),
      'correction': (Icons.edit_note, Colors.brown),
    }[kind] ?? (Icons.circle, Colors.grey);
  }

  String _formatRelative(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso);
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${d.day}/${d.month}/${d.year}';
  }
}
