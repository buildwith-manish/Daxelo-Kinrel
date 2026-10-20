// lib/features/circle/presentation/create_circle_sheet.dart
//
// DAXELO KINREL — Create Circle bottom sheet (Phase 2 — mockup 12)
//
// A full-height bottom sheet for creating a new account-level circle:
//   • Name field with an icon tile the user can change from a small set
//   • Selected people as removable chips
//   • Search people (name or kinship term)
//   • Quick-pick chips (+ Cousins, + Elders, + Mama's side) that
//     ONLY pre-tick checkboxes — computed from the viewer's
//     relationships using the existing RelationshipEngine via
//     kinshipTermsForFamilyProvider. The user can untick anyone.
//     Never creates anything without the user tapping Create.
//   • People grouped under family headers. Each row: avatar,
//     kinship term (bold, in the viewer's chosen kinship language)
//     plus first name (muted), checkbox. A person in several
//     families appears once (dedupe by userId). People not on
//     Kinrel are greyed out with an "Invite" action.
//   • Note shown when members span families: "Members from different
//     families will see each other's names."
//   • Footer button "Create circle · N people", disabled until a
//     name and at least one member exist. Shows loading and
//     server-error states; never loses the entered data on failure.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/kinship/kinship_term_providers.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/utils/accessibility_utils.dart';
import '../../family/presentation/providers/family_graph_provider.dart';
import '../../chat/providers/unified_inbox_provider.dart' show unifiedInboxProvider;
import '../data/circle_api_client.dart' as api;

/// Shows the create-circle bottom sheet.
Future<void> showCreateCircleSheet(
  BuildContext context, {
  required WidgetRef ref,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: KinrelColors.darkBackground,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(KinrelRadius.bottomSheet),
      ),
    ),
    builder: (_) => const _CreateCircleSheet(),
  );
}

class _CreateCircleSheet extends ConsumerStatefulWidget {
  const _CreateCircleSheet();

  @override
  ConsumerState<_CreateCircleSheet> createState() =>
      _CreateCircleSheetState();
}

class _CreateCircleSheetState extends ConsumerState<_CreateCircleSheet> {
  final _nameController = TextEditingController();
  String _selectedIconKey = 'default';
  final Set<String> _selectedUserIds = {};
  String _searchQuery = '';
  bool _isCreating = false;
  String? _errorMessage;
  List<_FamilyGroup> _peopleGroups = const [];

  @override
  void initState() {
    super.initState();
    _loadPeople();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadPeople() async {
    final familiesAsync = ref.read(familyListProvider);
    final families = familiesAsync.valueOrNull ?? [];
    if (families.isEmpty) return;

    final groups = <_FamilyGroup>[];
    final seenUserIds = <String>{};

    for (final family in families) {
      final graphAsync = ref.read(familyGraphProvider(family.id));
      final graph = graphAsync.valueOrNull;
      if (graph == null) continue;

      final termsAsync =
          ref.read(kinshipTermsForFamilyProvider(family.id));
      final terms = termsAsync.valueOrNull ??
          const <String, KinshipTerm>{};

      final people = <_PersonPick>[];
      for (final p in graph.persons) {
        if (p['isViewer'] == true) continue;

        final userId = p['linkedUserId']?.toString();
        final personId = p['id']?.toString() ?? '';
        final name = p['name']?.toString() ?? 'Unknown';
        final firstName = kinrelFirstName(name);
        final avatarUrl = p['photoUrl']?.toString() ??
            p['avatarUrl']?.toString();

        // Dedupe by linkedUserId (auth userId). A person in multiple
        // families appears once — with the kinship term from the first
        // family where the term resolves.
        if (userId != null && userId.isNotEmpty) {
          if (seenUserIds.contains(userId)) continue;
          seenUserIds.add(userId);
        }

        final term = terms[personId];
        final kinshipKey = term?.kinshipKey;

        people.add(_PersonPick(
          personId: personId,
          userId: userId,
          name: name,
          firstName: firstName,
          avatarUrl: avatarUrl,
          kinshipPrimary: term?.primary ?? firstName,
          kinshipKey: kinshipKey,
          familyId: family.id,
          familyName: family.name,
          isOnKinrel: userId != null && userId.isNotEmpty,
        ));
      }

      if (people.isNotEmpty) {
        groups.add(_FamilyGroup(
          familyId: family.id,
          familyName: family.name,
          people: people,
        ));
      }
    }

    if (mounted) {
      setState(() => _peopleGroups = groups);
    }
  }

  // ── Quick-pick chips ──────────────────────────────────────────

  void _quickPick(String pattern) {
    HapticService.tap();
    final matches = <String>{};
    for (final group in _peopleGroups) {
      for (final person in group.people) {
        if (person.kinshipKey != null &&
            person.kinshipKey!.toLowerCase().contains(pattern)) {
          if (person.isOnKinrel && person.userId != null) {
            matches.add(person.userId!);
          }
        }
      }
    }
    setState(() {
      _selectedUserIds.addAll(matches);
    });
  }

  bool _isQuickPickActive(String pattern) {
    final matches = <String>{};
    for (final group in _peopleGroups) {
      for (final person in group.people) {
        if (person.kinshipKey != null &&
            person.kinshipKey!.toLowerCase().contains(pattern)) {
          if (person.isOnKinrel && person.userId != null) {
            matches.add(person.userId!);
          }
        }
      }
    }
    return matches.isNotEmpty &&
        matches.every((id) => _selectedUserIds.contains(id));
  }

  // ── Create circle ──────────────────────────────────────────────

  Future<void> _createCircle() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _selectedUserIds.isEmpty) return;

