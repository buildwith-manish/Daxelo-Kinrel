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
  final TransformationController _transformController = TransformationController();

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
    ref.read(kinshipInitializedProvider.future);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _lineController.dispose();
    _transformController.dispose();
    super.dispose();
  }

  // ── Normalize relationship key to lowercase, no spaces ──────────────
  String _normKey(String key) => key.toLowerCase().trim().replaceAll(' ', '_');

  bool _isParentRel(String key) {
    final k = _normKey(key);
    return k == 'father' || k == 'mother' || k == 'parent' ||
        k == 'father_in_law' || k == 'mother_in_law';
  }

  bool _isChildRel(String key) {
    final k = _normKey(key);
    return k == 'child' || k == 'son' || k == 'daughter' ||
        k == 'son_in_law' || k == 'daughter_in_law';
  }

  bool _isSpouseRel(String key) {
    final k = _normKey(key);
    return k == 'spouse' || k == 'husband' || k == 'wife';
  }

  bool _isSiblingRel(String key) {
    final k = _normKey(key);
    return k == 'brother' || k == 'sister' || k == 'sibling' ||
        k == 'brother_in_law' || k == 'sister_in_law';
  }

  // ── Layout: anchor center, radial spokes ───────────────────────────
  ({List<FamilyMember> members, List<FamilyConnection> connections, Size size})
      _buildLayout(FamilyDetail detail) {
    final kinshipService = ref.read(kinshipServiceProvider);
    final allMembers = detail.members.where((p) => p.deletedAt == null).toList();
    final relationships = detail.relationships.where((r) => r.isActive).toList();

    if (allMembers.isEmpty) {
      return (members: [], connections: [], size: Size.zero);
    }

    // 1. Find anchor
    final anchorId = detail.family.anchorPersonId;
    final anchor = allMembers.firstWhere(
      (p) => p.isAnchor == true || p.id == anchorId,
      orElse: () => allMembers.first,
    );

    // 2. Build relationship maps ONLY for relationships touching the anchor
    //    directly — this determines who goes where relative to the anchor.
    //    For all others we fall back to generationIndex or treat as sibling.

    // Maps: personId -> relationship TYPE relative to anchor
    // Types: 'parent', 'child', 'spouse', 'sibling', 'other'
    final relTypeToAnchor = <String, String>{};

    for (final rel in relationships) {
      final from = rel.fromPersonId;
      final to = rel.toPersonId;
      final key = rel.relationshipKey;

      if (from == anchor.id && to != anchor.id) {
        // anchor → other
        if (_isParentRel(key)) {
          // anchor IS the child, other IS the parent
          // e.g. rel says "anchor's father is X" → X is a parent
          relTypeToAnchor[to] = 'parent';
        } else if (_isChildRel(key)) {
          relTypeToAnchor[to] = 'child';
        } else if (_isSpouseRel(key)) {
          relTypeToAnchor[to] = 'spouse';
        } else if (_isSiblingRel(key)) {
          relTypeToAnchor[to] = 'sibling';
        } else {
          relTypeToAnchor.putIfAbsent(to, () => 'other');
        }
      } else if (to == anchor.id && from != anchor.id) {
        // other → anchor
        if (_isParentRel(key)) {
          // other claims to BE a parent of anchor
          relTypeToAnchor[from] = 'parent';
        } else if (_isChildRel(key)) {
          relTypeToAnchor[from] = 'child';
        } else if (_isSpouseRel(key)) {
          relTypeToAnchor[from] = 'spouse';
        } else if (_isSiblingRel(key)) {
          relTypeToAnchor[from] = 'sibling';
        } else {
          relTypeToAnchor.putIfAbsent(from, () => 'other');
        }
      }
    }

    // For members not directly connected to anchor, check generationIndex
    for (final m in allMembers) {
      if (m.id == anchor.id) continue;
      if (!relTypeToAnchor.containsKey(m.id)) {
        if (m.generationIndex > 0) {
          final anchorGen = anchor.generationIndex > 0 ? anchor.generationIndex : 3;
          final diff = m.generationIndex - anchorGen;
          if (diff < 0) relTypeToAnchor[m.id] = 'parent';
          else if (diff > 0) relTypeToAnchor[m.id] = 'child';
          else relTypeToAnchor[m.id] = 'sibling';
        } else {
          relTypeToAnchor[m.id] = 'other';
        }
      }
    }

    // 3. Bucket by role
    final parents  = <String>[];
    final children = <String>[];
    final spouses  = <String>[];
    final siblings = <String>[];
    final others   = <String>[];

    for (final m in allMembers) {
      if (m.id == anchor.id) continue;
      switch (relTypeToAnchor[m.id] ?? 'other') {
        case 'parent':  parents.add(m.id);  break;
        case 'child':   children.add(m.id); break;
        case 'spouse':  spouses.add(m.id);  break;
        case 'sibling': siblings.add(m.id); break;
        default:        others.add(m.id);   break;
      }
    }

    // 4. Radial positions
    //    Canvas: 900×900, anchor at center (450, 450)
    const double cw = 900.0;
    const double ch = 900.0;
    const Offset center = Offset(cw / 2, ch / 2);
    const double r1 = 200.0; // first orbit
    const double r2 = 370.0; // second orbit (grandparents etc.)

    final positions = <String, Offset>{};
    positions[anchor.id] = center;

    // Helper: place N nodes in an arc between startDeg and endDeg at radius r
    void placeArc(List<String> ids, double radius, double startDeg, double endDeg) {
      if (ids.isEmpty) return;
      if (ids.length == 1) {
        final mid = (startDeg + endDeg) / 2 * math.pi / 180;
        positions[ids[0]] = Offset(
          center.dx + radius * math.cos(mid),
          center.dy + radius * math.sin(mid),
        );
        return;
      }
      final step = (endDeg - startDeg) / (ids.length - 1);
      for (int i = 0; i < ids.length; i++) {
        final angle = (startDeg + i * step) * math.pi / 180;
        positions[ids[i]] = Offset(
          center.dx + radius * math.cos(angle),
          center.dy + radius * math.sin(angle),
        );
      }
    }

    // Spouse: directly right of anchor
    if (spouses.isNotEmpty) {
      positions[spouses[0]] = Offset(center.dx + r1, center.dy);
      // if multiple spouses (rare), fan them slightly
      for (int i = 1; i < spouses.length; i++) {
        final angle = (-20 + i * 40) * math.pi / 180;
        positions[spouses[i]] = Offset(
          center.dx + r1 * math.cos(angle),
          center.dy + r1 * math.sin(angle),
        );
      }
    }

    // Parents: upper arc  (-150° to -30°  = upper-left to upper-right)
    placeArc(parents, r1, -150, -30);

    // Siblings: left arc  (120° to 240° = lower-left through left to upper-left)
    placeArc(siblings, r1, 120, 240);

    // Children: lower arc (30° to 150° = lower-right to lower-left)
    placeArc(children, r1, 30, 150);

    // Others: spread on outer orbit, top-right quadrant
    placeArc(others, r2, -90, 0);

    // 5. Compute canvas bounds and shift so no negative coords
    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    for (final p in positions.values) {
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }
    const double pad = 130.0;
    final finalW = math.max(maxX - minX + pad * 2, cw);
    final finalH = math.max(maxY - minY + pad * 2, ch);

    // Shift so anchor ends up at true center of final canvas
    final dx = finalW / 2 - center.dx;
    final dy = finalH / 2 - center.dy;
    final shifted = <String, Offset>{};
    for (final e in positions.entries) {
      shifted[e.key] = Offset(e.value.dx + dx, e.value.dy + dy);
    }

    // 6. Build connections (deduplicated)
    final connections = <FamilyConnection>[];
    final seen = <String>{};
    for (final rel in relationships) {
      final f = rel.fromPersonId;
      final t = rel.toPersonId;
      if (!shifted.containsKey(f) || !shifted.containsKey(t)) continue;
      final k1 = '$f|$t';
      final k2 = '$t|$f';
      if (seen.contains(k1) || seen.contains(k2)) continue;
      seen.add(k1);
      seen.add(k2);
      connections.add(FamilyConnection(fromId: f, toId: t));
    }

    // 7. Build FamilyMember list with kinship labels
    final familyMembers = <FamilyMember>[];
    for (final p in allMembers) {
      final pos = shifted[p.id] ?? (Offset(finalW / 2, finalH / 2));
      final isSelf = p.id == anchor.id;

      String role = '';
      String nickname = '';

      if (isSelf) {
        role = 'You';
        nickname = '';
      } else {
        // Find the relationship involving this person and anchor
        FamilyRelationship? directRel;
        for (final rel in relationships) {
          if ((rel.fromPersonId == anchor.id && rel.toPersonId == p.id) ||
              (rel.toPersonId == anchor.id && rel.fromPersonId == p.id)) {
            directRel = rel;
            break;
          }
        }

        if (directRel != null) {
          final key = directRel.relationshipKey;
          final kinshipRel = kinshipService.getRelationship(key);
          if (kinshipRel != null) {
            role = kinshipRel.englishTerm;
            final hindiTranslation = kinshipService.getKinshipTerm(key, 'hindi');
            if (hindiTranslation != null) nickname = hindiTranslation.native;
          } else {
            role = key.replaceAll('_', ' ').split(' ').map((w) =>
                w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
          }
        } else {
          // Fallback: use bucketed type
          final t = relTypeToAnchor[p.id] ?? 'Member';
          role = t[0].toUpperCase() + t.substring(1);
        }
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

    return (
      members: familyMembers,
      connections: connections,
      size: Size(finalW, finalH),
    );
  }

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
          loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFF4FC3F7))),
          error: (e, _) => const Center(child: Text('Error loading families', style: TextStyle(color: Colors.white70))),
          data: (families) {
            if (families.isEmpty) {
              return const Center(
                child: Text('No families yet.\nCreate or join a family first.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 16)),
              );
            }
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) context.go('/family-tree?familyId=${families.first.id}');
            });
            return const Center(child: CircularProgressIndicator(color: Color(0xFF4FC3F7)));
          },
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: detailAsync == null
          ? const Center(child: Text('Loading...', style: TextStyle(color: Colors.white70)))
          : detailAsync.when(
              loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFF4FC3F7))),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.white54),
                      const SizedBox(height: 12),
                      const Text('Failed to load family tree', style: TextStyle(color: Colors.white70, fontSize: 16)),
                      const SizedBox(height: 8),
                      Text(e.toString(), style: const TextStyle(color: Colors.white38, fontSize: 12), textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
              data: (detail) {
                if (detail == null) {
                  return const Center(child: Text('Family not found', style: TextStyle(color: Colors.white70)));
                }
                return _buildTreeContent(detail);
              },
            ),
    );
  }

  Widget _buildTreeContent(FamilyDetail detail) {
    final layout = _buildLayout(detail);
    if (layout.members.isEmpty) {
      return const Center(child: Text('No members yet', style: TextStyle(color: Colors.white70, fontSize: 16)));
    }

    return Stack(
      children: [
        Positioned.fill(
          child: Opacity(
            opacity: 0.08,
            child: Image.network(
              'https://upload.wikimedia.org/wikipedia/commons/thumb/8/80/World_map_-_low_resolution.svg/1280px-World_map_-_low_resolution.svg.png',
              fit: BoxFit.cover,
              color: const Color(0xFF4FC3F7),
              colorBlendMode: BlendMode.srcIn,
              errorBuilder: (_, __, ___) => Container(color: const Color(0xFF0A0E1A)),
            ),
          ),
        ),
        InteractiveViewer(
          transformationController: _transformController,
          minScale: 0.3,
          maxScale: 3.0,
          boundaryMargin: const EdgeInsets.all(500),
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
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => context.pop(),
                  child: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    detail.family.name,
                    style: const TextStyle(
                      color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600,
                      letterSpacing: 0.3, fontFamily: KinrelTypography.displayFont,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _focusMode = !_focusMode),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_focusMode ? Icons.visibility : Icons.visibility_off, color: Colors.white70, size: 14),
                        const SizedBox(width: 5),
                        const Text('Focus Mode', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.person_outline, color: Colors.white70, size: 22),
              ],
            ),
          ),
        ),
        Positioned(
          bottom: 24, left: 0, right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0E1A).withOpacity(0.85),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF4FC3F7).withOpacity(0.3), width: 1),
              ),
              child: Text(
                '${detail.members.where((p) => p.deletedAt == null).length} members · ${detail.relationships.length} links',
                style: const TextStyle(color: Color(0xFF4FC3F7), fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
