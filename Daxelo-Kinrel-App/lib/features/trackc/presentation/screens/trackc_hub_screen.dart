// =============================================================================
// Track C v2.0 — Kinrel Governance Hub Screen
// =============================================================================
// Main entry screen for Kinrel Governance features.
//
// CONSOLIDATED from 6 tiles → 3 based on how users think about governance:
//   1. Constitution — the family's rules (read occasionally, link to Decisions)
//   2. Decisions — the primary "act" screen (voting + meeting minutes +
//      analytics trends live here as tabs)
//   3. Timeline — passive browsing/audit of governance history
//
// What moved:
//   - Kinrel Learning → Settings → Privacy & Data (it's invisible infra,
//     needs a transparency/reset screen but doesn't compete for governance nav)
//   - Kinrel Analytics → folded into Decisions as a "Trends" tab (it's trend
//     data ABOUT decisions — quorum decline, dormancy)
//   - Kinrel Secretary → folded into Decisions as an "Add Minutes" action
//     (a meeting's minutes are the artifact OF a decision session)
//   - Kinrel Search → stays as an AppBar icon (already correct)
//   - Kinrel Intelligence → backend-only (no UI tile, correct as-is)
//
// Backend modules are NOT touched — every NestJS module stays separate.
// This is purely a UI navigation consolidation.
// =============================================================================

import 'package:flutter/material.dart';
import '../../../../core/constants/brand_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/trackc_providers.dart';
import 'search_screen.dart';

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
      backgroundColor: KinrelColors.darkBackground,
      appBar: AppBar(
        title: const Text('Governance'),
        actions: [
          // Search stays as an icon — already correctly placed
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search governance records',
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
              child: Row(
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
                        Text('Family Governance',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(
                          'Rules · Decisions · History',
                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── 3 governance tiles ─────────────────────────────────────
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
            subtitle: 'Vote, meeting minutes & analytics trends',
            color: const Color(0xFF1E88E5),
            onTap: () => context.pushNamed(
              'trackc-decisions',
              pathParameters: {'id': widget.familyId},
            ),
          ),
          _FeatureCard(
            icon: Icons.history_edu,
            title: 'Timeline',
            subtitle: 'Append-only family history',
            color: const Color(0xFF8E24AA),
            onTap: () => context.pushNamed(
              'trackc-timeline',
              pathParameters: {'id': widget.familyId},
            ),
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
