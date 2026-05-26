import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../shared/widgets/dk_components.dart';
import '../providers/member_detail_provider.dart';

// ─────────────────────────────────────────────────────────────────────
// Person Detail Screen — Full-Screen Member Profile
//
// KINREL Global Top 1 Prompt specs:
//
// Hero Section:
//   - 120px avatar with orange gradient ring
//   - Name (Display Small, Outfit Bold)
//   - Kinship name to user in orange (e.g., "Your चाचा")
//   - Age / Date of birth
//   - Location (city)
//
// Stats Row (horizontal scroll):
//   - Direct connections count
//   - Generation number
//   - Kinship path to you (e.g., "Father → Brother")
//   - Each card: #191B2C bg, 12px radius, stat in Outfit Bold, label below
//
// Tabs (4):
//   1. Info — All personal details
//   2. Relations — Connected members with kinship names
//   3. Timeline — Events/milestones with vertical orange timeline
//   4. Notes — Personal notes, add note FAB
//
// Actions (in header & bottom):
//   - Edit profile
//   - Add relative
//   - Find path
//   - Share profile
//   - Mark as deceased
//   - Delete member (with confirmation)
// ─────────────────────────────────────────────────────────────────────

class PersonDetailScreen extends ConsumerStatefulWidget {
  const PersonDetailScreen({
    super.key,
    required this.memberId,
  });

  final String memberId;

  @override
  ConsumerState<PersonDetailScreen> createState() => _PersonDetailScreenState();
}

