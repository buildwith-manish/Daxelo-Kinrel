// =============================================================================
// Track C v2.0 — AURA Governance Hub Screen
// =============================================================================
// Main entry screen for Track C features. Provides navigation to:
//   - Constitution
//   - Decisions
//   - Timeline
//   - AURA Learning profile
//   - AURA Analytics
//   - AURA Search
//   - AURA Secretary
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/trackc_providers.dart';
import 'constitution_screen.dart';
import 'decisions_list_screen.dart';
import 'timeline_screen.dart';
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
        title: const Text('AURA Governance'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search',
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
                            Text('AURA Governance Engine',
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

          // Feature grid
          Text('Governance', style: theme.textTheme.titleSmall?.copyWith(color: Colors.grey[700])),
          const SizedBox(height: 8),
          _FeatureCard(
            icon: Icons.gavel,
            title: 'Constitution',
            subtitle: 'Family rules + amendments',
            color: const Color(0xFF2D8A4E),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const TrackcConstitutionScreen())),
          ),
          _FeatureCard(
            icon: Icons.how_to_vote,
            title: 'Decisions',
            subtitle: 'Active + past decisions',
            color: const Color(0xFF1E88E5),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const TrackcDecisionsListScreen())),
          ),
          _FeatureCard(
            icon: Icons.history_edu,
            title: 'AURA Timeline',
            subtitle: 'Append-only family history',
            color: const Color(0xFF8E24AA),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const TrackcTimelineScreen())),
          ),

          const SizedBox(height: 24),
          Text('Intelligence', style: theme.textTheme.titleSmall?.copyWith(color: Colors.grey[700])),
          const SizedBox(height: 8),
          _FeatureCard(
            icon: Icons.insights,
            title: 'AURA Learning',
            subtitle: 'Adaptive profile + reset',
            color: const Color(0xFFD81B60),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const TrackcLearningProfileScreen())),
          ),
          _FeatureCard(
            icon: Icons.bar_chart,
            title: 'AURA Analytics',
            subtitle: 'Private family insights',
            color: const Color(0xFFF4511E),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const TrackcAnalyticsScreen())),
          ),
          _FeatureCard(
            icon: Icons.description,
            title: 'AURA Secretary',
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
