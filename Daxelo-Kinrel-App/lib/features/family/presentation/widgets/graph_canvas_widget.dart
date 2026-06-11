// lib/features/family/presentation/widgets/graph_canvas_widget.dart
//
// DAXELO KINREL — Graph Canvas Widget
//
// The main graph canvas widget that combines the painter, edge dots,
// person nodes, and relationship popups into a zoomable, pannable
// family graph visualization.
//
// Stack structure:
//   Layer 1: CustomPaint with FamilyTreePainter (edges)
//   Layer 2: EdgeDotWidget for each relationship (positioned at midpoint)
//   Layer 3: Person node cards (Positioned widgets)
//   Layer 4: RelationshipPopupWidget (when an edge dot is tapped)
//
// Features:
//   - InteractiveViewer with TransformationController for zoom/pan
//   - Min scale: 0.1, Max scale: 4.0, constrained: false
//   - Person node cards with avatar, name, generation badge
//   - Anchor person "You" badge in gold
//   - Deceased person: opacity 0.4
//   - LOD-aware name sizing based on zoom level

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/services/graph_layout_service.dart';
import '../../../../shared/painters/family_tree_painter.dart';
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

  const PersonData({
    required this.id,
    required this.name,
    this.gender,
    this.generationIndex = 0,
    this.isAnchor = false,
    this.photoUrl,
    this.isDeceased = false,
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

  const RelationshipData({
    required this.id,
    required this.fromPersonId,
    required this.toPersonId,
    required this.relationshipKey,
  });

  /// Converts to EdgeData for the painter.
  EdgeData toEdgeData() => EdgeData(
        id: id,
        fromPersonId: fromPersonId,
        toPersonId: toPersonId,
        relationshipKey: relationshipKey,
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
/// Uses InteractiveViewer for zoom/pan, and a Stack to layer edges,
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
  late final Map<String, PersonData> _personMap;

  // ── Constants ──────────────────────────────────────────────────────

  static const double _nodeWidth = 90.0;
  static const double _nodeHeight = 110.0;

  // ── Lifecycle ──────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _personMap = {for (final p in widget.persons) p.id: p};
    _computeLayout();

    // Listen for zoom changes
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
    _layoutResult = service.computeLayout(
      persons: graphPersons,
      relationships: graphRelationships,
    );
  }

  // ── Transform Change Handler ───────────────────────────────────────

  void _onTransformChanged() {
    // Trigger rebuild for LOD-dependent rendering
    setState(() {});
  }

  /// Gets the current zoom level from the transformation matrix.
  double get _currentZoom {
    final matrix = _transformationController.value;
    // Extract scale from the transformation matrix
    return matrix.getMaxScaleOnAxis();
  }

  // ── Edge Dot Tap Handler ───────────────────────────────────────────

  void _onEdgeDotTapped(String edgeId) {
    final edge = widget.relationships.firstWhere(
      (r) => r.id == edgeId,
      orElse: () => widget.relationships.first,
    );

    setState(() {
      if (_selectedEdgeId == edgeId) {
        // Toggle off
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

    return ClipRect(
      child: InteractiveViewer(
        transformationController: _transformationController,
        minScale: 0.1,
        maxScale: 4.0,
        constrained: false,
        child: SizedBox(
          width: canvasWidth,
          height: canvasHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // ── Layer 1: Edges (CustomPaint) ───────────────────────
              Positioned.fill(
                child: CustomPaint(
                  size: Size(canvasWidth, canvasHeight),
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

      final midpoint = Offset(
        (fromPos.dx + toPos.dx) / 2,
        (fromPos.dy + toPos.dy) / 2,
      );

      dots.add(
        Positioned(
          left: midpoint.dx - 16,
          top: midpoint.dy - 16,
          child: EdgeDotWidget(
            dotPosition: midpoint,
            isSelected: _selectedEdgeId == edge.id,
            onTap: () => _onEdgeDotTapped(edge.id),
          ),
        ),
      );
    }

    return dots;
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

      nodes.add(
        Positioned(
          left: pos.dx - _nodeWidth / 2,
          top: pos.dy - _nodeHeight / 2,
          child: _PersonNodeCard(
            person: person,
            nodeWidth: _nodeWidth,
            nodeHeight: _nodeHeight,
            zoomLevel: zoomLevel,
          ),
        ),
      );
    }

    return nodes;
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

    final midpoint = Offset(
      (fromPos.dx + toPos.dx) / 2,
      (fromPos.dy + toPos.dy) / 2,
    );

    return RelationshipPopupWidget(
      personAName: fromPerson.name,
      personBName: toPerson.name,
      forwardKey: edge.relationshipKey,
      inverseKey: _getInverseKey(edge.relationshipKey),
      forwardHindi: hindiKinshipTerms[edge.relationshipKey],
      inverseHindi: hindiKinshipTerms[_getInverseKey(edge.relationshipKey)],
      dotPosition: midpoint,
      canvasSize: Size(canvasWidth, canvasHeight),
      onClose: _onPopupClose,
    );
  }

  /// Returns the inverse relationship key for a given key.
  String _getInverseKey(String key) {
    const inverseMap = <String, String>{
      'father': 'son',
      'mother': 'daughter',
      'son': 'father',
      'daughter': 'mother',
      'brother': 'brother',
      'sister': 'sister',
      'husband': 'wife',
      'wife': 'husband',
      'grandfather': 'grandson',
      'grandmother': 'granddaughter',
      'uncle': 'nephew',
      'aunt': 'niece',
      'nephew': 'uncle',
      'niece': 'aunt',
      'cousin': 'cousin',
      'father_in_law': 'son_in_law',
      'mother_in_law': 'daughter_in_law',
      'son_in_law': 'father_in_law',
      'daughter_in_law': 'mother_in_law',
    };
    return inverseMap[key] ?? key;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// PERSON NODE CARD
// ═══════════════════════════════════════════════════════════════════════

/// A single person node card in the graph canvas.
///
/// Displays:
///   - Avatar (48dp circle with gender color border)
///   - Fallback avatar: first letter of name on KinrelColors.orange bg
///   - Name: Outfit font, LOD-aware sizing
///   - Generation badge (top-right)
///   - Anchor person: "You" badge in gold
///   - Deceased person: opacity 0.4
class _PersonNodeCard extends StatelessWidget {
  const _PersonNodeCard({
    required this.person,
    required this.nodeWidth,
    required this.nodeHeight,
    required this.zoomLevel,
  });

  final PersonData person;
  final double nodeWidth;
  final double nodeHeight;
  final double zoomLevel;

  // ── Gender Color ───────────────────────────────────────────────────

  Color get _genderBorderColor {
    switch (person.gender?.toLowerCase()) {
      case 'male':
        return KinrelColors.blue;
      case 'female':
        return KinrelColors.coral;
      default:
        return KinrelColors.textDim;
    }
  }

  // ── Name Style ─────────────────────────────────────────────────────

  TextStyle get _nameStyle {
    if (zoomLevel < 0.8) {
      return TextStyle(
        fontFamily: KinrelTypography.displayFont,
        fontSize: 11.0,
        fontWeight: FontWeight.w500,
        color: KinrelColors.textWhite,
      );
    }
    return TextStyle(
      fontFamily: KinrelTypography.displayFont,
      fontSize: 13.0,
      fontWeight: FontWeight.w600,
      color: KinrelColors.textWhite,
    );
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: person.isDeceased ? 0.4 : 1.0,
      child: Container(
        width: nodeWidth,
        height: nodeHeight,
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(16.0),
          border: person.isAnchor
              ? Border.all(
                  color: KinrelColors.orange,
                  width: 2.0,
                )
              : Border.all(
                  color: const Color(0x1AFFFFFF), // rgba(255, 255, 255, 0.10)
                  width: 1.0,
                ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x4D000000), // rgba(0, 0, 0, 0.3)
              blurRadius: 16.0,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // ── Card Content ───────────────────────────────────────
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Avatar
                  _buildAvatar(),

                  const SizedBox(height: 6.0),

                  // Name
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: Text(
                      person.name,
                      style: _nameStyle,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            // ── Generation Badge (top-right) ───────────────────────
            Positioned(
              right: 4.0,
              top: 4.0,
              child: _buildGenerationBadge(),
            ),

            // ── "You" Badge for anchor (bottom-right) ─────────────
            if (person.isAnchor)
              Positioned(
                right: 4.0,
                bottom: 4.0,
                child: _buildYouBadge(),
              ),
          ],
        ),
      ),
    );
  }

  /// Builds the avatar circle with gender-colored border.
  Widget _buildAvatar() {
    return Container(
      width: 48.0,
      height: 48.0,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: _genderBorderColor,
          width: 2.0,
        ),
      ),
      child: ClipOval(
        child: person.photoUrl != null && person.photoUrl!.isNotEmpty
            ? Image.network(
                person.photoUrl!,
                width: 48.0,
                height: 48.0,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    _buildFallbackAvatar(),
              )
            : _buildFallbackAvatar(),
      ),
    );
  }

  /// Builds the fallback avatar with the first letter of the name.
  Widget _buildFallbackAvatar() {
    final initial = person.name.isNotEmpty ? person.name[0].toUpperCase() : '?';

    return Container(
      width: 48.0,
      height: 48.0,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: KinrelColors.orange,
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          fontFamily: KinrelTypography.displayFont,
          fontSize: 20.0,
          fontWeight: FontWeight.w600,
          color: KinrelColors.textWhite,
        ),
      ),
    );
  }

  /// Builds the generation badge (e.g., "G0", "G1").
  Widget _buildGenerationBadge() {
    return Container(
      width: 16.0,
      height: 16.0,
      decoration: BoxDecoration(
        color: KinrelColors.darkElevated,
        borderRadius: BorderRadius.circular(4.0),
      ),
      alignment: Alignment.center,
      child: Text(
        'G${person.generationIndex}',
        style: TextStyle(
          fontFamily: KinrelTypography.monoFont,
          fontSize: 7.0,
          fontWeight: FontWeight.w500,
          color: KinrelColors.textDim,
        ),
      ),
    );
  }

  /// Builds the "You" badge for the anchor person.
  Widget _buildYouBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 1.0),
      decoration: BoxDecoration(
        color: KinrelColors.gold.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4.0),
        border: Border.all(
          color: KinrelColors.gold.withValues(alpha: 0.4),
          width: 0.5,
        ),
      ),
      child: Text(
        'You',
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 7.0,
          fontWeight: FontWeight.w600,
          color: KinrelColors.gold,
        ),
      ),
    );
  }
}
