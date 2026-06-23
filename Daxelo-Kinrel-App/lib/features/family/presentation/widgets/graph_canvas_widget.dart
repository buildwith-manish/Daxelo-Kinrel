// lib/features/family/presentation/widgets/graph_canvas_widget.dart
//
// DAXELO KINREL — Graph Canvas Widget (v49 — Android pinch-zoom fix)
//
// ══════════════════════════════════════════════════════════════════════
// v49 (2026-06-22): CRITICAL FIX — removed RawGestureDetector from
// _PersonNodeCard. On Android, having TapGestureRecognizer +
// LongPressGestureRecognizer on every node widget competed with
// GraphPanZoom's ScaleGestureRecognizer in the gesture arena, causing
// pinch-zoom to stall or fail entirely on the real APK.
//
// FIX (mirrors family_graph.dart v48 pattern exactly):
//   - _PersonNodeCard is now a pure visual widget (NO gesture detectors).
//   - GraphPanZoom.onTap / onLongPress are wired to _hitTestPersonId(),
//     which does geometric hit-testing to find which node was tapped.
//   - Result: one ScaleGestureRecognizer in the arena, no competition —
//     both pinch-zoom AND node taps work correctly on Android APK.
// ══════════════════════════════════════════════════════════════════════
//
// Stack structure:
//   Layer 1: CustomPaint with FamilyTreePainter (edges)
//   Layer 2: EdgeDotWidget for each relationship (positioned at midpoint)
//   Layer 3: Person node cards (Positioned widgets — circular avatar nodes)
//   Layer 4: RelationshipPopupWidget (when an edge dot is tapped)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/family_graph_provider.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/kinship/kinship_edge_style.dart';
import '../../../../core/services/graph_layout_service.dart';
import '../../../../graph/widgets/graph_pan_zoom.dart';
import '../../../../shared/painters/family_tree_painter.dart';
import '../../../../shared/utils/node_colors.dart';
import 'edge_dot_widget.dart';
import 'relationship_popup_widget.dart';

// ═══════════════════════════════════════════════════════════════════════
// PERSON DATA MODEL (for API flat graph response)
// ═══════════════════════════════════════════════════════════════════════

/// Person data as received from the API flat graph response.
class PersonData {
  final String id;
  final String name;
  final String? gender;
  final int generationIndex;
  final bool isAnchor;
  final String? photoUrl;
  final bool isDeceased;
  /// Server-computed kinship category (e.g., "parent", "aunt_uncle") for node coloring.
  final String? kinshipCategory;
  /// Server-computed kinship term (e.g., "Uncle", "Cousin") for node label.
  final String? computedKinship;

  const PersonData({
    required this.id,
    required this.name,
    this.gender,
    this.generationIndex = 0,
    this.isAnchor = false,
    this.photoUrl,
    this.isDeceased = false,
    this.kinshipCategory,
    this.computedKinship,
  });

  /// Converts to GraphPerson for layout computation.
  GraphPerson toGraphPerson() => GraphPerson(
        id: id,
        name: name,
        gender: gender,
        generationIndex: generationIndex,
        isAnchor: isAnchor,
        photoUrl: photoUrl,
        isDeceased: isDeceased,
      );
}

/// Relationship data as received from the API flat graph response.
class RelationshipData {
  final String id;
  final String fromPersonId;
  final String toPersonId;
  final String relationshipKey;
  /// Optional display label from enriched graph API (e.g., "Father", "Mother's Brother").
  final String? displayLabel;

  const RelationshipData({
    required this.id,
    required this.fromPersonId,
    required this.toPersonId,
    required this.relationshipKey,
    this.displayLabel,
  });

  /// Converts to EdgeData for the painter.
  EdgeData toEdgeData() => EdgeData(
        id: id,
        fromPersonId: fromPersonId,
        toPersonId: toPersonId,
        relationshipKey: relationshipKey,
        displayLabel: displayLabel,
      );

  /// Converts to GraphRelationship for layout computation.
  GraphRelationship toGraphRelationship() => GraphRelationship(
        id: id,
        fromPersonId: fromPersonId,
        toPersonId: toPersonId,
        relationshipKey: relationshipKey,
      );
}

