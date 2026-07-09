// =============================================================================
// Track C v2.0 — AURA Learning Profile Screen
// =============================================================================
// Shows what the Learning Engine has learned about the family, with a reset
// button (admin-only). Section 9.5 transparency commitment.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/trackc_providers.dart';

class TrackcLearningProfileScreen extends ConsumerWidget {
  const TrackcLearningProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(learningProfileProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AURA Learning'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reset profile',
            onPressed: () => _showResetDialog(context, ref),
          ),
        ],
      ),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (profile) {
          if (profile == null) {
            return const Center(child: Text('No profile yet'));
          }

          final confidence = (profile['confidenceScore'] as num?)?.toDouble() ?? 0;
          final sampleSize = profile['sampleSize'] as int? ?? 0;
          final usingDefaults = profile['usingDefaults'] as bool? ?? true;
          final version = profile['version'] as int? ?? 0;
          final reminderLeads = (profile['preferredReminderLeadHours'] as Map?)?.cast<String, dynamic>() ?? {};
          final weekdayDist = (profile['preferredWeekdayDistribution'] as Map?)?.cast<String, dynamic>() ?? {};
          final todBuckets = (profile['preferredTimeOfDayBuckets'] as Map?)?.cast<String, dynamic>() ?? {};
          final acceptRates = (profile['insightAcceptRateByKind'] as Map?)?.cast<String, dynamic>() ?? {};
          final elderThreshold = (profile['elderAutoIncludeThreshold'] as num?)?.toDouble() ?? 0.6;
          final avgDuration = (profile['averageDecisionDurationHours'] as num?)?.toDouble();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Confidence card
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            usingDefaults ? Icons.info_outline : Icons.check_circle,
                            color: usingDefaults ? Colors.orange : Colors.green,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              usingDefaults
                                  ? 'Using global defaults'
                                  : 'Personalized for your family',
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text('Confidence Score', style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: confidence,
                        minHeight: 12,
                        backgroundColor: Colors.grey[200],
                        color: _confidenceColor(confidence),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${(confidence * 100).round()}% (v$version, $sampleSize signals)',
                        style: theme.textTheme.bodySmall,
                      ),
                      if (usingDefaults) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'AURA is still learning your family\'s patterns. Personalization kicks in after 30 signals.',
                            style: TextStyle(color: Colors.orange.shade900, fontSize: 13),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Reminder lead preferences
              _SectionCard(
                title: 'Reminder Timing',
                icon: Icons.notifications,
                children: [
                  for (final entry in reminderLeads.entries)
                    _StatRow(
                      label: _capitalize(entry.key),
                      value: '${entry.value}h before',
                    ),
                ],
              ),

              const SizedBox(height: 12),

              // Weekday distribution
              _SectionCard(
                title: 'Preferred Weekdays',
                icon: Icons.calendar_today,
                children: [
                  for (final day in ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'])
                    _BarRow(
                      label: _capitalize(day),
                      value: (weekdayDist[day] as num?)?.toDouble() ?? 0,
                    ),
                ],
              ),

              const SizedBox(height: 12),

              // Time of day buckets
              _SectionCard(
                title: 'Preferred Times of Day',
                icon: Icons.access_time,
                children: [
                  for (final bucket in ['morning', 'afternoon', 'evening', 'night'])
                    _BarRow(
                      label: _capitalize(bucket),
                      value: (todBuckets[bucket] as num?)?.toDouble() ?? 0,
                    ),
                ],
              ),

              const SizedBox(height: 12),

              // Insight accept rates
              if (acceptRates.isNotEmpty)
                _SectionCard(
                  title: 'AI Insight Acceptance Rates',
                  icon: Icons.lightbulb,
                  children: [
                    for (final entry in acceptRates.entries)
                      _BarRow(
                        label: _humanKind(entry.key),
                        value: (entry.value as num?)?.toDouble() ?? 0,
                      ),
                  ],
                ),

              const SizedBox(height: 12),

              // Misc stats
              _SectionCard(
                title: 'Decision Patterns',
                icon: Icons.trending_up,
                children: [
                  _StatRow(
                    label: 'Elder Auto-Include Threshold',
                    value: '${(elderThreshold * 100).round()}%',
                  ),
                  if (avgDuration != null)
                    _StatRow(
                      label: 'Average Decision Duration',
                      value: '${avgDuration.toStringAsFixed(1)}h',
                    ),
                ],
              ),

              const SizedBox(height: 24),

              // Privacy notice
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lock, color: Colors.blue.shade700, size: 18),
                        const SizedBox(width: 8),
                        Text('Privacy', style: theme.textTheme.titleSmall?.copyWith(color: Colors.blue.shade900)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'AURA Learning stores only pseudonymous shapes — never raw text or PII. '
                      'Every signal is a count, duration, or day-of-week bucket. '
                      'Reset returns to defaults; previous versions retained 90 days for audit.',
                      style: TextStyle(color: Colors.blue.shade900, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Color _confidenceColor(double c) {
    if (c < 0.4) return Colors.orange;
    if (c < 0.7) return Colors.amber;
    return Colors.green;
  }

  String _capitalize(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  String _humanKind(String kind) {
    return kind.split('_').map(_capitalize).join(' ');
  }

  void _showResetDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Learning Profile?'),
        content: const Text(
          'This will clear all learned patterns and return to global defaults. '
          'The reset is logged to the timeline. Previous profile versions are retained '
          'server-side for 90 days.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              final familyId = ref.read(selectedFamilyIdProvider);
              if (familyId == null) return;
              final api = ref.read(trackcApiClientProvider);
              try {
                await api.resetLearningProfile(familyId);
                ref.invalidate(learningProfileProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Learning profile reset')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Reset failed: $e')),
                  );
                }
              }
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.icon, required this.children});

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
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

class _BarRow extends StatelessWidget {
  const _BarRow({required this.label, required this.value});

  final String label;
  final double value; // 0..1

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(color: Colors.grey[700], fontSize: 13)),
              Text('${(value * 100).round()}%',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: value,
            minHeight: 6,
            backgroundColor: Colors.grey[200],
          ),
        ],
      ),
    );
  }
}
