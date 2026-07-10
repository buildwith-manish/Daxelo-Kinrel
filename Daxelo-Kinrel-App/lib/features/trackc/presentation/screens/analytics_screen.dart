// =============================================================================
// Track C v2.0 — Kinrel Analytics Screen
// =============================================================================
// Private family insights. NO leaderboards, NO cross-family comparisons.
//
// CONSOLIDATION: This screen now supports an `embedded` mode for use as a
// tab inside the Decisions screen. When embedded=true, it renders without
// its own Scaffold/AppBar (the parent Decisions screen provides the chrome).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/trackc_providers.dart';

class TrackcAnalyticsScreen extends ConsumerWidget {
  const TrackcAnalyticsScreen({super.key, this.embedded = false});

  /// When true, renders as a tab content (no Scaffold/AppBar).
  /// When false, renders as a standalone screen with its own Scaffold.
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(analyticsSummaryProvider);
    final theme = Theme.of(context);

    final body = summaryAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Failed to load: $e')),
      data: (summary) {
        if (summary == null) {
          return const Center(child: Text('No analytics available'));
        }

        final current = (summary['current'] as Map?)?.cast<String, dynamic>() ?? {};
        final metrics = (current['metrics'] as Map?)?.cast<String, dynamic>() ?? {};
        final anomalies = (current['anomalies'] as List? ?? []).cast<Map<String, dynamic>>();
        final trend = (summary['trend'] as Map?)?.cast<String, dynamic>();

        final decisionsCreated = metrics['decisionsCreated'] as int? ?? 0;
        final decisionsResolved = metrics['decisionsResolved'] as int? ?? 0;
        final decisionsExpired = metrics['decisionsExpired'] as int? ?? 0;
        final participationRate = (metrics['participationRate'] as num?)?.toDouble() ?? 0;
        final quorumMetRate = (metrics['quorumMetRate'] as num?)?.toDouble() ?? 0;
        final avgDurationHours = (metrics['avgDurationHours'] as num?)?.toDouble() ?? 0;
        final timelineEventCount = metrics['timelineEventCount'] as int? ?? 0;
        final meetingArtifactCount = metrics['meetingArtifactCount'] as int? ?? 0;
        final periodStart = current['periodStart'] as String?;
        final periodEnd = current['periodEnd'] as String?;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Period
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.date_range, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_formatDate(periodStart)} – ${_formatDate(periodEnd)}',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          Text('Weekly', style: TextStyle(color: Colors.grey[600])),
                        ],
                      ),
                    ),
                  ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Anomalies
              if (anomalies.isNotEmpty) ...[
                for (final a in anomalies)
                  Card(
                    color: _anomalyColor(a['severity'] as String? ?? 'low').withOpacity(0.1),
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(Icons.warning,
                          color: _anomalyColor(a['severity'] as String? ?? 'low')),
                      title: Text(a['kind'] as String? ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(a['message'] as String? ?? ''),
                    ),
                  ),
                const SizedBox(height: 16),
              ],

              // KPI grid
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1.5,
                children: [
                  _KpiCard(
                    label: 'Decisions Created',
                    value: '$decisionsCreated',
                    icon: Icons.add_circle,
                    color: Colors.blue,
                    trend: _trendDelta(trend?['decisionsCreated']),
                  ),
                  _KpiCard(
                    label: 'Decisions Resolved',
                    value: '$decisionsResolved',
                    icon: Icons.check_circle,
                    color: Colors.green,
                    trend: _trendDelta(trend?['decisionsResolved']),
                  ),
                  _KpiCard(
                    label: 'Participation Rate',
                    value: '${(participationRate * 100).round()}%',
                    icon: Icons.people,
                    color: Colors.purple,
                    trend: _trendDelta(trend?['participationRate']),
                  ),
                  _KpiCard(
                    label: 'Quorum Met Rate',
                    value: '${(quorumMetRate * 100).round()}%',
                    icon: Icons.how_to_vote,
                    color: Colors.teal,
                    trend: _trendDelta(trend?['quorumMetRate']),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Additional metrics
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Additional Metrics',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(height: 12),
                      _StatRow(label: 'Avg Decision Duration', value: '${avgDurationHours.toStringAsFixed(1)}h'),
                      _StatRow(label: 'Decisions Expired', value: '$decisionsExpired'),
                      _StatRow(label: 'Timeline Events', value: '$timelineEventCount'),
                      _StatRow(label: 'Meeting Artifacts', value: '$meetingArtifactCount'),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Privacy notice
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock, color: Colors.green.shade700, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Analytics are private to your family. No leaderboards. No cross-family comparisons.',
                        style: TextStyle(color: Colors.green.shade900, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    // In embedded mode, return the body directly (no Scaffold/AppBar).
    // The parent Decisions screen provides the chrome.
    if (embedded) {
      return body;
    }

    // Standalone mode: wrap in a Scaffold
    return Scaffold(
      appBar: AppBar(title: const Text('Trends')),
      body: body,
    );
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return '${d.day}/${d.month}';
  }

  Color _anomalyColor(String severity) {
    switch (severity) {
      case 'high': return Colors.red;
      case 'medium': return Colors.orange;
      default: return Colors.amber;
    }
  }

  String? _trendDelta(dynamic trendEntry) {
    if (trendEntry == null) return null;
    final delta = (trendEntry as Map?)?['delta'];
    if (delta == null) return null;
    final d = (delta as num).toDouble();
    final sign = d > 0 ? '+' : '';
    return '$sign${d.toStringAsFixed(1)}';
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.trend,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? trend;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(label,
                      style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(value,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
                if (trend != null) ...[
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      trend!,
                      style: TextStyle(
                        fontSize: 11,
                        color: trend!.startsWith('+') ? Colors.green : Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[700], fontSize: 13)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}
