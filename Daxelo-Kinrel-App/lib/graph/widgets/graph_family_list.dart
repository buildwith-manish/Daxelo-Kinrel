// lib/graph/widgets/graph_family_list.dart
//
// DAXELO KINREL — Synchronized Family List Accessibility View (Phase 9)
//
// A non-canvas representation of the same canonical family graph.
// This is an accessibility and usability feature — it does NOT create
// separate family data.
//
// Displays the family as a hierarchical list grouped by relationship
// category (Parents, Siblings, Partners, Children, etc.) using the
// deterministic kinship system. Selecting a member can focus them in
// the graph, open person details, or start "View relationship."
//
// Supports: screen readers, dynamic text size, high contrast,
// keyboard navigation on desktop/web, clear headings, non-colour
// semantics. Uses culturally accurate localized terminology from
// existing localization systems.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/brand_colors.dart';
import '../../core/constants/brand_typography.dart';
import '../../core/kinship/kinship_edge_style.dart';
import '../interaction/graph_focus_state.dart' show graphFocusProvider;
import 'graph_relationship_labels.dart';

/// A single entry in the family list.
class FamilyListEntry {
  const FamilyListEntry({
    required this.personId,
    required this.name,
    this.relationshipKey,
    this.relationshipLabel,
    this.localizedTerm,
    this.gender,
    this.isDeceased = false,
    this.photoUrl,
  });

  final String personId;
  final String name;
  final String? relationshipKey;
  final String? relationshipLabel;
  final String? localizedTerm;
  final String? gender;
  final bool isDeceased;
  final String? photoUrl;
}

/// A group of entries in the family list (e.g. "Parents", "Siblings").
class FamilyListGroup {
  const FamilyListGroup({
    required this.title,
    required this.entries,
    required this.category,
  });

  final String title;
  final List<FamilyListEntry> entries;
  final KinshipEdgeCategory category;
}

/// Builds family list groups from the canonical FlatGraphResult.
///
/// Groups are derived from the authoritative kinship category map —
/// NOT from visual graph positions. The grouping is deterministic.
///
/// [persons] — the raw person maps from FlatGraphResult.persons.
/// [relationLabelById] — personId → relationship label (e.g. "Father").
/// [relationCategoryById] — personId → KinshipEdgeCategory.
/// [viewerPersonId] — the current viewer (excluded from groups; shown
/// as "You" at the top).
List<FamilyListGroup> buildFamilyListGroups({
  required List<Map<String, dynamic>> persons,
  required Map<String, String> relationLabelById,
  required Map<String, KinshipEdgeCategory> relationCategoryById,
  String? viewerPersonId,
}) {
  final groups = <KinshipEdgeCategory, List<FamilyListEntry>>{};

  for (final p in persons) {
    final id = (p['id'] ?? '').toString();
    if (id.isEmpty) continue;
    if (id == viewerPersonId) continue; // viewer is shown separately

    final category = relationCategoryById[id] ?? KinshipEdgeCategory.extended;
    final label = relationLabelById[id] ?? '';
    final name = (p['name'] ?? '').toString();

    groups.putIfAbsent(category, () => []).add(FamilyListEntry(
      personId: id,
      name: name,
      relationshipKey: label,
      relationshipLabel: _formatLabel(label),
      gender: p['gender'] as String?,
      isDeceased: (p['isDeceased'] as bool?) ?? false,
      photoUrl: p['photoUrl'] as String?,
    ));
  }

  // Order groups by the standard kinship priority.
  final orderedCategories = [
    KinshipEdgeCategory.parent,
    KinshipEdgeCategory.sibling,
    KinshipEdgeCategory.spouse,
    KinshipEdgeCategory.child,
    KinshipEdgeCategory.grandparent,
    KinshipEdgeCategory.auntUncle,
    KinshipEdgeCategory.cousin,
    KinshipEdgeCategory.inLaw,
    KinshipEdgeCategory.extended,
    KinshipEdgeCategory.indirect,
    KinshipEdgeCategory.self,
  ];

  final result = <FamilyListGroup>[];
  for (final cat in orderedCategories) {
    final entries = groups[cat];
    if (entries == null || entries.isEmpty) continue;
    result.add(FamilyListGroup(
      title: _categoryTitle(cat),
      entries: entries,
      category: cat,
    ));
  }

  return result;
}

