// lib/features/family/presentation/family_tree_widget.dart
//
// DAXELO KINREL — Family Tree Widget
//
// Performant family tree visualization using CustomPaint.
// Uses buildTree() from GraphService to get TreeNode hierarchy.
// Renders a vertical tree layout (grandparents at top, children at bottom).
//
// Features:
// - Zoom (ScaleGesture) and Pan (GestureDetector)
// - Collapse/expand nodes (tap on node)
// - Spouse nodes shown side by side
// - Children shown below parents
// - Animated transitions when expanding/collapsing
// - CustomPaint for performance (NOT nested ListView)

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/graph/graph_service.dart';
import '../../../core/graph/graph_provider.dart';
import '../../../core/family/family_provider.dart';

// ═══════════════════════════════════════════════════════════════════════
// LAYOUT CONSTANTS
// ═══════════════════════════════════════════════════════════════════════

const double _nodeWidth = 120.0;
const double _nodeHeight = 70.0;
const double _spouseGap = 24.0;
const double _siblingGap = 32.0;
const double _generationGap = 100.0;
const double _avatarRadius = 18.0;
const double _borderRadius = 12.0;

// ═══════════════════════════════════════════════════════════════════════
// LAYOUT NODE (internal representation for painting)
// ═══════════════════════════════════════════════════════════════════════

class _LayoutNode {
  const _LayoutNode({
    required this.person,
    this.spouse,
    required this.offset,
    this.spouseOffset,
    this.childrenOffsets = const [],
    this.isCollapsed = false,
  });

  final GraphPerson person;
  final GraphPerson? spouse;
  final Offset offset;
  final Offset? spouseOffset;
  final List<Offset> childrenOffsets;
  final bool isCollapsed;
}

// ═══════════════════════════════════════════════════════════════════════
// FAMILY TREE WIDGET
// ═══════════════════════════════════════════════════════════════════════

/// A performant family tree visualization widget.
///
/// Uses [GraphService.buildTree] to convert flat graph data into
/// hierarchical [TreeNode] structure, then renders a vertical tree
/// layout using CustomPaint.
///
/// Features:
/// - **Zoom** via ScaleGesture (pinch-to-zoom)
/// - **Pan** via drag gesture
/// - **Collapse/expand** by tapping on a node
/// - **Animated transitions** when expanding/collapsing
class FamilyTreeWidget extends ConsumerStatefulWidget {
  const FamilyTreeWidget({
    super.key,
    required this.members,
    required this.relationships,
    required this.rootPersonId,
    this.familyId = '',
    this.onNodeTap,
  });

  final List<Person> members;
  final List<FamilyRelationship> relationships;
  final String rootPersonId;
  final String familyId;
  final ValueChanged<GraphPerson>? onNodeTap;

  @override
  ConsumerState<FamilyTreeWidget> createState() => _FamilyTreeWidgetState();
}

