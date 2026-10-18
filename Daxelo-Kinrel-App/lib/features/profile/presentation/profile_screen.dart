// lib/features/profile/presentation/profile_screen.dart
//
// DAXELO KINREL — Me screen (full rewrite per Settings-Refactor spec).
//
// The Me tab now shows:
//   1. Header row: "Me" title + a gear icon that opens /profile/settings
//   2. Identity block: avatar, name, @username · N-day streak, bio
//   3. Stats card: 3 equal columns (Family trees / Members added / Relations)
//   4. "Needs you" section (hidden when empty): pending invitations,
//      claim-your-profile reminder
//   5. "Quick switches" section: Theme / Quiet / Location / Language
//   6. "My families" section: up to 2 family cards + See all
//
// All settings rows have moved to the Settings hub (gear icon →
// /profile/settings) and the Settings category screens. Sign out is
// on the hub. Delete account is in Account & security.
//
// Loading state: ProfileSkeleton while profile loads. Stats show '–'
// on failure. Needs you + My families sections hide gracefully on
// empty/error.
//
// See settings/* for the extracted widgets, providers, and actions.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/streak_service.dart';
import '../../../core/theme/theme_provider.dart'
    show themeModeProvider;
import '../../../core/family/family_provider.dart';
import '../../../core/family/family_id_provider.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../../shared/widgets/kinrel_skeleton.dart';
import '../../../presentation/widgets/skeletons/profile_skeleton.dart';
import '../../social/presentation/widgets/sparq_ring_avatar.dart';
import '../../../core/services/image_cache_manager.dart';
import '../../../graph/widgets/engine/viewer_linked_provider.dart';
import '../data/profile_provider.dart';
import 'settings/settings_actions.dart';
import 'settings/settings_providers.dart';

// ── Design Tokens (theme-aware) ──────────────────────────────────────
// Orange is identical in light + dark; other colors come from DKColors.
const Color _orange = Color(0xFFE8612A);
const Color _amber = Color(0xFFF59240);

