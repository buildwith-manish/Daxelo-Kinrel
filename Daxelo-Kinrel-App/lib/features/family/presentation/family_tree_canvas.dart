import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/graph/graph_service.dart';
import '../../../core/family/family_provider.dart';

// ── Data models for visualization ──────────────────────────────────

/// Extended tree node with layout metadata
class VisTreeNode {
  final GraphPerson person;
  final GraphPerson? spouse;
  final List<VisTreeNode> children;
  final String lineage; // 'paternal', 'maternal', 'marital', 'self'

  const VisTreeNode({
    required this.person,
    this.spouse,
    this.children = const [],
    this.lineage = '',
  });
}

/// Lineage color coding for node backgrounds
enum NodeLineage { paternal, maternal, marital, self, none }

// ── Filter state ───────────────────────────────────────────────────

class GraphFilters {
  final Set<int> visibleGenerations;
  final String branch; // 'all', 'paternal', 'maternal'
  final bool showDeceased;
  final bool showMaritalLinks;

  const GraphFilters({
    this.visibleGenerations = const {1, 2, 3, 4, 5},
    this.branch = 'all',
    this.showDeceased = true,
    this.showMaritalLinks = true,
  });

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

/// Stores layout position and node metadata keyed by person ID
class LayoutResult {
  final Map<String, Rect> positions;
  final Map<String, VisTreeNode> nodes;
  final Map<String, String> nodeLineages;

  const LayoutResult({
    required this.positions,
    required this.nodes,
    required this.nodeLineages,
  });
}

// ── Main canvas widget ─────────────────────────────────────────────

/// Advanced family tree canvas with generation layers, minimap,
/// filters, lineage coloring, and rich node design.
class FamilyTreeCanvas extends StatefulWidget {
  final List<Person> members;
  final List<FamilyRelationship> relationships;
  final String? anchorPersonId;
  final ValueChanged<Person>? onNodeTap;
  final void Function(Person person)? onNodeLongPress;

  const FamilyTreeCanvas({
    super.key,
    required this.members,
    required this.relationships,
    this.anchorPersonId,
    this.onNodeTap,
    this.onNodeLongPress,
  });

  @override
  State<FamilyTreeCanvas> createState() => _FamilyTreeCanvasState();
}

class _FamilyTreeCanvasState extends State<FamilyTreeCanvas> {
  Offset _offset = Offset.zero;
  double _scale = 1.0;
  String? _selectedNodeId;
  GraphFilters _filters = const GraphFilters();

  // Node dimensions
  static const double nodeWidth = 160.0;
  static const double nodeHeight = 72.0;
  static const double horizontalGap = 24.0;
  static const double verticalGap = 90.0;

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