    HapticService.tap();
    setState(() {
      _isCreating = true;
      _errorMessage = null;
    });

    try {
      await api.createCircleDirect(
        name: name,
        iconKey: _selectedIconKey,
        memberUserIds: _selectedUserIds.toList(),
      );
      if (mounted) {
        // Invalidate the inbox so the new circle appears
        ref.invalidate(unifiedInboxProvider);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCreating = false;
          _errorMessage = 'Could not create circle. Please try again.';
        });
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final hasMultipleFamilies = _peopleGroups.length > 1;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: screenHeight * 0.9,
        child: Scaffold(
          backgroundColor: KinrelColors.darkBackground,
          body: SafeArea(
            child: Column(
              children: [
                // ── Header ──────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      KinrelSpacing.base, 12, 8, 4),
                  child: Row(
                    children: [
                      const Text(
                        'New circle',
                        style: TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: KinrelColors.textWhite,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: KinrelColors.textSilver),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),

                // ── Name + icon picker ──────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: KinrelSpacing.base),
                  child: Row(
                    children: [
                      _IconTilePicker(
                        selectedKey: _selectedIconKey,
                        onSelected: (key) {
                          HapticService.selection();
                          setState(() => _selectedIconKey = key);
                        },
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _nameController,
                          style: const TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 16,
                            color: KinrelColors.textWhite,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Circle name',
                            hintStyle: const TextStyle(
                                color: KinrelColors.textDim),
                            filled: true,
                            fillColor: KinrelColors.darkElevated,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  KinrelRadius.input),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                          ),
                          onChanged: (_) =>
                              setState(() {}), // refresh footer state
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Selected people chips ──────────────────────
                if (_selectedUserIds.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 40,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                          horizontal: KinrelSpacing.base),
                      itemCount: _selectedUserIds.length,
                      itemBuilder: (ctx, index) {
                        final userId =
                            _selectedUserIds.elementAt(index);
                        final person =
                            _findPersonByUserId(userId);
                        if (person == null) return const SizedBox();
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Chip(
                            label: Text(
                              person.firstName,
                              style: const TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 12,
                                color: KinrelColors.textWhite,
                              ),
                            ),
                            backgroundColor:
                                KinrelColors.orange.withValues(alpha: 0.15),
                            side: BorderSide(
                              color:
                                  KinrelColors.orange.withValues(alpha: 0.3),
                            ),
                            deleteIcon: const Icon(Icons.close_rounded,
                                size: 16, color: KinrelColors.textSilver),
                            onDeleted: () {
                              HapticService.selection();
                              setState(() =>
                                  _selectedUserIds.remove(userId));
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],

                // ── Search bar ───────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      KinrelSpacing.base, 8, KinrelSpacing.base, 4),
                  child: TextField(
                    style: const TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      color: KinrelColors.textWhite,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search people',
                      hintStyle:
                          const TextStyle(color: KinrelColors.textDim),
                      prefixIcon: const Icon(Icons.search_rounded,
                          size: 20, color: KinrelColors.textDim),
                      filled: true,
                      fillColor: KinrelColors.darkElevated,
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(KinrelRadius.input),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      isDense: true,
                    ),
                    onChanged: (q) =>
                        setState(() => _searchQuery = q.toLowerCase()),
                  ),
                ),

                // ── Quick-pick chips ─────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: KinrelSpacing.base, vertical: 4),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _QuickPickChip(
                        label: '+ Cousins',
                        isActive: _isQuickPickActive('cousin'),
                        onTap: () => _quickPick('cousin'),
                      ),
                      _QuickPickChip(
                        label: '+ Elders',
                        isActive: _isQuickPickActive('grand'),
                        onTap: () => _quickPick('grand'),
                      ),
                      _QuickPickChip(
                        label: "+ Mama's side",
                        isActive: _isQuickPickActive('maternal'),
                        onTap: () => _quickPick('maternal'),
                      ),
                    ],
                  ),
                ),

                // ── Cross-family note ───────────────────────────
                if (hasMultipleFamilies && _selectedUserIds.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: KinrelSpacing.base, vertical: 4),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded,
                            size: 14,
                            color: KinrelColors.gold.withValues(alpha: 0.7)),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Text(
                            'Members from different families will see each other\'s names.',
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 11,
                              color: KinrelColors.textDim,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // ── People list ─────────────────────────────────
                Expanded(
                  child: _peopleGroups.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Add relatives to your family first to create a circle.',
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 14,
                                color: KinrelColors.textDim,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _peopleGroups.length,
                          itemBuilder: (ctx, groupIndex) {
                            final group = _peopleGroups[groupIndex];
                            final filteredPeople = group.people
                                .where((p) =>
                                    _searchQuery.isEmpty ||
                                    p.name
                                        .toLowerCase()
                                        .contains(_searchQuery) ||
                                    p.kinshipPrimary
                                        .toLowerCase()
                                        .contains(_searchQuery))
                                .toList();
                            if (filteredPeople.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Family header
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      KinrelSpacing.base,
                                      12,
                                      KinrelSpacing.base,
                                      4),
                                  child: Text(
                                    '${group.familyName} Family',
                                    style: const TextStyle(
                                      fontFamily: KinrelTypography.monoFont,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 1.5,
                                      color: KinrelColors.textDim,
                                    ),
                                  ),
                                ),
                                // People rows
                                for (final person in filteredPeople)
                                  _PersonRow(
                                    person: person,
                                    isSelected: person.userId != null &&
                                        _selectedUserIds
                                            .contains(person.userId),
                                    onTap: () {
                                      if (!person.isOnKinrel ||
                                          person.userId == null) {
                                        // Not on Kinrel — invite
                                        HapticService.tap();
                                        context.push(
                                          '/family-qr?familyId=${person.familyId}&familyName=${group.familyName}',
                                        );
                                        return;
                                      }
                                      HapticService.selection();
                                      setState(() {
                                        if (_selectedUserIds
                                            .contains(person.userId)) {
                                          _selectedUserIds
                                              .remove(person.userId);
                                        } else {
                                          _selectedUserIds
                                              .add(person.userId!);
                                        }
                                      });
                                    },
                                  ),
                              ],
                            );
                          },
                        ),
                ),

                // ── Error message ───────────────────────────────
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: KinrelSpacing.base, vertical: 4),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        color: KinrelColors.error,
                      ),
                    ),
                  ),

                // ── Footer CTA ───────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      KinrelSpacing.base, 8, KinrelSpacing.base, 12),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: (_nameController.text.trim().isNotEmpty &&
                              _selectedUserIds.isNotEmpty &&
                              !_isCreating)
                          ? _createCircle
                          : null,
                      icon: _isCreating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.add_rounded, size: 20),
                      label: Text(
                        _isCreating
                            ? 'Creating…'
                            : 'Create circle · ${_selectedUserIds.length} ${_selectedUserIds.length == 1 ? 'person' : 'people'}',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: KinrelColors.orange,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            KinrelColors.darkElevated,
                        disabledForegroundColor: KinrelColors.textDim,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(KinrelRadius.input),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  _PersonPick? _findPersonByUserId(String userId) {
    for (final group in _peopleGroups) {
      for (final person in group.people) {
        if (person.userId == userId) return person;
      }
    }
    return null;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Sub-widgets
// ═══════════════════════════════════════════════════════════════════════

class _IconTilePicker extends StatelessWidget {
  const _IconTilePicker({
    required this.selectedKey,
    required this.onSelected,
  });

  final String selectedKey;
  final void Function(String key) onSelected;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showIconPicker(context),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: KinrelGradients.igniteGradient,
        ),
        child: Icon(
          api.iconForCircleKey(selectedKey),
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }

  void _showIconPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Choose an icon',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: api.circleIconSet.map((icon) {
                  final isSelected = icon.key == selectedKey;
                  return GestureDetector(
                    onTap: () {
                      onSelected(icon.key);
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: isSelected
                            ? KinrelColors.orange.withValues(alpha: 0.2)
                            : KinrelColors.darkElevated,
                        border: isSelected
                            ? Border.all(color: KinrelColors.orange, width: 2)
                            : null,
                      ),
                      child: Icon(
                        icon.icon,
                        color: isSelected
                            ? KinrelColors.orange
                            : KinrelColors.textSilver,
                        size: 24,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickPickChip extends StatelessWidget {
  const _QuickPickChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? KinrelColors.orange.withValues(alpha: 0.15)
              : KinrelColors.darkElevated,
          borderRadius: BorderRadius.circular(KinrelRadius.full),
          border: isActive
              ? Border.all(
                  color: KinrelColors.orange.withValues(alpha: 0.3))
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isActive ? KinrelColors.orange : KinrelColors.textSilver,
          ),
        ),
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.person,
    required this.isSelected,
    required this.onTap,
  });

  final _PersonPick person;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: KinrelSpacing.base, vertical: 6),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KinrelColors.darkElevated,
              ),
              child: person.avatarUrl != null && person.avatarUrl!.isNotEmpty
                  ? ClipOval(
                      child: Image.network(
                        person.avatarUrl!,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _initials(),
                      ),
                    )
                  : _initials(),
            ),
            const SizedBox(width: 10),
            // Kinship term (bold) + first name (muted)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    person.kinshipPrimary,
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: person.isOnKinrel
                          ? KinrelColors.textWhite
                          : KinrelColors.textDim,
                    ),
                  ),
                  Text(
                    person.firstName,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: KinrelColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
            // Checkbox or Invite
            if (person.isOnKinrel)
              Checkbox(
                value: isSelected,
                onChanged: (_) => onTap(),
                activeColor: KinrelColors.orange,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              )
            else
              TextButton(
                onPressed: onTap,
                child: const Text(
                  'Invite',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.orange,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _initials() {
    final initials = person.name.isNotEmpty
        ? person.name
            .split(' ')
            .map((e) => e[0])
            .take(2)
            .join()
            .toUpperCase()
        : '?';
    return Center(
      child: Text(
        initials,
        style: const TextStyle(
          fontFamily: KinrelTypography.displayFont,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: KinrelColors.textSilver,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Data classes
// ═══════════════════════════════════════════════════════════════════════

class _FamilyGroup {
  const _FamilyGroup({
    required this.familyId,
    required this.familyName,
    required this.people,
  });
  final String familyId;
  final String familyName;
  final List<_PersonPick> people;
}

class _PersonPick {
  const _PersonPick({
    required this.personId,
    this.userId,
    required this.name,
    required this.firstName,
    this.avatarUrl,
    required this.kinshipPrimary,
    this.kinshipKey,
    required this.familyId,
    required this.familyName,
    required this.isOnKinrel,
  });

  final String personId;
  final String? userId; // auth userId — null if not on Kinrel
  final String name;
  final String firstName;
  final String? avatarUrl;
  final String kinshipPrimary; // kinship term (bold) or firstName fallback
  final String? kinshipKey; // raw key for quick-pick filtering
  final String familyId;
  final String familyName;
  final bool isOnKinrel;
}