class _FamilyTreeWidgetState extends ConsumerState<FamilyTreeWidget>
    with TickerProviderStateMixin {
  // ── View state ──────────────────────────────────────────────────
  double _scale = 1.0;

  // ── Tree state ──────────────────────────────────────────────────
  TreeNode? _treeRoot;
  Map<String, bool> _collapsedNodes = {};
  List<_LayoutNode> _layoutNodes = [];

  // ── Animation ───────────────────────────────────────────────────
  late AnimationController _expandController;

  // ── Transformation controller ───────────────────────────────────
  final TransformationController _transformationController =
      TransformationController();

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _rebuildTree();
  }

  @override
  void dispose() {
    _expandController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(FamilyTreeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.members, widget.members) ||
        oldWidget.rootPersonId != widget.rootPersonId) {
      _rebuildTree();
    }
  }

  // ── Tree Building ───────────────────────────────────────────────

  void _rebuildTree() {
    final graphService = ref.read(graphServiceProvider);
    final activeMembers = widget.members
        .where((p) => p.deletedAt == null)
        .toList();

    final persons = activeMembers.map((p) => p.toGraphPerson()).toList();
    final rels = widget.relationships.map((r) => r.toGraphEdge()).toList();

    _treeRoot = graphService.buildTree(
      persons: persons,
      relationships: rels,
      rootPersonId: widget.rootPersonId,
    );

    _computeLayout();
  }

  // ── Layout Computation ──────────────────────────────────────────

  void _computeLayout() {
    _layoutNodes = [];
    if (_treeRoot == null) return;

    _layoutSubtree(_treeRoot!, Offset.zero, 0);
  }

  /// Compute the width needed for a subtree.
  double _subtreeWidth(TreeNode node) {
    if (_collapsedNodes[node.person.id] == true || node.children.isEmpty) {
      final hasSpouse = node.spouse != null;
      return hasSpouse ? _nodeWidth * 2 + _spouseGap : _nodeWidth;
    }

    double totalChildWidth = 0;
    for (int i = 0; i < node.children.length; i++) {
      totalChildWidth += _subtreeWidth(node.children[i]);
      if (i < node.children.length - 1) {
        totalChildWidth += _siblingGap;
      }
    }

    final hasSpouse = node.spouse != null;
    final coupleWidth = hasSpouse ? _nodeWidth * 2 + _spouseGap : _nodeWidth;

    return math.max(totalChildWidth, coupleWidth);
  }

  /// Recursively compute layout positions for each node.
  void _layoutSubtree(TreeNode node, Offset startOffset, int generation) {
    final isCollapsed = _collapsedNodes[node.person.id] == true;
    final subtreeW = _subtreeWidth(node);
    final hasSpouse = node.spouse != null;
    final coupleWidth = hasSpouse ? _nodeWidth * 2 + _spouseGap : _nodeWidth;

    // Center the couple within the subtree width
    final coupleStartX = startOffset.dx + (subtreeW - coupleWidth) / 2;
    final y = startOffset.dy + generation * _generationGap;

    final nodeOffset = Offset(coupleStartX, y);
    Offset? spouseOffset;
    if (hasSpouse) {
      spouseOffset = Offset(coupleStartX + _nodeWidth + _spouseGap, y);
    }

    // Calculate children offsets
    final childrenOffsets = <Offset>[];
    if (!isCollapsed && node.children.isNotEmpty) {
      double childX = startOffset.dx;
      for (final child in node.children) {
        final childWidth = _subtreeWidth(child);
        _layoutSubtree(child, Offset(childX, 0), generation + 1);
        childX += childWidth + _siblingGap;
      }

      // Calculate actual child node offsets for connector lines
      childX = startOffset.dx;
      for (final child in node.children) {
        final childWidth = _subtreeWidth(child);
        final childCoupleWidth = child.spouse != null
            ? _nodeWidth * 2 + _spouseGap
            : _nodeWidth;
        final childSubtreeW = _subtreeWidth(child);
        final childCoupleStartX = childX + (childSubtreeW - childCoupleWidth) / 2;
        childrenOffsets.add(
          Offset(childCoupleStartX + childCoupleWidth / 2, y + _generationGap),
        );
        childX += childWidth + _siblingGap;
      }
    }

    _layoutNodes.add(_LayoutNode(
      person: node.person,
      spouse: node.spouse,
      offset: nodeOffset,
      spouseOffset: spouseOffset,
      childrenOffsets: childrenOffsets,
      isCollapsed: isCollapsed,
    ));
  }

  // ── Toggle Collapse ─────────────────────────────────────────────

  void _toggleCollapse(String personId) {
    setState(() {
      _collapsedNodes[personId] = !(_collapsedNodes[personId] ?? false);
      _computeLayout();
    });
  }

  // ── Hit Test ────────────────────────────────────────────────────

  /// Find which node was tapped, considering pan offset and scale.
  _LayoutNode? _hitTest(Offset localPosition) {
    final transform = _transformationController.value;
    final inverse = Matrix4.identity()..copyInverse(transform);
    final graphPos = MatrixUtils.transformPoint(inverse, localPosition);

    for (final node in _layoutNodes) {
      // Check main person node
      final nodeRect = Rect.fromLTWH(
        node.offset.dx,
        node.offset.dy,
        _nodeWidth,
        _nodeHeight,
      );
      if (nodeRect.contains(graphPos)) {
        return node;
      }

      // Check spouse node
      if (node.spouseOffset != null) {
        final spouseRect = Rect.fromLTWH(
          node.spouseOffset!.dx,
          node.spouseOffset!.dy,
          _nodeWidth,
          _nodeHeight,
        );
        if (spouseRect.contains(graphPos)) {
          return node;
        }
      }
    }
    return null;
  }

  // ══════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (_treeRoot == null || _layoutNodes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_tree_outlined, size: 48, color: KinrelColors.textDim),
            const SizedBox(height: 12),
            Text(
              'No family tree data available',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: KinrelColors.textDim,
              ),
            ),
          ],
        ),
      );
    }

    // Calculate the canvas size needed
    double maxX = 0, maxY = 0;
    for (final node in _layoutNodes) {
      maxX = math.max(maxX, node.offset.dx + _nodeWidth);
      maxY = math.max(maxY, node.offset.dy + _nodeHeight);
      if (node.spouseOffset != null) {
        maxX = math.max(maxX, node.spouseOffset!.dx + _nodeWidth);
      }
    }

    final canvasWidth = maxX + 80;
    final canvasHeight = maxY + 80;

    return Container(
      color: const Color(0xFF131416),
      child: Stack(
        children: [
          // ── Interactive tree canvas ────────────────────────────
          InteractiveViewer(
            transformationController: _transformationController,
            minScale: 0.3,
            maxScale: 3.0,
            boundaryMargin: const EdgeInsets.all(2000),
            onInteractionUpdate: (details) {
              setState(() {
                _scale = details.scale;
              });
            },
            child: GestureDetector(
              onTapUp: (details) {
                final hit = _hitTest(details.localPosition);
                if (hit != null) {
                  // If the node has children, toggle collapse
                  final treeNode = _findTreeNode(hit.person.id);
                  if (treeNode != null && treeNode.children.isNotEmpty) {
                    _toggleCollapse(hit.person.id);
                  }
                  widget.onNodeTap?.call(hit.person);
                }
              },
              child: SizedBox(
                width: canvasWidth,
                height: canvasHeight,
                child: CustomPaint(
                  painter: _FamilyTreePainter(
                    layoutNodes: _layoutNodes,
                    collapsedNodes: _collapsedNodes,
                    rootPersonId: widget.rootPersonId,
                    scale: _scale,
                  ),
                ),
              ),
            ),
          ),

          // ── Zoom controls (bottom-right) ──────────────────────
          Positioned(
            bottom: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ZoomButton(
                  icon: Icons.add,
                  onPressed: _zoomIn,
                  semanticLabel: 'Zoom in',
                ),
                const SizedBox(height: 8),
                _ZoomButton(
                  icon: Icons.remove,
                  onPressed: _zoomOut,
                  semanticLabel: 'Zoom out',
                ),
                const SizedBox(height: 8),
                _ZoomButton(
                  icon: Icons.fit_screen_outlined,
                  onPressed: _fitToScreen,
                  semanticLabel: 'Fit to screen',
                ),
              ],
            ),
          ),

          // ── Legend (top-left) ──────────────────────────────────
          Positioned(
            top: 8,
            left: 8,
            child: _TreeLegend(),
          ),
        ],
      ),
    );
  }

  // ── Tree node lookup ────────────────────────────────────────────

  TreeNode? _findTreeNode(String personId) {
    TreeNode? search(TreeNode node) {
      if (node.person.id == personId) return node;
      for (final child in node.children) {
        final found = search(child);
        if (found != null) return found;
      }
      return null;
    }

    if (_treeRoot == null) return null;
    return search(_treeRoot!);
  }

  // ── Zoom helpers ────────────────────────────────────────────────

  void _zoomIn() {
    final current = _transformationController.value;
    final newScale = (_scale * 1.2).clamp(0.3, 3.0);
    final scaleFactor = newScale / _scale;
    setState(() {
      final m = Matrix4.copy(current);
      m.scaleByDouble(scaleFactor, scaleFactor, 1.0, 1.0);
      _transformationController.value = m;
      _scale = newScale;
    });
  }

  void _zoomOut() {
    final current = _transformationController.value;
    final newScale = (_scale / 1.2).clamp(0.3, 3.0);
    final scaleFactor = newScale / _scale;
    setState(() {
      final m = Matrix4.copy(current);
      m.scaleByDouble(scaleFactor, scaleFactor, 1.0, 1.0);
      _transformationController.value = m;
      _scale = newScale;
    });
  }

  void _fitToScreen() {
    setState(() {
      _transformationController.value = Matrix4.identity();
      _scale = 1.0;
    });
  }
}

