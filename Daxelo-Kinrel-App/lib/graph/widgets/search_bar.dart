// lib/graph/widgets/search_bar.dart
//
// DAXELO KINREL — Graph Search Bar Widget
//
// Graph-specific search bar with filters.
//
// Search dimensions:
//   By Name: Supabase FTS with trigram similarity, <150ms
//   By Username: exact + prefix matching, <100ms
//   By Relationship: filter by type from kinship_types, <150ms
//   By Member ID: direct UUID lookup, <50ms
//
// Offline: cached names/usernames indexed locally
//
// Filter types:
//   Relationship Type: chip group (show only selected, others dimmed 20%)
//   Generation: dropdown
//   Blood vs. Marriage: toggle
//   Active Members: toggle (persistent)
//   Custom Range: slider 1-5 degrees
//
// Debounced input (300ms)
// Search results dropdown with avatar + name + relationship
// Tap result → camera focuses on that node
// Keyboard shortcut: Ctrl/Cmd+K to open
// Tracks search events via AnalyticsTracker

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/brand_colors.dart';
import '../../core/constants/brand_typography.dart';
import '../analytics/analytics_tracker.dart';
import 'graph_node.dart';

// ═══════════════════════════════════════════════════════════════════════
// SEARCH RESULT MODEL
// ═══════════════════════════════════════════════════════════════════════

/// A single search result from the graph search.
class GraphSearchResult {
  /// The member ID.
  final String memberId;

  /// Display name.
  final String name;

  /// Optional avatar URL.
  final String? photoUrl;

  /// Relationship type key from the anchor.
  final String? relationshipKey;

  /// Generation index.
  final int generationIndex;

  /// Optional username.
  final String? username;

  const GraphSearchResult({
    required this.memberId,
    required this.name,
    this.photoUrl,
    this.relationshipKey,
    this.generationIndex = 0,
    this.username,
  });
}

// ═══════════════════════════════════════════════════════════════════════
// FILTER TYPES
// ═══════════════════════════════════════════════════════════════════════

/// Relationship filter chip options for the search bar.
enum RelationshipFilter {
  parent('Parent', 'parent'),
  child('Child', 'child'),
  sibling('Sibling', 'sibling'),
  spouse('Spouse', 'spouse'),
  grandparent('Grandparent', 'grandparent'),
  auntUncle('Aunt/Uncle', 'aunt_uncle'),
  cousin('Cousin', 'cousin'),
  inLaw('In-Law', 'in_law'),
  extended('Extended', 'extended');

  const RelationshipFilter(this.label, this.key);

  /// Display label for the filter chip.
  final String label;

  /// Key used for filtering.
  final String key;
}

/// Generation filter options.
enum GenerationFilter {
  all('All', null),
  self('Self (Gen 0)', 0),
  parents('Parents (Gen -1)', -1),
  grandparents('Grandparents (Gen -2)', -2),
  children('Children (Gen 1)', 1),
  grandchildren('Grandchildren (Gen 2)', 2);

  const GenerationFilter(this.label, this.generationIndex);

  /// Display label for the dropdown.
  final String label;

  /// Generation index to filter by, or null for all.
  final int? generationIndex;
}

// ═══════════════════════════════════════════════════════════════════════
// GRAPH SEARCH BAR WIDGET
// ═══════════════════════════════════════════════════════════════════════

/// A graph-specific search bar with filters, debounced input,
/// and result dropdown.
///
/// Features:
///   - Debounced input (300ms)
///   - Search by name, username, relationship type, or member ID
///   - Relationship type filter chips
///   - Generation dropdown filter
///   - Blood vs. Marriage toggle
///   - Active Members toggle
///   - Custom degree range slider (1-5)
///   - Search results dropdown with avatar + name + relationship
///   - Tap result → camera focuses on that node
///   - Keyboard shortcut: Ctrl/Cmd+K to open
///   - Tracks search events via AnalyticsTracker
///
/// Usage:
/// ```dart
/// GraphSearchBar(
///   familyId: 'family-123',
///   onResultTap: (memberId) => focusCamera(memberId),
///   onClose: () => toggleSearchBar(),
/// )
/// ```
class GraphSearchBar extends ConsumerStatefulWidget {
  const GraphSearchBar({
    super.key,
    required this.familyId,
    required this.onResultTap,
    required this.onClose,
  });

