// lib/features/family/presentation/family_members_screen.dart
//
// Extracted from FamilyDetailScreen's _MembersTab — full-screen
// member list with search, sort, and member cards.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import 'add_member_options_sheet.dart';

class FamilyMembersScreen extends ConsumerStatefulWidget {
  const FamilyMembersScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<FamilyMembersScreen> createState() =>
      _FamilyMembersScreenState();
}

class _FamilyMembersScreenState extends ConsumerState<FamilyMembersScreen> {
  String _searchQuery = '';
  String _sortBy = 'name';

  @override
  Widget build(BuildContext context) {
    final detailAsync =
        ref.watch(familyDetailProvider(widget.familyId));
    final combinedMembers =
        ref.watch(combinedMembersProvider(widget.familyId));
    final membershipsAsync =
        ref.watch(familyMembershipsProvider(widget.familyId));
    final memberships = membershipsAsync.valueOrNull ?? [];
    final currentUserId =
        ref.read(supabaseProvider)?.auth.currentUser?.id;

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Members',
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
          onRetry: () =>
              ref.invalidate(familyDetailProvider(widget.familyId)),
        ),
        data: (detail) {
          if (detail == null) {
            return const Center(child: Text('Family not found'));
          }

          final family = detail.family;
          final isCreator = family.createdBy != null &&
              family.createdBy == currentUserId;
          final currentUserMembership = memberships
              .where((m) => m.userId == currentUserId)
              .firstOrNull;
          final isAdmin = isCreator ||
              (currentUserMembership?.isAdmin ?? false);

          final activeMembers = combinedMembers
              .where((p) => p.deletedAt == null)
              .toList();

          var filtered = activeMembers;
          if (_searchQuery.isNotEmpty) {
            final q = _searchQuery.toLowerCase();
            filtered = filtered
                .where((p) =>
                    p.name.toLowerCase().contains(q) ||
                    (p.gender?.toLowerCase().contains(q) ?? false))
                .toList();
          }

          if (_sortBy == 'name') {
            filtered.sort((a, b) => a.name.compareTo(b.name));
          } else {
            filtered.sort((a, b) =>
                (a.gender ?? '').compareTo(b.gender ?? ''));
          }

          return Column(
            children: [
              // Search + sort bar
              Padding(
                padding: const EdgeInsets.all(KinrelSpacing.base),
                child: Row(
                  children: [
                    Expanded(
                      child: DKSearchField(
                        hint: 'Search members...',
                        onChanged: (v) =>
                            setState(() => _searchQuery = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      onSelected: (v) => setState(() => _sortBy = v),
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: 'name', child: Text('Sort by name')),
                        const PopupMenuItem(
                            value: 'gender',
                            child: Text('Sort by gender')),
                      ],
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: KinrelColors.darkElevated,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.sort_rounded,
                            color: KinrelColors.textSilver, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
              // Member count
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: KinrelSpacing.base),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${filtered.length} ${filtered.length == 1 ? "member" : "members"}',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      color: KinrelColors.textDim,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Member list
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          'No members found',
                          style: TextStyle(color: KinrelColors.textDim),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(
                          left: KinrelSpacing.base,
                          right: KinrelSpacing.base,
                          bottom: 88,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final person = filtered[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: KinrelColors.darkCard,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 22,
                                  backgroundColor: KinrelColors.orange
                                      .withValues(alpha: 0.15),
                                  backgroundImage: person.photoUrl != null
                                      ? NetworkImage(person.photoUrl!)
                                      : null,
                                  child: person.photoUrl == null
                                      ? Text(
                                          person.name.isNotEmpty
                                              ? person.name[0]
                                                  .toUpperCase()
                                              : '?',
                                          style: TextStyle(
                                            fontFamily: KinrelTypography
                                                .displayFont,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                            color: KinrelColors.orange,
                                          ),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        person.name,
                                        style: TextStyle(
                                          fontFamily: KinrelTypography
                                              .displayFont,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: KinrelColors.textWhite,
                                        ),
                                      ),
                                      if (person.gender != null)
                                        Text(
                                          person.gender!,
                                          style: TextStyle(
                                            fontFamily: KinrelTypography
                                                .bodyFont,
                                            fontSize: 12,
                                            color: KinrelColors.textDim,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (person.isAnchor)
                                  Icon(Icons.star_rounded,
                                      color: KinrelColors.gold, size: 18),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () =>
            showAddMemberOptions(context, familyId: widget.familyId),
        backgroundColor: KinrelColors.orange,
        child: const Icon(Icons.person_add_alt_1_rounded,
            color: Colors.white),
      ),
    );
  }
}
