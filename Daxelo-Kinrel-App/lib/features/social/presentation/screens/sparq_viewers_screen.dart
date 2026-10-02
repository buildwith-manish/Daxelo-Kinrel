import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../data/providers/sparq_provider.dart';

class SparqViewersScreen extends ConsumerWidget {
  const SparqViewersScreen({super.key, required this.sparqId});
  final String sparqId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewersAsync = ref.watch(sparqViewersProvider(sparqId));

    return Scaffold(
      backgroundColor: KinrelColors.darkBackground,
      appBar: AppBar(
        backgroundColor: KinrelColors.darkBackground,
        title: const Text('Viewers', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600)),
      ),
      body: viewersAsync.when(
        data: (viewers) {
          if (viewers.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.visibility_off, size: 48, color: KinrelColors.textDim),
                  SizedBox(height: 12),
                  Text('No viewers yet', style: TextStyle(color: KinrelColors.textSilver, fontSize: 16)),
                  SizedBox(height: 4),
                  Text('Viewers will appear here', style: TextStyle(color: KinrelColors.textDim, fontSize: 13)),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: viewers.length,
            separatorBuilder: (_, __) => const Divider(color: KinrelColors.elevation1),
            itemBuilder: (context, index) {
              final viewer = viewers[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: viewer['avatarUrl'] != null
                      ? NetworkImage(viewer['avatarUrl'] as String)
                      : null,
                  backgroundColor: KinrelColors.elevation2,
                  child: viewer['avatarUrl'] == null
                      ? const Icon(Icons.person, color: KinrelColors.textSilver)
                      : null,
                ),
                title: Text(
                  viewer['name'] as String? ?? 'Unknown',
                  style: const TextStyle(color: KinrelColors.textWhite, fontFamily: 'DM Sans'),
                ),
                trailing: Text(
                  _timeAgo(viewer['viewedAt'] as String?),
                  style: const TextStyle(color: KinrelColors.textDim, fontSize: 12),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: KinrelColors.orange)),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: KinrelColors.error),
              const SizedBox(height: 12),
              const Text('Failed to load viewers', style: TextStyle(color: KinrelColors.textSilver)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => ref.invalidate(sparqViewersProvider(sparqId)),
                style: ElevatedButton.styleFrom(backgroundColor: KinrelColors.orange),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _timeAgo(String? timestamp) {
    if (timestamp == null) return '';
    try {
      final dt = DateTime.parse(timestamp);
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inHours < 1) return '${diff.inMinutes}m ago';
      if (diff.inDays < 1) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return '';
    }
  }
}
