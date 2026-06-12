// lib/features/family/presentation/family_graph_screen.dart
//
// DAXELO KINREL — Family Graph Screen
//
// Full-screen graph viewer for visualizing family relationships.
// Features:
//   - AppBar with family name, back button, stacked avatar previews
//   - Loading/error/empty states
//   - Graph canvas with zoom/pan controls
//   - Generation legend chips (top-left floating)
//   - Bottom legend bar with dynamic categories
//   - Bottom zoom/control bar with -, +, recenter, fit-to-screen
//   - Truncation warning banner for large families
//   - Real-time updates via Socket.IO

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import 'providers/family_graph_provider.dart';
import 'widgets/graph_canvas_widget.dart';
import 'widgets/generation_legend_widget.dart';

// ═══════════════════════════════════════════════════════════════════════
// FAMILY GRAPH SCREEN
// ═══════════════════════════════════════════════════════════════════════

class FamilyGraphScreen extends ConsumerStatefulWidget {
  const FamilyGraphScreen({
    super.key,
    required this.familyId,
    this.familyName,
  });

  final String familyId;
  final String? familyName;

  @override
  ConsumerState<FamilyGraphScreen> createState() => _FamilyGraphScreenState();
}

class _FamilyGraphScreenState extends ConsumerState<FamilyGraphScreen> {
  final TransformationController _transformCtrl = TransformationController();

  /// Highlighted generation index (null = no highlight).
  int? _highlightedGeneration;

  @override
  void dispose() {
    _transformCtrl.dispose();
    super.dispose();
  }

  // ── Zoom Controls ─────────────────────────────────────────────────

  void _zoomIn() {
    final current = _transformCtrl.value;
    final scale = current.storage[0];
    final newScale = (scale * 1.2).clamp(0.1, 4.0);
    _transformCtrl.value = Matrix4.diagonal3Values(newScale, newScale, 1.0);
    ref.read(graphZoomProvider.notifier).state = newScale;
  }

  void _zoomOut() {
    final current = _transformCtrl.value;
    final scale = current.storage[0];
    final newScale = (scale / 1.2).clamp(0.1, 4.0);
    _transformCtrl.value = Matrix4.diagonal3Values(newScale, newScale, 1.0);
    ref.read(graphZoomProvider.notifier).state = newScale;
  }

  void _resetView() {
    _transformCtrl.value = Matrix4.identity();
    ref.read(graphZoomProvider.notifier).state = 1.0;
  }