class _PersonDetailScreenState extends ConsumerState<PersonDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedTab = 0;

  // Notes list managed locally for demo (would be in provider in production)
  final List<MemberNote> _localNotes = [];
  bool _notesInitialized = false;

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
        setState(() => _selectedTab = _tabController.index);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(memberDetailProvider(widget.memberId));

    return Scaffold(
      backgroundColor: KinrelColors.darkSurface, // #13141E
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(),
      body: detailAsync.when(
        loading: () => _buildLoading(),
        error: (err, _) => _buildError(err),
        data: (detail) => _buildContent(detail),
      ),
      floatingActionButton: _selectedTab == 3
          ? _buildAddNoteFAB()
          : null,
    );
  }

  // ── App Bar ────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: KinrelColors.darkCard.withValues(alpha: 0.7),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.arrow_back_ios_new,
            size: 16,
            color: KinrelColors.textWhite,
          ),
        ),
        onPressed: () => context.pop(),
      ),
      actions: [
        _ActionIconButton(
          icon: Icons.edit_outlined,
          tooltip: 'Edit Profile',
          onTap: () {
            HapticFeedback.lightImpact();
            _showSnackBar('Edit profile coming soon');
          },
        ),
        _ActionIconButton(
          icon: Icons.person_add_outlined,
          tooltip: 'Add Relative',
          onTap: () {
            HapticFeedback.lightImpact();
            _showSnackBar('Add relative coming soon');
          },
        ),
        _ActionIconButton(
          icon: Icons.route_outlined,
          tooltip: 'Find Path',
          onTap: () {
            HapticFeedback.lightImpact();
            _showSnackBar('Find path coming soon');
          },
        ),
        PopupMenuButton<String>(
          icon: Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: KinrelColors.darkCard.withValues(alpha: 0.7),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.more_vert,
              size: 18,
              color: KinrelColors.textWhite,
            ),
          ),
          color: KinrelColors.darkElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KinrelRadius.lg),
          ),
          offset: Offset(0, 40),
          onSelected: (value) => _handleMenuAction(value),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'share',
              child: Row(
                children: [
                  Icon(Icons.share_outlined, size: 18, color: KinrelColors.textSilver),
                  SizedBox(width: 10),
                  Text('Share Profile', style: TextStyle(color: KinrelColors.textWhite)),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'deceased',
              child: Row(
                children: [
                  Icon(Icons.cloud_outlined, size: 18, color: KinrelColors.textSilver),
                  SizedBox(width: 10),
                  Text('Mark as Deceased', style: TextStyle(color: KinrelColors.textSilver)),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_outline, size: 18, color: KinrelColors.error),
                  SizedBox(width: 10),
                  Text('Delete Member', style: TextStyle(color: KinrelColors.error)),
                ],
              ),
            ),
          ],
        ),
        SizedBox(width: 4),
      ],
    );
  }

  // ── Loading State ──────────────────────────────────────────────

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(KinrelColors.orange),
            ),
          ),
          SizedBox(height: 16),
          Text(
            'Loading member details...',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              color: KinrelColors.textSilver,
            ),
          ),
        ],
      ),
    );
  }

  // ── Error State ────────────────────────────────────────────────

  Widget _buildError(Object err) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(KinrelSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: KinrelColors.error),
            SizedBox(height: 16),
            Text(
              'Failed to load member',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
            SizedBox(height: 8),
            Text(
              err.toString(),
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: KinrelColors.textSilver,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 20),
            DKButton(
              label: 'Retry',
              variant: DKButtonVariant.primary,
              size: DKButtonSize.sm,
              onPressed: () {
                ref.invalidate(memberDetailProvider(widget.memberId));
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Main Content ───────────────────────────────────────────────

  Widget _buildContent(MemberDetailModel detail) {
    // Initialize local notes from provider data (once)
    if (!_notesInitialized && detail.notes.isNotEmpty) {
      _localNotes.addAll(detail.notes);
      _notesInitialized = true;
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top padding for AppBar
          SizedBox(height: MediaQuery.of(context).padding.top + 56),

          // Hero Section
          _buildHeroSection(detail),
          SizedBox(height: 20),

          // Stats Row
          _buildStatsRow(detail),
          SizedBox(height: 20),

          // Tab Bar
          _buildTabBar(),
          SizedBox(height: 12),

          // Tab Content
          _buildTabContent(detail),

          SizedBox(height: 100), // Bottom padding for FAB
        ],
      ),
    );
  }

  // ── Hero Section ───────────────────────────────────────────────

  Widget _buildHeroSection(MemberDetailModel detail) {
    return Column(
      children: [
        // 120px Avatar with orange gradient ring
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: detail.isDeceased
                ? LinearGradient(
                    colors: [
                      KinrelColors.textDim,
                      KinrelColors.darkSurface,
                    ],
                  )
                : KinrelGradients.igniteGradient, // Orange ring
          ),
          child: Container(
            margin: EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: KinrelColors.darkCard,
            ),
            child: detail.photoUrl != null && detail.photoUrl!.isNotEmpty
                ? ClipOval(
                    child: Image.network(
                      detail.photoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          _buildAvatarInitials(detail),
                    ),
                  )
                : _buildAvatarInitials(detail),
          ),
        ),
        SizedBox(height: 14),

        // Name — Display Small, Outfit Bold
        Text(
          detail.name,
          style: KinrelTypography.displaySmall.copyWith(
            color: detail.isDeceased
                ? KinrelColors.textSilver
                : KinrelColors.textWhite,
          ),
          textAlign: TextAlign.center,
        ),

        // Nickname
        if (detail.nickname != null && detail.nickname!.isNotEmpty) ...[
          SizedBox(height: 4),
          Text(
            '"${detail.nickname}"',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontStyle: FontStyle.italic,
              color: KinrelColors.textDim,
            ),
          ),
        ],
        SizedBox(height: 6),

        // Kinship name to user in orange
        if (detail.kinshipNameToUser != null) ...[
          Container(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              gradient: KinrelGradients.igniteGradient,
              borderRadius: BorderRadius.circular(KinrelRadius.full),
            ),
            child: Text(
              'Your ${detail.kinshipNameToUser}',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                letterSpacing: 0.3,
              ),
            ),
          ),
          SizedBox(height: 8),
        ],

        // Age / Date of birth
        if (detail.age != null || detail.dateOfBirth != null) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cake_outlined, size: 14, color: KinrelColors.textSilver),
              SizedBox(width: 6),
              Text(
                detail.age != null
                    ? '${detail.age} years old'
                    : detail.dateOfBirth ?? '',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  color: KinrelColors.textSilver,
                ),
              ),
            ],
          ),
          SizedBox(height: 4),
        ],

        // Location (city)
        if (detail.currentCity != null && detail.currentCity!.isNotEmpty)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.location_on_outlined,
                  size: 14, color: KinrelColors.textDim),
              SizedBox(width: 4),
              Text(
                detail.currentCity!,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  color: KinrelColors.textDim,
                ),
              ),
            ],
          ),

        // Deceased badge
        if (detail.isDeceased) ...[
          SizedBox(height: 8),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: KinrelColors.textDim.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(KinrelRadius.full),
              border: Border.all(
                color: KinrelColors.textDim.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_outlined, size: 14, color: KinrelColors.textDim),
                SizedBox(width: 6),
                Text(
                  'Deceased',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
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

  Widget _buildAvatarInitials(MemberDetailModel detail) {
    final initials = detail.name
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    return Center(
      child: Text(
        initials,
        style: TextStyle(
          fontFamily: KinrelTypography.displayFont,
          fontSize: 36,
          fontWeight: FontWeight.w700,
          color: KinrelColors.orange,
          height: 1,
        ),
      ),
    );
  }

  // ── Stats Row ──────────────────────────────────────────────────

  Widget _buildStatsRow(MemberDetailModel detail) {
    return SizedBox(
      height: 76,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
        children: [
          _StatCard(
            value: '${detail.directConnectionsCount}',
            label: 'Connections',
            icon: Icons.people_outline,
          ),
          SizedBox(width: 8),
          _StatCard(
            value: detail.generationNumber > 0
                ? 'Gen ${detail.generationNumber}'
                : '—',
            label: 'Generation',
            icon: Icons.account_tree_outlined,
          ),
          SizedBox(width: 8),
          if (detail.kinshipPathToUser != null)
            _StatCard(
              value: detail.kinshipPathToUser!,
              label: 'Path to You',
              icon: Icons.route_outlined,
              isWide: true,
            ),
          if (detail.kinshipPathToUser != null) SizedBox(width: 8),
          _StatCard(
            value: detail.gender ?? '—',
            label: 'Gender',
            icon: Icons.wc,
          ),
        ],
      ),
    );
  }

  // ── Tab Bar ────────────────────────────────────────────────────

  Widget _buildTabBar() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      height: 40,
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          gradient: KinrelGradients.igniteGradient,
          borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorPadding: EdgeInsets.all(3),
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
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

  // ── Tab Content ────────────────────────────────────────────────

  Widget _buildTabContent(MemberDetailModel detail) {
    switch (_selectedTab) {
      case 0:
        return _buildInfoTab(detail);
      case 1:
        return _buildRelationsTab(detail);
      case 2:
        return _buildTimelineTab(detail);
      case 3:
        return _buildNotesTab(detail);
      default:
        return _buildInfoTab(detail);
    }
  }

  // ── 1. Info Tab ────────────────────────────────────────────────

  Widget _buildInfoTab(MemberDetailModel detail) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: Column(
        children: [
          // Personal Details Card
          _InfoCard(
            title: 'Personal Details',
            icon: Icons.person_outline,
            children: [
              if (detail.name != 'Family Member')
                _InfoRow(
                  icon: Icons.badge_outlined,
                  label: 'Full Name',
                  value: detail.name,
                ),
              if (detail.nickname != null && detail.nickname!.isNotEmpty)
                _InfoRow(
                  icon: Icons.emoji_emotions_outlined,
                  label: 'Nickname',
                  value: detail.nickname!,
                ),
              if (detail.gender != null)
                _InfoRow(
                  icon: Icons.wc,
                  label: 'Gender',
                  value: detail.gender!,
                ),
              if (detail.dateOfBirth != null && detail.dateOfBirth!.isNotEmpty)
                _InfoRow(
                  icon: Icons.calendar_today_outlined,
                  label: 'Date of Birth',
                  value: detail.dateOfBirth!,
                ),
              if (detail.age != null)
                _InfoRow(
                  icon: Icons.cake_outlined,
                  label: 'Age',
                  value: '${detail.age} years',
                ),
              _InfoRow(
                icon: detail.isDeceased ? Icons.cloud_outlined : Icons.favorite,
                label: 'Status',
                value: detail.isDeceased ? 'Deceased' : 'Alive',
                valueColor: detail.isDeceased
                    ? KinrelColors.textDim
                    : KinrelColors.success,
              ),
            ],
          ),

          SizedBox(height: 10),

          // Location Card
          if (detail.birthplace != null ||
              detail.currentCity != null)
            _InfoCard(
              title: 'Location',
              icon: Icons.location_on_outlined,
              children: [
                if (detail.birthplace != null && detail.birthplace!.isNotEmpty)
                  _InfoRow(
                    icon: Icons.home_outlined,
                    label: 'Birthplace',
                    value: detail.birthplace!,
                  ),
                if (detail.currentCity != null &&
                    detail.currentCity!.isNotEmpty)
                  _InfoRow(
                    icon: Icons.location_city,
                    label: 'Current City',
                    value: detail.currentCity!,
                  ),
              ],
            ),

          if (detail.birthplace != null || detail.currentCity != null)
            SizedBox(height: 10),

          // Contact & Occupation Card
          if (detail.phone != null ||
              detail.email != null ||
              detail.occupation != null)
            _InfoCard(
              title: 'Contact & Work',
              icon: Icons.work_outline,
              children: [
                if (detail.phone != null && detail.phone!.isNotEmpty)
                  _InfoRow(
                    icon: Icons.phone_outlined,
                    label: 'Phone',
                    value: detail.phone!,
                  ),
                if (detail.email != null && detail.email!.isNotEmpty)
                  _InfoRow(
                    icon: Icons.email_outlined,
                    label: 'Email',
                    value: detail.email!,
                  ),
                if (detail.occupation != null &&
                    detail.occupation!.isNotEmpty)
                  _InfoRow(
                    icon: Icons.work_outline,
                    label: 'Occupation',
                    value: detail.occupation!,
                  ),
              ],
            ),

          if (detail.phone != null ||
              detail.email != null ||
              detail.occupation != null)
            SizedBox(height: 10),

          // Bio Card
          if (detail.bio != null && detail.bio!.isNotEmpty)
            _InfoCard(
              title: 'About',
              icon: Icons.info_outline,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    detail.bio!,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      color: KinrelColors.textSilver,
                      height: 1.6,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ── 2. Relations Tab ───────────────────────────────────────────

  Widget _buildRelationsTab(MemberDetailModel detail) {
    if (detail.relations.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(KinrelSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.people_outline, size: 56, color: KinrelColors.textDim),
              SizedBox(height: 16),
              Text(
                'No relationships yet',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textSilver,
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
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: Column(
        children: detail.relations.map((relation) {
          return _RelationTile(
            relation: relation,
            onTap: () {
              // Navigate to that member's detail screen
              HapticFeedback.lightImpact();
              context.push('/member/${relation.memberId}');
            },
          );
        }).toList(),
      ),
    );
  }

  // ── 3. Timeline Tab ────────────────────────────────────────────

  Widget _buildTimelineTab(MemberDetailModel detail) {
    if (detail.timelineEvents.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(KinrelSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.timeline, size: 56, color: KinrelColors.textDim),
              SizedBox(height: 16),
              Text(
                'No timeline events',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textSilver,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Events and milestones will appear here',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  color: KinrelColors.textDim,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: Column(
        children: _buildTimelineItems(detail.timelineEvents),
      ),
    );
  }

  List<Widget> _buildTimelineItems(List<TimelineEvent> events) {
    final sorted = List<TimelineEvent>.from(events)
      ..sort((a, b) => a.date.compareTo(b.date));

    return sorted.asMap().entries.map((entry) {
      final index = entry.key;
      final event = entry.value;
      final isLast = index == sorted.length - 1;

      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Timeline line & dot
            SizedBox(
              width: 40,
              child: Column(
                children: [
                  // Orange dot
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: KinrelGradients.igniteGradient,
                      boxShadow: [
                        BoxShadow(
                          color: KinrelColors.orange.withValues(alpha: 0.4),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: KinrelColors.darkSurface,
                        ),
                      ),
                    ),
                  ),
                  // Vertical orange line
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2,
                        decoration: BoxDecoration(
                          gradient: KinrelGradients.timelineGradient,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(width: 12),

            // Event card
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
                child: Container(
                  padding: EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: KinrelColors.darkCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _getEventBorderColor(event.eventType)
                          .withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Date & type badge
                      Row(
                        children: [
                          // Event type badge
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _getEventBorderColor(event.eventType)
                                  .withValues(alpha: 0.15),
                              borderRadius:
                                  BorderRadius.circular(KinrelRadius.full),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _getEventIcon(event.eventType),
                                  size: 12,
                                  color: _getEventBorderColor(
                                      event.eventType),
                                ),
                                SizedBox(width: 4),
                                Text(
                                  _getEventTypeLabel(event.eventType),
                                  style: TextStyle(
                                    fontFamily: KinrelTypography.monoFont,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w500,
                                    color: _getEventBorderColor(
                                        event.eventType),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Spacer(),
                          Text(
                            _formatDate(event.date),
                            style: TextStyle(
                              fontFamily: KinrelTypography.monoFont,
                              fontSize: 10,
                              color: KinrelColors.textDim,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),

                      // Title
                      Text(
                        event.title,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: KinrelColors.textWhite,
                          height: 1.3,
                        ),
                      ),

                      // Description
                      if (event.description != null &&
                          event.description!.isNotEmpty) ...[
                        SizedBox(height: 6),
                        Text(
                          event.description!,
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 13,
                            color: KinrelColors.textSilver,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  // ── 4. Notes Tab ───────────────────────────────────────────────

  Widget _buildNotesTab(MemberDetailModel detail) {
    final notes = _localNotes;

    if (notes.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(KinrelSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.note_outlined, size: 56, color: KinrelColors.textDim),
              SizedBox(height: 16),
              Text(
                'No notes yet',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textSilver,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Tap the + button to add a note',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  color: KinrelColors.textDim,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: Column(
        children: notes.map((note) {
          return Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Container(
              padding: EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: KinrelColors.darkCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: KinrelColors.orange.withValues(alpha: 0.08),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note.content,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      color: KinrelColors.textSilver,
                      height: 1.6,
                    ),
                  ),
                  SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.person_outline,
                          size: 12, color: KinrelColors.textDim),
                      SizedBox(width: 4),
                      Text(
                        note.author,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 11,
                          color: KinrelColors.textDim,
                        ),
                      ),
                      Spacer(),
                      Text(
                        _formatDate(note.createdAt),
                        style: TextStyle(
                          fontFamily: KinrelTypography.monoFont,
                          fontSize: 10,
                          color: KinrelColors.textDim,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Add Note FAB ───────────────────────────────────────────────

  Widget _buildAddNoteFAB() {
    return Container(
      decoration: BoxDecoration(
        gradient: KinrelGradients.igniteGradient,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: KinrelColors.orange.withValues(alpha: 0.4),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
      child: FloatingActionButton(
        onPressed: _showAddNoteDialog,
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Icon(Icons.add, size: 28, color: Colors.white),
      ),
    );
  }

  void _showAddNoteDialog() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KinrelColors.darkElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
        ),
        title: Row(
          children: [
            Icon(Icons.note_add_outlined, color: KinrelColors.orange, size: 22),
            SizedBox(width: 10),
            Text(
              'Add Note',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18,
                color: KinrelColors.textWhite,
              ),
            ),
          ],
        ),
        content: TextField(
          controller: controller,
          maxLines: 4,
          autofocus: true,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 14,
            color: KinrelColors.textWhite,
          ),
          decoration: InputDecoration(
            hintText: 'Write a note about this person...',
            hintStyle: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              color: KinrelColors.textDim,
            ),
            filled: true,
            fillColor: KinrelColors.darkCard,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(KinrelRadius.md),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(KinrelRadius.md),
              borderSide:
                  BorderSide(color: KinrelColors.orange, width: 1.5),
            ),
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
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                setState(() {
                  _localNotes.insert(
                    0,
                    MemberNote(
                      id: 'note_${DateTime.now().millisecondsSinceEpoch}',
                      content: controller.text.trim(),
                      createdAt: DateTime.now()
                          .toIso8601String()
                          .substring(0, 10),
                      author: 'You',
                    ),
                  );
                });
              }
              Navigator.of(ctx).pop();
            },
            child: Text(
              'Add',
              style: TextStyle(
                color: KinrelColors.orange,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Menu Actions ───────────────────────────────────────────────

  void _handleMenuAction(String action) {
    switch (action) {
      case 'share':
        HapticFeedback.lightImpact();
        _showSnackBar('Share profile coming soon');
        break;
      case 'deceased':
        _confirmMarkDeceased();
        break;
      case 'delete':
        _confirmDelete();
        break;
    }
  }

  void _confirmMarkDeceased() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KinrelColors.darkElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
        ),
        title: Text(
          'Mark as Deceased?',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 18,
            color: KinrelColors.textWhite,
          ),
        ),
        content: Text(
          'This will update their status in the family tree. You can always change this later.',
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
            onPressed: () {
              Navigator.of(ctx).pop();
              _showSnackBar('Member marked as deceased');
            },
            child: Text(
              'Mark Deceased',
              style: TextStyle(
                color: KinrelColors.orange,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KinrelColors.darkElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
        ),
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: KinrelColors.error, size: 24),
            SizedBox(width: 10),
            Text(
              'Delete Member?',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18,
                color: KinrelColors.textWhite,
              ),
            ),
          ],
        ),
        content: Text(
          'This person will be permanently removed from the family tree. All their relationships will also be deleted. This action cannot be undone.',
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
            onPressed: () {
              Navigator.of(ctx).pop();
              _showSnackBar('Member deleted');
              context.pop();
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

  // ── Helpers ────────────────────────────────────────────────────

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: KinrelColors.darkCard,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.md),
        ),
      ),
    );
  }

  Color _getEventBorderColor(TimelineEventType type) {
    switch (type) {
      case TimelineEventType.birth:
        return KinrelColors.success;
      case TimelineEventType.marriage:
        return KinrelColors.amber;
      case TimelineEventType.education:
        return KinrelColors.info;
      case TimelineEventType.career:
        return KinrelColors.gold;
      case TimelineEventType.milestone:
        return KinrelColors.orange;
      case TimelineEventType.travel:
        return Color(0xFF60A5FA);
      case TimelineEventType.family:
        return Color(0xFF4ADE80);
      case TimelineEventType.memorial:
        return KinrelColors.textDim;
    }
  }

  IconData _getEventIcon(TimelineEventType type) {
    switch (type) {
      case TimelineEventType.birth:
        return Icons.child_care;
      case TimelineEventType.marriage:
        return Icons.favorite;
      case TimelineEventType.education:
        return Icons.school;
      case TimelineEventType.career:
        return Icons.work;
      case TimelineEventType.milestone:
        return Icons.star;
      case TimelineEventType.travel:
        return Icons.flight;
      case TimelineEventType.family:
        return Icons.family_restroom;
      case TimelineEventType.memorial:
        return Icons.cloud;
    }
  }

  String _getEventTypeLabel(TimelineEventType type) {
    switch (type) {
      case TimelineEventType.birth:
        return 'BIRTH';
      case TimelineEventType.marriage:
        return 'MARRIAGE';
      case TimelineEventType.education:
        return 'EDUCATION';
      case TimelineEventType.career:
        return 'CAREER';
      case TimelineEventType.milestone:
        return 'MILESTONE';
      case TimelineEventType.travel:
        return 'TRAVEL';
      case TimelineEventType.family:
        return 'FAMILY';
      case TimelineEventType.memorial:
        return 'MEMORIAL';
    }
  }

  String _formatDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      final months = [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${dt.day} ${months[dt.month]} ${dt.year}';
    } catch (_) {
      return isoDate;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SUB-WIDGETS
// ═══════════════════════════════════════════════════════════════════════

/// Action icon button used in the AppBar.
class _ActionIconButton extends StatelessWidget {
  const _ActionIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard.withValues(alpha: 0.7),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 16, color: KinrelColors.textWhite),
      ),
      tooltip: tooltip,
      onPressed: onTap,
    );
  }
}

/// Horizontal stat card — #191B2C background, 12px radius.
/// Stat number in Outfit Bold (orange), label below.
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
              color: KinrelColors.orange,
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
      padding: EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: KinrelColors.textDim),
          SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              color: KinrelColors.textSilver,
            ),
          ),
          Spacer(),
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
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Relation tile with avatar, name, and kinship.
class _RelationTile extends StatelessWidget {
  const _RelationTile({
    required this.relation,
    required this.onTap,
  });

  final MemberRelation relation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: KinrelColors.darkCard,
              borderRadius: BorderRadius.circular(KinrelRadius.md),
              border: Border.all(
                color: KinrelColors.textDim.withValues(alpha: 0.06),
              ),
            ),
            child: Row(
              children: [
                // Avatar
                DKAvatar(
                  initials: relation.name
                      .split(' ')
                      .where((w) => w.isNotEmpty)
                      .take(2)
                      .map((w) => w[0].toUpperCase())
                      .join(),
                  size: DKAvatarSize.md,
                  borderColor: KinrelColors.orange.withValues(alpha: 0.4),
                ),
                SizedBox(width: 12),

                // Name & kinship
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        relation.name,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: KinrelColors.textWhite,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (relation.kinshipName != null) ...[
                        SizedBox(height: 2),
                        Text(
                          relation.kinshipName!,
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 12,
                            color: KinrelColors.orange,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Arrow
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: KinrelColors.textDim,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
