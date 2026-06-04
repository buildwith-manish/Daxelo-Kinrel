import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/kinship/kinship_provider.dart';
import 'relationship_graph_painter.dart';

// ═══════════════════════════════════════════════════════════════════════
// RELATIONSHIP GRAPH PICKER
// ═══════════════════════════════════════════════════════════════════════

/// Visual constellation-style relationship picker.
/// Shows the anchor person in the center with radiating relationship
/// nodes. Tapping a node selects that relationship type.
///
/// Uses Kinrel orange/amber color scheme with animated glow pulses,
/// orbit rings, and dashed connection lines.
class RelationshipGraphPicker extends ConsumerStatefulWidget {
  const RelationshipGraphPicker({
    super.key,
    this.anchorName,
    this.anchorGender,
    this.existingRelationshipTypes = const [],
  });

  final String? anchorName;
  final String? anchorGender;
  final List<String> existingRelationshipTypes;

  /// Show the picker and return selected relationship key
  static Future<String?> show(
    BuildContext context, {
    String? anchorName,
    String? anchorGender,
    List<String> existingRelationshipTypes = const [],
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: KinrelColors.darkBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      builder: (_) => RelationshipGraphPicker(
        anchorName: anchorName,
        anchorGender: anchorGender,
        existingRelationshipTypes: existingRelationshipTypes,
      ),
    );
  }

  @override
  ConsumerState<RelationshipGraphPicker> createState() =>
      _RelationshipGraphPickerState();
}