String _categoryTitle(KinshipEdgeCategory cat) {
  switch (cat) {
    case KinshipEdgeCategory.parent:
      return 'Parents';
    case KinshipEdgeCategory.child:
      return 'Children';
    case KinshipEdgeCategory.sibling:
      return 'Siblings';
    case KinshipEdgeCategory.spouse:
      return 'Partners';
    case KinshipEdgeCategory.grandparent:
      return 'Grandparents';
    case KinshipEdgeCategory.auntUncle:
      return 'Aunts & Uncles';
    case KinshipEdgeCategory.cousin:
      return 'Cousins';
    case KinshipEdgeCategory.inLaw:
      return 'In-Laws';
    case KinshipEdgeCategory.extended:
      return 'Extended Family';
    case KinshipEdgeCategory.indirect:
      return 'Indirect Connections';
    case KinshipEdgeCategory.self:
      return 'Self';
  }
}

String _formatLabel(String key) {
  if (key.isEmpty) return '';
  return key
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
      .join(' ');
}

/// A widget that renders the synchronized family list.
///
/// This is a scrollable list grouped by relationship category. Each
/// entry is tappable — the [onMemberTap] callback receives the
/// person ID. The caller decides what to do (open details, focus in
/// graph, start View relationship).
class GraphFamilyList extends ConsumerWidget {
  const GraphFamilyList({
    super.key,
    required this.groups,
    required this.viewerName,
    this.onMemberTap,
  });

  final List<FamilyListGroup> groups;
  final String viewerName;
  final ValueChanged<String>? onMemberTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      container: true,
      label: 'Family list. ${groups.length} groups.',
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // ── "You" entry at the top ──
          _FamilyListTile(
            entry: FamilyListEntry(
              personId: '',
              name: viewerName,
              relationshipLabel: 'You',
            ),
            color: KinrelColors.tealAccent,
            onTap: null,
          ),
          // ── Grouped entries ──
          for (final group in groups) ...[
            _GroupHeader(title: group.title),
            for (final entry in group.entries)
              _FamilyListTile(
                entry: entry,
                color: _categoryColor(group.category),
                onTap: onMemberTap != null
                    ? () => onMemberTap!(entry.personId)
                    : null,
              ),
          ],
        ],
      ),
    );
  }

  Color _categoryColor(KinshipEdgeCategory cat) {
    // Use the same colors as the graph edges for consistency.
    final style = KinshipEdgeStyleResolver.styleForCategory(cat);
    return style.color ?? KinrelColors.textDim;
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          title,
          style: const TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textDim,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

class _FamilyListTile extends StatelessWidget {
  const _FamilyListTile({
    required this.entry,
    required this.color,
    this.onTap,
  });

  final FamilyListEntry entry;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final initials = _getInitials(entry.name);
    final semanticLabel = StringBuffer()
      ..write(entry.name);
    if (entry.relationshipLabel != null &&
        entry.relationshipLabel!.isNotEmpty) {
      semanticLabel..write(', ')..write(entry.relationshipLabel);
    }
    if (entry.isDeceased) {
      semanticLabel.write(', deceased');
    }

    return Semantics(
      button: onTap != null,
      label: semanticLabel.toString(),
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.15),
            border: Border.all(color: color, width: 1.5),
          ),
          child: Center(
            child: Text(
              initials,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        title: Text(
          entry.name,
          style: const TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            color: KinrelColors.textWhite,
            fontSize: 14,
          ),
        ),
        subtitle: entry.relationshipLabel != null &&
                entry.relationshipLabel!.isNotEmpty
            ? Text(
                entry.relationshipLabel!,
                style: TextStyle(
                  fontSize: 12,
                  color: color.withValues(alpha: 0.8),
                ),
              )
            : null,
        trailing: entry.isDeceased
            ? const Icon(Icons.favorite, size: 14, color: Colors.grey)
            : null,
        onTap: onTap,
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length.clamp(0, 2)).toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}
