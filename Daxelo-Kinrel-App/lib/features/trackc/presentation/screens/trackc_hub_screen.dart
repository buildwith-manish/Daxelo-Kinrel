// =============================================================================
// Track C v2.0 — Kinrel Governance Hub Screen
// =============================================================================
// Main entry screen for Track C features. Provides navigation to:
//   - Constitution
//   - Decisions
//   - Timeline
//   - Kinrel Learning profile
//   - Kinrel Analytics
//   - Kinrel Search
//   - Kinrel Secretary
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/trackc_providers.dart';
import 'learning_profile_screen.dart';
import 'analytics_screen.dart';
import 'search_screen.dart';
import 'secretary_screen.dart';

class TrackcHubScreen extends ConsumerStatefulWidget {
  const TrackcHubScreen({super.key, required this.familyId});

  final String familyId;

  @override
  ConsumerState<TrackcHubScreen> createState() => _TrackcHubScreenState();
}

class _TrackcHubScreenState extends ConsumerState<TrackcHubScreen> {
  @override
  void initState() {
    super.initState();
    // Set the selected family for all providers
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(selectedFamilyIdProvider.notifier).state = widget.familyId;
    });
  }

  @override
  Widget build(BuildContext context) {
    final syncEngine = ref.watch(trackcSyncEngineProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kinrel Governance'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search',
            // Search has no deep-link route of its own yet — it's still a
            // push-on-stack detail screen. We use Navigator.push here so the
            // behavior matches what existed before; if/when a route is added,
            // switch to context.pushNamed('trackc-search').
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TrackcSearchScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Sync now',
            onPressed: syncEngine == null
                ? null
                : () async {
                    final ok = await syncEngine.fullSync();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(ok ? 'Sync complete' : 'Sync failed — will retry')),
                      );
                    }
                  },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Hero card
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFC8853A), Color(0xFF6B3FA0)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.auto_awesome, color: Colors.white, size: 32),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Kinrel Governance Engine',
                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(
                              'Constitution · Decisions · Timeline · AI',
                              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Feature grid — Governance section uses GoRouter sub-routes so the
          // system back button and deep links work correctly. Intelligence
          // sub-screens (Learning, Analytics, Secretary) keep Navigator.push
          // for now — they're leaf screens that don't need deep-link support
          // and don't yet have their own routes.
          Text('Governance', style: theme.textTheme.titleSmall?.copyWith(color: Colors.grey[700])),
          const SizedBox(height: 8),
          _FeatureCard(
            icon: Icons.gavel,
            title: 'Constitution',
            subtitle: 'Family rules + amendments',
            color: const Color(0xFF2D8A4E),
            onTap: () => context.pushNamed(
              'trackc-constitution',
              pathParameters: {'id': widget.familyId},
            ),
          ),
          _FeatureCard(
            icon: Icons.how_to_vote,
            title: 'Decisions',
            subtitle: 'Active + past decisions',
            color: const Color(0xFF1E88E5),
            onTap: () => context.pushNamed(
              'trackc-decisions',
              pathParameters: {'id': widget.familyId},
            ),
          ),
          _FeatureCard(
            icon: Icons.history_edu,
            title: 'Kinrel Timeline',
            subtitle: 'Append-only family history',
            color: const Color(0xFF8E24AA),
            onTap: () => context.pushNamed(
              'trackc-timeline',
              pathParameters: {'id': widget.familyId},
            ),
          ),

          const SizedBox(height: 24),
          Text('Intelligence', style: theme.textTheme.titleSmall?.copyWith(color: Colors.grey[700])),
          const SizedBox(height: 8),
          _FeatureCard(
            icon: Icons.insights,
            title: 'Kinrel Learning',
            subtitle: 'Adaptive profile + reset',
            color: const Color(0xFFD81B60),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const TrackcLearningProfileScreen())),
          ),
          _FeatureCard(
            icon: Icons.bar_chart,
            title: 'Kinrel Analytics',
            subtitle: 'Private family insights',
            color: const Color(0xFFF4511E),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const TrackcAnalyticsScreen())),
          ),
          _FeatureCard(
            icon: Icons.description,
            title: 'Kinrel Secretary',
            subtitle: 'Meeting minutes + action items',
            color: const Color(0xFF00897B),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const TrackcSecretaryScreen())),
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
