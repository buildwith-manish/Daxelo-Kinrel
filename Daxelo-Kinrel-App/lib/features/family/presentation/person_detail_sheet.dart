import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/kinship/kinship_service.dart';
import 'add_person_sheet.dart';

// ─────────────────────────────────────────────────────────────────────
// Person Detail Sheet — Hero + Stats + Tabs
//
// Hero: 120px avatar, name, kinship name, age, location
// Stats: connections, generation, kinship path
// Tabs: Info | Relations | Timeline | Notes
// Actions: Edit, Add relative, Find path, Share, Deceased, Delete
// ─────────────────────────────────────────────────────────────────────

class PersonDetailSheet extends ConsumerStatefulWidget {
  const PersonDetailSheet({
    super.key,
    required this.person,
    required this.familyId,
    this.kinshipService,
  });

  final Person person;
  final String familyId;
  final KinshipService? kinshipService;

  /// Show as a full-screen bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required Person person,
    required String familyId,
    KinshipService? kinshipService,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: KinrelColors.darkBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      builder: (_) => PersonDetailSheet(
        person: person,
        familyId: familyId,
        kinshipService: kinshipService,
      ),
    );
  }

  @override
  ConsumerState<PersonDetailSheet> createState() => _PersonDetailSheetState();
}

class _PersonDetailSheetState extends ConsumerState<PersonDetailSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  static const _tabLabels = ['Info', 'Relations', 'Timeline', 'Notes'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _tabLabels.length,
      vsync: this,
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Kinship helpers ────────────────────────────────────────────

  String? _getKinshipNameToYou() {
    final service = widget.kinshipService;
    if (service == null || !service.isLoaded) return null;

    // Try to find a relationship from this person to the anchor
    // by looking through family relationships
    final relationships = ref
        .read(familyRelationshipsProvider(widget.familyId))
        .valueOrNull;

    if (relationships == null) return null;

    // Find relationships involving this person
    for (final rel in relationships) {
      if (rel.toPersonId == widget.person.id ||
          rel.fromPersonId == widget.person.id) {
        final translation =
            service.getKinshipTerm(rel.relationshipKey, 'hindi');
        if (translation != null) {
          return translation.native;
        }
        // Fallback to English term
        final kinshipRel = service.getRelationship(rel.relationshipKey);
        if (kinshipRel != null) {
          return kinshipRel.englishTerm;
        }
      }
    }
    return null;
  }

  /// Get the kinship path to the anchor person (e.g., "Father → Brother").
  String? _getKinshipPath() {
    final service = widget.kinshipService;
    if (service == null || !service.isLoaded) return null;

    final relationships = ref
        .read(familyRelationshipsProvider(widget.familyId))
        .valueOrNull;

    if (relationships == null) return null;

    // Find direct relationships and build a simple path
    final path = <String>[];
    for (final rel in relationships) {
      if (rel.fromPersonId == widget.person.id) {
        final kinshipRel = service.getRelationship(rel.relationshipKey);
        if (kinshipRel != null) {
          path.add(kinshipRel.englishTerm);
        }
      }
    }

    if (path.isEmpty) return null;
    return path.take(3).join(' → ');
  }

  /// Count direct connections for this person.
  int _getConnectionCount() {
    final relationships = ref
        .read(familyRelationshipsProvider(widget.familyId))
        .valueOrNull;

    if (relationships == null) return 0;

    return relationships
        .where((r) =>
            (r.fromPersonId == widget.person.id ||
                r.toPersonId == widget.person.id) &&
            r.isActive)
        .length;
  }

  /// Get related members with their kinship names.
  List<({Person person, String kinship})> _getRelatedMembers() {
    final relationships = ref
        .read(familyRelationshipsProvider(widget.familyId))
        .valueOrNull;
    final members = ref
        .read(familyMembersProvider(widget.familyId))
        .valueOrNull;

    if (relationships == null || members == null) return [];

    final result = <({Person person, String kinship})>[];

    for (final rel in relationships) {
      if (!rel.isActive) continue;

      Person? relatedPerson;
      String kinshipLabel = rel.relationshipKey.snakeToTitle;

      if (rel.fromPersonId == widget.person.id) {
        // This person is the source — look for the target
        relatedPerson = members.where((m) => m.id == rel.toPersonId).firstOrNull;
      } else if (rel.toPersonId == widget.person.id) {
        // This person is the target — look for the source
        relatedPerson = members.where((m) => m.id == rel.fromPersonId).firstOrNull;
      }

      if (relatedPerson != null) {
        // Try to get native kinship term
        final service = widget.kinshipService;
        if (service != null && service.isLoaded) {
          final translation =
              service.getKinshipTerm(rel.relationshipKey, 'hindi');
          if (translation != null) {
            kinshipLabel = translation.native;
          } else {
            final kinshipRel = service.getRelationship(rel.relationshipKey);
            if (kinshipRel != null) {
              kinshipLabel = kinshipRel.englishTerm;
            }
          }
        }

        // Avoid duplicates
        if (!result.any((r) => r.person.id == relatedPerson!.id)) {
          result.add((person: relatedPerson, kinship: kinshipLabel));
        }
      }
    }

    return result;
  }

  // ── Age calculation ────────────────────────────────────────────

  String? get _ageText {
    if (widget.person.dateOfBirth == null ||
        widget.person.dateOfBirth!.isEmpty) return null;

    try {
      final dob = DateTime.parse(widget.person.dateOfBirth!);
      final now = DateTime.now();
      int age = now.year - dob.year;
      if (now.month < dob.month ||
          (now.month == dob.month && now.day < dob.day)) {
        age--;
      }
      return '$age years';
    } catch (_) {
      return null;
    }
  }

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final person = widget.person;
    final kinshipName = _getKinshipNameToYou();

    return SizedBox(
      height: screenHeight * 0.94,
      child: Padding(
        padding: EdgeInsets.only(
          left: KinrelSpacing.base,
          right: KinrelSpacing.base,
          top: KinrelSpacing.lg,
          bottom: math.max(bottomInset, KinrelSpacing.xl),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            _buildHandleBar(),
            SizedBox(height: 16),

            // Hero section
            _buildHeroSection(person, kinshipName),
            SizedBox(height: 16),

            // Stats row
            _buildStatsRow(person),
            SizedBox(height: 20),

            // Tab bar
            _buildTabBar(),
            SizedBox(height: 12),

            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildInfoTab(person),
                  _buildRelationsTab(),
                  _buildTimelineTab(),
                  _buildNotesTab(person),
                ],
              ),
            ),

            // Actions
            SizedBox(height: 12),
            _buildActions(person),
          ],
        ),
      ),
    );
  }

  // ── Handle bar ─────────────────────────────────────────────────

  Widget _buildHandleBar() {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: KinrelColors.textDim.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  // ── Hero section ───────────────────────────────────────────────

  Widget _buildHeroSection(Person person, String? kinshipName) {
    return Column(
      children: [
        // 120px Avatar with orange ring
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: person.isDeceased
                ? LinearGradient(
                    colors: [
                      KinrelColors.textDim,
                      KinrelColors.darkSurface,
                    ],
                  )
                : KinrelGradients.igniteGradient,
          ),
          child: Container(
            margin: EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: KinrelColors.darkCard,
            ),
            child: person.photoUrl != null && person.photoUrl!.isNotEmpty
                ? ClipOval(
                    child: Image.network(
                      person.photoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildInitials(person),
                    ),
                  )
                : _buildInitials(person),
          ),
        ),
        SizedBox(height: 12),

        // Name — Display Small
        Text(
          person.name,
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.4,
            color: person.isDeceased
                ? KinrelColors.textSilver
                : KinrelColors.textWhite,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 4),

        // Kinship name in orange
        if (kinshipName != null) ...[
          Text(
            'Your $kinshipName',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: KinrelColors.orange,
            ),
          ),
          SizedBox(height: 4),
        ],

        // Age / DOB
        if (_ageText != null || person.dateOfBirth != null) ...[
          Text(
            _ageText ?? person.dateOfBirth!,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              color: KinrelColors.textSilver, // #C9B4A8
            ),
          ),
          SizedBox(height: 2),
        ],

        // Location
        if (person.city != null && person.city!.isNotEmpty)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.location_on_outlined,
                  size: 14, color: KinrelColors.textDim), // #8A7A72
              SizedBox(width: 4),
              Text(
                person.city!,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  color: KinrelColors.textDim, // #8A7A72
                ),
              ),
            ],
          ),

        // Deceased badge
        if (person.isDeceased) ...[
          SizedBox(height: 6),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: KinrelColors.textDim.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud, size: 12, color: KinrelColors.textDim),
                SizedBox(width: 4),
                Text(
                  'Deceased',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 11,
                    color: KinrelColors.textDim,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildInitials(Person person) {
    return Center(
      child: Text(
        person.name.isNotEmpty ? person.name[0].toUpperCase() : '?',
        style: TextStyle(
          fontFamily: KinrelTypography.displayFont,
          fontSize: 40,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }

  // ── Stats row ──────────────────────────────────────────────────

  Widget _buildStatsRow(Person person) {
    final connections = _getConnectionCount();
    final generation = person.generationIndex;
    final kinshipPath = _getKinshipPath();

    return SizedBox(
      height: 72,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _StatCard(
            value: '$connections',
            label: 'Connections',
            icon: Icons.people_outline,
          ),
          SizedBox(width: 8),
          _StatCard(
            value: generation > 0 ? 'Gen $generation' : '—',
            label: 'Generation',
            icon: Icons.account_tree_outlined,
          ),
          if (kinshipPath != null) ...[
            SizedBox(width: 8),
            _StatCard(
              value: kinshipPath,
              label: 'Path to You',
              icon: Icons.route_outlined,
              isWide: true,
            ),
          ],
          SizedBox(width: 8),
          _StatCard(
            value: (person.gender ?? 'unknown').capitalized,
            label: 'Gender',
            icon: Icons.wc,
          ),
        ],
      ),
    );
  }

  // ── Tab bar ────────────────────────────────────────────────────

  Widget _buildTabBar() {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: KinrelColors.orange.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
          border: Border.all(
            color: KinrelColors.orange.withValues(alpha: 0.3),
          ),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorPadding: EdgeInsets.all(3),
        dividerColor: Colors.transparent,
        labelColor: KinrelColors.orange,
        unselectedLabelColor: KinrelColors.textDim,
        labelStyle: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        tabs: _tabLabels.map((l) => Tab(text: l)).toList(),
      ),
    );
  }

  // ── Info tab ───────────────────────────────────────────────────

  Widget _buildInfoTab(Person person) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Personal details card
          _InfoCard(
            title: 'Personal Details',
            icon: Icons.person_outline,
            children: [
              if (person.dateOfBirth != null &&
                  person.dateOfBirth!.isNotEmpty)
                _InfoRow(
                  icon: Icons.calendar_today_outlined,
                  label: 'Date of Birth',
                  value: person.dateOfBirth!,
                ),
              if (person.gender != null)
                _InfoRow(
                  icon: Icons.wc,
                  label: 'Gender',
                  value: person.gender!.capitalized,
                ),
              if (_ageText != null)
                _InfoRow(
                  icon: Icons.cake_outlined,
                  label: 'Age',
                  value: _ageText!,
                ),
              _InfoRow(
                icon: person.isDeceased ? Icons.cloud : Icons.favorite,
                label: 'Status',
                value: person.isDeceased ? 'Deceased' : 'Alive',
                valueColor: person.isDeceased
                    ? KinrelColors.textDim
                    : KinrelColors.success,
              ),
            ],
          ),

          SizedBox(height: 10),

          // Location card
          if (person.city != null && person.city!.isNotEmpty)
            _InfoCard(
              title: 'Location',
              icon: Icons.location_on_outlined,
              children: [
                _InfoRow(
                  icon: Icons.location_city,
                  label: 'City / Village',
                  value: person.city!,
                ),
              ],
            ),

          if (person.city != null && person.city!.isNotEmpty)
            SizedBox(height: 10),

          // Family details card
          if (person.gotra != null && person.gotra!.isNotEmpty ||
              person.occupation != null && person.occupation!.isNotEmpty)
            _InfoCard(
              title: 'Family & Occupation',
              icon: Icons.work_outline,
              children: [
                if (person.gotra != null && person.gotra!.isNotEmpty)
                  _InfoRow(
                    icon: Icons.account_balance,
                    label: 'Gotra',
                    value: person.gotra!,
                  ),
                if (person.occupation != null && person.occupation!.isNotEmpty)
                  _InfoRow(
                    icon: Icons.work_outline,
                    label: 'Occupation',
                    value: person.occupation!,
                  ),
              ],
            ),
        ],
      ),
    );
  }

  // ── Relations tab ──────────────────────────────────────────────

  Widget _buildRelationsTab() {
    final relatedMembers = _getRelatedMembers();

    if (relatedMembers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 48, color: KinrelColors.textDim),
            SizedBox(height: 12),
            Text(
              'No relationships yet',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 15,
                color: KinrelColors.textDim,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Add a relative to start building connections',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: KinrelColors.textDim,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: relatedMembers.length,
      itemBuilder: (context, index) {
        final item = relatedMembers[index];
        return _RelationTile(
          person: item.person,
          kinship: item.kinship,
          onTap: () {
            Navigator.of(context).pop();
            PersonDetailSheet.show(
              context,
              person: item.person,
              familyId: widget.familyId,
              kinshipService: widget.kinshipService,
            );
          },
        );
      },
    );
  }

  // ── Timeline tab ───────────────────────────────────────────────

  Widget _buildTimelineTab() {
    // Placeholder — timeline events not yet in data model
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.timeline, size: 48, color: KinrelColors.textDim),
          SizedBox(height: 12),
          Text(
            'Timeline coming soon',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 15,
              color: KinrelColors.textDim,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Events, photos, and milestones\nwill appear here',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              color: KinrelColors.textDim,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── Notes tab ──────────────────────────────────────────────────

  Widget _buildNotesTab(Person person) {
    if (person.notes != null && person.notes!.isNotEmpty) {
      return SingleChildScrollView(
        padding: EdgeInsets.zero,
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: KinrelColors.darkCard,
            borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
            border: Border.all(
              color: KinrelColors.textDim.withValues(alpha: 0.08),
            ),
          ),
          child: Text(
            person.notes!,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              color: KinrelColors.textSilver,
              height: 1.6,
            ),
          ),
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.note_outlined, size: 48, color: KinrelColors.textDim),
          SizedBox(height: 12),
          Text(
            'No notes yet',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 15,
              color: KinrelColors.textDim,
            ),
          ),
        ],
      ),
    );
  }

  // ── Actions ────────────────────────────────────────────────────

  Widget _buildActions(Person person) {
    return Column(
      children: [
        // Primary actions row
        Row(
          children: [
            // Edit profile
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  AddPersonSheet.show(
                    context,
                    familyId: widget.familyId,
                    existingPerson: person,
                  );
                },
                icon: Icon(Icons.edit_outlined, size: 16),
                label: Text('Edit'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: KinrelColors.orange,
                  side: BorderSide(color: KinrelColors.orange),
                  padding: EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(KinrelSpacing.radiusSm),
                  ),
                  textStyle: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            SizedBox(width: 8),

            // Add relative
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  AddPersonSheet.show(
                    context,
                    familyId: widget.familyId,
                    anchorPerson: person,
                  );
                },
                icon: Icon(Icons.person_add_outlined, size: 16),
                label: Text('Add Relative'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: KinrelColors.orange,
                  side: BorderSide(
                      color: KinrelColors.orange.withValues(alpha: 0.5)),
                  padding: EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(KinrelSpacing.radiusSm),
                  ),
                  textStyle: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            SizedBox(width: 8),

            // Find path
            SizedBox(
              height: 38,
              width: 38,
              child: IconButton(
                onPressed: () {
                  // TODO: Implement find path navigation
                  HapticFeedback.lightImpact();
                  context.showSnackBar('Find path coming soon');
                },
                icon: Icon(Icons.route_outlined, size: 18),
                color: KinrelColors.orange,
                padding: EdgeInsets.zero,
                style: IconButton.styleFrom(
                  side: BorderSide(
                      color: KinrelColors.orange.withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(KinrelSpacing.radiusSm),
                  ),
                ),
              ),
            ),
            SizedBox(width: 6),

            // Share
            SizedBox(
              height: 38,
              width: 38,
              child: IconButton(
                onPressed: () {
                  // TODO: Implement share profile
                  HapticFeedback.lightImpact();
                  context.showSnackBar('Share coming soon');
                },
                icon: Icon(Icons.share_outlined, size: 18),
                color: KinrelColors.textSilver,
                padding: EdgeInsets.zero,
                style: IconButton.styleFrom(
                  side: BorderSide(
                      color: KinrelColors.textDim.withValues(alpha: 0.3)),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(KinrelSpacing.radiusSm),
                  ),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 8),

        // Secondary actions row
        Row(
          children: [
            // Mark as deceased
            Expanded(
              child: TextButton.icon(
                onPressed: person.isDeceased
                    ? null
                    : () => _markAsDeceased(person),
                icon: Icon(Icons.cloud_outlined, size: 16),
                label: Text(
                  person.isDeceased ? 'Marked Deceased' : 'Mark Deceased',
                ),
                style: TextButton.styleFrom(
                  foregroundColor: KinrelColors.textDim,
                  padding: EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(KinrelSpacing.radiusSm),
                  ),
                  textStyle: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                  ),
                ),
              ),
            ),

            // Delete member
            Expanded(
              child: TextButton.icon(
                onPressed: () => _confirmDelete(person),
                icon: Icon(Icons.delete_outline, size: 16),
                label: Text('Delete'),
                style: TextButton.styleFrom(
                  foregroundColor: KinrelColors.error,
                  padding: EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(KinrelSpacing.radiusSm),
                  ),
                  textStyle: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Delete confirmation ────────────────────────────────────────

  void _confirmDelete(Person person) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KinrelColors.darkElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KinrelSpacing.radiusLg),
        ),
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: KinrelColors.error, size: 22),
            SizedBox(width: 10),
            Text(
              'Delete ${person.name}?',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18,
                color: KinrelColors.textWhite,
              ),
            ),
          ],
        ),
        content: Text(
          'This person will be removed from the family tree. This action cannot be undone.',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            color: KinrelColors.textSilver,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: KinrelColors.textSilver),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop(); // Close dialog
              Navigator.of(context).pop(); // Close sheet

              try {
                await deletePerson(
                  ref: ref,
                  personId: person.id,
                  familyId: widget.familyId,
                );

                if (context.mounted) {
                  context.showSnackBar('${person.name} removed');
                }
              } catch (e) {
                if (context.mounted) {
                  context.showSnackBar(
                    'Failed to delete: ${e.toString().split('\n').first}',
                    isError: true,
                  );
                }
              }
            },
            child: Text(
              'Delete',
              style: TextStyle(
                color: KinrelColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Mark as deceased ───────────────────────────────────────────

  Future<void> _markAsDeceased(Person person) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KinrelColors.darkElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KinrelSpacing.radiusLg),
        ),
        title: Text(
          'Mark ${person.name} as deceased?',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 18,
            color: KinrelColors.textWhite,
          ),
        ),
        content: Text(
          'This will update their status in the family tree.',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            color: KinrelColors.textSilver,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(color: KinrelColors.textSilver),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Mark Deceased',
              style: TextStyle(color: KinrelColors.orange),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await updatePerson(
        ref: ref,
        personId: person.id,
        familyId: widget.familyId,
        name: person.name,
        gender: person.gender,
        dateOfBirth: person.dateOfBirth,
        city: person.city,
        gotra: person.gotra,
        isDeceased: true,
      );

      if (mounted) {
        context.showSnackBar('${person.name} marked as deceased');
        Navigator.of(context).pop(); // Close sheet to refresh
      }
    } catch (e) {
      if (mounted) {
        context.showSnackBar(
          'Failed to update: ${e.toString().split('\n').first}',
          isError: true,
        );
      }
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
// SUB-WIDGETS
// ═══════════════════════════════════════════════════════════════════

/// Horizontal stat card — #191B2C background, 12px radius.
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.value,
    required this.label,
    required this.icon,
    this.isWide = false,
  });

  final String value;
  final String label;
  final IconData icon;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: isWide ? 180 : 110,
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard, // #191B2C
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: KinrelColors.textDim.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: KinrelColors.textDim),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 10,
                    color: KinrelColors.textDim,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont, // Outfit Bold
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: KinrelColors.orange, // Orange number
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}

