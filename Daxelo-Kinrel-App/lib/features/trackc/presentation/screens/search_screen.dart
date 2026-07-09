// =============================================================================
// Track C v2.0 — AURA Search Screen
// =============================================================================
// Universal cross-entity search with offline-capable banner.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/trackc_providers.dart';
import '../../../core/widgets/offline_banner.dart';

class TrackcSearchScreen extends ConsumerStatefulWidget {
  const TrackcSearchScreen({super.key});

  @override
  ConsumerState<TrackcSearchScreen> createState() => _TrackcSearchScreenState();
}

class _TrackcSearchScreenState extends ConsumerState<TrackcSearchScreen> {
  final _controller = TextEditingController();
  bool _showOffline = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resultsAsync = ref.watch(searchResultsProvider);
    final query = ref.watch(searchQueryProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search decisions, constitution, timeline…',
            border: InputBorder.none,
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) {
            ref.read(searchQueryProvider.notifier).state = v;
            setState(() => _showOffline = false);
          },
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _controller.clear();
                ref.read(searchQueryProvider.notifier).state = '';
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // Offline banner (shown when search fails — would be cached results)
          if (_showOffline)
            const OfflineBanner(),

          Expanded(
            child: query.trim().isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text('Search across constitution, decisions, memory, and timeline',
                            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                            textAlign: TextAlign.center),
                      ],
                    ),
                  )
                : resultsAsync.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) {
                      // On error, mark as offline — the local Drift mirror would be searched here
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _showOffline = true);
                      });
                      return _OfflineResults(query: query);
                    },
                    data: (result) {
                      if (result == null) return const SizedBox.shrink();
                      final items = (result['items'] as List? ?? []).cast<Map<String, dynamic>>();
                      final count = result['count'] as int? ?? items.length;
                      if (items.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text('No results for "$query"'),
                            ],
                          ),
                        );
                      }
                      return ListView(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text('$count results for "$query"',
                                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
                          ),
                          ...items.map((item) => _SearchResultTile(item: item)),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final entityType = item['entityType'] as String? ?? '';
    final title = item['title'] as String? ?? '';
    final body = item['body'] as String? ?? '';
    final (icon, color) = _entityVisual(entityType);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(body, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(_entityLabel(entityType),
              style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  (IconData, Color) _entityVisual(String type) {
    return {
      'decision': (Icons.how_to_vote, Colors.blue),
      'memory': (Icons.psychology, Colors.purple),
      'timeline_event': (Icons.history, Colors.amber),
      'constitution_article': (Icons.article, Colors.green),
      'constitution_clause': (Icons.rule, Colors.teal),
      'meeting_artifact': (Icons.description, Colors.deepOrange),
    }[type] ?? (Icons.help_outline, Colors.grey);
  }

  String _entityLabel(String type) {
    return type.split('_').map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
  }
}

class _OfflineResults extends StatelessWidget {
  const _OfflineResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    // In production, this would query the local Drift SearchIndex mirror.
    // For now, show a placeholder.
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('You\'re offline', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Search results will be served from the local cache when available.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}
