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

  /// Compute positions for a radial/spoke layout with the anchor
  /// person at the exact center and all other members orbiting in
  /// concentric rings — parents above, siblings left/right, children
  /// below, spouse directly to the right.
  ({List<FamilyMember> members, List<FamilyConnection> connections, Size size})
      _buildLayout(FamilyDetail detail) {
    final kinshipService = ref.read(kinshipServiceProvider);
    final members = detail.members.where((p) => p.deletedAt == null).toList();
    final relationships = detail.relationships;

    if (members.isEmpty) {
      return (members: [], connections: [], size: Size.zero);
    }

    // ── 1. Find anchor person ────────────────────────────────────
    final anchorId = detail.family.anchorPersonId;
    final anchor = members.firstWhere(
      (p) => p.isAnchor || p.id == anchorId,
      orElse: () => members.first,
    );

    // ── 2. Build adjacency maps ──────────────────────────────────
    final parentOf = <String, List<String>>{};
    final childOf = <String, List<String>>{};
    final spouseOf = <String, String?>{};
    final siblingOf = <String, List<String>>{};

    for (final rel in relationships) {
      final type = rel.relationshipKey.toLowerCase();
      final fromId = rel.fromPersonId;
      final toId = rel.toPersonId;
      if (!members.any((m) => m.id == fromId) ||
          !members.any((m) => m.id == toId)) continue;

      if (['father', 'mother', 'parent'].contains(type)) {
        parentOf.putIfAbsent(toId, () => []).add(fromId);
        childOf.putIfAbsent(fromId, () => []).add(toId);
      } else if (['child', 'son', 'daughter'].contains(type)) {
        parentOf.putIfAbsent(fromId, () => []).add(toId);
        childOf.putIfAbsent(toId, () => []).add(fromId);
      } else if (['spouse', 'husband', 'wife'].contains(type)) {
        spouseOf[fromId] = toId;
        spouseOf[toId] = fromId;
      } else if (['brother', 'sister', 'sibling'].contains(type)) {
        siblingOf.putIfAbsent(fromId, () => []).add(toId);
        siblingOf.putIfAbsent(toId, () => []).add(fromId);
      }
    }

    // ── 3. BFS generation assignment ─────────────────────────────
    final generationMap = <String, int>{};
    final visited = <String>{};
    final queue = <({String id, int gen})>[];
    generationMap[anchor.id] = 3;
    visited.add(anchor.id);
    queue.add((id: anchor.id, gen: 3));

    while (queue.isNotEmpty) {
      final item = queue.removeAt(0);
      for (final pid in parentOf[item.id] ?? []) {
        if (!visited.contains(pid)) {
          visited.add(pid);
          generationMap[pid] = item.gen - 1;
          queue.add((id: pid, gen: item.gen - 1));
        }
      }
      for (final cid in childOf[item.id] ?? []) {
        if (!visited.contains(cid)) {
          visited.add(cid);
          generationMap[cid] = item.gen + 1;
          queue.add((id: cid, gen: item.gen + 1));
        }
      }
      final sid = spouseOf[item.id];
      if (sid != null && !visited.contains(sid)) {
        visited.add(sid);
        generationMap[sid] = item.gen;
        queue.add((id: sid, gen: item.gen));
      }
      for (final sib in siblingOf[item.id] ?? []) {
        if (!visited.contains(sib)) {
          visited.add(sib);
          generationMap[sib] = item.gen;
          queue.add((id: sib, gen: item.gen));
        }
      }
    }
    for (final m in members) {
      if (!visited.contains(m.id)) {
        generationMap[m.id] = m.generationIndex > 0 ? m.generationIndex : 3;
        visited.add(m.id);
      }
    }

    // ── 4. Place anchor at exact center ──────────────────────────
    const double canvasW = 900.0;
    const double canvasH = 900.0;
    const Offset center = Offset(canvasW / 2, canvasH / 2);
    const double orbit1 = 200.0; // parents / siblings / spouse
    const double orbit2 = 380.0; // grandparents / children
    const double orbit3 = 540.0; // great-grandparents / grandchildren

    final positions = <String, Offset>{};
    positions[anchor.id] = center;

    // ── 5. Bucket non-anchor nodes by genDiff ────────────────────
    final above1 = <String>[]; // genDiff == -1 (parents)
    final above2 = <String>[]; // genDiff == -2 (grandparents)
    final above3 = <String>[]; // genDiff <= -3
    final sameLevel = <String>[]; // genDiff == 0, not anchor (siblings + spouse)
    final below1 = <String>[]; // genDiff == +1 (children)
    final below2 = <String>[]; // genDiff == +2
    final below3 = <String>[]; // genDiff >= +3

    for (final m in members) {
      if (m.id == anchor.id) continue;
      final genDiff = (generationMap[m.id] ?? 3) - 3;
      if (genDiff == -1) above1.add(m.id);
      else if (genDiff == -2) above2.add(m.id);
      else if (genDiff <= -3) above3.add(m.id);
      else if (genDiff == 0) sameLevel.add(m.id);
      else if (genDiff == 1) below1.add(m.id);
      else if (genDiff == 2) below2.add(m.id);
      else below3.add(m.id);
    }

    // ── Helper: place nodes in a semi-circular arc ───────────────
    void placeArc(List<String> ids, double radius,
        {double startAngle = -math.pi, double endAngle = 0}) {
      if (ids.isEmpty) return;
      if (ids.length == 1) {
        final angle = (startAngle + endAngle) / 2;
        positions[ids[0]] = Offset(
            center.dx + radius * math.cos(angle),
            center.dy + radius * math.sin(angle));
        return;
      }
      final step = (endAngle - startAngle) / (ids.length - 1);
      for (int i = 0; i < ids.length; i++) {
        final angle = startAngle + i * step;
        positions[ids[i]] = Offset(
            center.dx + radius * math.cos(angle),
            center.dy + radius * math.sin(angle));
      }
    }

    // ── 6. Place spouse adjacent to anchor (right side) ──────────
    final anchorSpouseId = spouseOf[anchor.id];
    if (anchorSpouseId != null && sameLevel.contains(anchorSpouseId)) {
      positions[anchorSpouseId] = Offset(center.dx + orbit1, center.dy);
      sameLevel.remove(anchorSpouseId);
    }

    // ── 7. Siblings: left side arc ───────────────────────────────
    if (sameLevel.isNotEmpty) {
      if (sameLevel.length == 1) {
        positions[sameLevel[0]] = Offset(center.dx - orbit1, center.dy);
      } else {
        placeArc(sameLevel, orbit1,
            startAngle: math.pi * 0.65, endAngle: math.pi * 1.35);
      }
    }

    // ── 8. Parents: upper arc ────────────────────────────────────
    if (above1.isNotEmpty) {
      if (above1.length <= 2) {
        placeArc(above1, orbit1,
            startAngle: -math.pi * 0.75, endAngle: -math.pi * 0.25);
      } else {
        placeArc(above1, orbit1,
            startAngle: -math.pi * 0.9, endAngle: -math.pi * 0.1);
      }
    }

    // ── 9. Grandparents: orbit2 upper arc ────────────────────────
    if (above2.isNotEmpty) {
      placeArc(above2, orbit2,
          startAngle: -math.pi * 0.85, endAngle: -math.pi * 0.15);
    }

    // ── 10. Great-grandparents: orbit3 upper arc ─────────────────
    if (above3.isNotEmpty) {
      placeArc(above3, orbit3,
          startAngle: -math.pi * 0.85, endAngle: -math.pi * 0.15);
    }

    // ── 11. Children: lower arc ──────────────────────────────────
    if (below1.isNotEmpty) {
      if (below1.length == 1) {
        positions[below1[0]] = Offset(center.dx, center.dy + orbit1);
      } else {
        placeArc(below1, orbit1,
            startAngle: math.pi * 0.15, endAngle: math.pi * 0.85);
      }
    }

    // ── 12. Grandchildren: orbit2 lower arc ──────────────────────
    if (below2.isNotEmpty) {
      placeArc(below2, orbit2,
          startAngle: math.pi * 0.15, endAngle: math.pi * 0.85);
    }

    // ── 13. Great-grandchildren: orbit3 lower arc ────────────────
    if (below3.isNotEmpty) {
      placeArc(below3, orbit3,
          startAngle: math.pi * 0.15, endAngle: math.pi * 0.85);
    }

    // ── 14. Compute final canvas bounds with padding ─────────────
    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    for (final pos in positions.values) {
      if (pos.dx < minX) minX = pos.dx;
      if (pos.dy < minY) minY = pos.dy;
      if (pos.dx > maxX) maxX = pos.dx;
      if (pos.dy > maxY) maxY = pos.dy;
    }

    const double padding = 120.0;
    final finalW = math.max(maxX - minX + padding * 2, canvasW);
    final finalH = math.max(maxY - minY + padding * 2, canvasH);

    // Shift all positions so no negative coords and anchor is centered
    final shiftX = finalW / 2 - center.dx;
    final shiftY = finalH / 2 - center.dy;
    final shiftedPositions = <String, Offset>{};
    for (final entry in positions.entries) {
      shiftedPositions[entry.key] =
          Offset(entry.value.dx + shiftX, entry.value.dy + shiftY);
    }

    // ── 15. Build connections (deduplicated) ─────────────────────
    final connections = <FamilyConnection>[];
    final edgeSet = <String>{};
    for (final rel in relationships) {
      final fromId = rel.fromPersonId;
      final toId = rel.toPersonId;
      if (!shiftedPositions.containsKey(fromId) ||
          !shiftedPositions.containsKey(toId)) continue;
      final key1 = '$fromId-$toId';
      final key2 = '$toId-$fromId';
      if (edgeSet.contains(key1) || edgeSet.contains(key2)) continue;
      connections.add(FamilyConnection(fromId: fromId, toId: toId));
      edgeSet.add(key1);
      edgeSet.add(key2);
    }

    // ── 16. Build FamilyMember list with kinship labels ──────────
    final familyMembers = <FamilyMember>[];
    for (final p in members) {
      final pos = shiftedPositions[p.id] ?? center;
      final isSelf = p.id == anchor.id;

      String role = 'Member';
      String nickname = '';

      for (final rel in relationships) {
        if (rel.fromPersonId == p.id || rel.toPersonId == p.id) {
          final key = rel.relationshipKey;
          final kinshipRel = kinshipService.getRelationship(key);
          if (kinshipRel != null) {
            role = kinshipRel.englishTerm;
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
        nodeScale: isSelf ? 1.15 : 1.0,
      ));
    }

    return (members: familyMembers, connections: connections, size: Size(finalW, finalH));
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
