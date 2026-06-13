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
//   Layer 3: Person node cards (Positioned widgets — circular avatar nodes)
//   Layer 4: RelationshipPopupWidget (when an edge dot is tapped)
//
// Features:
//   - InteractiveViewer with TransformationController for zoom/pan
//   - Min scale: 0.1, Max scale: 4.0, constrained: false
//   - Circular avatar nodes (72dp) with generation-colored rings
//   - Anchor person double-ring highlight
//   - Name + relation label below circle
//   - highlightedGeneration state: dims persons outside that generation
//   - Deceased person: opacity 0.4
//   - Tap → navigate to person profile; Long-press → bottom sheet
//   - Accessibility semantics

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/family_graph_provider.dart';

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
// SPOUSE KEY SET
// ═══════════════════════════════════════════════════════════════════════

/// Relationship keys that represent spouse/partner connections.
const Set<String> _spouseKeys = <String>{
  'husband',
  'wife',
  'spouse',
  'partner',
};

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

  /// When set, persons NOT in this generation get opacity 0.25.
  int? highlightedGeneration;

  // ── Constants ──────────────────────────────────────────────────────

  static const double _nodeWidth = 72.0;
  static const double _nodeHeight = 72.0;

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

      final isSpouse = _spouseKeys.contains(edge.relationshipKey);

      dots.add(
        Positioned(
          left: midpoint.dx - 16,
          top: midpoint.dy - 16,
          child: EdgeDotWidget(
            dotPosition: midpoint,
            isSelected: _selectedEdgeId == edge.id,
            isSpouse: isSpouse,
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

      // Compute opacity based on highlightedGeneration
      final double nodeOpacity;
      if (highlightedGeneration != null &&
          person.generationIndex != highlightedGeneration) {
        nodeOpacity = 0.25;
      } else {
        nodeOpacity = 1.0;
      }

      // Resolve relation label relative to anchor
      final relationLabel = _getRelationLabel(person);

      nodes.add(
        Positioned(
          left: pos.dx - _nodeWidth / 2,
          top: pos.dy - _nodeHeight / 2,
          child: _PersonNodeCard(
            person: person,
            nodeWidth: _nodeWidth,
            nodeHeight: _nodeHeight,
            zoomLevel: zoomLevel,
            opacity: nodeOpacity,
            relationLabel: relationLabel,
            familyId: widget.familyId,
            relationships: widget.relationships,
            personMap: _personMap,
          ),
        ),
      );
    }

    return nodes;
  }

  // ── Relation Label Resolution ──────────────────────────────────────

  /// Returns the relationship label for [person] relative to the anchor.
  ///
  /// Looks up the edge connecting this person to the anchor, then
  /// formats the relationship key. Returns "You" for the anchor.
  String _getRelationLabel(PersonData person) {
    if (person.isAnchor) return 'You';

    final anchor = _anchorPerson;
    if (anchor == null) return '';

    // Search for an edge connecting this person to the anchor
    for (final edge in widget.relationships) {
      // Case 1: anchor → person (relationshipKey describes person's
      //         relationship TO the anchor, i.e. person is the "to" end)
      if (edge.fromPersonId == anchor.id && edge.toPersonId == person.id) {
        return _formatKey(edge.relationshipKey);
      }
      // Case 2: person → anchor (relationshipKey describes anchor's
      //         relationship TO person, so we need the inverse)
      if (edge.fromPersonId == person.id && edge.toPersonId == anchor.id) {
        return _formatKey(_getInverseKey(edge.relationshipKey));
      }
    }

    return '';
  }

  /// Formats a relationship key like 'father_in_law' → 'Father In Law'.
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

    final midpoint = Offset(
      (fromPos.dx + toPos.dx) / 2,
      (fromPos.dy + toPos.dy) / 2,
    );

    // Gender-aware inverse resolution
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
      forwardNative: hindiKinshipTerms[edge.relationshipKey],
      inverseNative: hindiKinshipTerms[inverseKey],
      dotPosition: midpoint,
      canvasSize: Size(canvasWidth, canvasHeight),
      onClose: _onPopupClose,
    );
  }

  /// Returns the inverse relationship key for a given key.
  ///
  /// Uses a comprehensive map of 30+ relationship keys. When
  /// [personAGender] and [personBGender] are provided, gender-aware
  /// inverse resolution is used (e.g., son→father if B is male,
  /// son→mother if B is female).
  String _getInverseKey(
    String key, {
    String? personAGender,
    String? personBGender,
  }) {
    // Gender-aware overrides: the inverse of a relationship depends on
    // the gender of the person being described. For example, "son" from
    // A's perspective means A is the parent; the inverse describes A
    // from B's perspective, and whether A is "father" or "mother"
    // depends on A's gender.
    if (personAGender != null) {
      final aIsMale = personAGender.toLowerCase() == 'male';
      final aIsFemale = personAGender.toLowerCase() == 'female';

      switch (key) {
        case 'son':
        case 'daughter':
          return aIsMale ? 'father' : (aIsFemale ? 'mother' : 'parent');
        case 'grandson':
        case 'granddaughter':
          return aIsMale ? 'grandfather' : (aIsFemale ? 'grandmother' : 'grandparent');
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
          return bIsMale ? 'grandson' : (bIsFemale ? 'granddaughter' : 'grandchild');
        case 'uncle':
        case 'aunt':
          return bIsMale ? 'nephew' : (bIsFemale ? 'niece' : 'nephew/niece');
      }
    }

    // Fallback: comprehensive static inverse map (30+ keys)
    const inverseMap = <String, String>{
      // Immediate family
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
      // Grandparents / grandchildren
      'grandfather': 'grandson',
      'grandmother': 'granddaughter',
      'grandson': 'grandfather',
      'granddaughter': 'grandmother',
      // Uncles / aunts / nephews / nieces
      'uncle': 'nephew',
      'aunt': 'niece',
      'nephew': 'uncle',
      'niece': 'aunt',
      // Cousins
      'cousin': 'cousin',
      'cousin_brother': 'cousin_brother',
      'cousin_sister': 'cousin_sister',
      // In-laws
      'father_in_law': 'son_in_law',
      'mother_in_law': 'daughter_in_law',
      'son_in_law': 'father_in_law',
      'daughter_in_law': 'mother_in_law',
      'brother_in_law': 'sister_in_law',
      'sister_in_law': 'brother_in_law',
      // Paternal
      'paternal_uncle': 'nephew',
      'paternal_aunt': 'niece',
      // Maternal
      'maternal_uncle': 'nephew',
      'maternal_aunt': 'niece',
      // Step
      'stepfather': 'stepson',
      'stepmother': 'stepdaughter',
      'stepson': 'stepfather',
      'stepdaughter': 'stepmother',
      'stepbrother': 'stepbrother',
      'stepsister': 'stepsister',
      // Half-siblings
      'half_brother': 'half_brother',
      'half_sister': 'half_sister',
    };
    return inverseMap[key] ?? key;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// PERSON NODE CARD — Circular Avatar Node
// ═══════════════════════════════════════════════════════════════════════

/// A circular avatar node card for a person in the graph canvas.
///
/// Layout:
///   - 72dp diameter circle with generation-colored border ring
///   - Anchor person: double-ring (outer 88dp teal at 25% alpha,
///     inner 72dp teal solid 3dp)
///   - Content: 2-letter initials or ClipOval photo
///   - Deceased: Opacity(0.4)
///   - Name + relation label below the circle (2 lines, centered)
///   - Tap: navigate to person profile
///   - Long-press: bottom sheet with quick actions
///   - Semantics for accessibility
class _PersonNodeCard extends ConsumerWidget {
  const _PersonNodeCard({
    required this.person,
    required this.nodeWidth,
    required this.nodeHeight,
    required this.zoomLevel,
    required this.opacity,
    required this.relationLabel,
    required this.familyId,
    required this.relationships,
    required this.personMap,
  });

  final PersonData person;
  final double nodeWidth;
  final double nodeHeight;
  final double zoomLevel;
  final double opacity;
  final String relationLabel;
  final String familyId;
  final List<RelationshipData> relationships;
  final Map<String, PersonData> personMap;

  // ── Generation Ring Color ──────────────────────────────────────────

  Color get _ringColor {
    if (person.generationIndex < 0) {
      // Parents
      return KinrelColors.blue.withValues(alpha: 0.6);
    } else if (person.generationIndex == 0) {
      // Self / siblings
      return KinrelColors.tealAccent;
    } else {
      // Children
      return KinrelColors.coral.withValues(alpha: 0.6);
    }
  }

  // ── Initials ───────────────────────────────────────────────────────

  String get _initials {
    final parts = person.name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      // First letter of first name + first letter of last name
      return (parts.first[0] + parts.last[0]).toUpperCase();
    } else if (parts.isNotEmpty && parts.first.isNotEmpty) {
      // First two letters of single name
      return parts.first.length >= 2
          ? parts.first.substring(0, 2).toUpperCase()
          : parts.first[0].toUpperCase();
    }
    return '?';
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Opacity(
      opacity: person.isDeceased ? 0.4 * opacity : opacity,
      child: Semantics(
        label: '${person.name}, $relationLabel',
        button: true,
        child: GestureDetector(
          onTap: () => context.push('/family/$familyId/person/${person.id}'),
          onLongPress: () => _showQuickActions(context, ref),
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
        ),
      ),
    );
  }

  // ── Circle Node Builder ────────────────────────────────────────────

  Widget _buildCircleNode() {
    const double diameter = 72.0;

    // Anchor double-ring: outer glow ring behind, inner solid ring
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
                // Outer ring effect via box shadow
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

    // Standard node with generation-colored ring
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
    // If photo URL is available, show photo in ClipOval
    if (person.photoUrl != null && person.photoUrl!.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          person.photoUrl!,
          width: diameter,
          height: diameter,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildInitialsContent(),
        ),
      );
    }

    // Fallback: initials
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

  // ── Quick Actions Bottom Sheet ─────────────────────────────────────

  void _showQuickActions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      builder: (context) => SafeArea(
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
                Navigator.pop(context);
                context.push('/family/$familyId/person/${person.id}');
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
                Navigator.pop(context);
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
                Navigator.pop(context);
                final client = Supabase.instance.client;
                await client
                    .from('Person')
                    .update({'isAnchor': true})
                    .eq('id', person.id);
                await client
                    .from('Family')
                    .update({'anchorPersonId': person.id})
                    .eq('id', familyId);
                ref.invalidate(familyGraphProvider(familyId));
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: KinrelColors.coral),
              title: Text(
                'Remove',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  color: KinrelColors.textWhite,
                ),
              ),
              onTap: () async {
                Navigator.pop(context);
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    backgroundColor: const Color(0xFF191B2C),
                    title: Text('Remove ${person.name}?',
                        style: const TextStyle(color: Color(0xFFF5F0EE))),
                    content: const Text('This will soft-delete them from the family.',
                        style: TextStyle(color: Color(0xFF8A7A72))),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(context, true),
                          child: const Text('Remove',
                              style: TextStyle(color: Color(0xFFE8612A)))),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await Supabase.instance.client
                      .from('Person')
                      .update({'deletedAt': DateTime.now().toIso8601String()})
                      .eq('id', person.id);
                  ref.invalidate(familyGraphProvider(familyId));
                }
              },
            ),

            const SizedBox(height: 8.0),
          ],
        ),
      ),
    );
  }
}
