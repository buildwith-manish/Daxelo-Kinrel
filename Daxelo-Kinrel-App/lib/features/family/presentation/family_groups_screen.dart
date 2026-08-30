// lib/features/family/presentation/family_groups_screen.dart
//
// DAXELO KINREL — Family Space Groups Section (v137)
//
// Displays all groups within a Family Space as premium cards.
// Groups are child entities of the Family Space — they inherit its
// identity (same accent color, atmosphere, branding).
//
// Navigation: Family Space → Groups Section → Group Hub → Group Chat
//
// Tapping a group navigates to the Group Hub (not the chat directly),
// mirroring the Family Hub pattern.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../shared/widgets/dk_components.dart';
import '../data/group_provider.dart';
import 'family_space_floating_nav.dart';

class FamilyGroupsScreen extends ConsumerWidget {
  const FamilyGroupsScreen({super.key, required this.familyId});

  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(familyGroupsProvider(familyId));

    return DKScaffold(
      backgroundColor: const Color(0xFF0A0B16),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new,
              size: 18, color: KinrelColors.textSilver),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/family/$familyId');
            }
          },
        ),
        title: Text(
          'Groups',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: KinrelColors.textWhite,
            letterSpacing: 0.3,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.add_rounded, color: KinrelColors.ember, size: 24),
            onPressed: () =>
                context.push('/family/$familyId/groups/create'),
          ),
        ],
      ),
      bottomNavigationBar:
          FamilySpaceFloatingNav(familyId: familyId),
      body: groupsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: KinrelColors.orange),
        ),
        error: (e, _) => Center(
          child: Text(
            'Could not load groups',
            style: TextStyle(color: KinrelColors.textDim),
          ),
        ),
        data: (groups) {
          if (groups.isEmpty) {
            return _EmptyGroupsState(
              familyId: familyId,
              onCreate: () =>
                  context.push('/family/$familyId/groups/create'),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            itemCount: groups.length,
            itemBuilder: (ctx, i) {
              return _GroupCard(
                group: groups[i],
                onTap: () => context.push('/family/$familyId/groups/${groups[i].id}/hub'),
              );
            },
          );
        },
      ),
    );
  }
}

// ── Empty State ──────────────────────────────────────────────────────────

class _EmptyGroupsState extends StatelessWidget {
  const _EmptyGroupsState({
    required this.familyId,
    required this.onCreate,
  });

  final String familyId;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Large premium icon with ember glow
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KinrelColors.ember.withValues(alpha: 0.08),
                border: Border.all(
                  color: KinrelColors.ember.withValues(alpha: 0.25),
                  width: 1.2,
                ),
              ),
              child: Icon(
                Icons.groups_2_rounded,
                size: 36,
                color: KinrelColors.ember,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No Groups Yet',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textWhite,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create sub-groups within your family for cousins, parents, siblings, events, and more.',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: KinrelColors.textSilver.withValues(alpha: 0.70),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            // Create button
            GestureDetector(
              onTap: onCreate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  gradient: KinrelGradients.igniteGradient,
                  borderRadius: BorderRadius.circular(100),
                  boxShadow: [
                    BoxShadow(
                      color: KinrelColors.ember.withValues(alpha: 0.30),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, size: 18, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(
                      'Create Group',
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Group Card ───────────────────────────────────────────────────────────

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, required this.onTap});

  final FamilyGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final timeAgo = _formatTimeAgo(group.lastActivityAt);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF1A1D2E),
              const Color(0xFF14162A),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.06),
            width: 0.75,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.20),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Group avatar with type-colored ring
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: group.groupType.color.withValues(alpha: 0.45),
                  width: 1.5,
                ),
              ),
              child: ClipOval(
                child: group.avatarUrl != null && group.avatarUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: group.avatarUrl!,
                        fit: BoxFit.cover,
                        width: 54,
                        height: 54,
                        placeholder: (_, __) => _GroupInitials(group: group),
                        errorWidget: (_, __, ___) => _GroupInitials(group: group),
                      )
                    : _GroupInitials(group: group),
              ),
            ),
            const SizedBox(width: 14),
            // Group info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Group type icon
                      Icon(group.groupType.icon,
                          size: 13, color: group.groupType.color),
                      const SizedBox(width: 5),
                      // Group type label
                      Text(
                        group.groupType.label,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: group.groupType.color.withValues(alpha: 0.90),
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    group.name,
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.textWhite,
                      letterSpacing: 0.1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (group.description != null &&
                      group.description!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      group.description!,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 11.5,
                        color: KinrelColors.textSilver.withValues(alpha: 0.65),
                        height: 1.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.people_outline_rounded,
                          size: 11, color: KinrelColors.textDim),
                      const SizedBox(width: 4),
                      Text(
                        '${group.memberCount} members',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 10.5,
                          color: KinrelColors.textDim,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(Icons.access_time_rounded,
                          size: 11, color: KinrelColors.textDim),
                      const SizedBox(width: 4),
                      Text(
                        timeAgo,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 10.5,
                          color: KinrelColors.textDim,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Chevron
            Icon(Icons.chevron_right,
                size: 20, color: KinrelColors.textDim),
          ],
        ),
      ),
    );
  }

  String _formatTimeAgo(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${dt.month}/${dt.day}';
  }
}

class _GroupInitials extends StatelessWidget {
  const _GroupInitials({required this.group});
  final FamilyGroup group;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            group.groupType.color.withValues(alpha: 0.30),
            group.groupType.color.withValues(alpha: 0.12),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          group.groupType.icon,
          size: 24,
          color: Colors.white.withValues(alpha: 0.90),
        ),
      ),
    );
  }
}