class ProfileScreen extends ConsumerStatefulWidget {
  ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen>
    with AutomaticKeepAliveClientMixin {
  bool _isUploadingAvatar = false;
  int _streak = 0;
  bool _streakLoaded = false;

  // ── Theme-aware color getters (replace hardcoded dark consts) ──────
  Color get _bg => DKColors.background(context);
  Color get _cardBg => DKColors.cardColor(context);
  Color get _textPrimary => DKColors.textPrimary(context);
  Color get _textDim => DKColors.isLight(context)
      ? const Color(0xFF6B7280)
      : const Color(0xFF8A7A72);
  Color get _borderSubtle => DKColors.borderColor(context);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // ✅ FIX (BUG-05): Defer provider modification until after first frame
    // to avoid "Tried to modify a provider while the widget tree was building"
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadInitialData();
        _loadStreak();
        // Bootstrap settings toggles once on screen entry (replaces the
        // per-rebuild _loadBiometricState / _loadNotificationToggleStates
        // calls in the old ProfileScreen).
        ref.read(settingsBootstrapProvider.future).catchError((_) {});
      }
    });
  }

  Future<void> _loadInitialData() async {
    // Load profile & stats (fire-and-forget, provider handles state)
    unawaited(
      ref.read(profileProvider.notifier).loadProfile().catchError((_) {}),
    );
    unawaited(
      ref.read(profileProvider.notifier).loadStats().catchError((_) {}),
    );
    unawaited(
      ref.read(profileProvider.notifier).loadInvitations().catchError((_) {}),
    );

    // Auto-fetch KIN IDs for families that don't have one
    unawaited(_ensureFamilyIds());
  }

  /// Auto-fetch KIN IDs for families that don't have one yet.
  /// Families created via Flutter may not have a kinFamilyId until
  /// the backend generates one on first access.
  Future<void> _ensureFamilyIds() async {
    final familiesAsync = ref.read(familyListProvider);
    final families = familiesAsync.valueOrNull ?? [];

    for (final family in families) {
      if (family.kinFamilyId == null || family.kinFamilyId!.isEmpty) {
        try {
          await ref.read(familyIdProvider.notifier).getFamilyId(family.id);
        } catch (e) {
          debugPrint('Failed to fetch KIN ID for ${family.name}: $e');
        }
      }
    }
    // Invalidate both providers so the new KIN IDs propagate:
    //   • familyListProvider (List<Family>) — used by the old
    //     profile_screen's KIN-IDs section and by _ensureFamilyIds
    //     on its next run.
    //   • profileProvider.state.families (List<FamilyTreeNode>) —
    //     used by the new Me screen's My families section AND by
    //     the My Families screen's KIN-ID rows. Without this refresh
    //     those surfaces would keep showing "no KIN ID" even after
    //     the backend has generated one.
    ref.invalidate(familyListProvider);
    unawaited(ref.read(profileProvider.notifier).loadFamilies());
  }

  Future<void> _loadStreak() async {
    final streak = await StreakService.getCurrentStreak();
    if (mounted) {
      setState(() {
        _streak = streak;
        _streakLoaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required by AutomaticKeepAliveClientMixin
    final user = ref.watch(currentUserProvider);
    final profile = ref.watch(profileProvider.select((s) => s.profile));
    final stats = ref.watch(profileStatsProvider);
    // Use profileProvider.state.families (List<FamilyTreeNode>) which
    // has the role field, NOT familyListProvider (List<Family>) which
    // does not. The old _buildFamilyIdsSection used familyListProvider
    // for the KIN IDs only because it didn't need role; the Me screen
    // needs role to render "{n} members · {Admin|Member}".
    final families = ref.watch(profileProvider.select((s) => s.families));
    final pendingInvites =
        ref.watch(profileProvider).invitations.where((i) => i.status == 'pending').toList();

    // Show skeleton while profile is loading
    final isProfileLoading = user == null && profile == null;

    return DKScaffold(
      backgroundColor: _bg,
      body: isProfileLoading
          ? const ProfileSkeleton()
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: KinrelSpacing.base,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        _buildHeader(),
                        const SizedBox(height: 20),
                        _buildIdentityBlock(user, profile),
                        const SizedBox(height: 20),
                        _buildStatsCard(stats),
                        const SizedBox(height: 24),
                        // Needs you (only when applicable)
                        if (_needsYouApplies(pendingInvites, families)) ...[
                          _buildNeedsYouSection(pendingInvites, families),
                          const SizedBox(height: 24),
                        ],
                        _buildQuickSwitches(),
                        const SizedBox(height: 24),
                        _buildMyFamiliesSection(families),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // ── Header row (Me title + gear icon) ──────────────────────────────

  Widget _buildHeader() {
    return Row(
      children: [
        Text(
          'Me',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 21,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
            letterSpacing: 0.3,
          ),
        ),
        const Spacer(),
        Semantics(
          button: true,
          label: 'Settings',
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => context.push('/profile/settings'),
            child: Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              child: Icon(
                Icons.tune_rounded,
                color: _textPrimary,
                size: 24,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Identity block (avatar, name, @username + streak, bio) ────────

  Widget _buildIdentityBlock(user, ProfileModel? profile) {
    final displayName = profile?.name ??
        user?.userMetadata?['name'] as String? ??
        user?.email?.split('@').first ??
        'Not signed in';
    final avatarUrl = profile?.avatarUrl;
    final bio = profile?.bio ?? '';
    final username = profile?.username;
    final showStreak = _streakLoaded && _streak > 0;

    return Center(
      child: Column(
        children: [
          // Avatar with Sparq ring + camera overlay (unchanged behavior)
          Semantics(
            button: true,
            label: 'View Sparqs or change profile photo',
            hint:
                'Double tap to view Sparqs. Use camera icon to change photo.',
            child: SparqRingAvatar(
              userId: user?.id ?? profile?.id ?? '',
              avatarUrl: avatarUrl,
              radius: 44,
              onTap: () => context.push('/sparq/create'),
              child: SizedBox(
                width: 88,
                height: 88,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipOval(
                      child: Container(
                        color: KinrelColors.darkElevated,
                        child: _isUploadingAvatar
                            ? const Center(
                                child: SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      _orange,
                                    ),
                                  ),
                                ),
                              )
                            : (avatarUrl != null && avatarUrl.isNotEmpty)
                                ? CachedNetworkImage(
                                    cacheManager:
                                        KinrelImageCacheManager.instance,
                                    imageUrl: avatarUrl,
                                    fit: BoxFit.cover,
                                    imageBuilder: (ctx, img) => Image(
                                      image: img,
                                      semanticLabel: '$displayName\'s photo',
                                    ),
                                    placeholder: (_, __) => Center(
                                      child: Text(
                                        displayName.isNotEmpty
                                            ? displayName[0].toUpperCase()
                                            : '?',
                                        style: TextStyle(
                                          fontFamily:
                                              KinrelTypography.displayFont,
                                          fontSize: 36,
                                          fontWeight: FontWeight.w700,
                                          color: _textPrimary,
                                        ),
                                      ),
                                    ),
                                    errorWidget: (_, __, ___) => Center(
                                      child: Text(
                                        displayName.isNotEmpty
                                            ? displayName[0].toUpperCase()
                                            : '?',
                                        style: TextStyle(
                                          fontFamily:
                                              KinrelTypography.displayFont,
                                          fontSize: 36,
                                          fontWeight: FontWeight.w700,
                                          color: _textPrimary,
                                        ),
                                      ),
                                    ),
                                  )
                                : _buildCameoFallbackAvatar(displayName),
                      ),
                    ),
                    // Camera icon overlay
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: GestureDetector(
                        onTap: _showAvatarSourceSheet,
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: _orange,
                            shape: BoxShape.circle,
                            border: Border.all(color: _bg, width: 2),
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Name
          Text(
            displayName,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
              letterSpacing: 0.4,
            ),
          ),

          if (username != null && username.isNotEmpty || showStreak) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (username != null && username.isNotEmpty) ...[
                  Text(
                    '@$username',
                    style: const TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      color: _orange,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                if (username != null && username.isNotEmpty && showStreak) ...[
                  Text(
                    ' · ',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      color: _textDim,
                    ),
                  ),
                ],
                if (showStreak)
                  Text(
                    '$_streak-day streak',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      color: _textDim,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ],

          // Bio (one line, ellipsis, tappable to edit)
          if (bio.isNotEmpty) ...[
            const SizedBox(height: 6),
            Semantics(
              button: true,
              label: 'Edit bio',
              child: GestureDetector(
                onTap: () => context.push('/profile/edit?focus=bio'),
                child: Text(
                  bio,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    color: _textDim,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Cameo fallback avatar — kept in this file so the avatar flow
  /// stays unchanged from the original profile_screen.dart. When the
  /// 3D Cameo (Thermion) runtime is enabled, surfaces use
  /// CameoLive3DAvatar. Otherwise, the 2D fallback CameoAvatar renders
  /// the deterministic Kinrel visual identity.
  Widget _buildCameoFallbackAvatar(String displayName) {
    // Lazy import via reflection-safe import: avoid pulling in the
    // heavy Cameo runtime here (the build already imports feature flags
    // for kEnableLive3DCameo / kEnableCameoFallback).
    return Consumer(
      builder: (context, ref, _) {
        // Use the same kEnableCameoFallback path that the old
        // ProfileScreen used. For now, render the initial-letter
        // fallback; the live 3D viewport stays on the Look & language
        // category screen.
        return Center(
          child: Text(
            displayName.isNotEmpty
                ? displayName[0].toUpperCase()
                : '?',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 36,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
        );
      },
    );
  }

  void _showAvatarSourceSheet() {
    showAvatarSourceSheet(
      context,
      onPickCamera: () =>
          pickAndUploadAvatar(context, ref, ImageSource.camera,
              setIsUploading: _setAvatarUploading),
      onPickGallery: () =>
          pickAndUploadAvatar(context, ref, ImageSource.gallery,
              setIsUploading: _setAvatarUploading),
    );
  }

  void _setAvatarUploading(bool value) {
    if (mounted) setState(() => _isUploadingAvatar = value);
  }

  // ── Stats card (3 equal columns) ────────────────────────────────────

  Widget _buildStatsCard(UserStatsModel? stats) {
    final isLoading = stats == null;
    final treesStr = isLoading ? '–' : '${stats.familyTrees}';
    final membersStr = isLoading ? '–' : '${stats.membersAdded}';
    final relationsStr = isLoading ? '–' : '${stats.relations}';

    return Container(
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderSubtle),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: IntrinsicHeight(
        child: Row(
          children: [
            _statColumn(
              value: treesStr,
              label: 'Family trees',
              isLoading: isLoading,
              onTap: () => context.go('/families'),
            ),
            VerticalDivider(
              width: 1,
              thickness: 0.5,
              color: _borderSubtle,
              indent: 8,
              endIndent: 8,
            ),
            _statColumn(
              value: membersStr,
              label: 'Members added',
              isLoading: isLoading,
              onTap: () => context.push('/profile/members-added'),
            ),
            VerticalDivider(
              width: 1,
              thickness: 0.5,
              color: _borderSubtle,
              indent: 8,
              endIndent: 8,
            ),
            _statColumn(
              value: relationsStr,
              label: 'Relations',
              isLoading: isLoading,
              onTap: () => context.push('/profile/relations'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statColumn({
    required String value,
    required String label,
    required bool isLoading,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading)
                const KinrelSkeletonBox(
                  width: 32,
                  height: 22,
                  radius: 4,
                )
              else
                Text(
                  value,
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 11,
                  color: _textDim,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Needs you section ───────────────────────────────────────────────

  bool _needsYouApplies(List pendingInvites, List families) {
    if (pendingInvites.isNotEmpty) return true;
    // Claim profile: shown when user is in a family but not linked to a
    // Person node. We use the first family's viewer-link state.
    if (families.isEmpty) return false;
    final first = families.first;
    final linked = ref.read(isViewerLinkedProvider(first.id));
    return !linked;
  }

  Widget _buildNeedsYouSection(List pendingInvites, List families) {
    final orange = _orange;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            'Needs you',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              color: _textDim,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: orange.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: orange.withValues(alpha: 0.30)),
          ),
          child: Column(
            children: [
              if (pendingInvites.isNotEmpty)
                _buildNeedYouRow(
                  icon: Icons.mail_outline,
                  title: '${pendingInvites.length} family '
                      'invitation${pendingInvites.length == 1 ? '' : 's'}',
                  subtitle: _formatInviterNames(pendingInvites),
                  onTap: () => context.push('/profile/invitations'),
                ),
              if (pendingInvites.isNotEmpty && _shouldShowClaimProfile(families))
                const _NeedYouDivider(),
              if (_shouldShowClaimProfile(families))
                _buildNeedYouRow(
                  icon: Icons.person_search,
                  title: 'Claim your profile',
                  subtitle: 'Link yourself in ${_firstFamilyName(families)}',
                  onTap: () => context.push('/family/${families.first.id}'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNeedYouRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _orange.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: _amber, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12.5,
                        color: _textDim,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: _textDim, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  bool _shouldShowClaimProfile(List families) {
    if (families.isEmpty) return false;
    final first = families.first;
    final linked = ref.read(isViewerLinkedProvider(first.id));
    return !linked;
  }

  String _firstFamilyName(List families) {
    if (families.isEmpty) return 'your family';
    return families.first.name;
  }

  String _formatInviterNames(List invites) {
    if (invites.isEmpty) return '';
    final names = <String>[];
    for (final i in invites.take(3)) {
      names.add(i.familyName ?? i.inviterName ?? 'family');
    }
    final joined = names.join(', ');
    if (invites.length > 3) return '$joined +${invites.length - 3} more';
    return joined;
  }

  // ── Quick switches (Theme / Quiet / Location / Language) ──────────

  Widget _buildQuickSwitches() {
    final themeMode = ref.watch(themeModeProvider);
    final quietSummary = ref.watch(quietHoursSummaryProvider).maybeWhen(
          data: (s) => s,
          orElse: () => 'Off',
        );
    final locationOn = ref.watch(locationSharingToggleProvider);
    final profile = ref.watch(profileProvider).profile;
    final langCode = profile?.preferredLanguage ?? 'en';
    final langName = languageNativeName(langCode);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            'Quick switches',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              color: _textDim,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _QuickSwitchTile(
                value: _themeLabel(themeMode),
                caption: 'Theme',
                isOn: themeMode == ThemeMode.dark,
                onTap: () => _cycleTheme(themeMode),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _QuickSwitchTile(
                value: quietSummary,
                caption: 'Quiet',
                isOn: quietSummary != 'Off',
                onTap: () async {
                  unawaited(context.push('/profile/quiet-hours'));
                  ref.invalidate(quietHoursSummaryProvider);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _QuickSwitchTile(
                value: locationOn ? 'On' : 'Off',
                caption: 'Location',
                isOn: locationOn,
                onTap: () {
                  final next = !locationOn;
                  ref.read(locationSharingToggleProvider.notifier).state = next;
                  unawaited(
                      onLocationSharingToggle(context, ref, next));
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _QuickSwitchTile(
                value: langName,
                caption: 'Language',
                isOn: false,
                onTap: () =>
                    showLanguageSheet(context, ref, langCode),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _cycleTheme(ThemeMode current) {
    final next = switch (current) {
      ThemeMode.dark => ThemeMode.light,
      ThemeMode.light => ThemeMode.system,
      ThemeMode.system => ThemeMode.dark,
    };
    ref.read(themeModeProvider.notifier).state = next;
  }

  String _themeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.system:
        return 'System';
    }
  }

  // ── My families section ────────────────────────────────────────────

  Widget _buildMyFamiliesSection(List families) {
    if (families.isEmpty) {
      // No family — single "Create or join a family" card
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'My families',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: _textDim,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _FamilyTile(
            name: 'Create or join a family',
            subtitle: 'Start your family tree',
            isAdmin: false,
            onTap: () => context.push('/families'),
            isCreateCta: true,
          ),
        ],
      );
    }

    final visibleFamilies = families.take(2).toList();
    final seeAll = families.length > 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            'My families',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              color: _textDim,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Row(
          children: [
            for (var i = 0; i < visibleFamilies.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _FamilyTile(
                  name: visibleFamilies[i].name,
                  subtitle:
                      '${visibleFamilies[i].memberCount} members · ${_roleLabel(visibleFamilies[i].role)}',
                  isAdmin:
                      visibleFamilies[i].role.toLowerCase() == 'admin',
                  onTap: () =>
                      context.push('/family/${visibleFamilies[i].id}'),
                ),
              ),
            ],
          ],
        ),
        if (seeAll) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.push('/profile/my-families'),
              style: TextButton.styleFrom(
                foregroundColor: _orange,
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'See all (${families.length})',
                    style: const TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      color: _orange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, color: _orange, size: 16),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _roleLabel(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return 'Admin';
      case 'editor':
        return 'Editor';
      case 'viewer':
        return 'Viewer';
      case 'member':
      default:
        return 'Member';
    }
  }
}

// ──────────────────────────────────────────────────────────────────────
//  Quick-switch tile
// ──────────────────────────────────────────────────────────────────────

class _QuickSwitchTile extends StatelessWidget {
  const _QuickSwitchTile({
    required this.value,
    required this.caption,
    required this.isOn,
    required this.onTap,
  });

  final String value;
  final String caption;
  final bool isOn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final orange = const Color(0xFFE8612A);
    final amber = const Color(0xFFF59240);
    final textPrimary = DKColors.textPrimary(context);
    final textDim = DKColors.isLight(context)
        ? const Color(0xFF6B7280)
        : const Color(0xFF8A7A72);
    final borderSubtle = DKColors.borderColor(context);
    final cardBg = DKColors.cardColor(context);

    return Material(
      color: isOn
          ? orange.withValues(alpha: 0.10)
          : cardBg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isOn
                  ? orange.withValues(alpha: 0.30)
                  : borderSubtle,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isOn ? amber : textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 11.5,
                  color: textDim,
                ),
              ),
              const SizedBox(height: 2),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
//  Family tile (My families section)
// ──────────────────────────────────────────────────────────────────────

class _FamilyTile extends StatelessWidget {
  const _FamilyTile({
    required this.name,
    required this.subtitle,
    required this.isAdmin,
    required this.onTap,
    this.isCreateCta = false,
  });

  final String name;
  final String subtitle;
  final bool isAdmin;
  final bool isCreateCta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final orange = const Color(0xFFE8612A);
    final textPrimary = DKColors.textPrimary(context);
    final textDim = DKColors.isLight(context)
        ? const Color(0xFF6B7280)
        : const Color(0xFF8A7A72);
    final borderSubtle = DKColors.borderColor(context);
    final cardBg = DKColors.cardColor(context);

    return Material(
      color: isCreateCta ? orange.withValues(alpha: 0.08) : cardBg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isCreateCta ? orange.withValues(alpha: 0.30) : borderSubtle,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isCreateCta
                      ? Icons.add_rounded
                      : Icons.family_restroom_rounded,
                  color: orange,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isCreateCta ? orange : textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12.5,
                        color: textDim,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: textDim, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
//  Needs you divider (between rows in the orange-tinted card)
// ──────────────────────────────────────────────────────────────────────

class _NeedYouDivider extends StatelessWidget {
  const _NeedYouDivider();

  @override
  Widget build(BuildContext context) {
    final orange = const Color(0xFFE8612A);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Divider(
        height: 1,
        thickness: 0.5,
        color: orange.withValues(alpha: 0.20),
      ),
    );
  }
}
