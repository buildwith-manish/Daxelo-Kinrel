import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/graph/graph_service.dart';
import '../../../core/family/family_provider.dart';
import '../../../shared/widgets/dk_components.dart';

// ── Data models for visualization ──────────────────────────────────

/// Extended tree node with layout metadata
class VisTreeNode {
  const VisTreeNode({
    required this.person,
    this.spouse,
    this.children = [],
    this.lineage = '',
  });

  final GraphPerson person;
  final GraphPerson? spouse;
  final List<VisTreeNode> children;
  final String lineage;

}

/// Lineage color coding for node backgrounds
enum NodeLineage { paternal, maternal, marital, self, none }

// ── Filter state ───────────────────────────────────────────────────

class GraphFilters {
  const GraphFilters({
    this.visibleGenerations = {1, 2, 3, 4, 5},
    this.branch = 'all',
    this.showDeceased = true,
    this.showMaritalLinks = true,
  });

  final Set<int> visibleGenerations;
  final String branch;
  final bool showDeceased;
  final bool showMaritalLinks;


  GraphFilters copyWith({
    Set<int>? visibleGenerations,
    String? branch,
    bool? showDeceased,
    bool? showMaritalLinks,
  }) {
    return GraphFilters(
      visibleGenerations: visibleGenerations ?? this.visibleGenerations,
      branch: branch ?? this.branch,
      showDeceased: showDeceased ?? this.showDeceased,
      showMaritalLinks: showMaritalLinks ?? this.showMaritalLinks,
    );
  }
}

// ── Layout result ──────────────────────────────────────────────────

class LayoutResult {
  const LayoutResult({
    required this.positions,
    required this.nodes,
    required this.nodeLineages,
  });

  final Map<String, Rect> positions;
  final Map<String, VisTreeNode> nodes;
  final Map<String, String> nodeLineages;

}

// ── Main canvas widget ─────────────────────────────────────────────

/// Canvas-based interactive family tree view with zoom/pan,
/// curved purple connectors, circular nodes, and floating controls.
class FamilyTreeCanvas extends StatefulWidget {
  const FamilyTreeCanvas({
    super.key,
    required this.members,
    required this.relationships,
    this.anchorPersonId,
    this.onNodeTap,
    this.onNodeLongPress,
  });

  final List<Person> members;
  final List<FamilyRelationship> relationships;
  final String? anchorPersonId;
  final ValueChanged<Person>? onNodeTap;
  final void Function(Person person)? onNodeLongPress;


  @override
  State<FamilyTreeCanvas> createState() => _FamilyTreeCanvasState();
}

class _FamilyTreeCanvasState extends State<FamilyTreeCanvas> {
  Offset _offset = Offset.zero;
  double _scale = 1.0;
  String? _selectedNodeId;
  GraphFilters _filters = const GraphFilters();

  static const double nodeWidth = 160.0;
  static const double nodeHeight = 72.0;
  static const double horizontalGap = 24.0;
  static double verticalGap = 90.0;

  @override
  Widget build(BuildContext context) {
    final treeRoots = _buildTree();
    final activeMembers =
        widget.members.where((p) => p.deletedAt == null).toList();

    return Stack(
      children: [
        // Main canvas
        GestureDetector(
          onScaleStart: (_) {},
          onScaleUpdate: (details) {
            setState(() {
              _offset += details.focalPointDelta;
              _scale = (_scale * details.scale).clamp(0.25, 3.0);
            });
          },
          onDoubleTap: _fitToScreen,
          onTapUp: (details) {
            final localPos =
                (details.localPosition - _offset) / _scale;
            final layout = _computeLayout(treeRoots);
            String? tappedId;
            for (final entry in layout.positions.entries) {
              if (entry.value.contains(localPos)) {
                tappedId = entry.key;
                break;
              }
            }
            if (tappedId != null) {
              final person = widget.members.firstWhere(
                (p) => p.id == tappedId,
                orElse: () => Person(
                  id: tappedId!,
                  familyId: '',
                  name: 'Unknown',
                ),
              );
              setState(() => _selectedNodeId = tappedId);
              widget.onNodeTap?.call(person);
            }
          },
          onLongPressStart: (details) {
            final localPos =
                (details.localPosition - _offset) / _scale;
            final layout = _computeLayout(treeRoots);
            String? tappedId;
            for (final entry in layout.positions.entries) {
              if (entry.value.contains(localPos)) {
                tappedId = entry.key;
                break;
              }
            }
            if (tappedId != null) {
              final person = widget.members.firstWhere(
                (p) => p.id == tappedId,
                orElse: () => Person(
                  id: tappedId!,
                  familyId: '',
                  name: 'Unknown',
                ),
              );
              widget.onNodeLongPress?.call(person);
            }
          },
          child: ClipRect(
            child: CustomPaint(
              painter: _TreePainter(
                roots: treeRoots,
                offset: _offset,
                scale: _scale,
                selectedNodeId: _selectedNodeId,
                anchorPersonId: widget.anchorPersonId,
                members: widget.members,
                filters: _filters,
              ),
              size: Size.infinite,
            ),
          ),
        ),

        // Language selector (top-left, globe icon)
        Positioned(
          top: 8,
          left: 8,
          child: _LanguageSelectorButton(),
        ),

        // Filter bar (top-center)
        Positioned(
          top: 8,
          left: 52,
          right: 52,
          child: _FilterBar(
            filters: _filters,
            onFiltersChanged: (f) => setState(() => _filters = f),
          ),
        ),

        // Floating zoom controls (bottom-left)
        Positioned(
          bottom: 16,
          left: 16,
          child: _ZoomControls(
            scale: _scale,
            onZoomIn: () => setState(() {
              _scale = (_scale * 1.2).clamp(0.25, 3.0);
            }),
            onZoomOut: () => setState(() {
              _scale = (_scale / 1.2).clamp(0.25, 3.0);
            }),
            onFit: _fitToScreen,
          ),
        ),

        // Minimap (bottom-right)
        if (treeRoots.isNotEmpty)
          Positioned(
            bottom: 16,
            right: 16,
            child: _Minimap(
              roots: treeRoots,
              offset: _offset,
              scale: _scale,
              canvasSize: MediaQuery.of(context).size,
              onTap: (worldPos) {
                setState(() {
                  _offset = Offset(
                    MediaQuery.of(context).size.width / 2 - worldPos.dx * _scale,
                    MediaQuery.of(context).size.height / 2 - worldPos.dy * _scale,
                  );
                });
              },
              filters: _filters,
            ),
          ),
// Empty state
        if (activeMembers.isEmpty)
          Center(
            child: DKEmptyState(
              icon: Icons.account_tree_outlined,
              title: 'No Members Yet',
              subtitle: 'Add family members to start building your tree.',
            ),
          ),
      ],
    );
  }

