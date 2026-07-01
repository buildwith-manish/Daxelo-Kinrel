import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_typography.dart';
import '../../../core/family/family_provider.dart';
import '../../../graph/widgets/family_graph_engine_view.dart';

class FamilyTreeScreen extends ConsumerStatefulWidget {
  const FamilyTreeScreen({super.key, this.familyId});
  final String? familyId;

  @override
  ConsumerState<FamilyTreeScreen> createState() => _FamilyTreeScreenState();
}

class _FamilyTreeScreenState extends ConsumerState<FamilyTreeScreen> {
  @override
  Widget build(BuildContext context) {
    final familyId = widget.familyId;
    final detailAsync = familyId != null
        ? ref.watch(familyDetailProvider(familyId))
        : null;

    if (familyId == null) {
      final familiesAsync = ref.watch(familyListProvider);
      return Scaffold(
        backgroundColor: const Color(0xFF0A0E1A),
        body: familiesAsync.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: Color(0xFF4FC3F7))),
          error: (e, _) => const Center(
              child: Text('Error loading families',
                  style: TextStyle(color: Colors.white70))),
          data: (families) {
            if (families.isEmpty) {
              return const Center(
                child: Text('No families yet.\nCreate or join a family first.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 16)),
              );
            }
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                context.go('/family-tree?familyId=${families.first.id}');
              }
            });
            return const Center(
                child: CircularProgressIndicator(color: Color(0xFF4FC3F7)));
          },
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: detailAsync == null
          ? const Center(
              child: Text('Loading...',
                  style: TextStyle(color: Colors.white70)))
          : detailAsync.when(
              loading: () => const Center(
                  child:
                      CircularProgressIndicator(color: Color(0xFF4FC3F7))),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: Colors.white54),
                      const SizedBox(height: 12),
                      const Text('Failed to load family tree',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 16)),
                      const SizedBox(height: 8),
                      Text(e.toString(),
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 12),
                          textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
              data: (detail) {
                if (detail == null) {
                  return const Center(
                      child: Text('Family not found',
                          style: TextStyle(color: Colors.white70)));
                }
                return _buildTreeContent(detail);
              },
            ),
    );
  }

  Widget _buildTreeContent(FamilyDetail detail) {
    return FamilyGraphEngineView(
      familyId: detail.family.id,
    );
  }
}