class _RelationshipGraphPickerState
    extends ConsumerState<RelationshipGraphPicker>
    with TickerProviderStateMixin {
  // ── Animation ────────────────────────────────────────────────────
  late AnimationController _pulseController;
  late AnimationController _lineController;
  late AnimationController _orbitController;

  // ── Interaction state ────────────────────────────────────────────
  String? _selectedNodeId;
  String? _hoveredNodeId;

  // ── Nodes & edges ────────────────────────────────────────────────
  List<RelationshipGraphNode> _nodes = [];
  List<RelationshipGraphEdge> _edges = [];

  // ── Radial layout config ─────────────────────────────────────────
  static const double _canvasWidth = 400.0;
  static const double _canvasHeight = 520.0;

  // ── Relationship definitions ─────────────────────────────────────
  static const _relationshipDefs = <_RelDef>[
    _RelDef(id: 'father',        label: 'Father',        hindi: 'पिताजी',    icon: Icons.male,          gender: 'male',   lineage: 'paternal',  angle: -150),
    _RelDef(id: 'mother',        label: 'Mother',        hindi: 'माताजी',    icon: Icons.female,        gender: 'female', lineage: 'maternal',  angle: -120),
    _RelDef(id: 'grandfather_p', label: 'Grandfather',   hindi: 'दादाजी',    icon: Icons.elderly,       gender: 'male',   lineage: 'paternal',  angle: -175),
    _RelDef(id: 'grandmother_p', label: 'Grandmother',   hindi: 'दादीजी',    icon: Icons.elderly_woman, gender: 'female', lineage: 'paternal',  angle: -95),
    _RelDef(id: 'husband',       label: 'Husband',       hindi: 'पति',      icon: Icons.male,          gender: 'male',   lineage: 'marital',   angle: 0),
    _RelDef(id: 'wife',          label: 'Wife',          hindi: 'पत्नी',     icon: Icons.female,        gender: 'female', lineage: 'marital',   angle: 30),
    _RelDef(id: 'elder_brother', label: 'Elder Brother', hindi: 'बड़े भैया',  icon: Icons.male,          gender: 'male',   lineage: 'paternal',  angle: 70),
    _RelDef(id: 'elder_sister',  label: 'Elder Sister',  hindi: 'दीदी',      icon: Icons.female,        gender: 'female', lineage: 'maternal',  angle: 100),
    _RelDef(id: 'younger_brother',label:'Younger Brother',hindi: 'छोटे भैया', icon: Icons.male,          gender: 'male',   lineage: 'paternal',  angle: 145),
    _RelDef(id: 'younger_sister',label: 'Younger Sister', hindi: 'छोटी बहन', icon: Icons.female,        gender: 'female', lineage: 'maternal',  angle: 170),
    _RelDef(id: 'son',           label: 'Son',           hindi: 'बेटा',      icon: Icons.boy,            gender: 'male',   lineage: null,        angle: 200),
    _RelDef(id: 'daughter',      label: 'Daughter',      hindi: 'बेटी',      icon: Icons.girl,           gender: 'female', lineage: null,        angle: 230),
    _RelDef(id: 'uncle_p',       label: 'Uncle',         hindi: 'चाचा',      icon: Icons.male,          gender: 'male',   lineage: 'paternal',  angle: -60),
    _RelDef(id: 'aunt_p',        label: 'Aunt',          hindi: 'चाची',      icon: Icons.female,        gender: 'female', lineage: 'paternal',  angle: -30),
    _RelDef(id: 'uncle_m',       label: 'Mat. Uncle',    hindi: 'मामा',      icon: Icons.male,          gender: 'male',   lineage: 'maternal',  angle: 260),
    _RelDef(id: 'aunt_m',        label: 'Mat. Aunt',     hindi: 'मामी',      icon: Icons.female,        gender: 'female', lineage: 'maternal',  angle: 290),
  ];

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

    _orbitController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();

    // Build nodes with radial positions
    _buildGraph();

    // Ensure kinship data is loaded
    ref.read(kinshipInitializedProvider.future);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _lineController.dispose();
    _orbitController.dispose();
    super.dispose();
  }

  void _buildGraph() {
    final cx = _canvasWidth / 2;
    final cy = _canvasHeight / 2;
    const innerRadius = 90.0;
    const outerRadius = 155.0;

    // Center "You" node
    final selfNode = RelationshipGraphNode(
      id: 'self',
      label: widget.anchorName ?? 'You',
      hindiLabel: 'आप',
      icon: Icons.person,
      position: Offset(cx, cy),
      isSelf: true,
      gender: widget.anchorGender,
    );

    _nodes = [selfNode];
    _edges = [];

    // Filter out already-linked relationships
    final existing = widget.existingRelationshipTypes.toSet();
    final availableDefs = _relationshipDefs.where((def) {
      // Map common keys
      if (existing.contains(def.id)) return false;
      // Also check base keys
      final baseKey = def.id.split('_').first;
      if (existing.contains(baseKey)) return false;
      return true;
    }).toList();

    // Layout nodes in radial pattern
    // Inner ring: parents, spouse (closest relationships)
    // Outer ring: siblings, grandparents, uncle/aunt
    for (int i = 0; i < availableDefs.length; i++) {
      final def = availableDefs[i];
      final angleRad = def.angle * math.pi / 180;
      final isInnerRing = ['father', 'mother', 'husband', 'wife']
          .contains(def.id.split('_').first) ||
          ['father', 'mother', 'husband', 'wife'].contains(def.id);
      final radius = isInnerRing ? innerRadius : outerRadius;

      // Adjust position slightly based on index for better spacing
      final adjustedAngle = angleRad + (i * 0.05);
      final x = cx + radius * math.cos(adjustedAngle);
      final y = cy + radius * math.sin(adjustedAngle);

      _nodes.add(RelationshipGraphNode(
        id: def.id,
        label: def.label,
        hindiLabel: def.hindi,
        icon: def.icon,
        position: Offset(x, y),
        lineage: def.lineage,
        gender: def.gender,
      ));

      // Connect to center
      _edges.add(RelationshipGraphEdge(
        fromId: 'self',
        toId: def.id,
        label: def.hindi,
      ));
    }
  }

  // ── Hit test ─────────────────────────────────────────────────────

  String? _hitTest(Offset localPos) {
    for (final node in _nodes) {
      final dist = (node.position - localPos).distance;
      final hitRadius = node.isSelf ? 46.0 : 38.0;
      if (dist < hitRadius) return node.id;
    }
    return null;
  }

  // ── Resolve selection to relationship key ────────────────────────

  String? _resolveKey(String nodeId) {
    if (nodeId == 'self') return null;

    // Map the graph node ID to a kinship key
    final keyMap = <String, String>{
      'father': 'father',
      'mother': 'mother',
      'grandfather_p': 'grandfather',
      'grandmother_p': 'grandmother',
      'husband': 'husband',
      'wife': 'wife',
      'elder_brother': 'elder_brother',
      'elder_sister': 'elder_sister',
      'younger_brother': 'younger_brother',
      'younger_sister': 'younger_sister',
      'son': 'son',
      'daughter': 'daughter',
      'uncle_p': 'uncle',
      'aunt_p': 'aunt',
      'uncle_m': 'maternal_uncle',
      'aunt_m': 'maternal_aunt',
    };

    return keyMap[nodeId] ?? nodeId;
  }

  // ══════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final height = screenHeight * 0.85;

    return SizedBox(
      height: height,
      child: Column(
        children: [
          // ── Handle bar ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: KinrelColors.darkSurface,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),

          // ── Header ──────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(
              KinrelSpacing.base,
              KinrelSpacing.base,
              KinrelSpacing.base,
              KinrelSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select Relationship',
                        style: TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: KinrelColors.textWhite,
                        ),
                      ),
                      if (widget.anchorName != null) ...[
                        SizedBox(height: 4),
                        Text(
                          'Tap a node to link with ${widget.anchorName}',
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 13,
                            color: KinrelColors.textSilver,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Search button
                _HeaderButton(
                  icon: Icons.search_rounded,
                  label: 'Search',
                  onTap: () => _showSearchFallback(context),
                ),
              ],
            ),
          ),

          // ── Lineage legend ──────────────────────────────────────
          Padding(
            padding: EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
            child: Row(
              children: [
                _LineageDot(color: KinrelColors.orange, label: 'Paternal'),
                SizedBox(width: 12),
                _LineageDot(color: KinrelColors.amber, label: 'Maternal'),
                SizedBox(width: 12),
                _LineageDot(color: KinrelColors.gold, label: 'Marital'),
                SizedBox(width: 12),
                _LineageDot(color: Color(0xFFFF69B4).withOpacity(0.7), label: 'Female'),
              ],
            ),
          ),
          SizedBox(height: 8),

          // ── Graph canvas ────────────────────────────────────────
          Expanded(
            child: Center(
              child: GestureDetector(
                onTapUp: (details) {
                  final pos = details.localPosition;
                  final hitId = _hitTest(pos);
                  if (hitId != null && hitId != 'self') {
                    setState(() => _selectedNodeId = hitId);
                  } else {
                    setState(() => _selectedNodeId = null);
                  }
                },
                onLongPressStart: (details) {
                  final pos = details.localPosition;
                  final hitId = _hitTest(pos);
                  if (hitId != null && hitId != 'self') {
                    final key = _resolveKey(hitId);
                    if (key != null) {
                      Navigator.of(context).pop(key);
                    }
                  }
                },
                child: MouseRegion(
                  onHover: (event) {
                    final pos = event.localPosition;
                    final hitId = _hitTest(pos);
                    if (hitId != _hoveredNodeId) {
                      setState(() => _hoveredNodeId = hitId);
                    }
                  },
                  onExit: (_) {
                    if (_hoveredNodeId != null) {
                      setState(() => _hoveredNodeId = null);
                    }
                  },
                  child: SizedBox(
                    width: _canvasWidth,
                    height: _canvasHeight,
                    child: AnimatedBuilder(
                      animation: Listenable.merge([
                        _pulseController,
                        _lineController,
                        _orbitController,
                      ]),
                      builder: (context, _) {
                        return CustomPaint(
                          painter: RelationshipGraphPainter(
                            nodes: _nodes,
                            edges: _edges,
                            pulseValue: _pulseController.value,
                            lineProgress: _lineController.value,
                            orbitProgress: _orbitController.value,
                            selectedNodeId: _selectedNodeId,
                            hoveredNodeId: _hoveredNodeId,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Selected relationship detail ─────────────────────────
          if (_selectedNodeId != null)
            _buildSelectedDetail(),

          // ── Bottom action bar ────────────────────────────────────
          if (_selectedNodeId != null)
            _buildConfirmBar()
          else
            _buildHintBar(),
        ],
      ),
    );
  }

  // ── Selected detail panel ────────────────────────────────────────

  Widget _buildSelectedDetail() {
    final node = _nodes.firstWhere(
      (n) => n.id == _selectedNodeId,
      orElse: () => _nodes.first,
    );
    final key = _resolveKey(_selectedNodeId!);

    return Container(
      width: double.infinity,
      margin: EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      padding: EdgeInsets.all(KinrelSpacing.md),
      decoration: BoxDecoration(
        color: KinrelColors.darkElevated,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(
          color: _accentForLineage(node.lineage).withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          // Icon circle
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _accentForLineage(node.lineage).withOpacity(0.12),
              border: Border.all(
                color: _accentForLineage(node.lineage).withOpacity(0.5),
              ),
            ),
            child: Icon(
              node.gender == 'female' ? Icons.female : Icons.male,
              color: _accentForLineage(node.lineage),
              size: 22,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  node.label,
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  node.hindiLabel,
                  style: TextStyle(
                    fontFamily: 'NotoSansDevanagari',
                    fontSize: 14,
                    color: _accentForLineage(node.lineage),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          // Lineage badge
          if (node.lineage != null)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _accentForLineage(node.lineage!).withOpacity(0.12),
                borderRadius: BorderRadius.circular(KinrelRadius.xs),
                border: Border.all(
                  color: _accentForLineage(node.lineage!).withOpacity(0.3),
                ),
              ),
              child: Text(
                node.lineage!.toUpperCase(),
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: _accentForLineage(node.lineage!),
                  letterSpacing: 1,
                ),
              ),
            ),
          // Key badge
          if (key != null)
            Container(
              margin: EdgeInsets.only(left: 6),
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: KinrelColors.darkSurface,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                key,
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 9,
                  color: KinrelColors.textDim,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _accentForLineage(String? lineage) {
    switch (lineage) {
      case 'paternal':
        return KinrelColors.orange;
      case 'maternal':
        return KinrelColors.amber;
      case 'marital':
        return KinrelColors.gold;
      default:
        return KinrelColors.orange;
    }
  }

  // ── Confirm bar ──────────────────────────────────────────────────

  Widget _buildConfirmBar() {
    final key = _resolveKey(_selectedNodeId!);
    return Container(
      padding: EdgeInsets.fromLTRB(
        KinrelSpacing.base,
        KinrelSpacing.sm,
        KinrelSpacing.base,
        KinrelSpacing.xl,
      ),
      child: Row(
        children: [
          // Back button
          Expanded(
            child: OutlinedButton(
              onPressed: () => setState(() => _selectedNodeId = null),
              style: OutlinedButton.styleFrom(
                foregroundColor: KinrelColors.textSilver,
                side: BorderSide(color: KinrelColors.darkSurface),
                padding: EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(KinrelRadius.md),
                ),
              ),
              child: Text(
                'Deselect',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          SizedBox(width: 12),
          // Confirm button
          Expanded(
            flex: 2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: KinrelGradients.igniteGradient,
                borderRadius: BorderRadius.circular(KinrelRadius.md),
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(KinrelRadius.md),
                child: InkWell(
                  borderRadius: BorderRadius.circular(KinrelRadius.md),
                  onTap: key != null
                      ? () => Navigator.of(context).pop(key)
                      : null,
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        'Select This Relationship',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: KinrelColors.textWhite,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Hint bar (no selection) ──────────────────────────────────────

  Widget _buildHintBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        KinrelSpacing.base,
        KinrelSpacing.sm,
        KinrelSpacing.base,
        KinrelSpacing.xl,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.touch_app_outlined, size: 16, color: KinrelColors.textDim),
          SizedBox(width: 8),
          Text(
            'Tap a node to select, long-press to confirm quickly',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              color: KinrelColors.textDim,
            ),
          ),
        ],
      ),
    );
  }

  // ── Search fallback ──────────────────────────────────────────────

  void _showSearchFallback(BuildContext context) {
    // Navigate to the text-based relationship picker
    Navigator.of(context).pop(); // Close graph picker
    // The caller will handle showing the text picker
  }
}

// ═══════════════════════════════════════════════════════════════════════
// HELPER WIDGETS
// ═══════════════════════════════════════════════════════════════════════

class _RelDef {
  const _RelDef({
    required this.id,
    required this.label,
    required this.hindi,
    required this.icon,
    required this.gender,
    this.lineage,
    required this.angle,
  });

  final String id;
  final String label;
  final String hindi;
  final IconData icon;
  final String gender;
  final String? lineage;
  final double angle; // degrees, 0 = right, goes counter-clockwise
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: KinrelColors.darkElevated,
          borderRadius: BorderRadius.circular(KinrelRadius.sm),
          border: Border.all(color: KinrelColors.darkSurface),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: KinrelColors.textSilver),
            SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textSilver,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LineageDot extends StatelessWidget {
  const _LineageDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
        ),
        SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 10,
            color: KinrelColors.textDim,
          ),
        ),
      ],
    );
  }
}
