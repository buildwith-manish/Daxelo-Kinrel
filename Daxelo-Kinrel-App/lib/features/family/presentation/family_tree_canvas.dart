import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/graph/graph_service.dart';
import '../../../core/family/family_provider.dart';

/// TreeNode model for visualization
class VisTreeNode {
  final GraphPerson person;
  final GraphPerson? spouse;
  final List<VisTreeNode> children;

  const VisTreeNode({
    required this.person,
    this.spouse,
    this.children = const [],
  });
}

/// Interactive family tree canvas with pan/zoom
class FamilyTreeCanvas extends StatefulWidget {
  final List<Person> members;
  final List<FamilyRelationship> relationships;
  final ValueChanged<Person>? onNodeTap;

  const FamilyTreeCanvas({
    super.key,
    required this.members,
    required this.relationships,
    this.onNodeTap,
  });

  @override
  State<FamilyTreeCanvas> createState() => _FamilyTreeCanvasState();
}

class _FamilyTreeCanvasState extends State<FamilyTreeCanvas> {
  Offset _offset = Offset.zero;
  double _scale = 1.0;
  String? _selectedNodeId;

  // Node dimensions
  static const double nodeWidth = 140.0;
  static const double nodeHeight = 56.0;
  static const double horizontalGap = 20.0;
  static const double verticalGap = 80.0;

