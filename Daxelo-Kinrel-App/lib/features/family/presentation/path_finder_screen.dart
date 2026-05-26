import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/graph/graph_service.dart';
import '../../../core/graph/graph_provider.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/kinship/kinship_provider.dart';
import '../../../core/kinship/kinship_models.dart';

// ────────────────────────────────────────────────────────────────
// Path Finder Screen — Relationship Path Finder (#1 Wow Feature)
// ────────────────────────────────────────────────────────────────

class PathFinderScreen extends ConsumerStatefulWidget {
  PathFinderScreen({super.key, required this.familyId});

  final String familyId;

  @override
  ConsumerState<PathFinderScreen> createState() => _PathFinderScreenState();
}

class _PathFinderScreenState extends ConsumerState<PathFinderScreen>
    with TickerProviderStateMixin {
  String? _fromPersonId;
  String? _toPersonId;
  PathResult? _pathResult;
  bool _isSearching = false;

  // Animation controllers
  late AnimationController _dotPulseController;
  late AnimationController _pathRevealController;
  late AnimationController _resultAppearController;

  @override
  void initState() {
    super.initState();
    _dotPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pathRevealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _resultAppearController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void dispose() {
    _dotPulseController.dispose();
    _pathRevealController.dispose();
    _resultAppearController.dispose();
    super.dispose();
  }

  void _findPath() {
    if (_fromPersonId == null || _toPersonId == null) return;

    // Same person edge case
    if (_fromPersonId == _toPersonId) {
      setState(() {
        _pathResult = null;
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _pathResult = null;
    });

    final membersAsync = ref.read(familyMembersProvider(widget.familyId));
    final relsAsync =
        ref.read(familyRelationshipsProvider(widget.familyId));

    membersAsync.whenData((members) {
      relsAsync.whenData((relationships) {
        final graphService = ref.read(graphServiceProvider);

        final persons = members
            .where((p) => p.deletedAt == null)
            .map((p) => p.toGraphPerson())
            .toList();

        final edges = relationships.map((r) => r.toGraphEdge()).toList();

        final result = graphService.findPath(
          persons: persons,
          relationships: edges,
          fromPersonId: _fromPersonId!,
          toPersonId: _toPersonId!,
          locale: 'hi',
        );

        if (mounted) {
          setState(() => _isSearching = false);
          if (result != null) {
            setState(() => _pathResult = result);
            _pathRevealController.forward(from: 0).then((_) {
              _resultAppearController.forward(from: 0);
            });
          }
        }
      });
    });

    // Fallback timeout
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _isSearching) {
        setState(() => _isSearching = false);
      }
    });
  }

  void _onPersonSelected(String personId, bool isFrom) {
    setState(() {
      if (isFrom) {
        _fromPersonId = personId;
      } else {
        _toPersonId = personId;
      }
      _pathResult = null;
      _pathRevealController.reset();
      _resultAppearController.reset();
    });

    // Auto-search when both selected
    if (_fromPersonId != null && _toPersonId != null) {
      _findPath();
    }
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(familyMembersProvider(widget.familyId));

    return Scaffold(
      backgroundColor: KinrelColors.darkBackground,
      appBar: AppBar(
        backgroundColor: KinrelColors.darkBackground,
        elevation: 0,
        title: Text(
          'Path Finder',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: KinrelColors.textWhite,
          ),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: KinrelColors.textWhite),
      ),
      body: membersAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: KinrelColors.orange),
        ),
        error: (e, _) => Center(
          child: Text(
            'Failed to load members',
            style: TextStyle(color: KinrelColors.textDim),
          ),
        ),
        data: (members) {
          if (members.isEmpty) {
            return _EmptyState();
          }
          return _buildContent(members);
        },
      ),
    );
  }

  Widget _buildContent(List<Person> members) {
    final personMap = {for (final p in members) p.id: p};
    final fromPerson = _fromPersonId != null ? personMap[_fromPersonId] : null;
    final toPerson = _toPersonId != null ? personMap[_toPersonId] : null;
    final bothSelected = _fromPersonId != null && _toPersonId != null;
    final isSamePerson = _fromPersonId != null &&
        _toPersonId != null &&
        _fromPersonId == _toPersonId;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.base,
        vertical: KinrelSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Person Selector Cards ──────────────────────────────
          Row(
            children: [
              // Person A
              Expanded(
                child: _PersonSelectorCard(
                  label: 'Person A',
                  person: fromPerson,
                  isSelected: _fromPersonId != null,
                  onTap: () => _showPersonSelector(
                    members: members,
                    personMap: personMap,
                    isFrom: true,
                    currentlySelectedId: _fromPersonId,
                  ),
                ),
              ),

              // ── Animated Dotted/Solid Line Between Cards ──────
              SizedBox(
                width: 48,
                child: _AnimatedConnector(
                  bothSelected: bothSelected,
                  dotPulseAnimation: _dotPulseController,
                ),
              ),

              // Person B
              Expanded(
                child: _PersonSelectorCard(
                  label: 'Person B',
                  person: toPerson,
                  isSelected: _toPersonId != null,
                  onTap: () => _showPersonSelector(
                    members: members,
                    personMap: personMap,
                    isFrom: false,
                    currentlySelectedId: _toPersonId,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ── Swap Button ────────────────────────────────────────
          if (bothSelected && !isSamePerson)
            Center(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    final temp = _fromPersonId;
                    _fromPersonId = _toPersonId;
                    _toPersonId = temp;
                    _pathResult = null;
                    _pathRevealController.reset();
                    _resultAppearController.reset();
                  });
                  _findPath();
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: KinrelColors.darkElevated,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: KinrelColors.orange.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.swap_horiz,
                          size: 16, color: KinrelColors.orange),
                      const SizedBox(width: 4),
                      Text(
                        'Swap',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: KinrelColors.orange,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          const SizedBox(height: 24),

          // ── Searching Indicator ────────────────────────────────
          if (_isSearching) ...[
            Center(
              child: Column(
                children: [
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: KinrelColors.orange,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Finding relationship path...',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      color: KinrelColors.textSilver,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // ── Same Person Edge Case ──────────────────────────────
          if (isSamePerson && !_isSearching) ...[
            _SamePersonCard(),
            const SizedBox(height: 24),
          ],

          // ── No Path Edge Case ──────────────────────────────────
          if (bothSelected &&
              !_isSearching &&
              !isSamePerson &&
              _pathResult == null) ...[
            _NoPathCard(
              onAddConnection: () {
                // Could navigate to add-relationship screen
              },
            ),
            const SizedBox(height: 24),
          ],

          // ── Path Visualization Chain ───────────────────────────
          if (_pathResult != null && !_isSearching) ...[
            AnimatedBuilder(
              animation: _pathRevealController,
              builder: (context, _) {
                return Opacity(
                  opacity: _pathRevealController.value,
                  child: _PathVisualizationChain(
                    result: _pathResult!,
                    personMap: personMap,
                    fromPersonId: _fromPersonId!,
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
          ],

          // ── Hero Result Card ───────────────────────────────────
          if (_pathResult != null && !_isSearching) ...[
            AnimatedBuilder(
              animation: _resultAppearController,
              builder: (context, _) {
                return Transform.translate(
                  offset:
                      Offset(0, 20 * (1 - _resultAppearController.value)),
                  child: Opacity(
                    opacity: _resultAppearController.value,
                    child: _HeroResultCard(
                      result: _pathResult!,
                      personMap: personMap,
                      fromPersonId: _fromPersonId!,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 32),
          ],
        ],
      ),
    );
  }

  // ── Person Selector Bottom Sheet ──────────────────────────────
  void _showPersonSelector({
    required List<Person> members,
    required Map<String, Person> personMap,
    required bool isFrom,
    required String? currentlySelectedId,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.xxl),
        ),
      ),
      builder: (context) {
        return _PersonSelectorSheet(
          members: members,
          personMap: personMap,
          currentlySelectedId: currentlySelectedId,
          otherSelectedId: isFrom ? _toPersonId : _fromPersonId,
          onSelected: (personId) {
            Navigator.pop(context);
            _onPersonSelected(personId, isFrom);
          },
        );
      },
    );
  }
}

// ────────────────────────────────────────────────────────────────
// Person Selector Card
// ────────────────────────────────────────────────────────────────

class _PersonSelectorCard extends StatelessWidget {
  const _PersonSelectorCard({
    required this.label,
    required this.person,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final Person? person;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
          border: Border.all(
            color: isSelected
                ? KinrelColors.orange
                : Colors.white.withValues(alpha: 0.06),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: KinrelColors.orangeGlowSubtle,
                    blurRadius: 16,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            // Label
            Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 10,
                fontWeight: FontWeight.w500,
                letterSpacing: 1.5,
                color: isSelected
                    ? KinrelColors.orange
                    : KinrelColors.textDim,
              ),
            ),
            const SizedBox(height: 10),

            // Avatar
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? KinrelColors.orange.withValues(alpha: 0.15)
                    : KinrelColors.darkElevated,
                border: Border.all(
                  color: isSelected
                      ? KinrelColors.orange
                      : KinrelColors.textDim.withValues(alpha: 0.2),
                  width: 1.5,
                ),
              ),
              child: person != null
                  ? _buildAvatar(person!)
                  : Icon(
                      Icons.person_add_alt_1_outlined,
                      size: 20,
                      color: KinrelColors.textDim,
                    ),
            ),
            const SizedBox(height: 8),

            // Name
            Text(
              person?.name ?? 'Tap to select',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                fontWeight: person != null ? FontWeight.w600 : FontWeight.w400,
                color: person != null
                    ? KinrelColors.textWhite
                    : KinrelColors.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(Person person) {
    final initial = person.name.isNotEmpty ? person.name[0].toUpperCase() : '?';
    return Center(
      child: Text(
        initial,
        style: TextStyle(
          fontFamily: KinrelTypography.displayFont,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: KinrelColors.orange,
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────
// Animated Connector (dotted → solid)
// ────────────────────────────────────────────────────────────────

class _AnimatedConnector extends StatelessWidget {
  const _AnimatedConnector({
    required this.bothSelected,
    required this.dotPulseAnimation,
  });

  final bool bothSelected;
  final Animation<double> dotPulseAnimation;

  @override
  Widget build(BuildContext context) {
    if (bothSelected) {
      // Solid glowing line
      return Center(
        child: Container(
          height: 2,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                KinrelColors.orange.withValues(alpha: 0.3),
                KinrelColors.orange,
                KinrelColors.orange.withValues(alpha: 0.3),
              ],
            ),
            borderRadius: BorderRadius.circular(1),
            boxShadow: [
              BoxShadow(
                color: KinrelColors.orangeGlow,
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
      );
    }

    // Animated dotted line
    return AnimatedBuilder(
      animation: dotPulseAnimation,
      builder: (context, _) {
        final opacity = 0.3 + (dotPulseAnimation.value * 0.5);
        return CustomPaint(
          size: const Size(48, 2),
          painter: _DottedLinePainter(
            color: KinrelColors.textDim.withValues(alpha: opacity),
            dotRadius: 1.5,
            dotSpacing: 6,
          ),
        );
      },
    );
  }
}

class _DottedLinePainter extends CustomPainter {
  _DottedLinePainter({
    required this.color,
    required this.dotRadius,
    required this.dotSpacing,
  });

  final Color color;
  final double dotRadius;
  final double dotSpacing;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final y = size.height / 2;
    double x = dotRadius;
    while (x < size.width) {
      canvas.drawCircle(Offset(x, y), dotRadius, paint);
      x += dotSpacing;
    }
  }

  @override
  bool shouldRepaint(covariant _DottedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}

// ────────────────────────────────────────────────────────────────
// Path Visualization Chain
// ────────────────────────────────────────────────────────────────

class _PathVisualizationChain extends StatelessWidget {
  const _PathVisualizationChain({
    required this.result,
    required this.personMap,
    required this.fromPersonId,
  });

  final PathResult result;
  final Map<String, Person> personMap;
  final String fromPersonId;

  @override
  Widget build(BuildContext context) {
    final steps = result.path;
    if (steps.isEmpty) return const SizedBox.shrink();

    // Build the node list: fromPerson + all path steps
    final nodes = <_PathNode>[];
    final fromPerson = personMap[fromPersonId];
    if (fromPerson != null) {
      nodes.add(_PathNode(
        personId: fromPersonId,
        name: fromPerson.name,
        isSource: true,
      ));
    }
    for (int i = 0; i < steps.length; i++) {
      nodes.add(_PathNode(
        personId: steps[i].personId,
        name: steps[i].personName,
        edgeLabel: _formatEdgeLabel(steps[i].type),
        isSource: i == steps.length - 1,
      ));
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.base,
        vertical: KinrelSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section label
          Row(
            children: [
              Icon(Icons.route, size: 14, color: KinrelColors.orange),
              const SizedBox(width: 6),
              Text(
                'RELATIONSHIP PATH',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 2,
                  color: KinrelColors.textDim,
                ),
              ),
              const Spacer(),
              Text(
                '${steps.length} step${steps.length != 1 ? 's' : ''}',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: KinrelColors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Horizontal scrollable chain
          SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: nodes.length,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              separatorBuilder: (_, i) {
                final node = nodes[i];
                return _PathEdge(edgeLabel: node.edgeLabel);
              },
              itemBuilder: (_, i) {
                final node = nodes[i];
                return _PathNodeWidget(node: node);
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatEdgeLabel(String type) {
    // Convert snake_case to readable label like "son of", "brother of"
    final words = type.replaceAll('_', ' ').split(' ');
    if (words.length == 1) {
      return '${words[0]} of';
    }
    return words.join(' ');
  }
}

class _PathNode {
  _PathNode({
    required this.personId,
    required this.name,
    this.edgeLabel,
    this.isSource = false,
  });

  final String personId;
  final String name;
  final String? edgeLabel;
  final bool isSource;
}

class _PathNodeWidget extends StatelessWidget {
  const _PathNodeWidget({required this.node});

  final _PathNode node;

  @override
  Widget build(BuildContext context) {
    final initial = node.name.isNotEmpty ? node.name[0].toUpperCase() : '?';
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: KinrelColors.darkElevated,
            border: Border.all(
              color: node.isSource
                  ? KinrelColors.orange
                  : KinrelColors.orange.withValues(alpha: 0.4),
              width: 1.5,
            ),
          ),
          child: Center(
            child: Text(
              initial,
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: KinrelColors.orange,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 52,
          child: Text(
            node.name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 9,
              fontWeight: FontWeight.w500,
              color: KinrelColors.textWhite,
            ),
          ),
        ),
      ],
    );
  }
}

class _PathEdge extends StatelessWidget {
  const _PathEdge({required this.edgeLabel});

  final String? edgeLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Arrow line
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 1.5,
              color: KinrelColors.orange.withValues(alpha: 0.4),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 8,
              color: KinrelColors.orange.withValues(alpha: 0.5),
            ),
          ],
        ),
        const SizedBox(height: 2),
        // Edge label
        if (edgeLabel != null)
          SizedBox(
            width: 40,
            child: Text(
              edgeLabel!,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 8,
                fontWeight: FontWeight.w400,
                color: KinrelColors.textSilver,
                height: 1.2,
              ),
            ),
          ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────
// Hero Result Card
// ────────────────────────────────────────────────────────────────

class _HeroResultCard extends ConsumerWidget {
  const _HeroResultCard({
    required this.result,
    required this.personMap,
    required this.fromPersonId,
  });

  final PathResult result;
  final Map<String, Person> personMap;
  final String fromPersonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Try to resolve a compound kinship key from the path
    final pathTypes = result.path.map((s) => s.type).toList();
    final kinshipService = ref.watch(kinshipServiceProvider);

    KinshipRelationship? resolvedRelationship;
    try {
      resolvedRelationship = kinshipService.resolvePathToKey(pathTypes);
    } catch (_) {
      // KinshipService might not be loaded yet
    }

    // Get localized term
    String? nativeTerm;
    String? transliteration;
    String? englishTerm;
    String? culturalNote;
    int? generationDiff;
    int? degreeOfRelation;

    if (resolvedRelationship != null) {
      englishTerm = resolvedRelationship.englishTerm;
      generationDiff = resolvedRelationship.generation;
      degreeOfRelation = resolvedRelationship.relationshipPath.length;
      culturalNote = resolvedRelationship.notes;

      // Try to get Hindi translation
      try {
        final translation =
            kinshipService.getKinshipTerm(resolvedRelationship.relationshipKey, 'hindi');
        if (translation != null) {
          nativeTerm = translation.native;
          transliteration = translation.latin;
        }
      } catch (_) {}
    }

    // Fallback: use PathResult's localizedDescription
    if (nativeTerm == null && result.localizedDescription != null) {
      nativeTerm = result.localizedDescription;
    }
    englishTerm ??= result.relationshipDescription;

    // Calculate generation difference from person data
    if (generationDiff == null || generationDiff == 0) {
      // Estimate from path using generation indices
      final fromGen = personMap[fromPersonId]?.generationIndex ?? 0;
      int genDiff = 0;
      for (final step in result.path) {
        final p = personMap[step.personId];
        if (p != null) {
          genDiff = p.generationIndex - fromGen;
        }
      }
      generationDiff = genDiff;
    }

    return Container(
      padding: const EdgeInsets.all(KinrelSpacing.xl),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.xl),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: KinrelColors.orangeGlowSubtle,
            blurRadius: 24,
            spreadRadius: 0,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Kinship term in regional script (hero moment) ─────
          if (nativeTerm != null) ...[
            ShaderMask(
              shaderCallback: (bounds) {
                return KinrelGradients.igniteGradient.createShader(bounds);
              },
              child: Text(
                nativeTerm,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.15,
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],

          // ── Transliteration ───────────────────────────────────
          if (transliteration != null) ...[
            Text(
              transliteration,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: KinrelColors.textWhite,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 4),
          ],

          // ── English term ──────────────────────────────────────
          Text(
            englishTerm.titleCase,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: KinrelColors.textSilver,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 20),

          // ── Divider ───────────────────────────────────────────
          Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  KinrelColors.orange.withValues(alpha: 0.2),
                  Colors.transparent,
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── Full path description ─────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: KinrelColors.darkElevated.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(KinrelRadius.sm),
            ),
            child: Text(
              result.relationshipDescription,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: KinrelColors.orange,
                height: 1.4,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Audio + Generation + Degree row ───────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Audio pronunciation button
              _InfoChip(
                icon: Icons.volume_up_outlined,
                label: 'Listen',
                onTap: () {
                  // TODO: implement audio pronunciation
                },
                isButton: true,
              ),
              const SizedBox(width: 10),

              // Generation difference
              _InfoChip(
                icon: Icons.vertical_align_center,
                label: _formatGeneration(generationDiff),
              ),
              const SizedBox(width: 10),

              // Degree of relation
              _InfoChip(
                icon: Icons.device_hub_outlined,
                label: '${degreeOfRelation ?? result.length}${_ordinalSuffix(degreeOfRelation ?? result.length)} degree',
              ),
            ],
          ),

          // ── Cultural note ─────────────────────────────────────
          if (culturalNote != null && culturalNote.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: KinrelColors.orange.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(KinrelRadius.sm),
                border: Border.all(
                  color: KinrelColors.orange.withValues(alpha: 0.12),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.auto_stories_outlined,
                      size: 16, color: KinrelColors.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      culturalNote,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: KinrelColors.textSilver,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatGeneration(int? diff) {
    if (diff == null || diff == 0) return 'Same generation';
    if (diff > 0) return '+$diff generation';
    return '$diff generation';
  }

  String _ordinalSuffix(int n) {
    if (n >= 11 && n <= 13) return 'th';
    switch (n % 10) {
      case 1:
        return 'st';
      case 2:
        return 'nd';
      case 3:
        return 'rd';
      default:
        return 'th';
    }
  }
}

// ────────────────────────────────────────────────────────────────
// Info Chip (used in hero card)
// ────────────────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    this.onTap,
    this.isButton = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isButton;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isButton
              ? KinrelColors.orange.withValues(alpha: 0.12)
              : KinrelColors.darkElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isButton
                ? KinrelColors.orange.withValues(alpha: 0.25)
                : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 13,
                color: isButton ? KinrelColors.orange : KinrelColors.textDim),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: isButton ? KinrelColors.orange : KinrelColors.textSilver,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────
// Same Person Edge Case Card
// ────────────────────────────────────────────────────────────────

class _SamePersonCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(KinrelSpacing.xl),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: KinrelColors.orange.withValues(alpha: 0.12),
              border: Border.all(
                color: KinrelColors.orange.withValues(alpha: 0.3),
              ),
            ),
            child: const Icon(
              Icons.sentiment_satisfied_alt_outlined,
              size: 28,
              color: KinrelColors.orange,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            "That's you! 👋",
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'You selected the same person twice.\nPick two different people to find their relationship.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              color: KinrelColors.textSilver,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────
// No Path Edge Case Card
// ────────────────────────────────────────────────────────────────

class _NoPathCard extends StatelessWidget {
  const _NoPathCard({required this.onAddConnection});

  final VoidCallback onAddConnection;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(KinrelSpacing.xl),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: KinrelColors.darkElevated,
              border: Border.all(
                color: KinrelColors.textDim.withValues(alpha: 0.2),
              ),
            ),
            child: Icon(
              Icons.link_off_outlined,
              size: 28,
              color: KinrelColors.textDim,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'No connection found',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Are they in the same family?\nAdd a relationship to connect them.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              color: KinrelColors.textSilver,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: onAddConnection,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: KinrelColors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: KinrelColors.orange.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_link, size: 16, color: KinrelColors.orange),
                  const SizedBox(width: 6),
                  Text(
                    'Add Connection',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.orange,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────
// Person Selector Bottom Sheet
// ────────────────────────────────────────────────────────────────

class _PersonSelectorSheet extends ConsumerStatefulWidget {
  const _PersonSelectorSheet({
    required this.members,
    required this.personMap,
    required this.currentlySelectedId,
    this.otherSelectedId,
    required this.onSelected,
  });

  final List<Person> members;
  final Map<String, Person> personMap;
  final String? currentlySelectedId;
  final String? otherSelectedId;
  final ValueChanged<String> onSelected;

  @override
  ConsumerState<_PersonSelectorSheet> createState() =>
      _PersonSelectorSheetState();
}

class _PersonSelectorSheetState extends ConsumerState<_PersonSelectorSheet> {
  String _searchQuery = '';

  List<Person> get _filteredMembers {
    if (_searchQuery.isEmpty) return widget.members;
    final q = _searchQuery.toLowerCase();
    return widget.members
        .where((p) => p.name.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredMembers;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      padding: EdgeInsets.only(bottom: bottomPadding + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: KinrelColors.textDim.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KinrelSpacing.base,
              vertical: KinrelSpacing.sm,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: KinrelColors.darkElevated,
                borderRadius: BorderRadius.circular(KinrelRadius.md),
              ),
              child: Row(
                children: [
                  Icon(Icons.search,
                      size: 20, color: KinrelColors.orange),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      autofocus: true,
                      onChanged: (v) =>
                          setState(() => _searchQuery = v),
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 14,
                        color: KinrelColors.textWhite,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search family members...',
                        hintStyle: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 14,
                          color: KinrelColors.textDim,
                        ),
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 4),

          // Member list
          Flexible(
            child: filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'No members found',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 14,
                        color: KinrelColors.textDim,
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const ClampingScrollPhysics(),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final person = filtered[index];
                      final isSelected =
                          person.id == widget.currentlySelectedId;
                      final isOther =
                          person.id == widget.otherSelectedId;

                      return _PersonListTile(
                        person: person,
                        isSelected: isSelected,
                        isOther: isOther,
                        onTap: () => widget.onSelected(person.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _PersonListTile extends StatelessWidget {
  const _PersonListTile({
    required this.person,
    required this.isSelected,
    required this.isOther,
    required this.onTap,
  });

  final Person person;
  final bool isSelected;
  final bool isOther;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final initial = person.name.isNotEmpty ? person.name[0].toUpperCase() : '?';

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.base,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? KinrelColors.orange.withValues(alpha: 0.08)
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: Colors.white.withValues(alpha: 0.04),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? KinrelColors.orange.withValues(alpha: 0.15)
                    : KinrelColors.darkElevated,
                border: Border.all(
                  color: isSelected
                      ? KinrelColors.orange
                      : KinrelColors.textDim.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: Center(
                child: Text(
                  initial,
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? KinrelColors.orange
                        : KinrelColors.textSilver,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Name + gender
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    person.name,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? KinrelColors.textWhite
                          : KinrelColors.textSilver,
                    ),
                  ),
                  if (person.gender != null) ...[
                    const SizedBox(height: 1),
                    Text(
                      person.gender!.capitalize(),
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 11,
                        color: KinrelColors.textDim,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Selected checkmark or "other" badge
            if (isSelected)
              Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: KinrelColors.orange,
                ),
                child: const Icon(
                  Icons.check,
                  size: 14,
                  color: Colors.white,
                ),
              )
            else if (isOther)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: KinrelColors.darkElevated,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Selected',
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 9,
                    color: KinrelColors.textDim,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────
// Empty State
// ────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KinrelSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KinrelColors.orange.withValues(alpha: 0.08),
              ),
              child: Icon(
                Icons.route,
                size: 36,
                color: KinrelColors.orange.withValues(alpha: 0.4),
              ),
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
              'Add family members first to find\nrelationship paths between them.',
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

// ────────────────────────────────────────────────────────────────
// String extension for capitalize
// ────────────────────────────────────────────────────────────────

extension _StringCapitalize on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}

// ────────────────────────────────────────────────────────────────
// AnimatedBuilder helper (using standard Flutter AnimatedBuilder)
// ────────────────────────────────────────────────────────────────
// Note: Flutter's AnimatedBuilder is used directly — no custom widget needed.
