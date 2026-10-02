// lib/features/family/presentation/family_activity_screen.dart
//
// Extracted from FamilyDetailScreen's _ActivityTab — full-screen
// activity feed showing relationships created and members added.
//
// Phase (family-state-aware-home-screen): rows now use the shared
// PersonAvatar widget + bold-name + action + relative-timestamp
// pattern, matching the home-screen Family Pulse preview so the two
// surfaces read as one consistent activity feed.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/widgets/person_avatar.dart';
import '../../../shared/widgets/dk_components.dart';
import 'package:go_router/go_router.dart';

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
          onPressed: () { if (context.canPop()) { context.pop(); } else { context.go('/home'); } },
        ),
        title: const Text(
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
        loading: () => const Center(
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
              actorName: fromPerson?.name ?? 'Someone',
              actorPhotoUrl: fromPerson?.photoUrl,
              action: 'added ${toPerson?.name ?? "a family member"} as '
                  '${rel.relationshipKey.replaceAll("_", " ")}',
              timestamp: rel.createdAt,
            ));
          }

          for (final member in detail.members) {
            activities.add(_ActivityItem(
              type: _ActivityType.memberAdded,
              actorName: member.name,
              actorPhotoUrl: member.photoUrl,
              action: 'joined the family',
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
                    // Phase (family-state-aware-home-screen): avatar
                    // replaces the prior colored icon container, matching
                    // the home-screen Family Pulse preview's scannable
                    // avatar + bold-name + action + timestamp pattern.
                    PersonAvatar(
                      name: activity.actorName,
                      photoUrl: activity.actorPhotoUrl,
                      size: 36,
                      borderColor: activity.type == _ActivityType.link
                          ? KinrelColors.orange.withValues(alpha: 0.35)
                          : KinrelColors.purple.withValues(alpha: 0.35),
                      borderWidth: 1,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RichText(
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            text: TextSpan(
                              style: const TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 14,
                                color: KinrelColors.textSilver,
                                height: 1.3,
                              ),
                              children: [
                                TextSpan(
                                  text: activity.actorName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: KinrelColors.textWhite,
                                  ),
                                ),
                                const TextSpan(text: ' '),
                                TextSpan(text: activity.action),
                              ],
                            ),
                          ),
                          if (activity.timestamp != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              _formatTime(activity.timestamp!),
                              style: const TextStyle(
                                fontFamily: KinrelTypography.monoFont,
                                fontSize: 11,
                                color: KinrelColors.textDim,
                              ),
                            ),
                          ],
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
    required this.actorName,
    required this.actorPhotoUrl,
    required this.action,
    this.timestamp,
  });
  final _ActivityType type;
  final String actorName;
  final String? actorPhotoUrl;
  final String action;
  final DateTime? timestamp;
}