  @override
  Widget build(BuildContext context) {
    // Build tree structure from flat data
    final treeRoots = _buildTree();

    return GestureDetector(
      onScaleStart: (_) {},
      onScaleUpdate: (details) {
        setState(() {
          _offset += details.focalPointDelta;
          _scale = (_scale * details.scale).clamp(0.3, 3.0);
        });
      },
      onTapUp: (details) {
        final localPos =
            (details.localPosition - _offset) / _scale;
        final tappedNode = _hitTest(treeRoots, localPos);
        if (tappedNode != null) {
          final person = widget.members.firstWhere(
            (p) => p.id == tappedNode.person.id,
            orElse: () => Person(
              id: tappedNode.person.id,
              familyId: '',
              name: tappedNode.person.name,
            ),
          );
          setState(() => _selectedNodeId = tappedNode.person.id);
          widget.onNodeTap?.call(person);
        }
      },
      child: ClipRect(
        child: CustomPaint(
          painter: _TreePainter(
            roots: treeRoots,
            offset: _offset,
            scale: _scale,
            selectedNodeId: _selectedNodeId,
            members: widget.members,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }

  /// Build tree hierarchy from flat person + relationship data
  List<VisTreeNode> _buildTree() {
    final persons = widget.members
        .where((p) => p.deletedAt == null)
        .map((p) => p.toGraphPerson())
        .toList();

    final rels = widget.relationships
        .map((r) => r.toGraphEdge())
        .toList();

    if (persons.isEmpty) return [];

    // Build a map for quick lookup
    final personMap = {for (final p in persons) p.id: p};

    // Find parent-child relationships
    final childOf = <String, String>{}; // childId → parentId
    final spouseOf = <String, String>{}; // personId → spouseId

    for (final rel in rels) {
      final type = rel.type.toLowerCase();
      if (['child', 'son', 'daughter'].contains(type)) {
        childOf[rel.fromId] = rel.toId;
      } else if (['father', 'mother', 'parent'].contains(type)) {
        childOf[rel.toId] = rel.fromId;
      } else if (type == 'spouse' || type == 'husband' || type == 'wife') {
        spouseOf[rel.fromId] = rel.toId;
        spouseOf[rel.toId] = rel.fromId;
      }
    }

    // Find roots (persons without parents in the tree)
    final rootIds = <String>{};
    for (final p in persons) {
      if (!childOf.containsKey(p.id)) {
        rootIds.add(p.id);
      }
    }

    // If all persons have parents, pick the first one
    if (rootIds.isEmpty && persons.isNotEmpty) {
      rootIds.add(persons.first.id);
    }

    // Build tree recursively
    final childrenOf = <String, List<String>>{};
    for (final entry in childOf.entries) {
      childrenOf.putIfAbsent(entry.value, () => []).add(entry.key);
    }

    // Track used persons (to avoid duplicates)
    final usedIds = <String>{};

    VisTreeNode? buildNode(String id) {
      if (usedIds.contains(id) || !personMap.containsKey(id)) return null;
      usedIds.add(id);

      final person = personMap[id]!;
      final spouseId = spouseOf[id];
      GraphPerson? spouse;
      if (spouseId != null &&
          personMap.containsKey(spouseId) &&
          !usedIds.contains(spouseId)) {
        usedIds.add(spouseId);
        spouse = personMap[spouseId]!;
      }

      final childIds = childrenOf[id] ?? [];
      final childNodes = <VisTreeNode>[];
      for (final childId in childIds) {
        final node = buildNode(childId);
        if (node != null) childNodes.add(node);
      }

      return VisTreeNode(
        person: person,
        spouse: spouse,
        children: childNodes,
      );
    }

    final roots = <VisTreeNode>[];
    for (final rootId in rootIds) {
      final node = buildNode(rootId);
      if (node != null) roots.add(node);
    }

    // Add remaining unlinked persons as separate roots
    for (final p in persons) {
      if (!usedIds.contains(p.id)) {
        roots.add(VisTreeNode(person: p));
        usedIds.add(p.id);
      }
    }

    return roots;
  }

  /// Hit test to find which node was tapped
  VisTreeNode? _hitTest(List<VisTreeNode> roots, Offset localPos) {
    final layout = _layoutTree(roots);
    for (final entry in layout.entries) {
      final node = entry.key;
      final rect = entry.value;
      if (rect.contains(localPos)) return node;
    }
    return null;
  }

  /// Layout the tree and return node positions
  Map<VisTreeNode, Rect> _layoutTree(List<VisTreeNode> roots) {
    final layout = <VisTreeNode, Rect>{};
    double xOffset = 0;

    for (final root in roots) {
      final width = _layoutSubtree(root, xOffset, 0, layout);
      xOffset += width + horizontalGap * 2;
    }

    return layout;
  }

  double _layoutSubtree(
    VisTreeNode node,
    double xOffset,
    double yOffset,
    Map<VisTreeNode, Rect> layout,
  ) {
    final hasSpouse = node.spouse != null;
    final coupleWidth =
        hasSpouse ? nodeWidth * 2 + horizontalGap : nodeWidth;

    if (node.children.isEmpty) {
      layout[node] = Rect.fromLTWH(xOffset, yOffset, nodeWidth, nodeHeight);
      if (hasSpouse) {
        layout[VisTreeNode(person: node.spouse!)] = Rect.fromLTWH(
          xOffset + nodeWidth + horizontalGap,
          yOffset,
          nodeWidth,
          nodeHeight,
        );
      }
      return coupleWidth;
    }

    // Layout children first
    double childX = xOffset;
    double maxChildWidth = 0;
    final childWidths = <double>[];

    for (final child in node.children) {
      final w = _layoutSubtree(child, childX, yOffset + nodeHeight + verticalGap, layout);
      childWidths.add(w);
      maxChildWidth += w + horizontalGap;
      childX += w + horizontalGap;
    }

    maxChildWidth -= horizontalGap; // remove last gap

    // Center parent over children
    final centerX = xOffset + maxChildWidth / 2 - coupleWidth / 2;
    layout[node] = Rect.fromLTWH(centerX, yOffset, nodeWidth, nodeHeight);
    if (hasSpouse) {
      layout[VisTreeNode(person: node.spouse!)] = Rect.fromLTWH(
        centerX + nodeWidth + horizontalGap,
        yOffset,
        nodeWidth,
        nodeHeight,
      );
    }

    return math.max(maxChildWidth, coupleWidth);
  }
}

/// Custom painter for the family tree
class _TreePainter extends CustomPainter {
  final List<VisTreeNode> roots;
  final Offset offset;
  final double scale;
  final String? selectedNodeId;
  final List<Person> members;

  _TreePainter({
    required this.roots,
    required this.offset,
    required this.scale,
    required this.selectedNodeId,
    required this.members,
  });

  static const double nodeWidth = 140.0;
  static const double nodeHeight = 56.0;
  static const double horizontalGap = 20.0;
  static const double verticalGap = 80.0;
  static const double radius = 10.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);

    if (roots.isEmpty) {
      _drawEmptyState(canvas, size);
      canvas.restore();
      return;
    }

    final layout = _layoutTree();

    // Draw connecting lines first
    for (final root in roots) {
      _drawConnections(canvas, root, layout);
    }

    // Draw nodes
    for (final entry in layout.entries) {
      final node = entry.key;
      final rect = entry.value;
      _drawNode(canvas, node.person, rect, node.person.id == selectedNodeId);
    }

    canvas.restore();
  }

  void _drawEmptyState(Canvas canvas, Size size) {
    final center = Offset(size.width / 2 / scale, size.height / 2 / scale);
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'Add members to see the family tree',
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 16,
          color: KinrelColors.textDim,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      center - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  void _drawConnections(
    Canvas canvas,
    VisTreeNode node,
    Map<VisTreeNode, Rect> layout,
  ) {
    final parentRect = layout[node];
    if (parentRect == null) return;

    final parentBottom = Offset(
      parentRect.left + parentRect.width / 2,
      parentRect.bottom,
    );

    for (final child in node.children) {
      final childRect = layout[child];
      if (childRect == null) continue;

      final childTop = Offset(
        childRect.left + childRect.width / 2,
        childRect.top,
      );

      final midY = (parentBottom.dy + childTop.dy) / 2;

      final path = Path()
        ..moveTo(parentBottom.dx, parentBottom.dy)
        ..lineTo(parentBottom.dx, midY)
        ..lineTo(childTop.dx, midY)
        ..lineTo(childTop.dx, childTop.dy);

      final paint = Paint()
        ..color = KinrelColors.darkSurface
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;

      canvas.drawPath(path, paint);

      // Recurse
      _drawConnections(canvas, child, layout);
    }
  }

  void _drawNode(
    Canvas canvas,
    GraphPerson person,
    Rect rect,
    bool isSelected,
  ) {
    // Glow effect for selected node
    if (isSelected) {
      final glowPaint = Paint()
        ..color = KinrelColors.orangeGlow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(6), Radius.circular(radius + 4)),
        glowPaint,
      );
    }

    // Background
    final bgPaint = Paint()
      ..color = isSelected ? KinrelColors.darkElevated : KinrelColors.darkCard;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(radius)),
      bgPaint,
    );

