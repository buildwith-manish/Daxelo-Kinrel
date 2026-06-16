// lib/graph/widgets/filter_panel.dart
//
// DAXELO KINREL — Graph Filter Panel (V2.1 Blueprint §17.2)
//
// A slide-in filter panel for the family graph. Provides relationship
// type filtering, generation filtering, blood/marriage toggle, active
// members toggle, and degrees-of-separation range slider.
//
// Panel slides in from the right on mobile, from bottom on compact
// screens (<400dp). Uses the app's dark theme with teal accent.
// Wrapped in RepaintBoundary for rendering isolation.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/brand_colors.dart';
import '../../core/constants/brand_typography.dart';

// ═══════════════════════════════════════════════════════════════════════
// FILTER STATE
// ═══════════════════════════════════════════════════════════════════════

/// Immutable filter state for the graph filter panel.
///
/// Default state has no filters active (all members visible).
/// Each filter narrows the visible set of nodes and edges.
class FilterState {
  /// Relationship categories to show. Empty = all categories visible.
  final Set<String> relationshipCategories;

  /// Generation level to filter by. Null = all generations visible.
  final int? generationLevel;

  /// Whether to show only blood relationships.
  /// Null = show both blood and marriage.
  /// True = blood only. False = marriage only.
  final bool? bloodOnly;

  /// Whether to hide inactive/pending members.
  final bool hideInactive;

  /// Maximum degrees of separation from self (1–5, default 5).
  final int maxDegrees;

  /// Creates a filter state with the given values.
  const FilterState({
    this.relationshipCategories = const {},
    this.generationLevel,
    this.bloodOnly,
    this.hideInactive = false,
    this.maxDegrees = 5,
  });

  /// Whether any filter is active (non-default).
  bool get isActive =>
      relationshipCategories.isNotEmpty ||
      generationLevel != null ||
      bloodOnly != null ||
      hideInactive ||
      maxDegrees < 5;

