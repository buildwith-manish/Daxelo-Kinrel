import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/family/family_provider.dart';
import 'add_person_sheet.dart';
import 'relationship_picker_sheet.dart';

/// Screen for graph-based relationship building.
///
/// Flow:
/// 1. Tap first person (highlighted in orange)
/// 2. Tap second person (highlighted in amber)
/// 3. RelationshipPickerSheet appears: "How is [Person2] related to [Person1]?"
/// 4. On selection, create the relationship via Supabase
/// 5. Visual feedback: Both nodes briefly glow, then a line appears between them
class RelationshipBuilderScreen extends ConsumerStatefulWidget {
  const RelationshipBuilderScreen({
    super.key,
    required this.familyId,
    required this.familyName,
  });

  final String familyId;
  final String familyName;


  @override
  ConsumerState<RelationshipBuilderScreen> createState() =>
      _RelationshipBuilderScreenState();
}

class _RelationshipBuilderScreenState
    extends ConsumerState<RelationshipBuilderScreen>
    with TickerProviderStateMixin {
  String? _selectedPerson1Id;
  String? _selectedPerson2Id;

  // Glow animation for linked nodes
  late AnimationController _glowController;
  String? _glowingNode1;
  String? _glowingNode2;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _glowController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _glowingNode1 = null;
          _glowingNode2 = null;
        });
        _glowController.reset();
      }
    });
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(familyDetailProvider(widget.familyId));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Link Members',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_selectedPerson1Id != null || _selectedPerson2Id != null)
            TextButton.icon(
              onPressed: _clearSelection,
              icon: Icon(Icons.clear, size: 16),
              label: Text(
                'Clear',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  color: KinrelColors.textSilver,
                ),
              ),
            ),
        ],
      ),
      body: detailAsync.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: KinrelColors.purple),
        ),
        error: (e, _) => _ErrorState(
          message: 'Failed to load family data',
          onRetry: () => ref.invalidate(familyDetailProvider(widget.familyId)),
        ),
        data: (detail) {
          if (detail == null) {
            return _ErrorState(
              message: 'Family not found',
              onRetry: () =>
                  ref.invalidate(familyDetailProvider(widget.familyId)),
            );
          }

          if (detail.members.isEmpty) {
            return _EmptyState(
              onAddMember: () => AddPersonSheet.show(
                context,
                familyId: widget.familyId,
              ),
            );
          }

          return _buildMemberGrid(detail);
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => AddPersonSheet.show(
          context,
          familyId: widget.familyId,
        ),
        backgroundColor: KinrelColors.purple,
        child: Icon(Icons.person_add, color: Colors.white),
      ),
    );
  }

  Widget _buildMemberGrid(FamilyDetail detail) {
    final members = detail.members.where((p) => p.deletedAt == null).toList();
    final relationships = detail.relationships;

    // Build relationship map for each person
    final personRels = <String, List<String>>{};
    for (final rel in relationships) {
      personRels.putIfAbsent(rel.fromPersonId, () => []).add(rel.relationshipKey);
      personRels.putIfAbsent(rel.toPersonId, () => []).add(rel.relationshipKey);
    }

    return Column(
      children: [
        // Instruction bar
        _buildInstructionBar(),

        // Person grid
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(KinrelSpacing.base),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: KinrelSpacing.sm,
              crossAxisSpacing: KinrelSpacing.sm,
              childAspectRatio: 0.85,
            ),
            itemCount: members.length,
            itemBuilder: (context, index) {
              final person = members[index];
              return _PersonCard(
                person: person,
                relationshipTags: personRels[person.id] ?? [],
                isSelected1: person.id == _selectedPerson1Id,
                isSelected2: person.id == _selectedPerson2Id,
                isGlowing:
                    person.id == _glowingNode1 || person.id == _glowingNode2,
                glowAnimation: _glowController,
                onTap: () => _onPersonTap(person),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildInstructionBar() {
    String instruction;
    Color instructionColor;

    if (_selectedPerson1Id == null) {
      instruction = 'Tap the first person to link';
      instructionColor = KinrelColors.textSilver;
    } else if (_selectedPerson2Id == null) {
      instruction = 'Now tap the second person';
      instructionColor = KinrelColors.amber;
    } else {
      instruction = 'Creating link...';
      instructionColor = KinrelColors.purple;
    }

    return AnimatedContainer(
      duration: KinrelMotion.normal,
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.base,
        vertical: KinrelSpacing.md,
      ),
      decoration: BoxDecoration(
        color: instructionColor.withValues(alpha: 0.08),
        border: Border(
          bottom: BorderSide(
            color: instructionColor.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.link, size: 18, color: instructionColor),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              instruction,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: instructionColor,
              ),
            ),
          ),
          // Selection indicators
          if (_selectedPerson1Id != null)
            _SelectionBadge(
              label: '1st',
              color: KinrelColors.purple,
            ),
          if (_selectedPerson2Id != null) ...[
            SizedBox(width: 6),
            _SelectionBadge(
              label: '2nd',
              color: KinrelColors.amber,
            ),
          ],
        ],
      ),
    );
  }

  void _onPersonTap(Person person) {
    if (_isCreating) return;

    if (_selectedPerson1Id == null) {
      // Select first person
      setState(() => _selectedPerson1Id = person.id);
    } else if (_selectedPerson2Id == null && person.id != _selectedPerson1Id) {
      // Select second person - show relationship picker
      setState(() => _selectedPerson2Id = person.id);
      _showRelationshipPicker(person);
    } else if (person.id == _selectedPerson1Id) {
      // Deselect first person
      setState(() => _selectedPerson1Id = null);
    }
  }

  void _showRelationshipPicker(Person person2) {
    final detailAsync = ref.read(familyDetailProvider(widget.familyId));
    final detail = detailAsync.valueOrNull;
    if (detail == null) return;

    final person1 = detail.members.firstWhere(
      (p) => p.id == _selectedPerson1Id,
      orElse: () => person2,
    );

    // Get existing relationship types for person1
    final existingRels = <String>[];
    for (final rel in detail.relationships) {
      if (rel.fromPersonId == person1.id) {
        existingRels.add(rel.relationshipKey);
      }
    }

    RelationshipPickerSheet.show(
      context,
      personAName: person1.name,
      personBName: person2.name,
      existingRelationshipTypes: existingRels,
    ).then((selectedKey) {
      if (selectedKey != null) {
        _createRelationship(person1, person2, selectedKey);
      } else {
        _clearSelection();
      }
    });
  }

  Future<void> _createRelationship(
    Person person1,
    Person person2,
    String relationshipKey,
  ) async {
    setState(() => _isCreating = true);

    try {
      await createRelationshipBetween(
        ref: ref,
        familyId: widget.familyId,
        fromPersonId: person1.id,
        toPersonId: person2.id,
        relationshipKey: relationshipKey,
      );

      if (mounted) {
        // Trigger glow animation
        setState(() {
          _glowingNode1 = person1.id;
          _glowingNode2 = person2.id;
        });
        unawaited(_glowController.forward());

        context.showSnackBar(
          'Linked: ${person2.name} is ${relationshipKey.snakeToTitle} of ${person1.name}',
        );

        // Clear selection after a brief delay
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) {
          _clearSelection();
        }
      }
    } catch (e) {
      if (mounted) {
        context.showSnackBar(
          'Failed to create link: ${e.toString().split('\n').first}',
          isError: true,
        );
        _clearSelection();
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  void _clearSelection() {
    setState(() {
      _selectedPerson1Id = null;
      _selectedPerson2Id = null;
    });
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────

class _PersonCard extends StatelessWidget {
  const _PersonCard({
    required this.person,
    required this.relationshipTags,
    required this.isSelected1,
    required this.isSelected2,
    required this.isGlowing,
    required this.glowAnimation,
    required this.onTap,
  });

  final Person person;
  final List<String> relationshipTags;
  final bool isSelected1;
  final bool isSelected2;
  final bool isGlowing;
  final Animation<double> glowAnimation;
  final VoidCallback onTap;


  @override
  Widget build(BuildContext context) {
    final borderColor = isSelected1
        ? KinrelColors.purple
        : isSelected2
            ? KinrelColors.amber
            : KinrelColors.darkSurface.withValues(alpha: 0.5);

    final bgColor = isSelected1
        ? KinrelColors.purple.withValues(alpha: 0.08)
        : isSelected2
            ? KinrelColors.amber.withValues(alpha: 0.08)
            : KinrelColors.darkCard;

    return AnimatedBuilder(
      animation: glowAnimation,
      builder: (context, child) {
        final glowValue = isGlowing ? glowAnimation.value : 0.0;
        return GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: KinrelMotion.fast,
            curve: KinrelMotion.easeOut,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
              border: Border.all(
                color: borderColor,
                width: isSelected1 || isSelected2 ? 2 : 1,
              ),
              boxShadow: isGlowing
                  ? [
                      BoxShadow(
                        color: KinrelColors.purpleGlow
                            .withValues(alpha: 0.3 + glowValue * 0.4),
                        blurRadius: 8 + glowValue * 16,
                        spreadRadius: glowValue * 4,
                      ),
                    ]
                  : null,
            ),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(KinrelSpacing.md),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar row
            Row(
              children: [
                // Avatar circle
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: person.isDeceased
                        ? LinearGradient(
                            colors: [
                              KinrelColors.textDim,
                              KinrelColors.darkSurface,
                            ],
                          )
                        : isSelected1
                            ? KinrelGradients.igniteGradient
                            : isSelected2
                                ? LinearGradient(
                                    colors: [
                                      KinrelColors.amber,
                                      KinrelColors.purple,
                                    ],
                                  )
                                : KinrelGradients.igniteGradient,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: person.isDeceased
                        ? Text(
                            '🕊️',
                            style: TextStyle(fontSize: 18),
                          )
                        : Text(
                            person.name.isNotEmpty
                                ? person.name[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              fontFamily: KinrelTypography.displayFont,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
                SizedBox(width: 10),

                // Selection badge
                if (isSelected1)
                  Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: KinrelColors.purple,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '1st',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  )
                else if (isSelected2)
                  Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: KinrelColors.amber,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '2nd',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),

                Spacer(),

                // Gender icon
                Icon(
                  person.gender == 'female'
                      ? Icons.female
                      : person.gender == 'male'
                          ? Icons.male
                          : Icons.person,
                  size: 16,
                  color: KinrelColors.textDim,
                ),
              ],
            ),
            SizedBox(height: 8),

            // Name
            Text(
              person.name,
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: person.isDeceased
                    ? KinrelColors.textSilver
                    : KinrelColors.textWhite,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),

            // Relationship key
            if (person.gender != null) ...[
              SizedBox(height: 2),
              Text(person.gender!.toUpperCase(),
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 11,
                  color: KinrelColors.purple,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],

            Spacer(),

            // Relationship tags
            if (relationshipTags.isNotEmpty)
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: relationshipTags.take(3).map((tag) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: KinrelColors.darkSurface.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      tag.snakeToTitle,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 9,
                        color: KinrelColors.textDim,
                      ),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}

class _SelectionBadge extends StatelessWidget {
  const _SelectionBadge({required this.label, required this.color});

  final String label;
  final Color color;


  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAddMember});

  final VoidCallback onAddMember;


  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KinrelSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Dotted circle with + icon
            CustomPaint(
              size: const Size(120, 120),
              painter: _DottedCirclePainter(
                color: KinrelColors.textDim.withValues(alpha: 0.3),
              ),
              child: const SizedBox(
                width: 120,
                height: 120,
                child: Center(
                  child: Icon(
                    Icons.add,
                    size: 40,
                    color: KinrelColors.textDim,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Add Members First',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add family members, then link them here\nto build your family graph.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: KinrelColors.textSilver,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAddMember,
              icon: const Icon(Icons.person_add, size: 18),
              label: const Text('Add First Member'),
              style: FilledButton.styleFrom(
                backgroundColor: KinrelColors.purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
                shape: const RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(KinrelSpacing.radiusSm),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;


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
            const Text(
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
                backgroundColor: KinrelColors.purple,
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

class _DottedCirclePainter extends CustomPainter {
  _DottedCirclePainter({required this.color});

  final Color color;


  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // Draw dashed circle
    const dashCount = 36;
    const dashAngle = math.pi * 2 / dashCount;
    const dashLength = dashAngle * 0.6;

    for (int i = 0; i < dashCount; i++) {
      final startAngle = i * dashAngle;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        dashLength,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DottedCirclePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