  void _fitToScreen() {
    setState(() {
      _offset = Offset(40, 40);
      _scale = 1.0;
    });
  }

  List<VisTreeNode> _buildTree() {
    var activeMembers =
        widget.members.where((p) => p.deletedAt == null).toList();

    if (!_filters.showDeceased) {
      activeMembers = activeMembers.where((p) => !p.isDeceased).toList();
    }

    final persons = activeMembers.map((p) => p.toGraphPerson()).toList();
    final rels = widget.relationships
        .map((r) => r.toGraphEdge())
        .toList();

    if (persons.isEmpty) return [];

    final personMap = {for (final p in persons) p.id: p};

    final childOf = <String, String>{};
    final spouseOf = <String, String>{};
    final lineageOf = <String, String>{};

    for (final rel in rels) {
      final type = rel.type.toLowerCase();
      if (['child', 'son', 'daughter'].contains(type)) {
        childOf[rel.fromId] = rel.toId;
      } else if (['father', 'mother', 'parent'].contains(type)) {
        childOf[rel.toId] = rel.fromId;
      } else if (type == 'spouse' || type == 'husband' || type == 'wife') {
        if (_filters.showMaritalLinks) {
          spouseOf[rel.fromId] = rel.toId;
          spouseOf[rel.toId] = rel.fromId;
        }
      }

      if (type == 'father' ||
          type == 'paternal_grandfather' ||
          type == 'paternal_grandmother') {
        lineageOf[rel.toId] = 'paternal';
      } else if (type == 'mother' ||
          type == 'maternal_grandfather' ||
          type == 'maternal_grandmother') {
        lineageOf[rel.toId] = 'maternal';
      }
    }

    final rootIds = <String>{};
    for (final p in persons) {
      if (!childOf.containsKey(p.id)) {
        rootIds.add(p.id);
      }
    }

    if (rootIds.isEmpty && persons.isNotEmpty) {
      rootIds.add(persons.first.id);
    }

    final childrenOf = <String, List<String>>{};
    for (final entry in childOf.entries) {
      childrenOf.putIfAbsent(entry.value, () => []).add(entry.key);
    }

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

      String lineage = lineageOf[id] ?? '';
      if (id == widget.anchorPersonId) lineage = 'self';

      return VisTreeNode(
        person: person,
        spouse: spouse,
        children: childNodes,
        lineage: lineage,
      );
    }

    final roots = <VisTreeNode>[];
    for (final rootId in rootIds) {
      final node = buildNode(rootId);
      if (node != null) roots.add(node);
    }

    for (final p in persons) {
      if (!usedIds.contains(p.id)) {
        roots.add(VisTreeNode(
          person: p,
          lineage: p.id == widget.anchorPersonId ? 'self' : '',
        ));
        usedIds.add(p.id);
      }
    }

