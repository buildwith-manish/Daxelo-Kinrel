// =============================================================================
// Track C v2.0 — Decisions List Screen
// =============================================================================
// Lists active and past decisions. Tap to view detail + vote.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/trackc_providers.dart';
import 'decision_create_screen.dart';

class TrackcDecisionsListScreen extends ConsumerStatefulWidget {
  const TrackcDecisionsListScreen({super.key});

  @override
  ConsumerState<TrackcDecisionsListScreen> createState() => _TrackcDecisionsListScreenState();
}

class _TrackcDecisionsListScreenState extends ConsumerState<TrackcDecisionsListScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Decisions'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Open', icon: Icon(Icons.how_to_vote)),
            Tab(text: 'Resolved', icon: Icon(Icons.task_alt)),
            Tab(text: 'All', icon: Icon(Icons.list)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _DecisionList(status: 'open'),
          _DecisionList(status: 'resolved'),
          _DecisionList(status: null),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          // Launch the multi-step create wizard. Returns true if a decision
          // was created, in which case we invalidate the providers so the
          // list refreshes.
          final created = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => const TrackcDecisionCreateScreen(),
              fullscreenDialog: true,
            ),
          );
          if (created == true) {
            ref.invalidate(decisionsProvider(null));
            ref.invalidate(decisionsProvider('open'));
            ref.invalidate(decisionsProvider('resolved'));
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('New decision'),
      ),
    );
  }
}

class _DecisionList extends ConsumerWidget {
  const _DecisionList({required this.status});

  final String? status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decisionsAsync = ref.watch(decisionsProvider(status));

    return decisionsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Failed to load: $e')),
      data: (decisions) {
        if (decisions.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.how_to_vote, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(status == null ? 'No decisions yet' : 'No $status decisions'),
                const SizedBox(height: 8),
                Text(
                  status == 'open' ? 'Create one to start voting.' : 'Decisions will appear here.',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: decisions.length,
          itemBuilder: (context, i) {
            final d = decisions[i];
            return _DecisionCard(
              decision: d,
              onTap: () {
                final familyId = ref.read(selectedFamilyIdProvider) ?? '';
                context.pushNamed(
                  'trackc-decision-detail',
                  pathParameters: {
                    'id': familyId,
                    'decisionId': d['id'] as String,
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _DecisionCard extends StatelessWidget {
  const _DecisionCard({required this.decision, required this.onTap});

  final Map<String, dynamic> decision;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = decision['type'] as String? ?? 'simple_vote';
    final status = decision['status'] as String? ?? 'open';
    final title = decision['title'] as String? ?? '';
    final description = decision['description'] as String?;
    final deadline = decision['deadlineAt'] as String?;
    final lifecycleState = decision['lifecycleState'] as String?;

    final typeLabel = {
      'simple_vote': 'Simple Vote',
      'consensus': 'Consensus',
      'elder_council': 'Elder Council',
      'constitution_amend': 'Constitution Amendment',
    }[type] ?? type;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(typeLabel,
                        style: TextStyle(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        )),
                  ),
                  const Spacer(),
                  _StatusBadge(status: status, lifecycleState: lifecycleState),
                ],
              ),
              const SizedBox(height: 12),
              Text(title,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              if (description != null && description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[700])),
              ],
              if (deadline != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.schedule, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(
                      'Deadline: ${_formatDateTime(deadline)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatDateTime(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    final now = DateTime.now();
    final diff = d.difference(now);
    if (diff.isNegative) return 'Expired';
    if (diff.inHours < 24) return 'in ${diff.inHours}h';
    return 'in ${diff.inDays}d';
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.lifecycleState});

  final String status;
  final String? lifecycleState;

  @override
  Widget build(BuildContext context) {
    final (color, label) = _statusColor(status, lifecycleState);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 8, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    );
  }

  (Color, String) _statusColor(String status, String? lifecycleState) {
    switch (status) {
      case 'open':
        return (Colors.blue, 'Open');
      case 'resolved':
        if (lifecycleState != null) {
          switch (lifecycleState) {
            case 'planned':
              return (Colors.indigo, 'Planned');
            case 'started':
              return (Colors.teal, 'Started');
            case 'in_progress':
              return (Colors.orange, 'In Progress');
            case 'completed':
              return (Colors.green, 'Completed');
            case 'cancelled':
              return (Colors.red, 'Cancelled');
            case 'expired':
              return (Colors.grey, 'Expired');
            case 'archived':
              return (Colors.brown, 'Archived');
          }
        }
        return (Colors.green, 'Resolved');
      case 'expired':
        return (Colors.grey, 'Expired');
      case 'cancelled':
        return (Colors.red, 'Cancelled');
      default:
        return (Colors.grey, status);
    }
  }
}