  void _fitToScreen() {
    // Reset to identity and let InteractiveViewer handle the fit
    _transformCtrl.value = Matrix4.identity();
    ref.read(graphZoomProvider.notifier).state = 1.0;
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    ref.watch(graphRealtimeProvider(widget.familyId));
    final graphAsync = ref.watch(familyGraphProvider(widget.familyId));

    return Scaffold(
      backgroundColor: KinrelColors.darkBackground,
      appBar: _buildAppBar(graphAsync.valueOrNull),
      body: graphAsync.when(
        loading: _buildLoadingState,
        error: _buildErrorState,
        data: _buildDataState,
      ),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(FlatGraphResult? graph) {
    // Build up to 3 overlapping avatar circles for the top-right
    final persons = graph?.toPersonDataList() ?? [];
    final avatarPersons = persons.take(3).toList();

    return AppBar(
      backgroundColor: KinrelColors.darkCard,
      foregroundColor: KinrelColors.textWhite,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, size: 22),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Text(
        widget.familyName ?? 'Family Graph',
        style: TextStyle(
          fontFamily: KinrelTypography.displayFont,
          fontWeight: FontWeight.w600,
          fontSize: 18,
        ),
      ),
      actions: [
        // 3 stacked circular avatar previews
        if (avatarPersons.isNotEmpty)
          GestureDetector(
            onTap: () => _showFamilyMembersSheet(persons),
            child: Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: SizedBox(
                width: 28.0 * avatarPersons.length.toDouble() + 12.0,
                height: 36.0,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: List.generate(avatarPersons.length, (i) {
                    final p = avatarPersons[i];
                    final initials = p.name.trim().split(RegExp(r'\s+'));
                    final letter = initials.length >= 2
                        ? '${initials[0][0]}${initials[1][0]}'.toUpperCase()
                        : p.name.substring(0, p.name.length > 1 ? 2 : 1).toUpperCase();

                    return Positioned(
                      left: i * 16.0,
                      child: Container(
                        width: 28.0,
                        height: 28.0,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: KinrelColors.darkElevated,
                          border: Border.all(color: KinrelColors.textWhite, width: 1.5),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          letter,
                          style: TextStyle(
                            fontFamily: KinrelTypography.displayFont,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: KinrelColors.textWhite,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _showFamilyMembersSheet(List<PersonData> persons) {
    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        minChildSize: 0.25,
        maxChildSize: 0.8,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Family Members',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textWhite,
                ),
              ),
            ),
            const Divider(color: Color(0x1AFFFFFF), height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: persons.length,
                itemBuilder: (context, index) {
                  final p = persons[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: KinrelColors.darkElevated,
                      child: Text(
                        p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                        style: TextStyle(color: KinrelColors.textWhite, fontSize: 14),
                      ),
                    ),
                    title: Text(p.name, style: TextStyle(color: KinrelColors.textWhite, fontFamily: KinrelTypography.displayFont)),
                    subtitle: Text('Generation ${p.generationIndex}', style: TextStyle(color: KinrelColors.textDim, fontSize: 12)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Loading State ─────────────────────────────────────────────────

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: KinrelColors.orange, strokeWidth: 3),
          SizedBox(height: 16),
          Text('Loading family graph...', style: TextStyle(color: KinrelColors.textSecondaryDark, fontFamily: 'DMSans', fontSize: 14)),
        ],
      ),
    );
  }

  // ── Error State ───────────────────────────────────────────────────

  Widget _buildErrorState(Object error, StackTrace stackTrace) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: KinrelColors.orange, size: 48),
            const SizedBox(height: 16),
            const Text('Something went wrong', style: TextStyle(color: KinrelColors.textWhite, fontFamily: 'Outfit', fontWeight: FontWeight.w600, fontSize: 18)),
            const SizedBox(height: 8),
            Text(error.toString(), style: const TextStyle(color: KinrelColors.textSecondaryDark, fontFamily: 'DMSans', fontSize: 13), textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => ref.invalidate(familyGraphProvider(widget.familyId)),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Tap to retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: KinrelColors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Data State ────────────────────────────────────────────────────

  Widget _buildDataState(FlatGraphResult graph) {
    if (graph.persons.isEmpty) return _buildEmptyState();

    final persons = graph.toPersonDataList();

    // Determine which generations are present
    final presentGenerations = <int>{};
    for (final p in persons) {
      presentGenerations.add(p.generationIndex);
    }

    return Stack(
      children: [
        // Main graph content
        Column(
          children: [
            if (graph.isTruncated) _buildTruncationBanner(graph),
            Expanded(
              child: GraphCanvasWidget(
                persons: persons,
                relationships: graph.toRelationshipDataList(),
                familyId: widget.familyId,
              ),
            ),
            // Bottom legend bar
            _buildBottomLegendBar(presentGenerations),
            // Bottom zoom/control bar
            _buildBottomControlBar(),
          ],
        ),

        // Generation legend chips (top-left floating)
        Positioned(
          left: 16,
          top: graph.isTruncated ? 48 : 16,
          child: GenerationLegendWidget(
            presentGenerations: presentGenerations,
            highlightedGeneration: _highlightedGeneration,
            onGenerationTap: (gen) {
              setState(() => _highlightedGeneration = gen);
            },
          ),
        ),
      ],
    );
  }

  // ── Empty State ───────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.family_restroom_outlined, color: KinrelColors.textDim, size: 64),
            const SizedBox(height: 16),
            const Text('No family members yet', style: TextStyle(color: KinrelColors.textWhite, fontFamily: 'Outfit', fontWeight: FontWeight.w600, fontSize: 18)),
            const SizedBox(height: 8),
            const Text('Add family members and relationships to see\nthe family graph visualization.', style: TextStyle(color: KinrelColors.textSecondaryDark, fontFamily: 'DMSans', fontSize: 14), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.person_add, size: 18),
              label: const Text('Add Family Member'),
              style: ElevatedButton.styleFrom(
                backgroundColor: KinrelColors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Truncation Banner ─────────────────────────────────────────────

  Widget _buildTruncationBanner(FlatGraphResult graph) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: KinrelColors.darkElevated,
        border: Border(bottom: BorderSide(color: KinrelColors.amber, width: 1)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: KinrelColors.amber, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              graph.totalCount != null
                  ? 'Showing first ${graph.persons.length} of ${graph.totalCount} persons.'
                  : 'Showing first ${graph.persons.length} persons.',
              style: const TextStyle(color: KinrelColors.textSecondaryDark, fontFamily: 'DMSans', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom Legend Bar ─────────────────────────────────────────────

  Widget _buildBottomLegendBar(Set<int> presentGenerations) {
    final categories = <_LegendChip>[];

    final hasParents = presentGenerations.any((g) => g < 0 && g.abs() < 2);
    final hasSelf = presentGenerations.contains(0);
    final hasSiblings = presentGenerations.contains(0); // Siblings are gen 0
    final hasChildren = presentGenerations.any((g) => g > 0 && g < 2);
    final hasExtended = presentGenerations.any((g) => g.abs() >= 2);
    final hasInLaws = presentGenerations.contains(99);

    if (hasParents) categories.add(_LegendChip('Parents', KinrelColors.blue));
    if (hasSelf) categories.add(_LegendChip('Self', KinrelColors.tealAccent));
    if (hasSiblings && !hasSelf) categories.add(_LegendChip('Siblings', KinrelColors.tealAccent));
    if (hasChildren) categories.add(_LegendChip('Children', KinrelColors.coral));
    if (hasExtended) categories.add(_LegendChip('Extended', KinrelColors.extendedPurple));
    if (hasInLaws) categories.add(_LegendChip('In-laws', KinrelColors.inLawGold));

    if (categories.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: KinrelColors.darkCard.withValues(alpha: 0.9),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: categories.map((chip) => _buildLegendChip(chip)).toList(),
      ),
    );
  }

  Widget _buildLegendChip(_LegendChip chip) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: chip.color),
          ),
          const SizedBox(width: 4),
          Text(
            chip.label,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 11,
              color: KinrelColors.textSecondaryDark,
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom Control Bar ────────────────────────────────────────────

  Widget _buildBottomControlBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      color: KinrelColors.darkCard,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Zoom out
          _buildControlButton(Icons.remove, _zoomOut),
          const SizedBox(width: 16),
          // Zoom in
          _buildControlButton(Icons.add, _zoomIn),
          const SizedBox(width: 24),
          // Recenter (orange filled circle)
          GestureDetector(
            onTap: _resetView,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KinrelColors.orange,
                boxShadow: [
                  BoxShadow(
                    color: KinrelColors.orange.withValues(alpha: 0.3),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.center_focus_strong, color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 24),
          // Fit to screen
          _buildControlButton(Icons.fullscreen, _fitToScreen),
        ],
      ),
    );
  }

  Widget _buildControlButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: KinrelColors.darkElevated,
          border: Border.all(color: const Color(0x1AFFFFFF), width: 1),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: KinrelColors.textWhite, size: 18),
      ),
    );
  }
}

// ── Helper class for legend chips ──────────────────────────────────

class _LegendChip {
  final String label;
  final Color color;
  const _LegendChip(this.label, this.color);
}