    return roots;
  }

  LayoutResult _computeLayout(List<VisTreeNode> roots) {
    final positions = <String, Rect>{};
    final nodes = <String, VisTreeNode>{};
    final lineages = <String, String>{};
    double xOffset = 40;

    for (final root in roots) {
      final width = _layoutSubtree(
        root, xOffset, 60, positions, nodes, lineages,
      );
      xOffset += width + horizontalGap * 2;
    }

    return LayoutResult(
      positions: positions,
      nodes: nodes,
      nodeLineages: lineages,
    );
  }

  double _layoutSubtree(
    VisTreeNode node,
    double xOffset,
    double yOffset,
    Map<String, Rect> positions,
    Map<String, VisTreeNode> nodes,
    Map<String, String> lineages,
  ) {
    final hasSpouse = node.spouse != null;
    final coupleWidth =
        hasSpouse ? nodeWidth * 2 + horizontalGap : nodeWidth;

    nodes[node.person.id] = node;
    lineages[node.person.id] = node.lineage;

    if (node.children.isEmpty) {
      positions[node.person.id] =
          Rect.fromLTWH(xOffset, yOffset, nodeWidth, nodeHeight);
      if (hasSpouse) {
        final spouseId = node.spouse!.id;
        positions[spouseId] = Rect.fromLTWH(
          xOffset + nodeWidth + horizontalGap,
          yOffset,
          nodeWidth,
          nodeHeight,
        );
        lineages[spouseId] = 'marital';
      }
      return coupleWidth;
    }

    double childX = xOffset;
    double maxChildWidth = 0;

    for (final child in node.children) {
      final w = _layoutSubtree(
        child, childX, yOffset + nodeHeight + verticalGap,
        positions, nodes, lineages,
      );
      maxChildWidth += w + horizontalGap;
      childX += w + horizontalGap;
    }

    maxChildWidth -= horizontalGap;

    final centerX = xOffset + maxChildWidth / 2 - coupleWidth / 2;
    positions[node.person.id] =
        Rect.fromLTWH(centerX, yOffset, nodeWidth, nodeHeight);
    if (hasSpouse) {
      final spouseId = node.spouse!.id;
      positions[spouseId] = Rect.fromLTWH(
        centerX + nodeWidth + horizontalGap,
        yOffset,
        nodeWidth,
        nodeHeight,
      );
      lineages[spouseId] = 'marital';
    }

    return math.max(maxChildWidth, coupleWidth);
  }
}

// ── Language Selector Button ────────────────────────────────────

class _LanguageSelectorButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isLight = DKColors.isLight(context);
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: isLight
            ? Colors.white.withValues(alpha: 0.9)
            : DKColors.darkBg.withValues(alpha: 0.85),
        shape: BoxShape.circle,
        border: Border.all(
          color: DKColors.brandPurple.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],),
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(Icons.language, color: DKColors.brandPurple, size: 18),
        tooltip: 'Language',
        onPressed: () {
          // TODO: Show language picker
        },
      ),
    );
  }
}

// ── Floating Zoom Controls ──────────────────────────────────────

class _ZoomControls extends StatelessWidget {
  const _ZoomControls({
    required this.scale,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
  });

  final double scale;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFit;


  @override
  Widget build(BuildContext context) {
    final isLight = DKColors.isLight(context);
    final bgColor = isLight
        ? Colors.white.withValues(alpha: 0.95)
        : const Color(0xFF1E1E2E);
    final iconColor = isLight ? DKColors.textDark : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(
          color: DKColors.brandPurple.withValues(alpha: 0.15),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ZoomButton(
            icon: Icons.add_rounded,
            color: iconColor,
            onTap: onZoomIn,
          ),
          Container(
            width: 32,
            height: 1,
            color: DKColors.brandPurple.withValues(alpha: 0.1),
          ),
          _ZoomButton(
            icon: Icons.remove_rounded,
            color: iconColor,
            onTap: onZoomOut,
          ),
          Container(
            width: 32,
            height: 1,
            color: DKColors.brandPurple.withValues(alpha: 0.1),
          ),
          _ZoomButton(
            icon: Icons.fit_screen_rounded,
            color: DKColors.brandPurple,
            onTap: onFit,
          ),
        ],
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;


  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(icon, color: color, size: 20),
        onPressed: onTap,
      ),
    );
  }
}

// ── Custom painter ─────────────────────────────────────────────────

class _TreePainter extends CustomPainter {
  _TreePainter({
    required this.roots,
    required this.offset,
    required this.scale,
    required this.selectedNodeId,
    required this.anchorPersonId,
    required this.members,
    required this.filters,
  });

  final List<VisTreeNode> roots;
  final Offset offset;
  final double scale;
  final String? selectedNodeId;
  final String? anchorPersonId;
  final List<Person> members;
  final GraphFilters filters;