    // Border
    final borderPaint = Paint()
      ..color = isSelected
          ? KinrelColors.orange
          : KinrelColors.darkSurface.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = isSelected ? 2 : 1;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(radius)),
      borderPaint,
    );

    // Deceased indicator
    if (person.isDeceased) {
      final deceasedPaint = Paint()
        ..color = KinrelColors.textDim.withValues(alpha: 0.3);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(radius)),
        deceasedPaint,
      );
    }

    // Name text
    final namePainter = TextPainter(
      text: TextSpan(
        text: person.name,
        style: TextStyle(
          fontFamily: KinrelTypography.displayFont,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: person.isDeceased
              ? KinrelColors.textDim
              : KinrelColors.textWhite,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    );
    namePainter.layout(maxWidth: rect.width - 16);
    namePainter.paint(
      canvas,
      Offset(rect.left + 8, rect.top + 8),
    );

    // Relationship type text
    if (person.relationship != null && person.relationship!.isNotEmpty) {
      final relPainter = TextPainter(
        text: TextSpan(
          text: person.relationship!.replaceAll('_', ' ').toUpperCase(),
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 9,
            fontWeight: FontWeight.w500,
            color: KinrelColors.orange,
            letterSpacing: 0.5,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      );
      relPainter.layout(maxWidth: rect.width - 16);
      relPainter.paint(
        canvas,
        Offset(rect.left + 8, rect.top + 30),
      );
    }
  }

  Map<VisTreeNode, Rect> _layoutTree() {
    final layout = <VisTreeNode, Rect>{};
    double xOffset = 40;

    for (final root in roots) {
      final width = _layoutSubtree(root, xOffset, 40, layout);
      xOffset += width + horizontalGap * 2;
    }

    return layout;
  }

  double _layoutSubtree(
    VisTreeNode node,
    double xOffset,
    double yOffset,
    Map<VisTreeNode, Rect> layout,
  ) {
    final hasSpouse = node.spouse != null;
    final coupleWidth =
        hasSpouse ? nodeWidth * 2 + horizontalGap : nodeWidth;

    if (node.children.isEmpty) {
      layout[node] = Rect.fromLTWH(xOffset, yOffset, nodeWidth, nodeHeight);
      if (hasSpouse) {
        layout[VisTreeNode(person: node.spouse!)] = Rect.fromLTWH(
          xOffset + nodeWidth + horizontalGap,
          yOffset,
          nodeWidth,
          nodeHeight,
        );
      }
      return coupleWidth;
    }

    double childX = xOffset;
    double maxChildWidth = 0;

    for (final child in node.children) {
      final w = _layoutSubtree(
        child,
        childX,
        yOffset + nodeHeight + verticalGap,
        layout,
      );
      maxChildWidth += w + horizontalGap;
      childX += w + horizontalGap;
    }

    maxChildWidth -= horizontalGap;

    final centerX = xOffset + maxChildWidth / 2 - coupleWidth / 2;
    layout[node] = Rect.fromLTWH(centerX, yOffset, nodeWidth, nodeHeight);
    if (hasSpouse) {
      layout[VisTreeNode(person: node.spouse!)] = Rect.fromLTWH(
        centerX + nodeWidth + horizontalGap,
        yOffset,
        nodeWidth,
        nodeHeight,
      );
    }

    return math.max(maxChildWidth, coupleWidth);
  }

  @override
  bool shouldRepaint(covariant _TreePainter oldDelegate) {
    return oldDelegate.roots != roots ||
        oldDelegate.offset != offset ||
        oldDelegate.scale != scale ||
        oldDelegate.selectedNodeId != selectedNodeId;
  }
}