// ═══════════════════════════════════════════════════════════════════════
// CUSTOM PAINTER
// ═══════════════════════════════════════════════════════════════════════

class _FamilyTreePainter extends CustomPainter {
  const _FamilyTreePainter({
    required this.layoutNodes,
    required this.collapsedNodes,
    required this.rootPersonId,
    required this.scale,
  });

  final List<_LayoutNode> layoutNodes;
  final Map<String, bool> collapsedNodes;
  final String rootPersonId;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    // ── Draw connector lines first (behind nodes) ──────────────
    final linePaint = Paint()
      ..color = KinrelColors.orange.withAlpha(60)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final spouseLinePaint = Paint()
      ..color = KinrelColors.amber.withAlpha(80)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    for (final node in layoutNodes) {
      final isCollapsed = collapsedNodes[node.person.id] == true;

      // ── Spouse connector line ─────────────────────────────────
      if (node.spouseOffset != null) {
        final from = Offset(
          node.offset.dx + _nodeWidth,
          node.offset.dy + _nodeHeight / 2,
        );
        final to = Offset(
          node.spouseOffset!.dx,
          node.spouseOffset!.dy + _nodeHeight / 2,
        );
        canvas.drawLine(from, to, spouseLinePaint);

        // Draw a small heart/link icon at midpoint
        final midX = (from.dx + to.dx) / 2;
        final midY = (from.dy + to.dy) / 2;
        final heartPaint = Paint()..color = KinrelColors.amber.withAlpha(120);
        canvas.drawCircle(Offset(midX, midY), 4, heartPaint);
      }

      // ── Parent-child connector lines ─────────────────────────
      if (!isCollapsed) {
        for (final childOffset in node.childrenOffsets) {
          final fromX = node.spouseOffset != null
              ? (node.offset.dx + _nodeWidth + node.spouseOffset!.dx) / 2
              : node.offset.dx + _nodeWidth / 2;
          final fromY = node.offset.dy + _nodeHeight;
          final toX = childOffset.dx;
          final toY = childOffset.dy;

          // Draw a step-down line: down to midpoint, then horizontal, then down
          final midY = (fromY + toY) / 2;
          final path = Path()
            ..moveTo(fromX, fromY)
            ..lineTo(fromX, midY)
            ..lineTo(toX, midY)
            ..lineTo(toX, toY);

          canvas.drawPath(path, linePaint);
        }
      }
    }