// ═══════════════════════════════════════════════════════════════════════
// GRAPH CANVAS WIDGET
// ═══════════════════════════════════════════════════════════════════════

/// The main graph canvas widget that renders the family tree graph.
///
/// Uses GraphPanZoom for zoom/pan, and a Stack to layer edges,
/// edge dots, person nodes, and popups.
///
/// Usage:
/// ```dart
/// GraphCanvasWidget(
///   persons: apiPersons,
///   relationships: apiRelationships,
///   familyId: 'family-123',
/// )
/// ```
class GraphCanvasWidget extends ConsumerStatefulWidget {
  const GraphCanvasWidget({
    super.key,
    required this.persons,
    required this.relationships,
    required this.familyId,
  });

  /// List of person data from the API flat graph response.
  final List<PersonData> persons;

  /// List of relationship data from the API flat graph response.
  final List<RelationshipData> relationships;

  /// The family ID for provider lookups.
  final String familyId;

  @override
  ConsumerState<GraphCanvasWidget> createState() => _GraphCanvasWidgetState();
}

class _GraphCanvasWidgetState extends ConsumerState<GraphCanvasWidget> {
  // ── Controllers ────────────────────────────────────────────────────

  final TransformationController _transformationController =
      TransformationController();

  // ── State ──────────────────────────────────────────────────────────

  /// Currently selected edge ID.
  String? _selectedEdgeId;

  /// Currently selected edge data (for popup).
  RelationshipData? _selectedEdgeData;

  /// Whether the relationship popup is visible.
  bool _showPopup = false;

  /// Computed layout result.
  GraphLayoutResult? _layoutResult;

  /// Map of person ID → PersonData for quick lookups.
  late Map<String, PersonData> _personMap;

  /// When set, persons NOT in this generation get opacity 0.25.
  int? highlightedGeneration;

  // ── Constants ──────────────────────────────────────────────────────

  static const double _nodeWidth = 72.0;
  static const double _nodeHeight = 72.0;

  /// Hit radius for tap detection (larger than visual node for easy tapping).
  static const double _hitRadius = 44.0;

