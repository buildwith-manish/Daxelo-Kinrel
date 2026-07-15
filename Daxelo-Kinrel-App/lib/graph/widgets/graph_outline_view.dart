// lib/graph/widgets/graph_outline_view.dart
//
// DAXELO KINREL — Screen-Reader Graph Overview / Outline-List View (P4.5)
//
// Per Vision §11 HP-7 + §5 Layer 3 — provides a screen-reader-navigable
// outline/list view of the graph as an alternative to the visual canvas.
// Screen-reader users can hear a summary of the graph and navigate to
// any node via a list.
//
// The outline view is toggled via a Semantics-announced button. When
// active, it renders a scrollable ListView of all persons with their
// name, relationship, and generation — each as a Semantics-annotated
// button that, when activated, focuses that node in the graph.
//
// Per WCAG 2.4.1 (Bypass Blocks): the outline view provides a way to
// skip the visual canvas entirely for screen-reader users.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/brand_colors.dart';
import '../data/graph_data_models.dart' show GraphEdgeData;

/// A screen-reader-accessible outline/list view of the graph.
///
/// Renders a scrollable ListView of all persons with:
///   - Name (with "Late" prefix for deceased)
///   - Relationship label
///   - Generation index
///   - On-this-day badge (if applicable)
///
/// Each item is a Semantics button. Activating it focuses the node in
/// the graph (calls [onNodeFocus]).
class GraphOutlineView extends ConsumerWidget {
  const GraphOutlineView({
    super.key,
    required this.persons,
    required this.relationshipLabels,
    required this.onNodeFocus,
    required this.onClose,
  });

  /// List of person data maps (same format as FlatGraphResult.persons).
  final List<Map<String, dynamic>> persons;

  /// Map of personId → relationship label (e.g., "Father", "Mother").
  final Map<String, String> relationshipLabels;

  /// Callback invoked when the user activates a node in the outline.
  /// Receives the personId.
  final void Function(String personId, String personName) onNodeFocus;

  /// Callback to close the outline view and return to the visual canvas.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      label: 'Graph outline view. ${persons.length} family members. '
          'Use up and down arrows to navigate.',
      child: Material(
        color: KinrelColors.darkBackground,
        child: Column(
          children: [
            // Header bar with title + close button.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: KinrelColors.darkElevated,
                border: Border(
                  bottom: BorderSide(color: KinrelColors.border, width: 1),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.list, color: KinrelColors.tealAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Family outline (${persons.length})',
                      style: const TextStyle(
                        color: KinrelColors.textWhite,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: KinrelColors.textWhite),
                    onPressed: onClose,
                    tooltip: 'Close outline view',
                  ),
                ],
              ),
            ),
            // Scrollable list of persons.
            Expanded(
              child: ListView.builder(
                itemCount: persons.length,
                itemBuilder: (context, index) {
                  final p = persons[index];
                  final id = p['id']?.toString() ?? '';
                  final name = (p['name'] as String?) ?? 'Unknown';
                  final isDeceased = (p['isDeceased'] as bool?) ?? false;
                  final isAnchor = (p['isAnchor'] as bool?) ?? false;
                  final genIndex =
                      (p['generationIndex'] as num?)?.toInt() ?? 0;
                  final relLabel = relationshipLabels[id] ?? '';

                  final displayName = isDeceased ? 'Late $name' : name;
                  final genLabel = _generationLabel(genIndex);

                  return Semantics(
                    label: '$displayName, $relLabel, $genLabel. '
                        '${isAnchor ? 'This is you. ' : ''}'
                        'Double-tap to focus in graph.',
                    button: true,
                    child: ListTile(
                      leading: Icon(
                        isAnchor
                            ? Icons.person_pin
                            : isDeceased
                                ? Icons.person_outline
                                : Icons.person,
                        color: isAnchor
                            ? KinrelColors.tealAccent
                            : isDeceased
                                ? KinrelColors.amber
                                : KinrelColors.textDim,
                      ),
                      title: Text(
                        displayName,
                        style: const TextStyle(
                          color: KinrelColors.textWhite,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: Text(
                        relLabel.isNotEmpty
                            ? '$relLabel · $genLabel'
                            : genLabel,
                        style: const TextStyle(
                          color: KinrelColors.textSecondaryDark,
                          fontSize: 13,
                        ),
                      ),
                      onTap: () => onNodeFocus(id, name),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _generationLabel(int genIndex) {
    if (genIndex == 0) return 'Your generation';
    if (genIndex == -1) return 'Parents\' generation';
    if (genIndex == 1) return 'Children\'s generation';
    if (genIndex == -2) return 'Grandparents\' generation';
    if (genIndex == 2) return 'Grandchildren\'s generation';
    if (genIndex < -2) return '${-genIndex} generations above';
    return '$genIndex generations below';
  }
}