  static const double nodeWidth = 160.0;
  static const double nodeHeight = 72.0;
  static const double horizontalGap = 24.0;
  static const double verticalGap = 90.0;
  static const double avatarSize = 32.0;
  static double radius = 12.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);

    if (roots.isEmpty) {
      canvas.restore();
      return;
    }

    final layout = _computeLayout();

    _drawGenerationLayers(canvas, size, layout);

    // Draw curved connections
    for (final root in roots) {
      _drawConnections(canvas, root, layout);
    }

    // Draw nodes
    for (final entry in layout.positions.entries) {
      final personId = entry.key;
      final rect = entry.value;
      final lineage = layout.nodeLineages[personId] ?? '';
      final node = layout.nodes[personId];
      _drawNode(
        canvas,
        personId: personId,
        personName: node?.person.name ?? 'Unknown',
        relationship: node?.person.relationship,
        isDeceased: node?.person.isDeceased ?? false,
        lineage: lineage,
        rect: rect,
        isSelected: personId == selectedNodeId,
        isAnchor: personId == anchorPersonId,
      );
    }

    canvas.restore();
  }

  void _drawGenerationLayers(
    Canvas canvas,
    Size size,
    LayoutResult layout,
  ) {
    if (layout.positions.isEmpty) return;

    final yPositions =
        layout.positions.values.map((r) => r.top).toSet().toList()..sort();

    for (int i = 0; i < yPositions.length; i++) {
      final y = yPositions[i];
      final genNumber = i + 1;

      if (!filters.visibleGenerations.contains(genNumber)) continue;

      final bandRect = Rect.fromLTWH(
        -offset.dx / scale - 200,
        y - 5,
        size.width / scale + 400,
        nodeHeight + 10,
      );

      final bandPaint = Paint()
        ..color = DKColors.brandPurple.withValues(alpha: 0.04);
      canvas.drawRect(bandRect, bandPaint);

      final labelPainter = TextPainter(
        text: TextSpan(
          text: 'Gen $genNumber',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 10,
            color: DKColors.brandPurple.withValues(alpha: 0.35),
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      labelPainter.layout();
      labelPainter.paint(
        canvas,
        Offset(-offset.dx / scale - 180, y + nodeHeight / 2 - 6),
      );
    }
  }

  /// Draw curved purple connectors between parent and children
  void _drawConnections(
    Canvas canvas,
    VisTreeNode node,
    LayoutResult layout,
  ) {
    final parentRect = layout.positions[node.person.id];
    if (parentRect == null) return;

    // Spouse connection (dotted purple)
    if (node.spouse != null && filters.showMaritalLinks) {
      final spouseRect = layout.positions[node.spouse!.id];
      if (spouseRect != null) {
        final startX = parentRect.right;
        final endX = spouseRect.left;
        final y = parentRect.top + parentRect.height / 2;

        final dotPaint = Paint()
          ..color = DKColors.brandPurple.withValues(alpha: 0.5)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke;

        _drawDottedLine(canvas, Offset(startX, y), Offset(endX, y), dotPaint);

        // Heart emoji in center
        final centerX = (startX + endX) / 2;
        final heartText = TextPainter(
          text: TextSpan(text: '💜', style: TextStyle(fontSize: 8)),
          textDirection: TextDirection.ltr,
        );
        heartText.layout();
        heartText.paint(
          canvas,
          Offset(centerX - heartText.width / 2, y - heartText.height / 2),
        );
      }
    }

    // Parent-child curved connections (purple, 50% opacity)
    if (node.children.isNotEmpty) {
      final parentBottom = Offset(
        parentRect.left + parentRect.width / 2,
        parentRect.bottom,
      );

      final childPositions = <Offset>[];
      for (final child in node.children) {
        final childRect = layout.positions[child.person.id];
        if (childRect == null) continue;
        childPositions.add(Offset(
          childRect.left + childRect.width / 2,
          childRect.top,
        ));
      }

      if (childPositions.isNotEmpty) {
        // Draw curved paths in purple with 50% opacity
        final curvePaint = Paint()
          ..color = DKColors.brandPurple.withValues(alpha: 0.5)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

        for (final childTop in childPositions) {
          // Draw a curved bezier path from parent to child
          final path = Path();
          path.moveTo(parentBottom.dx, parentBottom.dy);

          final midY = (parentBottom.dy + childTop.dy) / 2;

          // Curved path: down from parent, curve to child
          path.cubicTo(
            parentBottom.dx, midY,
            childTop.dx, midY,
            childTop.dx, childTop.dy,
          );

          canvas.drawPath(path, curvePaint);
        }
      }
    }

    // Recurse
    for (final child in node.children) {
      _drawConnections(canvas, child, layout);
    }
  }

  void _drawDottedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint,
  ) {
    const dashLength = 4.0;
    const gapLength = 4.0;
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final distance = math.sqrt(dx * dx + dy * dy);
    final steps = (distance / (dashLength + gapLength)).floor();

    for (int i = 0; i < steps; i++) {
      final startFraction = i * (dashLength + gapLength) / distance;
      final endFraction =
          (i * (dashLength + gapLength) + dashLength) / distance;
      canvas.drawLine(
        Offset(start.dx + dx * startFraction,
            start.dy + dy * startFraction),
        Offset(start.dx + dx * endFraction,
            start.dy + dy * endFraction),
        paint,
      );
    }
  }

  void _drawNode(
    Canvas canvas, {
    required String personId,
    required String personName,
    required String? relationship,
    required bool isDeceased,
    required String lineage,
    required Rect rect,
    required bool isSelected,
    required bool isAnchor,
  }) {
    final nodeLineage = _parseLineage(lineage);

    // Purple glow for anchor/self person
    if (isAnchor) {
      final glowPaint = Paint()
        ..color = DKColors.brandPurple.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            rect.inflate(8), Radius.circular(radius + 4)),
        glowPaint,
      );
    }

    // Glow for selected node
    if (isSelected && !isAnchor) {
      final glowPaint = Paint()
        ..color = DKColors.brandGold.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            rect.inflate(4), Radius.circular(radius + 2)),
        glowPaint,
      );
    }

    // Background with lineage tint
    final bgColor = _lineageBgColor(nodeLineage);
    final bgPaint = Paint()..color = bgColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      bgPaint,
    );

    // Border — purple for anchor, gold for selected
    final borderColor = isAnchor
        ? DKColors.brandPurple
        : isSelected
            ? DKColors.brandGold
            : _lineageBorderColor(nodeLineage);
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = isAnchor ? 2.5 : isSelected ? 2 : 1;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      borderPaint,
    );

    // Deceased overlay
    if (isDeceased) {
      final deceasedPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.1);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)),
        deceasedPaint,
      );
    }

    // Avatar circle with purple gradient
    final avatarRect = Rect.fromLTWH(
      rect.left + 8,
      rect.top + (rect.height - avatarSize) / 2,
      avatarSize,
      avatarSize,
    );
    final avatarGradient = _avatarGradient(nodeLineage, isDeceased);
    final avatarPaint = Paint()
      ..shader = avatarGradient.createShader(avatarRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          avatarRect, Radius.circular(avatarSize / 2)),
      avatarPaint,
    );

    // Avatar initial or dove
    if (isDeceased) {
      final dovePainter = TextPainter(
        text: TextSpan(text: '🕊️', style: TextStyle(fontSize: 14)),
        textDirection: TextDirection.ltr,
      );
      dovePainter.layout();
      dovePainter.paint(
        canvas,
        Offset(
          avatarRect.left + (avatarSize - dovePainter.width) / 2,
          avatarRect.top + (avatarSize - dovePainter.height) / 2,
        ),
      );
    } else {
      final initial =
          personName.isNotEmpty ? personName[0].toUpperCase() : '?';
      final initialPainter = TextPainter(
        text: TextSpan(
          text: initial,
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      initialPainter.layout();
      initialPainter.paint(
        canvas,
        Offset(
          avatarRect.left + (avatarSize - initialPainter.width) / 2,
          avatarRect.top + (avatarSize - initialPainter.height) / 2,
        ),
      );
    }

    // Gender symbol
    final genderIcon = _genderFromRelationship(relationship);
    final genderSymbol =
        genderIcon == 'male' ? '♂' : genderIcon == 'female' ? '♀' : '○';
    final genderColor = genderIcon == 'male'
        ? DKColors.brandBlue
        : genderIcon == 'female'
            ? DKColors.brandCoral
            : DKColors.textSecondaryLight;
    final genderPainter = TextPainter(
      text: TextSpan(
        text: genderSymbol,
        style: TextStyle(fontSize: 10, color: genderColor),
      ),
      textDirection: TextDirection.ltr,
    );
    genderPainter.layout();
    genderPainter.paint(
      canvas,
      Offset(rect.right - 16, rect.top + 6),
    );

    // Name text
    final textStartX = avatarRect.right + 8;
    final textMaxWidth = rect.right - textStartX - 24;

    final namePainter = TextPainter(
      text: TextSpan(
        text: personName,
        style: TextStyle(
          fontFamily: KinrelTypography.displayFont,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    );
    namePainter.layout(maxWidth: textMaxWidth);
    namePainter.paint(canvas, Offset(textStartX, rect.top + 12));

    // Relationship label (purple accent)
    if (relationship != null && relationship.isNotEmpty) {
      final relPainter = TextPainter(
        text: TextSpan(
          text: relationship.replaceAll('_', ' '),
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: DKColors.brandPurple.withValues(alpha: 0.8),
            letterSpacing: 0.3,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...',
      );
      relPainter.layout(maxWidth: textMaxWidth);
      relPainter.paint(canvas, Offset(textStartX, rect.top + 34));
    }

    // Lineage tag
    if (lineage.isNotEmpty && lineage != 'self') {
      final tagPainter = TextPainter(
        text: TextSpan(
          text: lineage.split("_").map((w) => w[0].toUpperCase() + w.substring(1)).join(" "),
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 8,
            fontWeight: FontWeight.w700,
            color: _lineageBorderColor(nodeLineage),
            letterSpacing: 0.5,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tagPainter.layout();
      tagPainter.paint(canvas, Offset(textStartX, rect.top + 52));
    }
  }

  NodeLineage _parseLineage(String lineage) {
    switch (lineage.toLowerCase()) {
      case 'paternal':
        return NodeLineage.paternal;
      case 'maternal':
        return NodeLineage.maternal;
      case 'marital':
        return NodeLineage.marital;
      case 'self':
        return NodeLineage.self;
      default:
        return NodeLineage.none;
    }
  }

  Color _lineageBgColor(NodeLineage lineage) {
    switch (lineage) {
      case NodeLineage.paternal:
        return DKColors.brandPurple.withValues(alpha: 0.08);
      case NodeLineage.maternal:
        return DKColors.brandGold.withValues(alpha: 0.06);
      case NodeLineage.marital:
        return DKColors.brandViolet.withValues(alpha: 0.06);
      case NodeLineage.self:
        return DKColors.brandPurple.withValues(alpha: 0.1);
      case NodeLineage.none:
        return DKColors.darkCard;
    }
  }

  Color _lineageBorderColor(NodeLineage lineage) {
    switch (lineage) {
      case NodeLineage.paternal:
        return DKColors.brandPurple.withValues(alpha: 0.4);
      case NodeLineage.maternal:
        return DKColors.brandGold.withValues(alpha: 0.4);
      case NodeLineage.marital:
        return DKColors.brandViolet.withValues(alpha: 0.4);
      case NodeLineage.self:
        return DKColors.brandPurple.withValues(alpha: 0.6);
      case NodeLineage.none:
        return DKColors.brandPurple.withValues(alpha: 0.15);
    }
  }

  LinearGradient _avatarGradient(NodeLineage lineage, bool isDeceased) {
    if (isDeceased) {
      return LinearGradient(
        colors: [Colors.grey, DKColors.darkElevated],
      );
    }
    switch (lineage) {
      case NodeLineage.paternal:
        return const LinearGradient(
            colors: [DKColors.brandPurple, DKColors.brandViolet]);
      case NodeLineage.maternal:
        return const LinearGradient(
            colors: [DKColors.brandGold, DKColors.brandBrightGold]);
      case NodeLineage.marital:
        return const LinearGradient(
            colors: [DKColors.brandViolet, DKColors.brandCoral]);
      case NodeLineage.self:
        return const LinearGradient(
            colors: [DKColors.brandPurple, DKColors.brandViolet]);
      case NodeLineage.none:
        return LinearGradient(
            colors: [DKColors.brandPurple, DKColors.brandDeepPurple]);
    }
  }

  String _genderFromRelationship(String? rel) {
    if (rel == null) return 'other';
    maleTerms = [
      'father', 'brother', 'son', 'husband', 'uncle', 'grandfather', 'nephew',
    ];
    femaleTerms = [
      'mother', 'sister', 'daughter', 'wife', 'aunt', 'grandmother', 'niece',
    ];
    final lower = rel.toLowerCase();
    for (final t in maleTerms) {
      if (lower.contains(t)) return 'male';
    }
    for (final t in femaleTerms) {
      if (lower.contains(t)) return 'female';
    }
    return 'other';
  }

  LayoutResult _computeLayout() {
    final positions = <String, Rect>{};
    final nodes = <String, VisTreeNode>{};
    final lineages = <String, String>{};
    double xOffset = 40;

    double layoutSubtree(
      VisTreeNode node,
      double xOff,
      double yOff,
    ) {
      final hasSpouse = node.spouse != null;
      final coupleWidth =
          hasSpouse ? nodeWidth * 2 + horizontalGap : nodeWidth;

      nodes[node.person.id] = node;
      lineages[node.person.id] = node.lineage;

      if (node.children.isEmpty) {
        positions[node.person.id] =
            Rect.fromLTWH(xOff, yOff, nodeWidth, nodeHeight);
        if (hasSpouse) {
          positions[node.spouse!.id] = Rect.fromLTWH(
            xOff + nodeWidth + horizontalGap,
            yOff,
            nodeWidth,
            nodeHeight,
          );
          lineages[node.spouse!.id] = 'marital';
        }
        return coupleWidth;
      }

      double childX = xOff;
      double maxChildWidth = 0;

      for (final child in node.children) {
        final w = layoutSubtree(child, childX, yOff + nodeHeight + verticalGap);
        maxChildWidth += w + horizontalGap;
        childX += w + horizontalGap;
      }

      maxChildWidth -= horizontalGap;

      final centerX = xOff + maxChildWidth / 2 - coupleWidth / 2;
      positions[node.person.id] =
          Rect.fromLTWH(centerX, yOff, nodeWidth, nodeHeight);
      if (hasSpouse) {
        positions[node.spouse!.id] = Rect.fromLTWH(
          centerX + nodeWidth + horizontalGap,
          yOff,
          nodeWidth,
          nodeHeight,
        );
        lineages[node.spouse!.id] = 'marital';
      }

      return math.max(maxChildWidth, coupleWidth);
    }

    for (final root in roots) {
      final width = layoutSubtree(root, xOffset, 60);
      xOffset += width + horizontalGap * 2;
    }

    return LayoutResult(
      positions: positions,
      nodes: nodes,
      nodeLineages: lineages,
    );
  }

  @override
  bool shouldRepaint(covariant _TreePainter oldDelegate) {
    return oldDelegate.roots != roots ||
        oldDelegate.offset != offset ||
        oldDelegate.scale != scale ||
        oldDelegate.selectedNodeId != selectedNodeId ||
        oldDelegate.filters != filters;
  }
}

// ── Filter bar ─────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filters,
    required this.onFiltersChanged,
  });

  final GraphFilters filters;
  final ValueChanged<GraphFilters> onFiltersChanged;


  @override
  Widget build(BuildContext context) {
    final isLight = DKColors.isLight(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.sm,
        vertical: KinrelSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: isLight
            ? Colors.white.withValues(alpha: 0.9)
            : DKColors.darkBg.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusLg),
        border: Border.all(
          color: DKColors.brandPurple.withValues(alpha: 0.15),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (int gen = 1; gen <= 5; gen++)
              Padding(
                padding: EdgeInsets.only(right: 4),
                child: DKSuggestionChip(
                  label: 'G$gen',
                  isSelected: filters.visibleGenerations.contains(gen),
                  onTap: () {
                    final newGens =
                        Set<int>.from(filters.visibleGenerations);
                    if (newGens.contains(gen)) {
                      newGens.remove(gen);
                    } else {
                      newGens.add(gen);
                    }
                    onFiltersChanged(
                      filters.copyWith(visibleGenerations: newGens),
                    );
                  },
                ),
              ),

            const SizedBox(width: 8),
            Container(
              width: 1,
              height: 20,
              color: DKColors.brandPurple.withValues(alpha: 0.15),
            ),
            SizedBox(width: 8),

            DKSuggestionChip(
              label: 'All',
              isSelected: filters.branch == 'all',
              onTap: () =>
                  onFiltersChanged(filters.copyWith(branch: 'all')),
            ),
            DKSuggestionChip(
              label: 'Paternal',
              isSelected: filters.branch == 'paternal',
              onTap: () =>
                  onFiltersChanged(filters.copyWith(branch: 'paternal')),
            ),
            DKSuggestionChip(
              label: 'Maternal',
              isSelected: filters.branch == 'maternal',
              onTap: () =>
                  onFiltersChanged(filters.copyWith(branch: 'maternal')),
            ),

            const SizedBox(width: 8),
            Container(
              width: 1,
              height: 20,
              color: DKColors.brandPurple.withValues(alpha: 0.15),
            ),
            SizedBox(width: 8),

            DKSuggestionChip(
              label: 'Deceased',
              isSelected: filters.showDeceased,
              onTap: () => onFiltersChanged(
                filters.copyWith(showDeceased: !filters.showDeceased),
              ),
            ),
            DKSuggestionChip(
              label: 'Marital',
              isSelected: filters.showMaritalLinks,
              onTap: () => onFiltersChanged(
                filters.copyWith(
                    showMaritalLinks: !filters.showMaritalLinks),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Minimap ────────────────────────────────────────────────────────

class _Minimap extends StatelessWidget {
  const _Minimap({
    required this.roots,
    required this.offset,
    required this.scale,
    required this.canvasSize,
    required this.onTap,
    required this.filters,
  });

  final List<VisTreeNode> roots;
  final Offset offset;
  final double scale;
  final Size canvasSize;
  final ValueChanged<Offset> onTap;
  final GraphFilters filters;


  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapUp: (details) {
        final localPos = details.localPosition;
        const minimapW = 140.0;
        const minimapH = 100.0;

        final layout = _computeLayout();
        if (layout.isEmpty) return;

        final minX = layout.values.map((r) => r.left).reduce(math.min);
        final maxX = layout.values.map((r) => r.right).reduce(math.max);
        final minY = layout.values.map((r) => r.top).reduce(math.min);
        final maxY = layout.values.map((r) => r.bottom).reduce(math.max);

        final worldX = minX + (localPos.dx / minimapW) * (maxX - minX);
        final worldY = minY + (localPos.dy / minimapH) * (maxY - minY);

        onTap(Offset(worldX, worldY));
      },
      child: Container(
        width: 140,
        height: 100,
        decoration: BoxDecoration(
          color: DKColors.cardColor(context),
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          border: Border.all(
            color: DKColors.brandPurple.withValues(alpha: 0.2),
          ),
        ),
        child: CustomPaint(
          painter: _MinimapPainter(
            roots: roots,
            offset: offset,
            scale: scale,
            canvasSize: canvasSize,
            filters: filters,
          ),
          size: const Size(140, 100),
        ),
      ),
    );
  }

  Map<String, Rect> _computeLayout() {
    final positions = <String, Rect>{};
    double xOffset = 40;

    double layoutSubtree(VisTreeNode node, double xOff, double yOff) {
      const nw = 160.0;
      const nh = 72.0;
      const hg = 24.0;
      const vg = 90.0;

      final hasSpouse = node.spouse != null;
      final coupleWidth = hasSpouse ? nw * 2 + hg : nw;

      if (node.children.isEmpty) {
        positions[node.person.id] = Rect.fromLTWH(xOff, yOff, nw, nh);
        if (hasSpouse) {
          positions[node.spouse!.id] = Rect.fromLTWH(
            xOff + nw + hg, yOff, nw, nh,
          );
        }
        return coupleWidth;
      }

      double childX = xOff;
      double maxChildWidth = 0;

      for (final child in node.children) {
        final w = layoutSubtree(child, childX, yOff + nh + vg);
        maxChildWidth += w + hg;
        childX += w + hg;
      }

      maxChildWidth -= hg;
      final centerX = xOff + maxChildWidth / 2 - coupleWidth / 2;
      positions[node.person.id] = Rect.fromLTWH(centerX, yOff, nw, nh);
      if (hasSpouse) {
        positions[node.spouse!.id] = Rect.fromLTWH(
          centerX + nw + hg, yOff, nw, nh,
        );
      }

      return math.max(maxChildWidth, coupleWidth);
    }

    for (final root in roots) {
      final width = layoutSubtree(root, xOffset, 60);
      xOffset += width + 48;
    }

    return positions;
  }
}

class _MinimapPainter extends CustomPainter {
  _MinimapPainter({
    required this.roots,
    required this.offset,
    required this.scale,
    required this.canvasSize,
    required this.filters,
  });

  final List<VisTreeNode> roots;
  final Offset offset;
  final double scale;
  final Size canvasSize;
  final GraphFilters filters;


  @override
  void paint(Canvas canvas, Size size) {
    final positions = _computeLayout();
    if (positions.isEmpty) return;

    final minX = positions.values.map((r) => r.left).reduce(math.min);
    final maxX = positions.values.map((r) => r.right).reduce(math.max);
    final minY = positions.values.map((r) => r.top).reduce(math.min);
    final maxY = positions.values.map((r) => r.bottom).reduce(math.max);

    final worldW = maxX - minX + 40;
    final worldH = maxY - minY + 40;
    final scaleX = size.width / worldW;
    final scaleY = size.height / worldH;
    final s = math.min(scaleX, scaleY) * 0.9;

    final paint = Paint()..color = DKColors.brandPurple.withValues(alpha: 0.5);
    final viewportPaint = Paint()
      ..color = DKColors.brandGold.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (final rect in positions.values) {
      final miniRect = Rect.fromLTWH(
        (rect.left - minX + 20) * s,
        (rect.top - minY + 20) * s,
        rect.width * s,
        rect.height * s,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(miniRect, Radius.circular(3 * s)),
        paint,
      );
    }

    // Viewport indicator
    final vpLeft = (-offset.dx / scale - minX + 20) * s;
    final vpTop = (-offset.dy / scale - minY + 20) * s;
    final vpW = (canvasSize.width / scale) * s;
    final vpH = (canvasSize.height / scale) * s;
    canvas.drawRect(Rect.fromLTWH(vpLeft, vpTop, vpW, vpH), viewportPaint);
  }

  Map<String, Rect> _computeLayout() {
    final positions = <String, Rect>{};
    double xOffset = 40;

    double layoutSubtree(VisTreeNode node, double xOff, double yOff) {
      const nw = 160.0;
      const nh = 72.0;
      const hg = 24.0;
      const vg = 90.0;

      final hasSpouse = node.spouse != null;
      final coupleWidth = hasSpouse ? nw * 2 + hg : nw;

      if (node.children.isEmpty) {
        positions[node.person.id] = Rect.fromLTWH(xOff, yOff, nw, nh);
        if (hasSpouse) {
          positions[node.spouse!.id] = Rect.fromLTWH(xOff + nw + hg, yOff, nw, nh);
        }
        return coupleWidth;
      }

      double childX = xOff;
      double maxChildWidth = 0;

      for (final child in node.children) {
        final w = layoutSubtree(child, childX, yOff + nh + vg);
        maxChildWidth += w + hg;
        childX += w + hg;
      }

      maxChildWidth -= hg;
      final centerX = xOff + maxChildWidth / 2 - coupleWidth / 2;
      positions[node.person.id] = Rect.fromLTWH(centerX, yOff, nw, nh);
      if (hasSpouse) {
        positions[node.spouse!.id] = Rect.fromLTWH(centerX + nw + hg, yOff, nw, nh);
      }

      return math.max(maxChildWidth, coupleWidth);
    }

    for (final root in roots) {
      final width = layoutSubtree(root, xOffset, 60);
      xOffset += width + 48;
    }

    return positions;
  }

  @override
  bool shouldRepaint(covariant _MinimapPainter oldDelegate) {
    return oldDelegate.offset != offset || oldDelegate.scale != scale;
  }
}
