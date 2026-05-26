import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/graph/graph_service.dart';
import '../../../core/graph/graph_provider.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/family/family_provider.dart';

class PathFinderScreen extends ConsumerStatefulWidget {
  PathFinderScreen({super.key, required this.familyId});

  final String familyId;


  @override
  ConsumerState<PathFinderScreen> createState() => _PathFinderScreenState();
}

class _PathFinderScreenState extends ConsumerState<PathFinderScreen> {
  String? _fromPersonId;
  String? _toPersonId;
  PathResult? _pathResult;
  bool _isSearching = false;

  void _findPath() {
    if (_fromPersonId == null || _toPersonId == null) return;

    setState(() => _isSearching = true);

    // Use real data from providers
    final membersAsync = ref.read(familyMembersProvider(widget.familyId));
    final relsAsync =
        ref.read(familyRelationshipsProvider(widget.familyId));

    membersAsync.whenData((members) {
      relsAsync.whenData((relationships) {
        final graphService = ref.read(graphServiceProvider);

        final persons = members
            .where((p) => p.deletedAt == null)
            .map((p) => p.toGraphPerson())
            .toList();

        final edges = relationships.map((r) => r.toGraphEdge()).toList();

        final result = graphService.findPath(
          persons: persons,
          relationships: edges,
          fromPersonId: _fromPersonId!,
          toPersonId: _toPersonId!,
          locale: 'hi',
        );

        if (mounted) {
          setState(() {
            _isSearching = false;
            _pathResult = result;
          });
        }
      });
    });

    // Fallback timeout
    Future.delayed(Duration(seconds: 2), () {
      if (mounted && _isSearching) {
        setState(() => _isSearching = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(familyMembersProvider(widget.familyId));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Find Path',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: membersAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: KinrelColors.purple),
        ),error: (e, _) => Center(
          child: Text(
            'Failed to load members',
            style: TextStyle(color: KinrelColors.textDim),
          ),
        ),
        data: (members) {
          if (members.isEmpty) {
            return _EmptyState();
          }
          return _buildContent(members);
        },
      ),
    );
  }

  Widget _buildContent(List<Person> members) {
    final personMap = {for (final p in members) p.id: p};

    return SingleChildScrollView(
      padding: EdgeInsets.all(KinrelSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Person A selector
          _PersonSelector(
            label: 'From',
            members: members,
            selectedId: _fromPersonId,
            onChanged: (id) => setState(() {
              _fromPersonId = id;
              _pathResult = null;
            }),
          ),

          const SizedBox(height: 12),

          // Swap button
          Center(
            child: IconButton(
              onPressed: () {
                setState(() {
                  final temp = _fromPersonId;
                  _fromPersonId = _toPersonId;
                  _toPersonId = temp;
                  _pathResult = null;
                });
              },const icon: Icon(Icons.swap_vert, color: KinrelColors.purple),
            ),
          ),

          SizedBox(height: 12),

          // Person B selector
          _PersonSelector(
            label: 'To',
            members: members,
            selectedId: _toPersonId,
            onChanged: (id) => setState(() {
              _toPersonId = id;
              _pathResult = null;
            }),
          ),

          const SizedBox(height: 24),

          // Find button
          FilledButton(
            onPressed: _fromPersonId != null &&
                    _toPersonId != null &&
                    !_isSearching
                ? _findPath
                : null,
            style: FilledButton.styleFrom(
              backgroundColor: KinrelColors.purple,
              foregroundColor: Colors.white,
              disabledBackgroundColor:
                  KinrelColors.purple.withValues(alpha: 0.4),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(KinrelSpacing.radiusSm),
              ),
            ),
            child: _isSearching
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    'Find Relationship Path',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),

          const SizedBox(height: 24),

          // Result
          if (_pathResult != null) ...[
            _PathResultCard(
              result: _pathResult!,
              personMap: personMap,
            ),
          ] else if (_fromPersonId != null &&
              _toPersonId != null &&
              !_isSearching) ...[
            Container(
              padding: const EdgeInsets.all(KinrelSpacing.base),
              decoration: BoxDecoration(
                color: KinrelColors.darkCard,
                borderRadius:
                    BorderRadius.circular(KinrelSpacing.radiusMd),
              ),child: Column(
                children: [
                  Text(
                    'Tap "Find Relationship Path" to discover how these family members are connected.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      color: KinrelColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KinrelSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.route,
              size: 64,
              color: KinrelColors.textDim.withValues(alpha: 0.3),
            ),
            SizedBox(height: 20),
            Text(
              'No Members Yet',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Add family members first to find relationship paths.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: KinrelColors.textSilver,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonSelector extends StatelessWidget {
  const _PersonSelector({
    required this.label,
    required this.members,
    required this.selectedId,
    required this.onChanged,
  });

  final String label;
  final List<Person> members;
  final String? selectedId;
  final ValueChanged<String?> onChanged;


  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(const label,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: KinrelColors.textSilver,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: KinrelColors.darkElevated,
            borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
            border: Border.all(
                color: KinrelColors.darkSurface.withValues(alpha: 0.3)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selectedId,
              hint: Text(
                'Select person',
                style: TextStyle(color: KinrelColors.textDim),
              ),isExpanded: true,
              icon: Icon(Icons.arrow_drop_down, color: KinrelColors.purple),
              dropdownColor: KinrelColors.darkElevated,
              items: members.map((p) {
                final subtitle = p.gender != null
                    ? ' (${p.gender!.toUpperCase()})'
                    : '';
                return DropdownMenuItem(
                  value: p.id,
                  child: Text(
                    '${p.name}$subtitle',
                    style: TextStyle(color: KinrelColors.textWhite),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _PathResultCard extends StatelessWidget {
  const _PathResultCard({
    required this.result,
    required this.personMap,
  });

  final PathResult result;
  final Map<String, Person> personMap;


  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(KinrelSpacing.base),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            KinrelColors.purple.withValues(alpha: 0.1),
            KinrelColors.amber.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
        border: Border.all(
            color: KinrelColors.purple.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            result.path.isEmpty
                ? 'Same Person'
                : 'Path Found (${result.length} step${result.length != 1 ? 's' : ''})',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: KinrelColors.purple,
            ),
          ),
          const SizedBox(height: 12),

          // Path steps
          ...result.path.map((step) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: KinrelColors.darkElevated,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${result.path.indexOf(step) + 1}',
                          style: TextStyle(
                            fontFamily: KinrelTypography.displayFont,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: KinrelColors.purple,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [const Text(
                            step.personName,
                            style: TextStyle(
                              fontFamily: KinrelTypography.displayFont,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: KinrelColors.textWhite,
                            ),
                          ),const Text(
                            step.type.snakeToTitle,
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 12,
                              color: KinrelColors.textSilver,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 12),

          // Relationship description
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: KinrelColors.darkElevated.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
            ),
            child: Column(
              children: [
                Text(const result.relationshipDescription,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 13,
                    color: KinrelColors.textSilver,
                  ),
                ),
                if (result.localizedDescription != null) ...[
                  const SizedBox(height: 6),
                  Text(const result.localizedDescription!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: KinrelColors.gold,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