/// Info card with icon header.
class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard, // #191B2C
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
        border: Border.all(
          color: KinrelColors.textDim.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: KinrelColors.orange),
              SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textWhite,
                ),
              ),
            ],
          ),
          if (children.isNotEmpty) ...[
            SizedBox(height: 12),
            ...children,
          ],
        ],
      ),
    );
  }
}

/// Single info row within a card.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 16, color: KinrelColors.textDim),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: KinrelColors.textDim,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: valueColor ?? KinrelColors.textWhite,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

/// Relation list tile.
class _RelationTile extends StatelessWidget {
  const _RelationTile({
    required this.person,
    required this.kinship,
    required this.onTap,
  });

  final Person person;
  final String kinship;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 6),
      child: Material(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
              border: Border.all(
                color: KinrelColors.textDim.withValues(alpha: 0.06),
              ),
            ),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: person.isDeceased
                        ? LinearGradient(
                            colors: [
                              KinrelColors.textDim,
                              KinrelColors.darkSurface,
                            ],
                          )
                        : KinrelGradients.igniteGradient,
                  ),
                  child: Center(
                    child: Text(
                      person.name.isNotEmpty
                          ? person.name[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12),

                // Name + kinship
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        person.name,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: KinrelColors.textWhite,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        kinship,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 12,
                          color: KinrelColors.orange,
                        ),
                      ),
                    ],
                  ),
                ),

                // Chevron
                Icon(Icons.chevron_right,
                    color: KinrelColors.textDim, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