  /// Creates a copy with optional field overrides.
  FilterState copyWith({
    Set<String>? relationshipCategories,
    int? Function()? generationLevel,
    bool? Function()? bloodOnly,
    bool? hideInactive,
    int? maxDegrees,
  }) {
    return FilterState(
      relationshipCategories:
          relationshipCategories ?? this.relationshipCategories,
      generationLevel:
          generationLevel != null ? generationLevel() : this.generationLevel,
      bloodOnly: bloodOnly != null ? bloodOnly() : this.bloodOnly,
      hideInactive: hideInactive ?? this.hideInactive,
      maxDegrees: maxDegrees ?? this.maxDegrees,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FilterState &&
          runtimeType == other.runtimeType &&
          _setEquals(relationshipCategories, other.relationshipCategories) &&
          generationLevel == other.generationLevel &&
          bloodOnly == other.bloodOnly &&
          hideInactive == other.hideInactive &&
          maxDegrees == other.maxDegrees;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(relationshipCategories),
        generationLevel,
        bloodOnly,
        hideInactive,
        maxDegrees,
      );

  static bool _setEquals<T>(Set<T> a, Set<T> b) {
    if (a.length != b.length) return false;
    for (final v in a) {
      if (!b.contains(v)) return false;
    }
    return true;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// RELATIONSHIP CATEGORY DEFINITIONS
// ═══════════════════════════════════════════════════════════════════════

/// Available relationship category keys for filtering.
class _FilterCategories {
  _FilterCategories._();

  static const List<({String key, String label, Color color})> all = [
    (key: 'self', label: 'Self', color: KinrelColors.nodeSelf),
    (key: 'parent', label: 'Parent', color: KinrelColors.nodeParent),
    (key: 'sibling', label: 'Sibling', color: KinrelColors.nodeSibling),
    (key: 'child', label: 'Child', color: KinrelColors.nodeChild),
    (key: 'spouse', label: 'Spouse', color: KinrelColors.nodeSpouse),
    (key: 'grandparent', label: 'Grandparent', color: KinrelColors.nodeGrandparent),
    (key: 'aunt_uncle', label: 'Aunt/Uncle', color: KinrelColors.nodeAuntUncle),
    (key: 'cousin', label: 'Cousin', color: KinrelColors.nodeCousin),
    (key: 'in_law', label: 'In-Law', color: KinrelColors.nodeInLaw),
    (key: 'extended', label: 'Extended', color: KinrelColors.nodeExtended),
  ];
}

// ═══════════════════════════════════════════════════════════════════════
// RIVERPOD PROVIDER
// ═══════════════════════════════════════════════════════════════════════

/// Provider for the current graph filter state.
final graphFilterProvider =
    StateNotifierProvider<GraphFilterNotifier, FilterState>(
  (ref) => GraphFilterNotifier(),
);

/// State notifier managing filter state with SharedPreferences persistence.
class GraphFilterNotifier extends StateNotifier<FilterState> {
  GraphFilterNotifier() : super(const FilterState());

  /// Updates the filter state and persists hideInactive to SharedPreferences.
  Future<void> updateFilter(FilterState newFilter) async {
    state = newFilter;

    // Persist hideInactive toggle
    if (newFilter.hideInactive) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('graph_filter_hide_inactive', newFilter.hideInactive);
    }
  }

  /// Resets all filters to default.
  Future<void> reset() async {
    state = const FilterState();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('graph_filter_hide_inactive');
  }

  /// Loads persisted filter preferences on startup.
  Future<void> loadPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    final hideInactive =
        prefs.getBool('graph_filter_hide_inactive') ?? false;
    if (hideInactive != state.hideInactive) {
      state = state.copyWith(hideInactive: hideInactive);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// GRAPH FILTER PANEL
// ═══════════════════════════════════════════════════════════════════════

/// A slide-in filter panel for the family graph.
///
/// Provides controls for filtering by relationship type, generation,
/// blood vs. marriage, active members, and degrees of separation.
/// The panel slides in from the right on standard mobile screens
/// and from the bottom on compact screens (<400dp width).
class GraphFilterPanel extends ConsumerWidget {
  /// Creates a graph filter panel.
  const GraphFilterPanel({
    super.key,
    required this.isVisible,
    required this.onClose,
    required this.onFilterChanged,
    required this.currentFilter,
  });

  /// Whether the panel is currently visible.
  final bool isVisible;

  /// Callback when the close button is tapped.
  final VoidCallback onClose;

  /// Callback when any filter value changes.
  final ValueChanged<FilterState> onFilterChanged;

  /// The current active filter state.
  final FilterState currentFilter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isVisible) return const SizedBox.shrink();

    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 400;

    // Positioned must be a direct structural descendant of the Stack.
    // Wrapping it in RepaintBoundary (a RenderObjectWidget) breaks
    // Stack's ability to read the positioning data. We therefore
    // return the Positioned directly and place RepaintBoundary inside.
    return isCompact ? _buildBottomPanel(context) : _buildSidePanel(context);
  }

  // ── Side Panel (right slide-in for standard mobile) ─────────────────

  Widget _buildSidePanel(BuildContext context) {
    return Positioned(
      top: 0,
      right: 0,
      bottom: 0,
      width: 300,
      child: RepaintBoundary(
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0A0E1A),
            border: Border(
              left: BorderSide(color: KinrelColors.border, width: 1),
            ),
          ),
          child: _buildPanelContent(context),
        ),
      ),
    );
  }

  // ── Bottom Panel (compact screens <400dp) ───────────────────────────

  Widget _buildBottomPanel(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: 360,
      child: RepaintBoundary(
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0A0E1A),
            border: Border(
              top: BorderSide(color: KinrelColors.border, width: 1),
            ),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(20),
            ),
          ),
          child: _buildPanelContent(context),
        ),
      ),
    );
  }

  // ── Panel Content ───────────────────────────────────────────────────

  Widget _buildPanelContent(BuildContext context) {
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
          child: Row(
            children: [
              const Icon(Icons.filter_list, size: 20, color: Color(0xFF0D9488)),
              const SizedBox(width: 8),
              Text(
                'Filter Graph',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                ),
              ),
              const Spacer(),
              if (currentFilter.isActive)
                TextButton(
                  onPressed: () => onFilterChanged(const FilterState()),
                  child: const Text(
                    'Reset',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      color: Color(0xFF0D9488),
                    ),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.close, size: 20, color: KinrelColors.textSilver),
                onPressed: onClose,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: KinrelColors.border),

        // Scrollable filter content
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // Relationship Type Filter
              _buildSectionLabel('Relationship Type'),
              const SizedBox(height: 8),
              _buildRelationshipChips(),
              const SizedBox(height: 20),

              // Generation Filter
              _buildSectionLabel('Generation'),
              const SizedBox(height: 8),
              _buildGenerationDropdown(),
              const SizedBox(height: 20),

              // Blood vs Marriage Toggle
              _buildSectionLabel('Connection Type'),
              const SizedBox(height: 8),
              _buildBloodMarriageToggle(),
              const SizedBox(height: 20),

              // Active Members Toggle
              _buildSectionLabel('Member Status'),
              const SizedBox(height: 8),
              _buildActiveMembersToggle(),
              const SizedBox(height: 20),

              // Degrees of Separation Slider
              _buildSectionLabel('Degrees of Separation'),
              const SizedBox(height: 8),
              _buildDegreesSlider(),
            ],
          ),
        ),
      ],
    );
  }

  // ── Section Label ───────────────────────────────────────────────────

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontFamily: KinrelTypography.bodyFont,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: KinrelColors.textDim,
        letterSpacing: 0.5,
      ),
    );
  }

  // ── Relationship Category Chips ─────────────────────────────────────

  Widget _buildRelationshipChips() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: _FilterCategories.all.map((cat) {
        final isSelected =
            currentFilter.relationshipCategories.contains(cat.key);
        return FilterChip(
          selected: isSelected,
          label: Text(
            cat.label,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              color: isSelected ? KinrelColors.textWhite : KinrelColors.textSilver,
            ),
          ),
          selectedColor: cat.color.withValues(alpha: 0.3),
          checkmarkColor: cat.color,
          side: BorderSide(
            color: isSelected ? cat.color : KinrelColors.border,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          onSelected: (selected) {
            final newCategories = Set<String>.from(
              currentFilter.relationshipCategories,
            );
            if (selected) {
              newCategories.add(cat.key);
            } else {
              newCategories.remove(cat.key);
            }
            onFilterChanged(
              currentFilter.copyWith(relationshipCategories: newCategories),
            );
          },
        );
      }).toList(),
    );
  }

  // ── Generation Dropdown ─────────────────────────────────────────────

  Widget _buildGenerationDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: KinrelColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: currentFilter.generationLevel,
          isExpanded: true,
          hint: const Text(
            'All Generations',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              color: KinrelColors.textSilver,
            ),
          ),
          dropdownColor: const Color(0xFF111827),
          style: const TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            color: KinrelColors.textWhite,
          ),
          items: [
            const DropdownMenuItem<int?>(
              value: null,
              child: Text('All Generations'),
            ),
            for (int i = -3; i <= 3; i++)
              DropdownMenuItem<int?>(
                value: i,
                child: Text(_generationLabel(i)),
              ),
          ],
          onChanged: (value) {
            onFilterChanged(
              currentFilter.copyWith(
                generationLevel: () => value,
              ),
            );
          },
        ),
      ),
    );
  }

  String _generationLabel(int gen) {
    if (gen == 0) return 'Generation 0 (Self)';
    if (gen < 0) return 'Generation $gen (Ancestors)';
    return 'Generation $gen (Descendants)';
  }

  // ── Blood vs Marriage Toggle ────────────────────────────────────────

  Widget _buildBloodMarriageToggle() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Row(
        children: [
          _buildToggleOption('All', null),
          _buildToggleOption('Blood', true),
          _buildToggleOption('Marriage', false),
        ],
      ),
    );
  }

  Widget _buildToggleOption(String label, bool? value) {
    final isActive = currentFilter.bloodOnly == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onFilterChanged(
          currentFilter.copyWith(bloodOnly: () => value),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFF0D9488).withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive
                    ? const Color(0xFF0D9488)
                    : KinrelColors.textSilver,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Active Members Toggle ───────────────────────────────────────────

  Widget _buildActiveMembersToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: KinrelColors.border),
      ),
      child: SwitchListTile(
        value: currentFilter.hideInactive,
        onChanged: (value) => onFilterChanged(
          currentFilter.copyWith(hideInactive: value),
        ),
        title: const Text(
          'Hide inactive members',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            color: KinrelColors.textWhite,
          ),
        ),
        subtitle: const Text(
          'Hides pending & deactivated members',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 11,
            color: KinrelColors.textDim,
          ),
        ),
        activeColor: const Color(0xFF0D9488),
        contentPadding: EdgeInsets.zero,
        dense: true,
      ),
    );
  }

  // ── Degrees of Separation Slider ────────────────────────────────────

  Widget _buildDegreesSlider() {
    return Column(
      children: [
        Row(
          children: [
            Text(
              '1',
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 11,
                color: KinrelColors.textDim,
              ),
            ),
            Expanded(
              child: Slider(
                value: currentFilter.maxDegrees.toDouble(),
                min: 1.0,
                max: 5.0,
                divisions: 4,
                activeColor: const Color(0xFF0D9488),
                inactiveColor: KinrelColors.border,
                onChanged: (value) {
                  onFilterChanged(
                    currentFilter.copyWith(maxDegrees: value.round()),
                  );
                },
              ),
            ),
            Text(
              '5',
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 11,
                color: KinrelColors.textDim,
              ),
            ),
          ],
        ),
        Text(
          '${currentFilter.maxDegrees} degree${currentFilter.maxDegrees > 1 ? 's' : ''} from you',
          style: const TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 12,
            color: KinrelColors.textSilver,
          ),
        ),
      ],
    );
  }
}