        // Filter bar (top)
        Positioned(
          top: 8,
          left: 8,
          right: 8,
          child: _FilterBar(
            filters: _filters,
            onFiltersChanged: (f) => setState(() => _filters = f),
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
            child: _EmptyCanvasState(
              onAddMember: () {},
            ),
          ),
      ],
    );
  }

  void _fitToScreen() {
    setState(() {
      _offset = const Offset(40, 40);
      _scale = 1.0;
    });
  }

  /// Build tree hierarchy from flat person + relationship data
  List<VisTreeNode> _buildTree() {
    var activeMembers =
        widget.members.where((p) => p.deletedAt == null).toList();

    // Filter deceased if needed
    if (!_filters.showDeceased) {
      activeMembers = activeMembers.where((p) => !p.isDeceased).toList();
    }

    final persons = activeMembers.map((p) => p.toGraphPerson()).toList();
    final rels = widget.relationships
        .map((r) => r.toGraphEdge())
        .toList();

    if (persons.isEmpty) return [];

    final personMap = {for (final p in persons) p.id: p};

    // Find parent-child relationships
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

      // Assign lineage
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

    // Find roots (persons without parents)
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

    // Add remaining unlinked persons
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

  /// Compute layout positions for all nodes
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

    // Store node data
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

// ── Custom painter ─────────────────────────────────────────────────

class _TreePainter extends CustomPainter {
  final List<VisTreeNode> roots;
  final Offset offset;
  final double scale;
  final String? selectedNodeId;
  final String? anchorPersonId;
  final List<Person> members;
  final GraphFilters filters;

  _TreePainter({
    required this.roots,
    required this.offset,
    required this.scale,
    required this.selectedNodeId,
    required this.anchorPersonId,
    required this.members,
    required this.filters,
  });

  static const double nodeWidth = 160.0;
  static const double nodeHeight = 72.0;
  static const double horizontalGap = 24.0;
  static const double verticalGap = 90.0;
  static const double avatarSize = 32.0;
  static const double radius = 12.0;

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

    // Draw generation layers
    _drawGenerationLayers(canvas, size, layout);

    // Draw connecting lines
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
        ..color = KinrelColors.darkSurface.withValues(alpha: 0.15);
      canvas.drawRect(bandRect, bandPaint);

      final labelPainter = TextPainter(
        text: TextSpan(
          text: 'Gen $genNumber',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 10,
            color: KinrelColors.textDim.withValues(alpha: 0.4),
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

  void _drawConnections(
    Canvas canvas,
    VisTreeNode node,
    LayoutResult layout,
  ) {
    final parentRect = layout.positions[node.person.id];
    if (parentRect == null) return;

    // Draw spouse connection (dotted line)
    if (node.spouse != null && filters.showMaritalLinks) {
      final spouseRect = layout.positions[node.spouse!.id];
      if (spouseRect != null) {
        final startX = parentRect.right;
        final endX = spouseRect.left;
        final y = parentRect.top + parentRect.height / 2;

        final dotPaint = Paint()
          ..color = KinrelColors.durgaPurple.withValues(alpha: 0.5)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke;

        _drawDottedLine(canvas, Offset(startX, y), Offset(endX, y), dotPaint);

        // Ring emoji in center
        final centerX = (startX + endX) / 2;
        final ringText = TextPainter(
          text: const TextSpan(text: '💍', style: TextStyle(fontSize: 8)),
          textDirection: TextDirection.ltr,
        );
        ringText.layout();
        ringText.paint(
          canvas,
          Offset(centerX - ringText.width / 2, y - ringText.height / 2),
        );
      }
    }

    // Draw parent-child connections (solid lines)
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
        final midY = parentBottom.dy + verticalGap * 0.4;
        final linePaint = Paint()
          ..color = KinrelColors.darkSurface
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke;

        // Vertical line from parent
        canvas.drawLine(
          parentBottom,
          Offset(parentBottom.dx, midY),
          linePaint,
        );

        if (childPositions.length == 1) {
          final childTop = childPositions.first;
          canvas.drawLine(
            Offset(parentBottom.dx, midY),
            Offset(childTop.dx, midY),
            linePaint,
          );
          canvas.drawLine(
            Offset(childTop.dx, midY),
            childTop,
            linePaint,
          );
        } else {
          final leftX =
              childPositions.map((p) => p.dx).reduce(math.min);
          final rightX =
              childPositions.map((p) => p.dx).reduce(math.max);

          // Horizontal bracket
          canvas.drawLine(
            Offset(leftX, midY),
            Offset(rightX, midY),
            linePaint,
          );

          for (final childTop in childPositions) {
            canvas.drawLine(
              Offset(childTop.dx, midY),
              childTop,
              linePaint,
            );
          }
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

    // Glow effect for anchor person
    if (isAnchor) {
      final glowPaint = Paint()
        ..color = KinrelColors.orangeGlow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            rect.inflate(8), const Radius.circular(radius + 4)),
        glowPaint,
      );
    }

    // Glow effect for selected node
    if (isSelected) {
      final glowPaint = Paint()
        ..color = KinrelColors.orangeGlow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            rect.inflate(4), const Radius.circular(radius + 2)),
        glowPaint,
      );
    }

    // Background with lineage tint
    final bgColor = _lineageBgColor(nodeLineage);
    final bgPaint = Paint()..color = bgColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(radius)),
      bgPaint,
    );

    // Border
    final borderColor = isAnchor
        ? KinrelColors.orange
        : isSelected
            ? KinrelColors.amber
            : _lineageBorderColor(nodeLineage);
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = isAnchor ? 2.5 : isSelected ? 2 : 1;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(radius)),
      borderPaint,
    );

    // Deceased overlay
    if (isDeceased) {
      final deceasedPaint = Paint()
        ..color = KinrelColors.textDim.withValues(alpha: 0.2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(radius)),
        deceasedPaint,
      );
    }

    // Avatar circle
    final avatarRect = Rect.fromLTWH(
      rect.left + 8,
      rect.top + (rect.height - avatarSize) / 2,
      avatarSize,
      avatarSize,
    );
    final avatarGradient =
        _avatarGradient(nodeLineage, isDeceased);
    final avatarPaint = Paint()
      ..shader = avatarGradient.createShader(avatarRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          avatarRect, const Radius.circular(avatarSize / 2)),
      avatarPaint,
    );

    // Avatar initial or dove
    if (isDeceased) {
      final dovePainter = TextPainter(
        text: const TextSpan(text: '🕊️', style: TextStyle(fontSize: 14)),
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
        ? KinrelColors.info
        : genderIcon == 'female'
            ? KinrelColors.holiPink
            : KinrelColors.textDim;
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
          color: isDeceased ? KinrelColors.textSilver : KinrelColors.textWhite,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    );
    namePainter.layout(maxWidth: textMaxWidth);
    namePainter.paint(canvas, Offset(textStartX, rect.top + 12));

    // Relationship label
    if (relationship != null && relationship.isNotEmpty) {
      final relPainter = TextPainter(
        text: TextSpan(
          text: relationship.replaceAll('_', ' '),
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: _lineageTextColor(nodeLineage),
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
        return KinrelColors.orange.withValues(alpha: 0.06);
      case NodeLineage.maternal:
        return KinrelColors.amber.withValues(alpha: 0.06);
      case NodeLineage.marital:
        return KinrelColors.durgaPurple.withValues(alpha: 0.06);
      case NodeLineage.self:
        return KinrelColors.success.withValues(alpha: 0.08);
      case NodeLineage.none:
        return KinrelColors.darkCard;
    }
  }

  Color _lineageBorderColor(NodeLineage lineage) {
    switch (lineage) {
      case NodeLineage.paternal:
        return KinrelColors.orange.withValues(alpha: 0.4);
      case NodeLineage.maternal:
        return KinrelColors.amber.withValues(alpha: 0.4);
      case NodeLineage.marital:
        return KinrelColors.durgaPurple.withValues(alpha: 0.4);
      case NodeLineage.self:
        return KinrelColors.success.withValues(alpha: 0.5);
      case NodeLineage.none:
        return KinrelColors.darkSurface.withValues(alpha: 0.5);
    }
  }

  Color _lineageTextColor(NodeLineage lineage) {
    switch (lineage) {
      case NodeLineage.paternal:
        return KinrelColors.orange;
      case NodeLineage.maternal:
        return KinrelColors.amber;
      case NodeLineage.marital:
        return KinrelColors.durgaPurple;
      case NodeLineage.self:
        return KinrelColors.success;
      case NodeLineage.none:
        return KinrelColors.orange;
    }
  }

  LinearGradient _avatarGradient(NodeLineage lineage, bool isDeceased) {
    if (isDeceased) {
      return LinearGradient(
        colors: [KinrelColors.textDim, KinrelColors.darkSurface],
      );
    }
    switch (lineage) {
      case NodeLineage.paternal:
        return const LinearGradient(
            colors: [KinrelColors.orange, KinrelColors.ember]);
      case NodeLineage.maternal:
        return const LinearGradient(
            colors: [KinrelColors.amber, KinrelColors.orange]);
      case NodeLineage.marital:
        return LinearGradient(
            colors: [KinrelColors.durgaPurple, KinrelColors.holiPink]);
      case NodeLineage.self:
        return const LinearGradient(
            colors: [KinrelColors.success, KinrelColors.eidGreen]);
      case NodeLineage.none:
        return KinrelColors.igniteGradient;
    }
  }

  String _genderFromRelationship(String? rel) {
    if (rel == null) return 'other';
    const maleTerms = [
      'father', 'brother', 'son', 'husband', 'uncle', 'grandfather', 'nephew',
    ];
    const femaleTerms = [
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
  final GraphFilters filters;
  final ValueChanged<GraphFilters> onFiltersChanged;

  const _FilterBar({
    required this.filters,
    required this.onFiltersChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.sm,
        vertical: KinrelSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: KinrelColors.darkBackground.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusLg),
        border: Border.all(
          color: KinrelColors.darkSurface.withValues(alpha: 0.3),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Generation chips
            for (int gen = 1; gen <= 5; gen++)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _FilterChip(
                  label: 'G$gen',
                  selected: filters.visibleGenerations.contains(gen),
                  selectedColor: KinrelColors.orange,
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
              color: KinrelColors.darkSurface,
            ),
            const SizedBox(width: 8),

            // Branch chips
            _FilterChip(
              label: 'All',
              selected: filters.branch == 'all',
              selectedColor: KinrelColors.textSilver,
              onTap: () =>
                  onFiltersChanged(filters.copyWith(branch: 'all')),
            ),
            _FilterChip(
              label: 'Paternal',
              selected: filters.branch == 'paternal',
              selectedColor: KinrelColors.orange,
              onTap: () =>
                  onFiltersChanged(filters.copyWith(branch: 'paternal')),
            ),
            _FilterChip(
              label: 'Maternal',
              selected: filters.branch == 'maternal',
              selectedColor: KinrelColors.amber,
              onTap: () =>
                  onFiltersChanged(filters.copyWith(branch: 'maternal')),
            ),

            const SizedBox(width: 8),
            Container(
              width: 1,
              height: 20,
              color: KinrelColors.darkSurface,
            ),
            const SizedBox(width: 8),

            // Show/Hide deceased
            _FilterChip(
              label: 'Deceased',
              selected: filters.showDeceased,
              selectedColor: KinrelColors.textDim,
              onTap: () => onFiltersChanged(
                filters.copyWith(showDeceased: !filters.showDeceased),
              ),
            ),

            // Show/Hide marital
            _FilterChip(
              label: 'Marital',
              selected: filters.showMaritalLinks,
              selectedColor: KinrelColors.durgaPurple,
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

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color selectedColor;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.selectedColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: KinrelMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? selectedColor.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? selectedColor.withValues(alpha: 0.5)
                : KinrelColors.darkSurface.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: selected ? selectedColor : KinrelColors.textDim,
          ),
        ),
      ),
    );
  }
}

// ── Minimap ────────────────────────────────────────────────────────

class _Minimap extends StatelessWidget {
  final List<VisTreeNode> roots;
  final Offset offset;
  final double scale;
  final Size canvasSize;
  final ValueChanged<Offset> onTap;
  final GraphFilters filters;

  const _Minimap({
    required this.roots,
    required this.offset,
    required this.scale,
    required this.canvasSize,
    required this.onTap,
    required this.filters,
  });

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

        final treeWidth = maxX - minX + 80;
        final treeHeight = maxY - minY + 80;

        final scaleX = minimapW / treeWidth;
        final scaleY = minimapH / treeHeight;
        final miniScale = math.min(scaleX, scaleY);

        final worldX = (localPos.dx / miniScale) + minX - 40;
        final worldY = (localPos.dy / miniScale) + minY - 40;

        onTap(Offset(worldX, worldY));
      },
      child: Container(
        width: 140,
        height: 100,
        decoration: BoxDecoration(
          color: KinrelColors.darkBackground.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
          border: Border.all(
            color: KinrelColors.darkSurface.withValues(alpha: 0.5),
          ),
        ),
        child: CustomPaint(
          painter: _MinimapPainter(
            roots: roots,
            offset: offset,
            scale: scale,
            canvasSize: canvasSize,
          ),
        ),
      ),
    );
  }

  Map<String, Rect> _computeLayout() {
    const nodeWidth = 160.0;
    const nodeHeight = 72.0;
    const horizontalGap = 24.0;
    const verticalGap = 90.0;

    final positions = <String, Rect>{};
    double xOffset = 40;

    double layoutSubtree(VisTreeNode node, double xOff, double yOff) {
      final hasSpouse = node.spouse != null;
      final coupleWidth =
          hasSpouse ? nodeWidth * 2 + horizontalGap : nodeWidth;

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
        }
        return coupleWidth;
      }

      double childX = xOff;
      double maxChildWidth = 0;

      for (final child in node.children) {
        final w = layoutSubtree(
            child, childX, yOff + nodeHeight + verticalGap);
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
      }

      return math.max(maxChildWidth, coupleWidth);
    }

    for (final root in roots) {
      final width = layoutSubtree(root, xOffset, 60);
      xOffset += width + horizontalGap * 2;
    }

    return positions;
  }
}

