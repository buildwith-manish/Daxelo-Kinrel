import 'package:kinrel/core/widgets/global_error_widget.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_typography.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/kinship/kinship_provider.dart';
import 'family_tree_painter.dart';
import 'family_tree_model.dart';

/// Pixel-perfect family tree screen that renders the Daxelo Kinrel graph
/// using real family data from Supabase + KinshipService for Hindi labels.
///
/// Accepts an optional [familyId]; if null, falls back to the first family.
class FamilyTreeScreen extends ConsumerStatefulWidget {
  const FamilyTreeScreen({super.key, this.familyId});

  final String? familyId;

  @override
  ConsumerState<FamilyTreeScreen> createState() => _FamilyTreeScreenState();
}

class _FamilyTreeScreenState extends ConsumerState<FamilyTreeScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _lineController;
  bool _focusMode = false;

  // Pan & zoom
  final TransformationController _transformController =
      TransformationController();

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _lineController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    // Ensure kinship data is loaded for Hindi labels
    ref.read(kinshipInitializedProvider.future);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _lineController.dispose();
    _transformController.dispose();
    super.dispose();
  }

  // ── Layout algorithm ─────────────────────────────────────────

  /// Compute positions for a hierarchical tree layout.
  /// Groups members by generation, centers each row.
  ({List<FamilyMember> members, List<FamilyConnection> connections, Size size})
      _buildLayout(FamilyDetail detail) {
    final kinshipService = ref.read(kinshipServiceProvider);
    final members = detail.members.where((p) => p.deletedAt == null).toList();
    final relationships = detail.relationships;

    if (members.isEmpty) {
      return (members: [], connections: [], size: Size.zero);
    }

    // Build generation map
    final generationMap = <String, int>{};
    final childOf = <String, String>{};
    final spouseOf = <String, String>{};

    for (final rel in relationships) {
      final type = rel.relationshipKey.toLowerCase();
      if (['child', 'son', 'daughter'].contains(type)) {
        childOf[rel.fromPersonId] = rel.toPersonId;
      } else if (['father', 'mother', 'parent'].contains(type)) {
        childOf[rel.toPersonId] = rel.fromPersonId;
      } else if (['spouse', 'husband', 'wife'].contains(type)) {
        spouseOf[rel.fromPersonId] = rel.toPersonId;
        spouseOf[rel.toPersonId] = rel.fromPersonId;
      }
    }

    // Assign generations starting from roots
    for (final p in members) {
      if (p.generationIndex > 0) {
        generationMap[p.id] = p.generationIndex;
      }
    }

    // For members without generation, compute from tree structure
    void assignGeneration(String id, int gen) {
      if (generationMap.containsKey(id)) return;
      generationMap[id] = gen;
      // Find children
      for (final entry in childOf.entries) {
        if (entry.value == id) {
          assignGeneration(entry.key, gen + 1);
        }
      }
    }

    // Find roots (no parent)
    final roots = members
        .where((p) => !childOf.containsKey(p.id))
        .toList();
    for (final root in roots) {
      assignGeneration(root.id, generationMap[root.id] ?? 1);
    }
    // Assign remaining
    for (final p in members) {
      generationMap.putIfAbsent(p.id, () => 1);
    }

    // Group by generation
    final byGen = <int, List<Person>>{};
    for (final p in members) {
      final gen = generationMap[p.id] ?? 1;
      byGen.putIfAbsent(gen, () => []).add(p);
    }

    // Sort generations
    final sortedGens = byGen.keys.toList()..sort();

    // Compute positions
    const double nodeSpacingX = 140.0;
    const double rowHeight = 180.0;
    const double startY = 120.0;
    const double canvasWidth = 600.0;

    final positions = <String, Offset>{};

    for (final gen in sortedGens) {
      final genMembers = byGen[gen]!;
      final totalWidth = (genMembers.length - 1) * nodeSpacingX;
      final startX = (canvasWidth - totalWidth) / 2;

      for (int i = 0; i < genMembers.length; i++) {
        positions[genMembers[i].id] = Offset(
          startX + i * nodeSpacingX,
          startY + (gen - 1) * rowHeight,
        );
      }
    }

    // Build connections from relationships
    final connections = <FamilyConnection>[];
    for (final rel in relationships) {
      if (!positions.containsKey(rel.fromPersonId) ||
          !positions.containsKey(rel.toPersonId)) continue;
      connections.add(FamilyConnection(
        fromId: rel.fromPersonId,
        toId: rel.toPersonId,
      ));
    }

    // Find anchor person ID
    final anchorId = detail.family.anchorPersonId;

    // Build FamilyMember list with kinship labels
    final familyMembers = <FamilyMember>[];
    for (final p in members) {
      final pos = positions[p.id] ?? const Offset(300, 300);
      final isSelf = p.id == anchorId || p.isAnchor;

      // Find the relationship key from the anchor to this person
      String role = 'Member';
      String nickname = '';

      // Look for a relationship involving this person
      for (final rel in relationships) {
        if (rel.fromPersonId == p.id || rel.toPersonId == p.id) {
          final key = rel.relationshipKey;
          // Get English term
          final kinshipRel = kinshipService.getRelationship(key);
          if (kinshipRel != null) {
            role = kinshipRel.englishTerm;
            // Get Hindi translation for nickname
            final hindiTranslation =
                kinshipService.getKinshipTerm(key, 'hindi');
            if (hindiTranslation != null) {
              nickname = hindiTranslation.native;
            }
          } else {
            role = key.replaceAll('_', ' ').split(' ').map((w) =>
                w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}'
            ).join(' ');
          }
          break;
        }
      }

      if (isSelf) {
        role = 'Self';
        nickname = 'You';
      }

      familyMembers.add(FamilyMember(
        id: p.id,
        name: p.name,
        role: role,
        nickname: nickname,
        position: pos,
        photoUrl: p.photoUrl,
        isSelf: isSelf,
      ));
    }

    // Compute canvas size
    double maxX = 0, maxY = 0;
    for (final pos in positions.values) {
      if (pos.dx > maxX) maxX = pos.dx;
      if (pos.dy > maxY) maxY = pos.dy;
    }
    final canvasSize = Size(
      math.max(canvasWidth, maxX + 100),
      math.max(720, maxY + 200),
    );

    return (members: familyMembers, connections: connections, size: canvasSize);
  }

  @override
  Widget build(BuildContext context) {
    // Resolve familyId — use provided or first available
    final familyId = widget.familyId;
    final detailAsync = familyId != null
        ? ref.watch(familyDetailProvider(familyId))
        : null;

    // If no familyId provided, try to get first family
    if (familyId == null) {
      final familiesAsync = ref.watch(familyListProvider);
      return Scaffold(
        backgroundColor: const Color(0xFF0A0E1A),
        body: familiesAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: Color(0xFF4FC3F7)),
          ),
          error: (e, _) => Center(
            child: Text(
              'Error loading families',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          data: (families) {
            if (families.isEmpty) {
              return Center(
                child: Text(
                  'No families yet.\nCreate or join a family first.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
              );
            }
            // Redirect to this screen with the first family's ID
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                context.go('/family-tree?familyId=${families.first.id}');
              }
            });
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF4FC3F7)),
            );
          },
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: detailAsync == null
          ? const Center(child: Text('Loading...', style: TextStyle(color: Colors.white70)))
          : detailAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: Color(0xFF4FC3F7)),
              ),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 48,
                          color: Colors.white54),
                      SizedBox(height: 12),
                      Text(
                        'Failed to load family tree',
                        style: TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                      SizedBox(height: 8),
                      Text(
                        e.toString(),
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              data: (detail) {
                if (detail == null) {
                  return Center(
                    child: Text(
                      'Family not found',
                      style: TextStyle(color: Colors.white70),
                    ),
                  );
                }
                return _buildTreeContent(detail);
              },
            ),
    );
  }

  Widget _buildTreeContent(FamilyDetail detail) {
    final layout = _buildLayout(detail);

    if (layout.members.isEmpty) {
      return Center(
        child: Text(
          'No members yet',
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
      );
    }

    return Stack(
      children: [
        // ── World map faded background ──────────────────────────
        Positioned.fill(
          child: Opacity(
            opacity: 0.08,
            child: Image.network(
              'https://upload.wikimedia.org/wikipedia/commons/thumb/8/80/World_map_-_low_resolution.svg/1280px-World_map_-_low_resolution.svg.png',
              fit: BoxFit.cover,
              color: const Color(0xFF4FC3F7),
              colorBlendMode: BlendMode.srcIn,
              errorBuilder: (_, __, ___) => Container(
                color: const Color(0xFF0A0E1A),
              ),
            ),
          ),
        ),

        // ── Graph canvas ────────────────────────────────────────
        InteractiveViewer(
          transformationController: _transformController,
          minScale: 0.5,
          maxScale: 3.0,
          boundaryMargin: const EdgeInsets.all(400),
          child: KinrelAnimatedBuilder(
            animation: Listenable.merge([_pulseController, _lineController]),
            builder: (context, _) {
              return CustomPaint(
                size: layout.size,
                painter: FamilyTreePainter(
                  members: layout.members,
                  connections: layout.connections,
                  pulseValue: _pulseController.value,
                  lineProgress: _lineController.value,
                  focusMode: _focusMode,
                ),
              );
            },
          ),
        ),

        // ── Top bar ─────────────────────────────────────────────
        SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => context.pop(),
                  child: const Icon(Icons.arrow_back_ios,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    detail.family.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                      fontFamily: KinrelTypography.displayFont,
                    ),
                  ),
                ),
                // Focus mode toggle
                GestureDetector(
                  onTap: () => setState(() => _focusMode = !_focusMode),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.2), width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _focusMode
                              ? Icons.visibility
                              : Icons.visibility_off,
                          color: Colors.white70,
                          size: 14,
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          'Focus Mode',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.person_outline,
                    color: Colors.white70, size: 22),
              ],
            ),
          ),
        ),

        // ── Member count badge ────────────────────────────────
        Positioned(
          bottom: 24,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0E1A).withOpacity(0.85),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFF4FC3F7).withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Text(
                '${detail.members.where((p) => p.deletedAt == null).length} members · ${detail.relationships.length} links',
                style: const TextStyle(
                  color: Color(0xFF4FC3F7),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