  // ── Lifecycle ──────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _personMap = {for (final p in widget.persons) p.id: p};
    _computeLayout();
    _transformationController.addListener(_onTransformChanged);
  }

  @override
  void didUpdateWidget(covariant GraphCanvasWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.persons != oldWidget.persons ||
        widget.relationships != oldWidget.relationships) {
      _personMap = {for (final p in widget.persons) p.id: p};
      _computeLayout();
    }
  }

  @override
  void dispose() {
    _transformationController.removeListener(_onTransformChanged);
    _transformationController.dispose();
    super.dispose();
  }

  // ── Layout Computation ─────────────────────────────────────────────

  void _computeLayout() {
    final graphPersons =
        widget.persons.map((p) => p.toGraphPerson()).toList();
    final graphRelationships =
        widget.relationships.map((r) => r.toGraphRelationship()).toList();

    final service = GraphLayoutService();
    setState(() {
      _layoutResult = service.computeLayout(
        persons: graphPersons,
        relationships: graphRelationships,
      );
    });

    // v52.4 FIX: Auto-center the graph after layout so nodes are always
    // visible regardless of viewport size. Without this, the canvas
    // renders at (0,0) which may leave the graph off-screen on small
    // viewports or in the corner on large ones.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _layoutResult == null) return;
      _autoCenterGraph();
    });
  }

  /// Centers the graph canvas in the viewport after layout.
  void _autoCenterGraph() {
    final layout = _layoutResult!;
    final canvasW = layout.canvasWidth;
    final canvasH = layout.canvasHeight;
    if (canvasW <= 0 || canvasH <= 0) return;

    final viewport = MediaQuery.of(context).size;
    final viewportW = viewport.width;
    final viewportH = viewport.height;
    if (viewportW <= 0 || viewportH <= 0) return;

    final margin = 80.0;
    final scaleX = (viewportW - margin * 2) / canvasW;
    final scaleY = (viewportH - margin * 2) / canvasH;
    final scale = [scaleX, scaleY, 1.0].reduce((a, b) => a < b ? a : b)
        .clamp(0.05, 1.0);

    final tx = (viewportW - canvasW * scale) / 2;
    final ty = (viewportH - canvasH * scale) / 2;

    _transformationController.value = Matrix4.identity()
      ..translate(tx, ty)
      ..scale(scale);
  }

  // ── Transform Change Handler ───────────────────────────────────────

  void _onTransformChanged() {
    setState(() {});
  }

  /// Gets the current zoom level from the transformation matrix.
  double get _currentZoom {
    return _transformationController.value.getMaxScaleOnAxis();
  }

  // ── Hit Testing ────────────────────────────────────────────────────

  /// Converts a tap position in GraphPanZoom's local coordinate space to
  /// canvas space and returns the ID of the person node under the tap,
  /// or null if no node was hit.
  ///
  /// GraphPanZoom renders the child canvas at:
  ///   left: tx,  top: ty,  scale: scale (Transform.scale, Alignment.topLeft)
  /// So:  canvas_pos = (widget_pos - Offset(tx, ty)) / scale
  ///
  /// Each node center is at positions[id] in canvas space.
  /// We use _hitRadius (44px) for finger-size tolerance.
  String? _hitTestPersonId(
    Offset localPosition,
    Map<String, Offset> positions,
  ) {
    final matrix = _transformationController.value;
    final scale = matrix.getMaxScaleOnAxis();
    if (scale == 0) return null;

    final tx = matrix.getTranslation().x;
    final ty = matrix.getTranslation().y;

    final canvasX = (localPosition.dx - tx) / scale;
    final canvasY = (localPosition.dy - ty) / scale;
    final canvasPos = Offset(canvasX, canvasY);

    String? bestId;
    double bestDist = double.infinity;

    for (final entry in positions.entries) {
      final dist = (entry.value - canvasPos).distance;
      if (dist < _hitRadius && dist < bestDist) {
        bestDist = dist;
        bestId = entry.key;
      }
    }

    return bestId;
  }

  // ── Edge Dot Tap Handler ───────────────────────────────────────────

  void _onEdgeDotTapped(String edgeId) {
    final edge = widget.relationships.firstWhere(
      (r) => r.id == edgeId,
      orElse: () => widget.relationships.first,
    );

    setState(() {
      if (_selectedEdgeId == edgeId) {
        _selectedEdgeId = null;
        _selectedEdgeData = null;
        _showPopup = false;
      } else {
        _selectedEdgeId = edgeId;
        _selectedEdgeData = edge;
        _showPopup = true;
      }
    });
  }

  void _onPopupClose() {
    setState(() {
      _showPopup = false;
      _selectedEdgeId = null;
      _selectedEdgeData = null;
    });
  }

  // ── Find anchor person ─────────────────────────────────────────────

  PersonData? get _anchorPerson {
    for (final p in widget.persons) {
      if (p.isAnchor) return p;
    }
    return null;
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_layoutResult == null) {
      return const Center(
        child: CircularProgressIndicator(
          color: KinrelColors.orange,
        ),
      );
    }

    final positions = _layoutResult!.positions;
    final canvasWidth = _layoutResult!.canvasWidth;
    final canvasHeight = _layoutResult!.canvasHeight;
    final zoomLevel = _currentZoom;

    final effectiveWidth = canvasWidth > 0 ? canvasWidth : 3000.0;
    final effectiveHeight = canvasHeight > 0 ? canvasHeight : 3000.0;

    // v49 FIX: Tap and long-press are now handled here via canvas-level
    // geometric hit testing (see _hitTestPersonId). _PersonNodeCard has
    // NO gesture detectors. This removes the ScaleGestureRecognizer vs
    // TapGestureRecognizer arena competition that broke pinch-zoom on
    // Android APK (mirrors family_graph.dart v48 fix exactly).
    return GraphPanZoom(
      transformationController: _transformationController,
      minScale: 0.05,
      maxScale: 8.0,
      onTransformChanged: () => setState(() {}),
      onTap: (localPosition) {
        final hitId = _hitTestPersonId(localPosition, positions);
        if (hitId != null) {
          context.push('/family/${widget.familyId}/person/$hitId');
        }
      },
      onLongPress: (localPosition) {
        final hitId = _hitTestPersonId(localPosition, positions);
        if (hitId != null) {
          final person = _personMap[hitId];
          if (person != null) {
            _showQuickActions(context, person);
          }
        }
      },
      child: SizedBox(
        width: effectiveWidth,
        height: effectiveHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // ── Layer 1: Edges (CustomPaint) ───────────────────────
            Positioned.fill(
              child: CustomPaint(
                size: Size(effectiveWidth, effectiveHeight),
                painter: FamilyTreePainter(
                  positions: positions,
                  relationships: widget.relationships
                      .map((r) => r.toEdgeData())
                      .toList(),
                  selectedEdgeId: _selectedEdgeId,
                  zoomLevel: zoomLevel,
                  nodeWidth: _nodeWidth,
                  nodeHeight: _nodeHeight,
                ),
              ),
            ),

            // ── Layer 2: Edge Dots ──────────────────────────────────
            ..._buildEdgeDots(positions),

            // ── Layer 3: Person Node Cards ──────────────────────────
            ..._buildPersonNodes(positions, zoomLevel),

            // ── Layer 4: Relationship Popup ─────────────────────────
            if (_showPopup && _selectedEdgeData != null)
              _buildRelationshipPopup(positions, canvasWidth, canvasHeight),
          ],
        ),
      ),
    );
  }

  // ── Layer 2: Edge Dots ─────────────────────────────────────────────

  List<Widget> _buildEdgeDots(Map<String, Offset> positions) {
    final dots = <Widget>[];

    for (final edge in widget.relationships) {
      final fromPos = positions[edge.fromPersonId];
      final toPos = positions[edge.toPersonId];
      if (fromPos == null || toPos == null) continue;

      final category =
          KinshipEdgeClassifier.classify(edge.relationshipKey);
      final style = KinshipEdgeStyleResolver.styleForCategory(category);

      // Compute the TRUE midpoint of the edge — for curves (sibling arc,
      // extended bezier, wide-arc, shallow-S) this is the t=0.5 point
      // on the bezier, not the linear midpoint. Must match what the
      // FamilyTreePainter draws so the dot sits on top of the visible
      // curve, not floating beside it.
      final midpoint = _computeEdgeMidpoint(
        fromPos,
        toPos,
        category,
        style.lineShape,
      );

      dots.add(
        Positioned(
          left: midpoint.dx - 16,
          top: midpoint.dy - 16,
          child: EdgeDotWidget(
            dotPosition: midpoint,
            isSelected: _selectedEdgeId == edge.id,
            category: category,
            onTap: () => _onEdgeDotTapped(edge.id),
          ),
        ),
      );
    }

    return dots;
  }

  /// Compute the visual midpoint of an edge — same formula the painter
  /// uses. For straight edges this is the linear midpoint; for curved
  /// edges (sibling arc, cousin wide-arc, aunt/uncle shallow-S,
  /// grandparent extended bezier) this is the t=0.5 point on the bezier.
  ///
  /// Keeping this in sync with the painter is what makes the dot sit
  /// ON the visible line instead of floating beside it.
  Offset _computeEdgeMidpoint(
    Offset fromPos,
    Offset toPos,
    KinshipEdgeCategory category,
    KinshipLineShape shape,
  ) {
    // Replicate _computeEndpoints logic.
    final Offset start;
    final Offset end;
    if (category == KinshipEdgeCategory.spouse ||
        category == KinshipEdgeCategory.inLaw) {
      if (fromPos.dx <= toPos.dx) {
        start = Offset(fromPos.dx + _nodeWidth / 2, fromPos.dy);
        end = Offset(toPos.dx - _nodeWidth / 2, toPos.dy);
      } else {
        start = Offset(fromPos.dx - _nodeWidth / 2, fromPos.dy);
        end = Offset(toPos.dx + _nodeWidth / 2, toPos.dy);
      }
    } else {
      if (fromPos.dy <= toPos.dy) {
        start = Offset(fromPos.dx, fromPos.dy + _nodeHeight / 2);
        end = Offset(toPos.dx, toPos.dy - _nodeHeight / 2);
      } else {
        start = Offset(fromPos.dx, fromPos.dy - _nodeHeight / 2);
        end = Offset(toPos.dx, toPos.dy + _nodeHeight / 2);
      }
    }

    switch (shape) {
      case KinshipLineShape.dashedArc:
        final arcHeight = (end.dx - start.dx).abs() * 0.25 + 30.0;
        final midX = (start.dx + end.dx) / 2;
        final cpY = start.dy - arcHeight;
        return Offset(
          midX,
          0.25 * start.dy + 0.5 * cpY + 0.25 * end.dy,
        );

      case KinshipLineShape.solidExtendedBezier:
        final dy = end.dy - start.dy;
        final cp1 = Offset(start.dx, start.dy + dy * 0.4);
        final cp2 = Offset(end.dx, start.dy + dy * 0.6);
        return Offset(
          0.125 * start.dx +
              0.375 * cp1.dx +
              0.375 * cp2.dx +
              0.125 * end.dx,
          0.125 * start.dy +
              0.375 * cp1.dy +
              0.375 * cp2.dy +
              0.125 * end.dy,
        );

      case KinshipLineShape.wideArcBezier:
        final dx = end.dx - start.dx;
        final dy = end.dy - start.dy;
        final offset = dx.abs() * 0.3 + 40.0;
        final sign = dx >= 0 ? 1.0 : -1.0;
        final cp1 = Offset(start.dx + offset * sign, start.dy + dy * 0.33);
        final cp2 = Offset(end.dx - offset * sign, start.dy + dy * 0.67);
        return Offset(
          0.125 * start.dx +
              0.375 * cp1.dx +
              0.375 * cp2.dx +
              0.125 * end.dx,
          0.125 * start.dy +
              0.375 * cp1.dy +
              0.375 * cp2.dy +
              0.125 * end.dy,
        );

      case KinshipLineShape.dashedShallowS:
        final midY = (start.dy + end.dy) / 2;
        final dxOffset = (end.dx - start.dx) * 0.2;
        final cp1 = Offset(start.dx + dxOffset, midY - 15);
        final cp2 = Offset(end.dx - dxOffset, midY + 15);
        return Offset(
          0.125 * start.dx +
              0.375 * cp1.dx +
              0.375 * cp2.dx +
              0.125 * end.dx,
          0.125 * start.dy +
              0.375 * cp1.dy +
              0.375 * cp2.dy +
              0.125 * end.dy,
        );

      case KinshipLineShape.solidBezier:
      case KinshipLineShape.dashedStraight:
      case KinshipLineShape.dashedDefault:
        return Offset(
          (start.dx + end.dx) / 2,
          (start.dy + end.dy) / 2,
        );
    }
  }

  // ── Layer 3: Person Node Cards ─────────────────────────────────────

  List<Widget> _buildPersonNodes(
    Map<String, Offset> positions,
    double zoomLevel,
  ) {
    final nodes = <Widget>[];

    for (final person in widget.persons) {
      final pos = positions[person.id];
      if (pos == null) continue;

      final double nodeOpacity;
      if (highlightedGeneration != null &&
          person.generationIndex != highlightedGeneration) {
        nodeOpacity = 0.25;
      } else {
        nodeOpacity = 1.0;
      }

      final relationLabel = _getRelationLabel(person);

      nodes.add(
        Positioned(
          left: pos.dx - _nodeWidth / 2,
          top: pos.dy - _nodeHeight / 2,
          // v49: No gesture detectors here — taps are routed from
          // GraphPanZoom.onTap/onLongPress via _hitTestPersonId.
          child: _PersonNodeCard(
            person: person,
            nodeWidth: _nodeWidth,
            nodeHeight: _nodeHeight,
            zoomLevel: zoomLevel,
            opacity: nodeOpacity,
            relationLabel: relationLabel,
          ),
        ),
      );
    }

    return nodes;
  }

  // ── Quick Actions Bottom Sheet ─────────────────────────────────────

  /// Shows the quick-actions bottom sheet for [person].
  /// Called from GraphPanZoom.onLongPress via _hitTestPersonId.
  void _showQuickActions(BuildContext context, PersonData person) {
    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Padding(
              padding: const EdgeInsets.only(top: 12.0, bottom: 4.0),
              child: Container(
                width: 40.0,
                height: 4.0,
                decoration: BoxDecoration(
                  color: KinrelColors.textDim,
                  borderRadius: BorderRadius.circular(2.0),
                ),
              ),
            ),

            // Person name header
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 20.0,
                vertical: 12.0,
              ),
              child: Text(
                person.name,
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 18.0,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                ),
              ),
            ),

            const Divider(
              color: Color(0x1AFFFFFF),
              height: 1.0,
            ),

            ListTile(
              leading: const Icon(Icons.person, color: KinrelColors.tealAccent),
              title: Text(
                'View Profile',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  color: KinrelColors.textWhite,
                ),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                context.push('/family/${widget.familyId}/person/${person.id}');
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit, color: KinrelColors.amber),
              title: Text(
                'Edit',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  color: KinrelColors.textWhite,
                ),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                context.push('/member/${person.id}');
              },
            ),
            ListTile(
              leading: const Icon(Icons.star, color: KinrelColors.gold),
              title: Text(
                'Set as Anchor',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  color: KinrelColors.textWhite,
                ),
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                final client = Supabase.instance.client;
                await client
                    .from('Person')
                    .update({'isAnchor': true}).eq('id', person.id);
                await client
                    .from('Family')
                    .update({'anchorPersonId': person.id}).eq(
                        'id', widget.familyId);
                ref.invalidate(familyGraphProvider(widget.familyId));
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: KinrelColors.coral),
              title: Text(
                'Remove',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  color: KinrelColors.textWhite,
                ),
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    backgroundColor: const Color(0xFF191B2C),
                    title: Text('Remove ${person.name}?',
                        style: const TextStyle(color: Color(0xFFF5F0EE))),
                    content: const Text(
                        'This will soft-delete them from the family.',
                        style: TextStyle(color: Color(0xFF8A7A72))),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel')),
                      TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Remove',
                              style:
                                  TextStyle(color: Color(0xFFE8612A)))),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await Supabase.instance.client
                      .from('Person')
                      .update(
                          {'deletedAt': DateTime.now().toIso8601String()})
                      .eq('id', person.id);
                  ref.invalidate(familyGraphProvider(widget.familyId));
                }
              },
            ),

            const SizedBox(height: 8.0),
          ],
        ),
      ),
    );
  }

  // ── Relation Label Resolution ──────────────────────────────────────

  String _getRelationLabel(PersonData person) {
    if (person.computedKinship != null && person.computedKinship!.isNotEmpty) {
      return person.computedKinship!;
    }

    if (person.isAnchor) return 'You';

    final anchor = _anchorPerson;
    if (anchor == null) return '';

    for (final edge in widget.relationships) {
      if (edge.fromPersonId == anchor.id && edge.toPersonId == person.id) {
        return _formatKey(edge.relationshipKey);
      }
      if (edge.fromPersonId == person.id && edge.toPersonId == anchor.id) {
        return _formatKey(_getInverseKey(edge.relationshipKey));
      }
    }

    return '';
  }

  static String _formatKey(String key) {
    return key
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  // ── Layer 4: Relationship Popup ────────────────────────────────────

  Widget _buildRelationshipPopup(
    Map<String, Offset> positions,
    double canvasWidth,
    double canvasHeight,
  ) {
    final edge = _selectedEdgeData!;
    final fromPerson = _personMap[edge.fromPersonId];
    final toPerson = _personMap[edge.toPersonId];

    if (fromPerson == null || toPerson == null) return const SizedBox.shrink();

    final fromPos = positions[edge.fromPersonId];
    final toPos = positions[edge.toPersonId];
    if (fromPos == null || toPos == null) return const SizedBox.shrink();

    // Compute the TRUE midpoint (same as the dot layer) so the popup
    // opens next to the visible dot, not at the linear midpoint.
    final category =
        KinshipEdgeClassifier.classify(edge.relationshipKey);
    final style = KinshipEdgeStyleResolver.styleForCategory(category);
    final midpoint = _computeEdgeMidpoint(
      fromPos,
      toPos,
      category,
      style.lineShape,
    );

    final inverseKey = _getInverseKey(
      edge.relationshipKey,
      personAGender: fromPerson.gender,
      personBGender: toPerson.gender,
    );

    return RelationshipPopupWidget(
      personAName: fromPerson.name,
      personBName: toPerson.name,
      personAGender: fromPerson.gender,
      personBGender: toPerson.gender,
      forwardKey: edge.relationshipKey,
      inverseKey: inverseKey,
      forwardNative: null,
      inverseNative: null,
      dotPosition: midpoint,
      canvasSize: Size(canvasWidth, canvasHeight),
      onClose: _onPopupClose,
    );
  }

  String _getInverseKey(
    String key, {
    String? personAGender,
    String? personBGender,
  }) {
    if (personAGender != null) {
      final aIsMale = personAGender.toLowerCase() == 'male';
      final aIsFemale = personAGender.toLowerCase() == 'female';

      switch (key) {
        case 'son':
        case 'daughter':
          return aIsMale ? 'father' : (aIsFemale ? 'mother' : 'parent');
        case 'grandson':
        case 'granddaughter':
          return aIsMale
              ? 'grandfather'
              : (aIsFemale ? 'grandmother' : 'grandparent');
        case 'nephew':
        case 'niece':
          return aIsMale ? 'uncle' : (aIsFemale ? 'aunt' : 'uncle/aunt');
        case 'brother':
        case 'sister':
          return aIsMale ? 'brother' : (aIsFemale ? 'sister' : 'sibling');
        case 'husband':
        case 'wife':
        case 'spouse':
        case 'partner':
          return aIsMale ? 'husband' : (aIsFemale ? 'wife' : 'spouse');
      }
    }

    if (personBGender != null) {
      final bIsMale = personBGender.toLowerCase() == 'male';
      final bIsFemale = personBGender.toLowerCase() == 'female';

      switch (key) {
        case 'father':
        case 'mother':
          return bIsMale ? 'son' : (bIsFemale ? 'daughter' : 'child');
        case 'grandfather':
        case 'grandmother':
          return bIsMale
              ? 'grandson'
              : (bIsFemale ? 'granddaughter' : 'grandchild');
        case 'uncle':
        case 'aunt':
          return bIsMale ? 'nephew' : (bIsFemale ? 'niece' : 'nephew/niece');
      }
    }

    const inverseMap = <String, String>{
      'father': 'son',
      'mother': 'daughter',
      'son': 'father',
      'daughter': 'mother',
      'brother': 'brother',
      'sister': 'sister',
      'husband': 'wife',
      'wife': 'husband',
      'spouse': 'spouse',
      'partner': 'partner',
      'grandfather': 'grandson',
      'grandmother': 'granddaughter',
      'grandson': 'grandfather',
      'granddaughter': 'grandmother',
      'uncle': 'nephew',
      'aunt': 'niece',
      'nephew': 'uncle',
      'niece': 'aunt',
      'cousin': 'cousin',
      'cousin_brother': 'cousin_brother',
      'cousin_sister': 'cousin_sister',
      'father_in_law': 'son_in_law',
      'mother_in_law': 'daughter_in_law',
      'son_in_law': 'father_in_law',
      'daughter_in_law': 'mother_in_law',
      'brother_in_law': 'sister_in_law',
      'sister_in_law': 'brother_in_law',
      'paternal_uncle': 'nephew',
      'paternal_aunt': 'niece',
      'maternal_uncle': 'nephew',
      'maternal_aunt': 'niece',
      'stepfather': 'stepson',
      'stepmother': 'stepdaughter',
      'stepson': 'stepfather',
      'stepdaughter': 'stepmother',
      'stepbrother': 'stepbrother',
      'stepsister': 'stepsister',
      'half_brother': 'half_brother',
      'half_sister': 'half_sister',
    };
    return inverseMap[key] ?? key;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// PERSON NODE CARD — Pure Visual Widget (NO gesture detectors)
// ═══════════════════════════════════════════════════════════════════════

/// A circular avatar node card for a person in the graph canvas.
///
/// v49: This is now a PURE VISUAL widget — it has NO GestureDetector,
/// no RawGestureDetector, no TapGestureRecognizer. Taps and long-presses
/// are handled at the GraphPanZoom level via geometric hit-testing in
/// _GraphCanvasWidgetState._hitTestPersonId(). This is the key fix for
/// pinch-zoom not working on Android APK.
///
/// Layout:
///   - 72dp diameter circle with generation-colored border ring
///   - Anchor person: double-ring (outer 88dp teal at 25% alpha,
///     inner 72dp teal solid 3dp)
///   - Content: 2-letter initials or ClipOval photo
///   - Deceased: Opacity(0.4)
///   - Name + relation label below the circle (2 lines, centered)
class _PersonNodeCard extends StatelessWidget {
  const _PersonNodeCard({
    required this.person,
    required this.nodeWidth,
    required this.nodeHeight,
    required this.zoomLevel,
    required this.opacity,
    required this.relationLabel,
  });

  final PersonData person;
  final double nodeWidth;
  final double nodeHeight;
  final double zoomLevel;
  final double opacity;
  final String relationLabel;

  // ── Generation Ring Color ──────────────────────────────────────────

  Color get _ringColor {
    if (person.kinshipCategory != null && person.kinshipCategory!.isNotEmpty) {
      return getNodeColorsFromCategory(person.kinshipCategory).ring;
    }
    if (person.generationIndex < 0) {
      return KinrelColors.blue.withValues(alpha: 0.6);
    } else if (person.generationIndex == 0) {
      return KinrelColors.tealAccent;
    } else {
      return KinrelColors.coral.withValues(alpha: 0.6);
    }
  }

  // ── Initials ───────────────────────────────────────────────────────

  String get _initials {
    final parts = person.name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return (parts.first[0] + parts.last[0]).toUpperCase();
    } else if (parts.isNotEmpty && parts.first.isNotEmpty) {
      return parts.first.length >= 2
          ? parts.first.substring(0, 2).toUpperCase()
          : parts.first[0].toUpperCase();
    }
    return '?';
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // v49: NO gesture detectors here. Taps/long-presses are routed from
    // GraphPanZoom.onTap / onLongPress via _hitTestPersonId.
    return Opacity(
      opacity: person.isDeceased ? 0.4 * opacity : opacity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Circle Node ───────────────────────────────────────
          _buildCircleNode(),

          const SizedBox(height: 6.0),

          // ── Name below circle ─────────────────────────────────
          Text(
            person.name,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 14.0,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textWhite,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

          // ── Relation label below name ─────────────────────────
          if (relationLabel.isNotEmpty)
            Text(
              relationLabel,
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 11.0,
                fontWeight: FontWeight.w500,
                color: _ringColor,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }

  // ── Circle Node Builder ────────────────────────────────────────────

  Widget _buildCircleNode() {
    const double diameter = 72.0;

    if (person.isAnchor) {
      return SizedBox(
        width: 88.0,
        height: 88.0,
        child: Center(
          child: Container(
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: KinrelColors.darkCard,
              border: Border.all(
                color: KinrelColors.tealAccent,
                width: 3.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: KinrelColors.tealAccent.withValues(alpha: 0.25),
                  blurRadius: 0.0,
                  spreadRadius: 8.0,
                ),
              ],
            ),
            child: _buildCircleContent(diameter),
          ),
        ),
      );
    }

    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: KinrelColors.darkCard,
        border: Border.all(
          color: _ringColor,
          width: 2.5,
        ),
      ),
      child: _buildCircleContent(diameter),
    );
  }

  // ── Circle Content (initials or photo) ─────────────────────────────

  Widget _buildCircleContent(double diameter) {
    if (person.photoUrl != null && person.photoUrl!.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          person.photoUrl!,
          width: diameter,
          height: diameter,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              _buildInitialsContent(),
        ),
      );
    }

    return _buildInitialsContent();
  }

  Widget _buildInitialsContent() {
    return Center(
      child: Text(
        _initials,
        style: TextStyle(
          fontFamily: KinrelTypography.displayFont,
          fontSize: 20.0,
          fontWeight: FontWeight.bold,
          color: KinrelColors.textWhite,
        ),
      ),
    );
  }
}
