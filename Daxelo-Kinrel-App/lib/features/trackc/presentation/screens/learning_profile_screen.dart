// =============================================================================
// Track C v2.0 — AURA Learning Profile Screen
// =============================================================================
// Shows what the Learning Engine has learned about the family, with a reset
// button (admin-only). Section 9.5 transparency commitment.
//
// VISIBILITY MATRIX:
//   - Admins (owner/admin): see the full raw behavior profile + reset button.
//   - Non-admins (member/elder/viewer, including minors): see a plain-language
//     summary sentence only (via the /learning/profile/summary endpoint).
//     The raw profile fields (reminder action rates, weekday distribution,
//     elder auto-include threshold, insight accept rates) are NOT shown.
//     The reset button is HIDDEN (admin-only).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/trackc_providers.dart';
import '../providers/trackc_visibility.dart';

class TrackcLearningProfileScreen extends ConsumerWidget {
  const TrackcLearningProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // VISIBILITY MATRIX: admin sees raw profile + reset button; non-admin sees summary
    final familyId = ref.watch(selectedFamilyIdProvider) ?? '';
    final caps = ref.watch(trackcCapabilitiesProvider(familyId));

    if (caps.isAdmin) {
      return _AdminLearningProfileScreen(
        familyId: familyId,
        caps: caps,
      );
    }
    return _MemberLearningSummaryScreen(familyId: familyId);
  }
}

/// Admin view: full raw behavior profile + reset button.
class _AdminLearningProfileScreen extends ConsumerWidget {
  const _AdminLearningProfileScreen({required this.familyId, required this.caps});

  final String familyId;
  final TrackcCapabilities caps;

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

// =============================================================================
// Member view: plain-language summary (no raw profile fields, no reset button)
// =============================================================================

/// Fetches the profile summary from the /learning/profile/summary endpoint.
final _profileSummaryProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, familyId) async {
  try {
    final api = ref.watch(trackcApiClientProvider);
    return await api.getLearningProfileSummary(familyId);
  } catch (_) {
    return null;
  }
});

class _MemberLearningSummaryScreen extends ConsumerWidget {
  const _MemberLearningSummaryScreen({required this.familyId});

  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(_profileSummaryProvider(familyId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AURA Learning'),
        // No reset button for non-admins
      ),
      body: summaryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not load learning summary.\n$e',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (data) {
          if (data == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Kinrel is still gathering data about your family\'s governance patterns.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final summary = data['summary'] as String? ??
              'Kinrel is still learning your family\'s rhythms.';
          final confidence = (data['confidenceScore'] as num?)?.toDouble() ?? 0;
          final sampleSize = data['sampleSize'] as int? ?? 0;
          final usingDefaults = data['usingDefaults'] as bool? ?? true;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Summary card — the plain-language sentence
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.lightbulb_outline,
                              size: 28, color: theme.colorScheme.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'What Kinrel has learned',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        summary,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Transparency card — safe aggregate metrics only
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: 18, color: theme.colorScheme.outline),
                          const SizedBox(width: 8),
                          Text(
                            'Transparency',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Kinrel has observed $sampleSize governance interactions from your family.',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 4),
                      if (usingDefaults)
                        Text(
                          'Your family is still in the learning phase — patterns shown above use global defaults.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        )
                      else
                        Text(
                          'Confidence: ${(confidence * 100).round()}%',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Privacy note
              Card(
                color: theme.colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.shield_outlined,
                          size: 18, color: theme.colorScheme.outline),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Detailed behavioral data is only visible to family admins. '
                          'This summary uses plain language to protect everyone\'s privacy.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
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
