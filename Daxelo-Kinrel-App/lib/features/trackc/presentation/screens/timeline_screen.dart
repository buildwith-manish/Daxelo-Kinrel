// =============================================================================
// Track C v2.0 — Kinrel Timeline Screen
// =============================================================================
// Append-only family history. Filter by kind. Tap for detail + corrections.
//
// VISIBILITY MATRIX:
//   - Default (all roles): shows the summary whitelist feed only
//     (decision_created, decision_resolved, constitution_amended, etc.).
//     The kind filter chips are limited to summary kinds.
//   - Admins (owner/admin): see a "Show raw log" toggle that switches to
//     the full unfiltered append-only log (?raw=true). Non-admins never
//     see this toggle.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/trackc_providers.dart';
import '../providers/trackc_visibility.dart';

class TrackcTimelineScreen extends ConsumerStatefulWidget {
  const TrackcTimelineScreen({super.key});

  @override
  ConsumerState<TrackcTimelineScreen> createState() => _TrackcTimelineScreenState();
}

class _TrackcTimelineScreenState extends ConsumerState<TrackcTimelineScreen> {
  String? _filterKind;
  bool _showRaw = false; // admin-only toggle for the full unfiltered log

  // Summary event types — these are the only kinds visible to non-admins.
  // Must match TIMELINE_SUMMARY_EVENT_TYPES on the server.
  static const _summaryKinds = <String>[
    'decision_created',
    'decision_resolved',
    'constitution_amended',
    'constitution_version_published',
    'constitution_created',
    'meeting_artifact_published',
  ];

  // All event types — only shown in the filter when raw mode is on (admin).
  static const _allKinds = <String?>[
    null,
    'constitution_created',
    'constitution_amended',
    'constitution_version_published',
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
    final familyId = ref.watch(selectedFamilyIdProvider) ?? '';
    final caps = ref.watch(trackcCapabilitiesProvider(familyId));

    // Non-admins always use summary mode (raw is server-blocked anyway)
    final effectiveRaw = _showRaw && caps.isAdmin;

    final timelineAsync = ref.watch(timelineProvider(_filterKind));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kinrel Timeline'),
        actions: [
          // "Show raw log" toggle — admin-only
          if (caps.isAdmin)
            IconButton(
              icon: Icon(effectiveRaw ? Icons.visibility : Icons.visibility_off),
              tooltip: effectiveRaw ? 'Showing raw log (all events)' : 'Show raw log (admin)',
              onPressed: () => setState(() => _showRaw = !effectiveRaw),
            ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Export',
            onPressed: () => _export(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // Mode banner
          if (effectiveRaw)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: theme.colorScheme.errorContainer,
              child: Row(
                children: [
                  Icon(Icons.warning_amber, size: 16, color: theme.colorScheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Raw log mode — showing all events including granular details',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: theme.colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  Icon(Icons.summarize, size: 16, color: theme.colorScheme.outline),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Summary feed — key governance actions only',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // Filter chips — only summary kinds for non-admins, all kinds for admins in raw mode
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: (effectiveRaw ? _allKinds : _summaryKinds.cast<String?>()).map((kind) {
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
                          'Governance events will appear here as your family uses Kinrel.',
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

class _TimelineTile extends ConsumerWidget {
  const _TimelineTile({required this.event});

  final Map<String, dynamic> event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = event['kind'] as String? ?? '';
    final title = event['title'] as String? ?? '';
    final description = event['description'] as String?;
    final occurredAt = event['occurredAt'] as String?;
    final actorId = event['actorId'] as String?;
    final eventId = event['id'] as String?;

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
              child: InkWell(
                onTap: eventId == null
                    ? null
                    : () {
                        final familyId = ref.read(selectedFamilyIdProvider) ?? '';
                        context.pushNamed(
                          'trackc-timeline-event',
                          pathParameters: {
                            'id': familyId,
                            'eventId': eventId,
                          },
                        );
                      },
                borderRadius: BorderRadius.circular(12),
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

// =============================================================================
// TrackcTimelineEventDetailScreen — full view of a single timeline event.
// Deep-linkable via /family/:id/governance/timeline/:eventId.
// =============================================================================

class TrackcTimelineEventDetailScreen extends ConsumerWidget {
  const TrackcTimelineEventDetailScreen({super.key, required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final familyId = ref.watch(selectedFamilyIdProvider);
    final timelineAsync = ref.watch(timelineProvider(null));

    return Scaffold(
      appBar: AppBar(title: const Text('Event Detail')),
      body: timelineAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (events) {
          final event = events.firstWhere(
            (e) => (e['id'] as String?) == eventId,
            orElse: () => <String, dynamic>{},
          );
          if (event.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.event_busy, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  const Text('Event not found'),
                  const SizedBox(height: 4),
                  Text(
                    familyId == null
                        ? 'No family context available.'
                        : 'This event may have been pruned. Reload the timeline.',
                    style: TextStyle(color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          final kind = event['kind'] as String? ?? '';
          final title = event['title'] as String? ?? '';
          final description = event['description'] as String?;
          final occurredAt = event['occurredAt'] as String?;
          final actorId = event['actorId'] as String?;
          final payload = event['payload'];

          final theme = Theme.of(context);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          kind.split('_').map((w) => w[0].toUpperCase() + w.substring(1)).join(' '),
                          style: TextStyle(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(title,
                          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                      if (description != null && description!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(description, style: theme.textTheme.bodyMedium),
                      ],
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                      if (occurredAt != null)
                        _DetailRow(label: 'Occurred', value: _formatFull(occurredAt)),
                      if (actorId != null)
                        _DetailRow(label: 'Actor', value: actorId),
                    ],
                  ),
                ),
              ),
              if (payload != null) ...[
                const SizedBox(height: 16),
                Text('Payload', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _prettyPrint(payload),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  String _formatFull(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return '${d.toLocal()}';
  }

  String _prettyPrint(dynamic obj) {
    try {
      // Treat the payload as a Map and pretty-print it
      if (obj is Map) {
        return obj.entries.map((e) => '${e.key}: ${e.value}').join('\n');
      }
      return obj.toString();
    } catch (_) {
      return obj.toString();
    }
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