  /// The family ID for search context.
  final String familyId;

  /// Callback when a search result is tapped.
  final ValueChanged<String> onResultTap;

  /// Callback when the search bar is closed.
  final VoidCallback onClose;

  @override
  ConsumerState<GraphSearchBar> createState() => _GraphSearchBarState();
}

class _GraphSearchBarState extends ConsumerState<GraphSearchBar> {
  // ── Controllers ────────────────────────────────────────────────────

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // ── State ──────────────────────────────────────────────────────────

  /// Current search results.
  List<GraphSearchResult> _results = [];

  /// Whether search is in progress.
  bool _isSearching = false;

  /// Selected relationship filters.
  final Set<RelationshipFilter> _selectedFilters = {};

  /// Selected generation filter.
  GenerationFilter _generationFilter = GenerationFilter.all;

  /// Blood vs. Marriage toggle (null = all, true = blood, false = marriage).
  bool? _bloodOnly;

  /// Active members only toggle.
  bool _activeOnly = true;

  /// Degree range slider value.
  double _degreeRange = 5.0;

  /// Whether the filter panel is expanded.
  bool _filtersExpanded = false;

  /// Debounce timer for search input.
  Timer? _debounceTimer;

  /// Search stopwatch for timing.
  final Stopwatch _searchStopwatch = Stopwatch();

  // ── Keyboard Shortcut ──────────────────────────────────────────────

  late final KeyboardListener _keyboardListener;

  @override
  void initState() {
    super.initState();
    _searchFocusNode.requestFocus();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchStopwatch.stop();
    super.dispose();
  }

  // ── Search Logic ───────────────────────────────────────────────────

