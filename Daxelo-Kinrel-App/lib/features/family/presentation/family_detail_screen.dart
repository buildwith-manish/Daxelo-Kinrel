import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/kinship/kinship_provider.dart';
import 'family_tree_canvas.dart';
import 'add_person_sheet.dart';
import 'person_detail_sheet.dart';

class FamilyDetailScreen extends ConsumerStatefulWidget {
  final String familyId;

  const FamilyDetailScreen({super.key, required this.familyId});

  @override
  ConsumerState<FamilyDetailScreen> createState() =>
      _FamilyDetailScreenState();
}

class _FamilyDetailScreenState extends ConsumerState<FamilyDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(familyDetailProvider(widget.familyId));

    return Scaffold(
      appBar: AppBar(
        title: detailAsync.when(
          loading: () => Text(
            'Family Tree',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontWeight: FontWeight.w600,
            ),
          ),
          error: (_, __) => Text(
            'Family Tree',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontWeight: FontWeight.w600,
            ),
          ),
          data: (detail) => Text(
            detail?.family.name ?? 'Family Tree',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.route),
            tooltip: 'Find Path',
            onPressed: () =>
                context.go('/family/${widget.familyId}/path-finder'),
          ),
        ],
      ),
      body: detailAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: KinrelColors.orange),
        ),
        error: (error, _) => _ErrorState(
          message: 'Failed to load family data',
          onRetry: () =>
              ref.invalidate(familyDetailProvider(widget.familyId)),
        ),
        data: (detail) {
          if (detail == null) {
            return _ErrorState(
              message: 'Family not found',
              onRetry: () =>
                  ref.invalidate(familyDetailProvider(widget.familyId)),
            );
          }

          return _FamilyDetailContent(
            detail: detail,
            familyId: widget.familyId,
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          AddPersonSheet.show(
            context,
            familyId: widget.familyId,
          );
        },
        backgroundColor: KinrelColors.orange,
        child: const Icon(Icons.person_add, color: Colors.white),
      ),
    );
  }
}

class _FamilyDetailContent extends ConsumerWidget {
  final FamilyDetail detail;
  final String familyId;

  const _FamilyDetailContent({
    required this.detail,
    required this.familyId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        // Family info header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(KinrelSpacing.base),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                KinrelColors.orange.withValues(alpha: 0.08),
                KinrelColors.amber.withValues(alpha: 0.03),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border(
              bottom: BorderSide(
                color: KinrelColors.darkSurface.withValues(alpha: 0.3),
              ),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: KinrelColors.orange.withValues(alpha: 0.15),
                  borderRadius:
                      BorderRadius.circular(KinrelSpacing.radiusSm),
                ),
                child: const Icon(
                  Icons.family_restroom,
                  color: KinrelColors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      detail.family.name,
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${detail.members.length} member${detail.members.length != 1 ? 's' : ''}',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13,
                        color: KinrelColors.textSilver,
                      ),
                    ),
                  ],
                ),
              ),
              if (detail.family.description != null &&
                  detail.family.description!.isNotEmpty)
                IconButton(
                  icon: Icon(Icons.info_outline, color: KinrelColors.textDim),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        backgroundColor: KinrelColors.darkElevated,
                        title: Text(
                          detail.family.name,
                          style: TextStyle(
                            fontFamily: KinrelTypography.displayFont,
                            color: KinrelColors.textWhite,
                          ),
                        ),
                        content: Text(
                          detail.family.description!,
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            color: KinrelColors.textSilver,
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              'Close',
                              style:
                                  TextStyle(color: KinrelColors.orange),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ),

        // Interactive family tree
        Expanded(
          child: detail.members.isEmpty
              ? _EmptyTreeState(
                  onAddMember: () {
                    AddPersonSheet.show(
                      context,
                      familyId: familyId,
                    );
                  },
                )
              : FamilyTreeCanvas(
                  members: detail.members,
                  relationships: detail.relationships,
                  onNodeTap: (person) {
                    final kinshipAsync = ref.read(kinshipServiceProvider);
                    PersonDetailSheet.show(
                      context,
                      person: person,
                      familyId: familyId,
                      kinshipService: kinshipAsync,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _EmptyTreeState extends StatelessWidget {
  final VoidCallback onAddMember;

  const _EmptyTreeState({required this.onAddMember});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KinrelSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.account_tree,
              size: 64,
              color: KinrelColors.textDim.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 20),
            Text(
              'No Members Yet',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add family members to start building your tree. '
              'Tap the + button below to add the first person.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: KinrelColors.textSilver,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KinrelSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: KinrelColors.error.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: KinrelColors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