    // ── Draw nodes (on top of lines) ───────────────────────────
    for (final node in layoutNodes) {
      _drawNode(canvas, node.person, node.offset, isRoot: node.person.id == rootPersonId);

      if (node.spouseOffset != null && node.spouse != null) {
        _drawNode(canvas, node.spouse!, node.spouseOffset!);
      }

      // Draw collapse/expand indicator if node has children
      final isCollapsed = collapsedNodes[node.person.id] == true;
      if (node.childrenOffsets.isNotEmpty || isCollapsed) {
        _drawCollapseIndicator(
          canvas,
          node.offset,
          isCollapsed,
          node.childrenOffsets.length,
        );
      }
    }
  }

  void _drawNode(Canvas canvas, GraphPerson person, Offset offset, {bool isRoot = false}) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(offset.dx, offset.dy, _nodeWidth, _nodeHeight),
      Radius.circular(_borderRadius),
    );

    // ── Node background ────────────────────────────────────────
    final bgPaint = Paint()
      ..color = isRoot
          ? KinrelColors.orange.withAlpha(30)
          : KinrelColors.darkElevated;
    canvas.drawRRect(rect, bgPaint);

    // ── Node border ────────────────────────────────────────────
    final borderPaint = Paint()
      ..color = isRoot ? KinrelColors.orange : KinrelColors.darkSurface
      ..strokeWidth = isRoot ? 2.0 : 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(rect, borderPaint);

    // ── Avatar placeholder ─────────────────────────────────────
    final avatarCenter = Offset(offset.dx + _avatarRadius + 10, offset.dy + _nodeHeight / 2);
    final avatarPaint = Paint()..color = KinrelColors.orange.withAlpha(40);
    canvas.drawCircle(avatarCenter, _avatarRadius, avatarPaint);
    final avatarBorderPaint = Paint()
      ..color = KinrelColors.orange.withAlpha(80)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(avatarCenter, _avatarRadius, avatarBorderPaint);

    // ── Initials in avatar ─────────────────────────────────────
    final initials = _getInitials(person.name);
    final textPainter = TextPainter(
      text: TextSpan(
        text: initials,
        style: TextStyle(
          fontFamily: KinrelTypography.displayFont,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: KinrelColors.orange,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        avatarCenter.dx - textPainter.width / 2,
        avatarCenter.dy - textPainter.height / 2,
      ),
    );

    // ── Name text ──────────────────────────────────────────────
    final nameTextPainter = TextPainter(
      text: TextSpan(
        text: person.name.length > 12 ? '${person.name.substring(0, 12)}…' : person.name,
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    );
    nameTextPainter.layout(maxWidth: _nodeWidth - _avatarRadius * 2 - 24);
    nameTextPainter.paint(
      canvas,
      Offset(
        offset.dx + _avatarRadius * 2 + 20,
        offset.dy + _nodeHeight / 2 - 14,
      ),
    );

    // ── Relationship label ─────────────────────────────────────
    if (person.relationship != null && person.relationship!.isNotEmpty) {
      final relLabel = person.relationship!.replaceAll('_', ' ');
      final relTextPainter = TextPainter(
        text: TextSpan(
          text: relLabel.length > 14 ? '${relLabel.substring(0, 14)}…' : relLabel,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 9,
            color: KinrelColors.textSilver,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      );
      relTextPainter.layout(maxWidth: _nodeWidth - _avatarRadius * 2 - 24);
      relTextPainter.paint(
        canvas,
        Offset(
          offset.dx + _avatarRadius * 2 + 20,
          offset.dy + _nodeHeight / 2 + 2,
        ),
      );
    }

    // ── Deceased indicator ─────────────────────────────────────
    if (person.isDeceased) {
      final deceasedPaint = Paint()
        ..color = KinrelColors.textDim.withAlpha(60)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawRRect(rect, deceasedPaint);
    }
  }

  void _drawCollapseIndicator(
    Canvas canvas,
    Offset nodeOffset,
    bool isCollapsed,
    int childCount,
  ) {
    final indicatorCenter = Offset(
      nodeOffset.dx + _nodeWidth / 2,
      nodeOffset.dy + _nodeHeight + 12,
    );

    // Background circle
    final bgPaint = Paint()
      ..color = isCollapsed ? KinrelColors.orange.withAlpha(40) : KinrelColors.darkSurface;
    canvas.drawCircle(indicatorCenter, 10, bgPaint);

    // Border
    final borderPaint = Paint()
      ..color = isCollapsed ? KinrelColors.orange : KinrelColors.textDim
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(indicatorCenter, 10, borderPaint);

    // Icon: + for collapsed, - for expanded
    final iconPaint = Paint()
      ..color = isCollapsed ? KinrelColors.orange : KinrelColors.textDim
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    // Horizontal line (minus/plus)
    canvas.drawLine(
      Offset(indicatorCenter.dx - 5, indicatorCenter.dy),
      Offset(indicatorCenter.dx + 5, indicatorCenter.dy),
      iconPaint,
    );

    // Vertical line (plus only, for collapsed)
    if (isCollapsed) {
      canvas.drawLine(
        Offset(indicatorCenter.dx, indicatorCenter.dy - 5),
        Offset(indicatorCenter.dx, indicatorCenter.dy + 5),
        iconPaint,
      );

      // Show child count badge
      if (childCount > 0) {
        final countPainter = TextPainter(
          text: TextSpan(
            text: '$childCount',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 8,
              fontWeight: FontWeight.w600,
              color: KinrelColors.orange,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        countPainter.layout();
        countPainter.paint(
          canvas,
          Offset(
            indicatorCenter.dx + 12,
            indicatorCenter.dy - countPainter.height / 2,
          ),
        );
      }
    }
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  @override
  bool shouldRepaint(covariant _FamilyTreePainter oldDelegate) {
    return layoutNodes != oldDelegate.layoutNodes ||
        collapsedNodes != oldDelegate.collapsedNodes ||
        scale != oldDelegate.scale;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// ZOOM BUTTON
// ═══════════════════════════════════════════════════════════════════════

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: KinrelColors.darkElevated,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: KinrelColors.darkSurface, width: 1),
            ),
            child: Icon(
              icon,
              color: KinrelColors.textSilver,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// TREE LEGEND
// ═══════════════════════════════════════════════════════════════════════

class _TreeLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard.withAlpha(230),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: KinrelColors.darkSurface, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Family Tree',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: KinrelColors.orange,
            ),
          ),
          const SizedBox(height: 4),
          _legendItem('━━', 'Parent → Child', KinrelColors.orange.withAlpha(60)),
          _legendItem('──', 'Spouse', KinrelColors.amber.withAlpha(80)),
          _legendItem('●', 'Tap to expand/collapse', KinrelColors.textDim),
        ],
      ),
    );
  }

  Widget _legendItem(String symbol, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          symbol,
          style: TextStyle(color: color, fontSize: 10),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 9,
            color: KinrelColors.textDim,
          ),
        ),
      ],
    );
  }
}