class _MinimapPainter extends CustomPainter {
  final List<VisTreeNode> roots;
  final Offset offset;
  final double scale;
  final Size canvasSize;

  _MinimapPainter({
    required this.roots,
    required this.offset,
    required this.scale,
    required this.canvasSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final layout = _computeLayout();
    if (layout.isEmpty) return;

    final allRects = layout.values.toList();
    final minX = allRects.map((r) => r.left).reduce(math.min);
    final maxX = allRects.map((r) => r.right).reduce(math.max);
    final minY = allRects.map((r) => r.top).reduce(math.min);
    final maxY = allRects.map((r) => r.bottom).reduce(math.max);

    final treeWidth = maxX - minX + 80;
    final treeHeight = maxY - minY + 80;

    final scaleX = size.width / treeWidth;
    final scaleY = size.height / treeHeight;
    final miniScale = math.min(scaleX, scaleY);

    final offsetX = (size.width - treeWidth * miniScale) / 2;
    final offsetY = (size.height - treeHeight * miniScale) / 2;

    // Draw nodes as tiny dots
    final nodePaint = Paint()
      ..color = KinrelColors.orange.withValues(alpha: 0.7)
      ..style = PaintingStyle.fill;

    for (final rect in allRects) {
      final x = (rect.left - minX + 40) * miniScale + offsetX;
      final y = (rect.top - minY + 40) * miniScale + offsetY;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            x,
            y,
            math.max(rect.width * miniScale, 4),
            math.max(rect.height * miniScale, 3),
          ),
          const Radius.circular(2),
        ),
        nodePaint,
      );
    }

    // Viewport indicator
    final viewportLeft =
        (-offset.dx / scale - minX + 40) * miniScale + offsetX;
    final viewportTop =
        (-offset.dy / scale - minY + 40) * miniScale + offsetY;
    final viewportWidth = (canvasSize.width / scale) * miniScale;
    final viewportHeight = (canvasSize.height / scale) * miniScale;

    final viewportPaint = Paint()
      ..color = KinrelColors.amber.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(
      Rect.fromLTWH(
          viewportLeft, viewportTop, viewportWidth, viewportHeight),
      viewportPaint,
    );
  }

  Map<String, Rect> _computeLayout() {
    const nodeWidth = 160.0;
    const nodeHeight = 72.0;
    const horizontalGap = 24.0;
    const verticalGap = 90.0;

    final positions = <String, Rect>{};
    double xOffset = 40;

    double layoutSubtree(VisTreeNode node, double xOff, double yOff) {
      final hasSpouse = node.spouse != null;
      final coupleWidth =
          hasSpouse ? nodeWidth * 2 + horizontalGap : nodeWidth;

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
      }

      return math.max(maxChildWidth, coupleWidth);
    }

    for (final root in roots) {
      final width = layoutSubtree(root, xOffset, 60);
      xOffset += width + horizontalGap * 2;
    }

    return positions;
  }

  @override
  bool shouldRepaint(covariant _MinimapPainter oldDelegate) {
    return oldDelegate.offset != offset ||
        oldDelegate.scale != scale ||
        oldDelegate.roots != roots;
  }
}

// ── Empty state ────────────────────────────────────────────────────

class _EmptyCanvasState extends StatelessWidget {
  final VoidCallback onAddMember;

  const _EmptyCanvasState({required this.onAddMember});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KinrelSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CustomPaint(
              size: const Size(140, 140),
              painter: _DottedCirclePainter(
                color: KinrelColors.textDim.withValues(alpha: 0.3),
              ),
              child: const SizedBox(
                width: 140,
                height: 140,
                child: Center(
                  child: Icon(
                    Icons.add,
                    size: 48,
                    color: KinrelColors.textDim,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Your Family Tree Awaits',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the + button to add your first family member',
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

class _DottedCirclePainter extends CustomPainter {
  final Color color;

  _DottedCirclePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    const dashCount = 40;
    const dashAngle = math.pi * 2 / dashCount;
    const dashLength = dashAngle * 0.55;

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