  /// Handles search input changes with 300ms debounce.
  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _performSearch(query);
    });
  }

  /// Performs the search with the current query and filters.
  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    _searchStopwatch.reset();
    _searchStopwatch.start();

    try {
      // Simulate search results (in production, this would call
      // Supabase FTS, username lookup, relationship filter, etc.)
      final results = await _searchGraph(query);

      _searchStopwatch.stop();

      if (mounted) {
        setState(() {
          _results = results;
          _isSearching = false;
        });

        // Track search event
        ref.read(analyticsTrackerProvider).trackSearchQuery(
              query.length,
              results.length,
              _searchStopwatch.elapsedMilliseconds,
            );
      }
    } catch (e) {
      _searchStopwatch.stop();
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  /// Searches the graph for members matching the query.
  ///
  /// In production, this would:
  /// 1. By Name: Supabase FTS with trigram similarity (<150ms)
  /// 2. By Username: exact + prefix matching (<100ms)
  /// 3. By Relationship: filter by type from kinship_types (<150ms)
  /// 4. By Member ID: direct UUID lookup (<50ms)
  /// 5. Apply active filters (generation, blood/marriage, degree)
  Future<List<GraphSearchResult>> _searchGraph(String query) async {
    // Placeholder: in production, replace with actual Supabase queries
    // This is a client-side filter that would use cached data
    await Future.delayed(const Duration(milliseconds: 50));

    return <GraphSearchResult>[
      // Results would be populated from the data layer
    ];
  }

  // ── Filter Toggle Handlers ─────────────────────────────────────────

  void _toggleFilter(RelationshipFilter filter) {
    setState(() {
      if (_selectedFilters.contains(filter)) {
        _selectedFilters.remove(filter);
      } else {
        _selectedFilters.add(filter);
      }
    });

    // Re-search with updated filters
    if (_searchController.text.isNotEmpty) {
      _performSearch(_searchController.text);
    }
  }

  void _setGenerationFilter(GenerationFilter filter) {
    setState(() {
      _generationFilter = filter;
    });

    if (_searchController.text.isNotEmpty) {
      _performSearch(_searchController.text);
    }
  }

  void _setBloodOnly(bool? value) {
    setState(() {
      _bloodOnly = value;
    });

    if (_searchController.text.isNotEmpty) {
      _performSearch(_searchController.text);
    }
  }

  void _setActiveOnly(bool value) {
    setState(() {
      _activeOnly = value;
    });

    if (_searchController.text.isNotEmpty) {
      _performSearch(_searchController.text);
    }
  }

  void _setDegreeRange(double value) {
    setState(() {
      _degreeRange = value;
    });
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: (event) {
        // Ctrl/Cmd+K to toggle search
        final isCmdOrCtrl = HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed;
        if (isCmdOrCtrl &&
            event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.keyK) {
          widget.onClose();
        }
        // Escape to close
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onClose();
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Search Input ───────────────────────────────────────────
          _buildSearchInput(),

          // ── Filter Panel (expandable) ──────────────────────────────
          if (_filtersExpanded) _buildFilterPanel(),

          // ── Results Dropdown ───────────────────────────────────────
          if (_results.isNotEmpty || _isSearching)
            _buildResultsDropdown(),
        ],
      ),
    );
  }

  // ── Search Input ───────────────────────────────────────────────────

  Widget _buildSearchInput() {
    return Container(
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(14.0),
        border: Border.all(
          color: KinrelColors.orange.withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: KinrelColors.orangeGlow,
            blurRadius: 16.0,
            spreadRadius: 2.0,
          ),
        ],
      ),
      child: Row(
        children: [
          // Search icon
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 14.0),
            child: Icon(
              Icons.search,
              size: 20.0,
              color: KinrelColors.orange,
            ),
          ),

          // Text field
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: _onSearchChanged,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 15.0,
                color: KinrelColors.textWhite,
              ),
              decoration: InputDecoration(
                hintText: 'Search by name, username, or relationship...',
                hintStyle: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14.0,
                  color: KinrelColors.textDim,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12.0,
                  vertical: 14.0,
                ),
              ),
            ),
          ),

          // Filter toggle button
          IconButton(
            onPressed: () {
              setState(() {
                _filtersExpanded = !_filtersExpanded;
              });
            },
            tooltip: 'Toggle filters',
            icon: Icon(
              _filtersExpanded
                  ? Icons.filter_list
                  : Icons.filter_list_outlined,
              size: 20.0,
              color: _filtersExpanded
                  ? KinrelColors.orange
                  : KinrelColors.textDim,
            ),
            splashRadius: 18.0,
          ),

          // Clear / close button
          if (_searchController.text.isNotEmpty)
            IconButton(
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _results = [];
                });
              },
              tooltip: 'Clear search',
              icon: const Icon(
                Icons.close,
                size: 18.0,
                color: KinrelColors.textDim,
              ),
              splashRadius: 18.0,
            )
          else
            IconButton(
              onPressed: widget.onClose,
              tooltip: 'Close search',
              icon: const Icon(
                Icons.close,
                size: 18.0,
                color: KinrelColors.textDim,
              ),
              splashRadius: 18.0,
            ),
        ],
      ),
    );
  }

  // ── Filter Panel ───────────────────────────────────────────────────

  Widget _buildFilterPanel() {
    return Container(
      margin: const EdgeInsets.only(top: 8.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(14.0),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Relationship Type Chips ───────────────────────────────
          Text(
            'Relationship Type',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12.0,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textSilver,
            ),
          ),
          const SizedBox(height: 8.0),
          Wrap(
            spacing: 6.0,
            runSpacing: 6.0,
            children: RelationshipFilter.values.map((filter) {
              final isSelected = _selectedFilters.contains(filter);
              final color = _filterChipColor(filter);

              return FilterChip(
                selected: isSelected,
                label: Text(
                  filter.label,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12.0,
                    color: isSelected
                        ? KinrelColors.textWhite
                        : KinrelColors.textDim,
                  ),
                ),
                onSelected: (_) => _toggleFilter(filter),
                backgroundColor: KinrelColors.darkElevated,
                selectedColor: color.withValues(alpha: 0.3),
                side: BorderSide(
                  color: isSelected
                      ? color
                      : KinrelColors.border,
                ),
                checkmarkColor: color,
              );
            }).toList(),
          ),

          const SizedBox(height: 16.0),

          // ── Row: Generation + Blood/Marriage + Active ────────────
          Row(
            children: [
              // Generation dropdown
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Generation',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12.0,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.textSilver,
                      ),
                    ),
                    const SizedBox(height: 6.0),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10.0),
                      decoration: BoxDecoration(
                        color: KinrelColors.darkElevated,
                        borderRadius: BorderRadius.circular(8.0),
                        border: Border.all(color: KinrelColors.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<GenerationFilter>(
                          value: _generationFilter,
                          isExpanded: true,
                          isDense: true,
                          icon: const Icon(
                            Icons.arrow_drop_down,
                            size: 18.0,
                            color: KinrelColors.textDim,
                          ),
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 13.0,
                            color: KinrelColors.textWhite,
                          ),
                          dropdownColor: KinrelColors.darkCard,
                          items: GenerationFilter.values
                              .map((gf) => DropdownMenuItem(
                                    value: gf,
                                    child: Text(gf.label),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            if (value != null) _setGenerationFilter(value);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 16.0),

              // Blood vs. Marriage toggle
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Connection',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12.0,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.textSilver,
                    ),
                  ),
                  const SizedBox(height: 6.0),
                  _buildSegmentedToggle(
                    options: const ['All', 'Blood', 'Marriage'],
                    selectedIndex: _bloodOnly == null
                        ? 0
                        : _bloodOnly!
                            ? 1
                            : 2,
                    onSelected: (index) {
                      _setBloodOnly(
                        index == 0
                            ? null
                            : index == 1
                                ? true
                                : false,
                      );
                    },
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12.0),

          // ── Row: Active Only toggle + Degree Range ───────────────
          Row(
            children: [
              // Active members only
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 36.0,
                    height: 20.0,
                    child: Switch(
                      value: _activeOnly,
                      onChanged: _setActiveOnly,
                      activeColor: KinrelColors.orange,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 6.0),
                  Text(
                    'Active only',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12.0,
                      color: _activeOnly
                          ? KinrelColors.textWhite
                          : KinrelColors.textDim,
                    ),
                  ),
                ],
              ),

              const Spacer(),

              // Degree range slider
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Max degree: ${_degreeRange.round()}',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12.0,
                      color: KinrelColors.textSilver,
                    ),
                  ),
                  SizedBox(
                    width: 140.0,
                    child: Slider(
                      value: _degreeRange,
                      min: 1.0,
                      max: 5.0,
                      divisions: 4,
                      activeColor: KinrelColors.orange,
                      inactiveColor: KinrelColors.border,
                      onChanged: _setDegreeRange,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Returns the color for a relationship filter chip.
  Color _filterChipColor(RelationshipFilter filter) {
    return switch (filter) {
      RelationshipFilter.parent => RelationshipColors.parent,
      RelationshipFilter.child => RelationshipColors.child,
      RelationshipFilter.sibling => RelationshipColors.sibling,
      RelationshipFilter.spouse => RelationshipColors.spouse,
      RelationshipFilter.grandparent => RelationshipColors.grandparent,
      RelationshipFilter.auntUncle => RelationshipColors.auntUncle,
      RelationshipFilter.cousin => RelationshipColors.cousin,
      RelationshipFilter.inLaw => RelationshipColors.inLaw,
      RelationshipFilter.extended => RelationshipColors.extended,
    };
  }

  /// Builds a segmented toggle button for blood/marriage filtering.
  Widget _buildSegmentedToggle({
    required List<String> options,
    required int selectedIndex,
    required ValueChanged<int> onSelected,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: KinrelColors.darkElevated,
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(options.length, (index) {
          final isSelected = index == selectedIndex;
          return GestureDetector(
            onTap: () => onSelected(index),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10.0,
                vertical: 6.0,
              ),
              decoration: BoxDecoration(
                color: isSelected
                    ? KinrelColors.orange.withValues(alpha: 0.2)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6.0),
              ),
              child: Text(
                options[index],
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12.0,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected
                      ? KinrelColors.orange
                      : KinrelColors.textDim,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Results Dropdown ───────────────────────────────────────────────

  Widget _buildResultsDropdown() {
    return Container(
      margin: const EdgeInsets.only(top: 8.0),
      constraints: const BoxConstraints(maxHeight: 300.0),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(14.0),
        border: Border.all(color: KinrelColors.border),
      ),
      child: _isSearching
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: SizedBox(
                  width: 20.0,
                  height: 20.0,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.0,
                    color: KinrelColors.orange,
                  ),
                ),
              ),
            )
          : _results.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text(
                    'No results found',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14.0,
                      color: KinrelColors.textDim,
                    ),
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  itemCount: _results.length,
                  separatorBuilder: (_, __) => const Divider(
                    color: KinrelColors.border,
                    height: 1.0,
                    indent: 56.0,
                  ),
                  itemBuilder: (context, index) {
                    final result = _results[index];
                    return _buildResultItem(result);
                  },
                ),
    );
  }

  // ── Result Item ────────────────────────────────────────────────────

  Widget _buildResultItem(GraphSearchResult result) {
    final borderColor =
        RelationshipColors.borderColorFor(result.relationshipKey);

    return InkWell(
      onTap: () => widget.onResultTap(result.memberId),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 14.0,
          vertical: 10.0,
        ),
        child: Row(
          children: [
            // Avatar circle
            Container(
              width: 36.0,
              height: 36.0,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KinrelColors.darkElevated,
                border: Border.all(color: borderColor, width: 2.0),
              ),
              child: result.photoUrl != null
                  ? ClipOval(
                      child: Image.network(
                        result.photoUrl!,
                        width: 36.0,
                        height: 36.0,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _buildInitialsAvatar(result, borderColor),
                      ),
                    )
                  : _buildInitialsAvatar(result, borderColor),
            ),

            const SizedBox(width: 12.0),

            // Name and relationship
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.name,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14.0,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.textWhite,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (result.relationshipKey != null)
                    Text(
                      _formatKey(result.relationshipKey!),
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12.0,
                        color: borderColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),

            // Generation badge
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8.0,
                vertical: 2.0,
              ),
              decoration: BoxDecoration(
                color: KinrelColors.darkElevated,
                borderRadius: BorderRadius.circular(6.0),
                border: Border.all(color: KinrelColors.border),
              ),
              child: Text(
                'Gen ${result.generationIndex}',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 10.0,
                  color: KinrelColors.textDim,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds an initials avatar for a search result.
  Widget _buildInitialsAvatar(GraphSearchResult result, Color borderColor) {
    final parts = result.name.trim().split(RegExp(r'\s+'));
    String initials;
    if (parts.length >= 2) {
      initials = (parts.first[0] + parts.last[0]).toUpperCase();
    } else if (parts.isNotEmpty && parts.first.isNotEmpty) {
      initials = parts.first.length >= 2
          ? parts.first.substring(0, 2).toUpperCase()
          : parts.first[0].toUpperCase();
    } else {
      initials = '?';
    }

    return Center(
      child: Text(
        initials,
        style: TextStyle(
          fontFamily: KinrelTypography.displayFont,
          fontSize: 14.0,
          fontWeight: FontWeight.bold,
          color: borderColor,
        ),
      ),
    );
  }

  /// Formats a relationship key like 'father_in_law' → 'Father In Law'.
  static String _formatKey(String key) {
    return key
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }
}
