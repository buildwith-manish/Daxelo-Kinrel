// lib/features/family/presentation/family_activity_screen.dart
//
// Extracted from FamilyDetailScreen's _ActivityTab — full-screen
// activity feed showing relationships created and members added.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/family/family_provider.dart';
import '../../../shared/widgets/dk_components.dart';

class FamilyActivityScreen extends ConsumerWidget {
  const FamilyActivityScreen({super.key, required this.familyId});
  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(familyDetailProvider(familyId));

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Activity',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
      ),
      body: detailAsync.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: KinrelColors.orange),
        ),
        error: (e, _) => DKErrorState(
          message: '$e',
          onRetry: () => ref.invalidate(familyDetailProvider(familyId)),
        ),
        data: (detail) {
          if (detail == null) {
            return const Center(child: Text('Family not found'));
          }

          final activities = <_ActivityItem>[];

          for (final rel in detail.relationships) {
            final fromPerson = detail.members
                .where((p) => p.id == rel.fromPersonId)
                .firstOrNull;
            final toPerson = detail.members
                .where((p) => p.id == rel.toPersonId)
                .firstOrNull;
            activities.add(_ActivityItem(
              type: _ActivityType.link,
              description:
                  '${fromPerson?.name ?? "Someone"} added ${toPerson?.name ?? "a family member"} as ${rel.relationshipKey.replaceAll("_", " ")}',
              timestamp: rel.createdAt,
            ));
          }

          for (final member in detail.members) {
            activities.add(_ActivityItem(
              type: _ActivityType.memberAdded,
              description: '${member.name} joined the family',
              timestamp: member.createdAt,
            ));
          }

          activities.sort((a, b) {
            if (a.timestamp == null && b.timestamp == null) return 0;
            if (a.timestamp == null) return 1;
            if (b.timestamp == null) return -1;
            return b.timestamp!.compareTo(a.timestamp!);
          });

          if (activities.isEmpty) {
            return DKEmptyState(
              icon: Icons.history_rounded,
              title: 'No Activity Yet',
              subtitle:
                  'Activity will appear here as you add\nmembers and create relationships.',
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(KinrelSpacing.base),
            itemCount: activities.length,
            itemBuilder: (context, index) {
              final activity = activities[index];
              return Container(
                margin: const EdgeInsets.only(bottom: KinrelSpacing.sm),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: KinrelColors.darkCard,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: activity.type == _ActivityType.link
                            ? KinrelColors.orange
                                .withValues(alpha: 0.15)
                            : KinrelColors.purple
                                .withValues(alpha: 0.15),
                      ),
                      child: Icon(
                        activity.type == _ActivityType.link
                            ? Icons.link_rounded
                            : Icons.person_add_alt_1_rounded,
                        color: activity.type == _ActivityType.link
                            ? KinrelColors.orange
                            : KinrelColors.purple,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            activity.description,
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 14,
                              color: KinrelColors.textWhite,
                            ),
                          ),
                          if (activity.timestamp != null)
                            Text(
                              _formatTime(activity.timestamp!),
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 11,
                                color: KinrelColors.textDim,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }
}

enum _ActivityType { link, memberAdded }

class _ActivityItem {
  const _ActivityItem({
    required this.type,
    required this.description,
    this.timestamp,
  });
  final _ActivityType type;
  final String description;
  final DateTime? timestamp;
}
