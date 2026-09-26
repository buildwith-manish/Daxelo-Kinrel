import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/feature_flags.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/family/optimistic_actions.dart';
import '../../../core/family/optimistic_provider.dart';
import '../../../core/kinship/kinship_provider.dart';
import '../../../core/networking/dio_client.dart';
import '../../../core/services/image_cache_manager.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../../presentation/widgets/skeletons/member_list_skeleton.dart';
import '../../../graph/widgets/family_graph_engine_view.dart';
import 'family_space_floating_nav.dart';
import 'add_person_sheet.dart';
import 'person_detail_sheet.dart';
// v5.15: kept for route compat but no longer called directly
import 'add_member_options_sheet.dart';

import '../../../core/utils/smart_preloader.dart';
import '../../../core/utils/share_helper.dart';
import '../../prediction_battle_v1/pb_v1_card.dart';
import '../../prediction_battle_v1/pb_v1_fun_fact_card.dart';
import '../../thinking/presentation/family_ring_widget.dart';
import '../../games/services/game_asset_manager.dart';
import '../../games/shared/icons/game_icons.dart';
import '../../games/shared/widgets/active_games_provider.dart';
import '../../presence/presentation/presence_widget.dart';
import '../../pulse/providers/cross_feature_moments_provider.dart';
import '../../shared_list/presentation/shared_list_screen.dart';
import 'premium/family_hub_sections.dart';
import 'premium/family_hub_highlights.dart';
import 'premium/hero_section.dart';
import 'widgets/image_crop_editor.dart';

class FamilyDetailScreen extends ConsumerStatefulWidget {
  FamilyDetailScreen({super.key, required this.familyId});

  final String familyId;

  @override
  ConsumerState<FamilyDetailScreen> createState() => _FamilyDetailScreenState();
}

class _FamilyDetailScreenState extends ConsumerState<FamilyDetailScreen> {
  // Premium redesign: scroll controller for the parallax hero collapse.
  final _hubScrollController = ScrollController();
  double _heroScrollOffset = 0;

  @override
  void initState() {
    super.initState();
    _hubScrollController.addListener(_onHubScroll);
  }

  @override
  void dispose() {
    _hubScrollController.removeListener(_onHubScroll);
    _hubScrollController.dispose();
    super.dispose();
  }

  void _onHubScroll() {
    final offset = _hubScrollController.offset.clamp(0.0, 200.0);
    if ((offset - _heroScrollOffset).abs() > 1) {
      setState(() => _heroScrollOffset = offset);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(familyDetailProvider(widget.familyId));
    // v121: Watch the centralized avatar provider for instant updates
    // (optimistic during upload, authoritative after).
    final avatarUrl = ref.watch(familyAvatarProvider(widget.familyId));

    // v116: PopScope ensures the Android device back button uses the
    // same logic as the top-left back arrow — pop if there's history,
    // otherwise go to Home. Without this, the system back gesture
    // would do nothing (or exit the app) when canPop() is false.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/home');
        }
      },
      child: DKScaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Go back',
          onPressed: () {
            // v116: Fix dead-end back button. Previously the fallback
            // was context.go('/family/${widget.familyId}') — which
            // navigated to the SAME screen the user was already on,
            // trapping them. Now the fallback goes to Home so the back
            // button always performs a valid navigation action.
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
        // ── Phase 1 fix (duplicate-space-home): the AppBar previously
        // showed the family name as its title (line 142 in the prior
        // version). That made the AppBar visually read as a SECOND
        // identity header — back arrow + family name + action icons —
        // stacked directly above the HeroSection which ALSO shows
        // the family name (with the avatar circle). Two identity
        // headers at the same scroll position was the root cause of
        // the perceived "two competing layouts" bug.
        //
        // Fix: drop the AppBar title entirely. The AppBar now holds
        // ONLY the back button + action icons (Kinrel, Governance).
        // The HeroSection immediately below is the SINGLE identity
        // header for the Family Space — avatar circle + family name
        // in display type + "N members · N links" caption. This
        // matches Instagram/WhatsApp profile screens where the
        // AppBar is minimal (back + a few action icons) and the
        // profile hero IS the identity surface.
        title: const SizedBox.shrink(),
        actions: [
          // ── AppBar actions — all icon-only, consistent sizing.
          //
          // Phase 1 (duplicate-space-home fix): slimmed from 4 to 2
          // actions. Family Chat moved to the persistent bottom nav.
          //
          // Phase 2 (this pass): Settings moved INTO the AppBar (was
          // previously in the now-deprecated QuickActionsRow middle
          // action row). Family Chat is NOT here — its only entry
          // point on this screen is the bottom nav item.
          //
          // The AppBar reads as "secondary power features" (Kinrel
          // when enabled, Governance, Settings) — all low-emphasis
          // icon-only. The primary action (Invite) lives in the body
          // as a standalone prominent button below the Highlights
          // row. This matches WhatsApp/Telegram/Instagram discipline
          // where the AppBar carries icon-only actions and the
          // primary CTA lives in the body.

          // Kinrel — Family Relationship Intelligence. Gated by
          // kEnableKinrel so it ships dark and can be flipped on per build.
          if (kEnableKinrel)
            IconButton(
              icon: const Icon(Icons.auto_awesome_outlined),
              tooltip: 'Kinrel',
              onPressed: () {
                final detail = ref
                    .read(familyDetailProvider(widget.familyId))
                    .valueOrNull;
                final familyName = detail?.family.name;
                context.push(
                  '/family/${widget.familyId}/kinrel',
                  extra: familyName != null
                      ? <String, dynamic>{'familyName': familyName}
                      : null,
                );
              },
            ),
          // Track C v2.0 — Kinrel Governance Engine (Constitution, Decisions, Timeline)
          IconButton(
            icon: const Icon(Icons.gavel_outlined),
            tooltip: 'Family Governance',
            onPressed: () {
              context.push('/family/${widget.familyId}/governance');
            },
          ),
          // ── Settings — moved here from the deprecated QuickActionsRow.
          // Icon-only, consistent with the Kinrel + Governance icons
          // above. Uses the existing _showFamilySettings handler (which
          // opens a bottom sheet with family info, edit, share, leave
          // actions — the same destination as before the move, so no
          // broken route).
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => _showFamilySettings(context),
          ),
        ],
      ),
      // Family Space floating nav — the SAME widget used on Members,
      // Games, Calendar, Lists, and Chat screens. Wired in here as a
      // `bottomNavigationBar` so the Scaffold reserves space for it and
      // the body content lays out above it. This replaces the legacy
      // QuickJumpNavRow fixed dock that was previously rendered inside
      // the body's Stack.
      bottomNavigationBar: FamilySpaceFloatingNav(familyId: widget.familyId),
      body: detailAsync.when(
        loading: () => const _FamilyDetailLoadingWidget(),
        error: (error, _) => DKErrorState(
          message: 'Failed to load family data',
          onRetry: () {
            ref.invalidate(familyListProvider);
            ref.invalidate(familyDetailProvider(widget.familyId));
            ref.invalidate(familyMembersProvider(widget.familyId));
            ref.invalidate(familyRelationshipsProvider(widget.familyId));
          },
        ),
        data: (detail) {
          if (detail == null) {
            return DKErrorState(
              message: 'Family not found',
              onRetry: () {
                ref.invalidate(familyListProvider);
                ref.invalidate(familyDetailProvider(widget.familyId));
                ref.invalidate(familyMembersProvider(widget.familyId));
                ref.invalidate(familyRelationshipsProvider(widget.familyId));
              },
            );
          }

          // ════════════════════════════════════════════════════════════
          // PREMIUM FAMILY SPACE — exactly 5 sections (4 scroll + 1 dock)
          //
          // 1. Hero (Kinrel symbol + family name + member/link caption)
          // 2. Truth Streak (the one "moment" — terracotta gradient)
          // 3. [FIXED DOCK] Quick-jump navigation row (Members, Games,
          //    Calendar, Memories, Chat — pinned to bottom, always visible)
          // 4. Family Pulse (nudges + activity merged, one empty state)
          // 5. Utility row (Invite, Settings, Leave — muted, secondary)
          //
          // The quick-jump row is a FIXED bottom dock — it doesn't
          // scroll with the content. It stays pinned above the safe
          // area at all times. The scroll content has extra bottom
          // padding so nothing is hidden behind the dock.
          // ════════════════════════════════════════════════════════════
          return Stack(
            children: [
              // ── Scrollable content (4 sections + utility) ──────────
              CustomScrollView(
                controller: _hubScrollController,
                slivers: [
                  // ── 1. HERO (parallax collapse) ────────────────────────
                  // Stays as-is — already polished. The redesign focuses
                  // on the sections BELOW the hero, not the hero itself.
                  SliverToBoxAdapter(
                    child: staggerFade(
                      HeroSection(
                        // v121: Key on the centralized avatarUrl so
                        // Flutter rebuilds when the avatar changes
                        // (optimistic or authoritative).
                        key: ValueKey('hero_$avatarUrl'),
                        familyId: widget.familyId,
                        familyName: detail.family.name,
                        memberCount: detail.members.length,
                        relationshipCount: detail.relationships.length,
                        scrollOffset: _heroScrollOffset,
                        // v121: Use the centralized avatarUrl (from
                        // familyAvatarProvider) for instant updates.
                        avatarUrl: avatarUrl,
                        onAvatarTap: () => _onAvatarInteraction(),
                        onAvatarLongPress: () => _onAvatarInteraction(),
                      ),
                      0,
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 8)),

                  // ── 1b. PRESENCE STRIP — who's home / at work / DND ──
                  // WhatsApp-style "online now" strip, persistent under hero.
                  SliverToBoxAdapter(
                    child: staggerFade(
                      PresenceRow(familyId: widget.familyId),
                      0,
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 12)),

                  // ── 2. HIGHLIGHTS ROW (Instagram-style) ───────────────
                  // Replaces the off-palette _QuickLinksRow chip strip
                  // (which used 5 different hex colors not in the Kinrel
                  // palette). Single-accent orange rings, circular
                  // tiles, 5 quick-access destinations. Also folds in
                  // the "Lists & Errands" tile (formerly _SharedListTile)
                  // so it no longer needs its own separate section.
                  SliverToBoxAdapter(
                    child: staggerFade(
                      HighlightsRow(familyId: widget.familyId),
                      1,
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 16)),

                  // ── 3. INVITE — standalone prominent full-width button ──
                  // Replaces the prior QuickActionsRow (Invite / Family
                  // Chat / Settings 3-pill row). Per the new IA:
                  //   • Family Chat removed entirely from the middle
                  //     action row — its only entry point on this
                  //     screen is the persistent bottom nav item.
                  //   • Settings moved to the AppBar as an icon-only
                  //     button (see AppBar actions above).
                  //   • Invite promoted to a standalone full-width
                  //     prominent button — the ONE visually-bold
                  //     element in this section, per the design-system
                  //     "spend your boldness in one place" principle.
                  SliverToBoxAdapter(
                    child: staggerFade(
                      InviteButton(
                        onTap: () => showAddMemberOptions(
                            context, familyId: widget.familyId),
                      ),
                      1,
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 18)),

                  // ── 4. FAMILY PULSE (activity feed) ────────────────────
                  // Phase 5 (ux/family-space-refinement): MOVED above the
                  // primary content feed. The screen now reads top-to-
                  // bottom as: identity (Hero) → shortcuts (Highlights) →
                  // invite (InviteButton) → activity (Family Pulse) →
                  // content feed (PB + CoinPool + Ring + Recent Moments).
                  // This is the "who/what is this, then what's happening"
                  // order — identity context before activity feed.
                  //
                  // The birthday "missing info" nags inside Family Pulse
                  // are collapsed into a single prompt per Phase 4 — see
                  // family_hub_sections.dart → FamilyPulseSection.build.
                  SliverToBoxAdapter(
                    child: staggerFade(
                      FamilyPulseSection(
                        detail: detail,
                        familyId: widget.familyId,
                      ),
                      2,
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 18)),

                  // ── 5. PREDICTION BATTLE — the "moment" (hero card) ──
                  // Backend-scheduled numeric-estimation game. This is
                  // the PRIMARY content feed element — uses AppCard.hero
                  // treatment (gradient + accent border + glow shadow)
                  // so it visually draws the eye first. The Family Coin
                  // Pool below it is a slim status strip (Phase 3) so
                  // the hierarchy reads: PB = hero, Coin Pool = ambient
                  // status.
                  SliverToBoxAdapter(
                    child: staggerFade(
                      PredictionBattleV1Card(familyId: widget.familyId),
                      3,
                    ),
                  ),

                  // 5a. Family coin pool — slim horizontal progress strip
                  // (Phase 3: downgraded from full hero card to single-
                  // row strip for clear visual hierarchy with PB above).
                  SliverToBoxAdapter(
                    child: staggerFade(
                      FamilyCoinPoolCard(familyId: widget.familyId),
                      3,
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 16)),

                  // ── 5b. THINKING OF YOU RING ──────────────────────────
                  SliverToBoxAdapter(
                    child: staggerFade(
                      FamilyRingWidget(familyId: widget.familyId),
                      4,
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 16)),

                  // ── 6. RECENT MOMENTS (unified) ───────────────────────
                  SliverToBoxAdapter(
                    child: staggerFade(
                      _RecentMomentsSectionAdapter(familyId: widget.familyId),
                      4,
                    ),
                  ),

                  // ── 7. FAMILY STRENGTH CLOSER (Peak-End Rule) ─────────
                  SliverToBoxAdapter(
                    child: staggerFade(
                      _FamilyStrengthCloser(
                        memberCount: detail.members
                            .where((p) => p.deletedAt == null)
                            .length,
                      ),
                      5,
                    ),
                  ),

                  // Bottom padding: sufficient spacing so the last card
                  // (Family Coin Pool or Family Strength closer) always
                  // renders fully above the persistent bottom nav.
                  //
                  // Phase 2 (ux/family-space-refinement): the prior
                  // padding was `MediaQuery.padding.bottom + 24` which
                  // only accounted for the safe-area inset — NOT the
                  // bottom nav's actual rendered height (~80px) or its
                  // bottom margin (24px). This caused the Family Coin
                  // Pool card's last line ("12/500 coins") to be
                  // clipped behind the bottom nav on devices with
                  // gesture navigation bars.
                  //
                  // Fix: bottom nav height (80) + nav bottom margin
                  // (24) + safe-area inset + comfortable breathing
                  // gap (16) = total bottom padding. This ensures the
                  // last card always renders fully above the nav with
                  // a comfortable margin, not flush against it.
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 80 + 24 + MediaQuery.of(context).padding.bottom + 16,
                    ),
                  ),
                ],
              ),

            ],
          );
        },
      ),
    ),
    );
  }

  void _shareFamily(BuildContext context) {
    final detailAsync = ref.read(familyDetailProvider(widget.familyId));
    final familyName = detailAsync.valueOrNull?.family.name ?? 'Family';
    ShareHelper.shareFamily(familyId: widget.familyId, familyName: familyName);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // v118 — Family Avatar Interaction (role-based)
  // ═══════════════════════════════════════════════════════════════════════

  /// Called when the user taps or long-presses the family avatar.
  /// Determines the user's role and shows the appropriate UI:
  /// - Creator/Admin → bottom sheet menu with View / Change / Remove
  /// - Regular member → full-screen avatar viewer (no edit controls)
  void _onAvatarInteraction() {
    final detailAsync = ref.read(familyDetailProvider(widget.familyId));
    final family = detailAsync.valueOrNull?.family;
    if (family == null) return;

    final currentUserId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isCreator = family.createdBy != null &&
        family.createdBy == currentUserId;

    final membershipsAsync =
        ref.read(familyMembershipsProvider(widget.familyId));
    final memberships = membershipsAsync.valueOrNull ?? [];
    final currentUserMembership = memberships
        .where((m) => m.userId == currentUserId)
        .firstOrNull;
    final isAdminOrOwner = isCreator ||
        currentUserMembership?.isAdmin == true;

    if (isAdminOrOwner) {
      _showAvatarMenu(family);
    } else {
      // v121: Use the centralized avatarUrl for the full-screen viewer.
      final avatarUrl = ref.read(familyAvatarProvider(widget.familyId));
      _showFullScreenAvatar(avatarUrl, family.name);
    }
  }

  /// Shows the role-based bottom sheet menu for creators/admins:
  /// - View Family Profile Picture (full-screen)
  /// - Change Family Profile Picture (gallery picker → upload)
  /// - Remove Family Profile Picture (only if one exists)
  void _showAvatarMenu(Family family) {
    // v121: Use the centralized avatarUrl (includes optimistic updates).
    final avatarUrl = ref.read(familyAvatarProvider(widget.familyId));
    final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;

    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: const Align(
                alignment: Alignment.centerLeft,
                child: const Text(
                  'Family Profile Picture',
                  style: const TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                  ),
                ),
              ),
            ),
            // View (only if an avatar exists)
            if (hasAvatar)
              ListTile(
                leading: const Icon(Icons.visibility_outlined,
                    color: KinrelColors.textSilver),
                title: const Text('View Profile Picture',
                    style: const TextStyle(color: KinrelColors.textWhite)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showFullScreenAvatar(avatarUrl, family.name);
                },
              ),
            // Change
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: KinrelColors.orange),
              title: const Text('Change Profile Picture',
                  style: const TextStyle(color: KinrelColors.textWhite)),
              onTap: () {
                Navigator.pop(ctx);
                _uploadAvatar();
              },
            ),
            // Remove (only if one exists)
            if (hasAvatar)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: Colors.redAccent),
                title: const Text('Remove Profile Picture',
                    style: const TextStyle(color: KinrelColors.textWhite)),
                onTap: () {
                  Navigator.pop(ctx);
                  _removeAvatar();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Opens a full-screen avatar viewer with pinch-to-zoom support.
  /// Shown to ALL users (admin + regular) when they want to view the
  /// current avatar.
  void _showFullScreenAvatar(String? avatarUrl, String familyName) {
    if (avatarUrl == null || avatarUrl.isEmpty) {
      // No avatar to view — show a snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No profile picture set for $familyName'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullScreenAvatarViewer(
          imageUrl: avatarUrl,
          familyName: familyName,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  /// Picks an image from the gallery, opens a crop editor, uploads the
  /// cropped image to Supabase Storage, and updates the Family row's
  /// avatarUrl. Shows loading/success/error states via a SnackBar.
  ///
  /// v120: Fixes the "old image still showing after upload" bug by:
  /// 1. Capturing the old avatar URL before upload.
  /// 2. Evicting the old image from Flutter's ImageCache +
  ///    CachedNetworkImage's disk cache after upload.
  /// 3. Deleting the old storage file to prevent accumulation.
  /// 4. Forcing familyDetailProvider to re-fetch from Supabase (not
  ///    from the stale familyListProvider fast path).
  Future<void> _uploadAvatar() async {
    // 1. Pick image from gallery (web-compatible — no camera option).
    final picker = ImagePicker();
    final xFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 90,
    );
    if (xFile == null) return; // user cancelled

    if (!mounted) return;

    // 2. Open the crop editor.
    final rawBytes = await xFile.readAsBytes();
    if (!mounted) return;
    final croppedBytes = await ImageCropEditor.show(
      context,
      imageBytes: rawBytes,
    );
    if (croppedBytes == null) return; // user cancelled crop

    if (!mounted) return;

    // 3. v121: Optimistic UI update — show the cropped image instantly
    //    via a data URI before the upload completes. This makes the
    //    avatar change appear in <1 second across ALL screens that
    //    watch familyAvatarProvider.
    final optimisticUrl =
        'data:image/png;base64,${base64Encode(croppedBytes)}';
    ref
        .read(familyAvatarProvider(widget.familyId).notifier)
        .setOptimistic(optimisticUrl);

    // 4. Capture the OLD avatar URL (to evict its cache + delete the
    //    storage file after the new upload succeeds).
    final oldAvatarUrl = ref
        .read(familyDetailProvider(widget.familyId))
        .valueOrNull
        ?.family
        .avatarUrl;

    // 4. Show loading indicator.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 16),
            Text('Uploading…'),
          ],
        ),
        duration: Duration(seconds: 30),
        behavior: SnackBarBehavior.floating,
      ),
    );

    try {
      // 5. Upload to Supabase Storage.
      final client = ref.read(supabaseProvider);
      if (client == null) throw Exception('Not connected to server');

      if (client.auth.currentSession == null) {
        throw Exception('Not signed in. Please sign in and try again.');
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path = 'family-avatars/$timestamp.png';

      await client.storage.from('avatars').uploadBinary(
            path,
            croppedBytes,
            fileOptions: const FileOptions(
              contentType: 'image/png',
              upsert: false,
            ),
          );

      // Build the public URL with a cache-busting query param.
      final url =
          '${client.storage.from('avatars').getPublicUrl(path)}?t=$timestamp';

      // 6. Update the Family row with the new avatar URL.
      await updateFamily(
        ref: ref,
        familyId: widget.familyId,
        avatarUrl: url,
      );

      // 7. Evict the OLD image from all caches so it doesn't linger.
      _evictOldAvatarCache(oldAvatarUrl);

      // 8. Delete the old storage file (best-effort, don't block on it).
      _deleteOldStorageFile(client, oldAvatarUrl);

      // 9. Force-refresh the providers so the UI rebuilds with the
      //    new URL immediately. updateFamily already invalidated
      //    familyDetailProvider + familyListProvider, but the detail
      //    provider's fast path reads from familyListProvider which
      //    may still be re-fetching. Invalidating again after the
      //    DB update ensures the next read goes to Supabase.
      ref.invalidate(familyDetailProvider(widget.familyId));
      ref.invalidate(familyListProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile picture updated!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on StorageException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Storage error: ${e.message}. '
            'Make sure you are signed in and have permission to upload.',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 8),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Evicts the old avatar image from Flutter's in-memory ImageCache
  /// and CachedNetworkImage's disk cache (native only). This ensures
  /// the old image doesn't linger after a new upload.
  void _evictOldAvatarCache(String? oldAvatarUrl) {
    if (oldAvatarUrl == null || oldAvatarUrl.isEmpty) return;

    // Evict from Flutter's in-memory image cache (works on all platforms).
    // PaintingBinding.instance.imageCache caches decoded images by URL.
    try {
      final imageCache = PaintingBinding.instance.imageCache;
      // The ImageCache stores by the ImageProvider's key, which for
      // CachedNetworkImage is the URL. We need to evict both the
      // raw URL and any cached resized variants.
      imageCache.clear();
      imageCache.clearLiveImages();
    } catch (_) {}

    // On native, also evict from CachedNetworkImage's disk cache.
    // On web, CachedNetworkImage uses network-only mode (no disk cache),
    // so this is skipped.
    if (!kIsWeb) {
      try {
        CachedNetworkImage.evictFromCache(oldAvatarUrl);
      } catch (_) {}
    }
  }

  /// Deletes the old avatar file from Supabase Storage (best-effort).
  /// Extracts the storage path from the public URL and removes the file.
  /// Failures are silently ignored — old files are cosmetic clutter, not
  /// a correctness issue.
  Future<void> _deleteOldStorageFile(
    dynamic client,
    String? oldAvatarUrl,
  ) async {
    if (oldAvatarUrl == null || oldAvatarUrl.isEmpty) return;
    try {
      // The public URL looks like:
      // https://<project>.supabase.co/storage/v1/object/public/avatars/family-avatars/123.png?t=456
      // We need to extract: family-avatars/123.png
      final uri = Uri.parse(oldAvatarUrl);
      // Remove the query string (cache-busting param).
      final pathPart = uri.path;
      // Extract everything after '/avatars/' in the path.
      final avatarsIdx = pathPart.indexOf('/avatars/');
      if (avatarsIdx == -1) return;
      final storagePath = pathPart.substring(avatarsIdx + '/avatars/'.length);
      if (storagePath.isEmpty) return;

      await client.storage.from('avatars').remove([storagePath]);
    } catch (_) {
      // Best-effort — don't fail the upload if old file deletion fails.
    }
  }

  /// Removes the family avatar by setting avatarUrl to null.
  Future<void> _removeAvatar() async {
    // Confirm
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KinrelColors.darkCard,
        title: const Text('Remove Profile Picture?',
            style: const TextStyle(color: KinrelColors.textWhite)),
        content: const Text(
            'The family profile picture will be removed for all members.',
            style: const TextStyle(color: KinrelColors.textSilver)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove',
                  style: const TextStyle(color: Colors.redAccent))),
        ],
      ),
    );

    if (confirmed != true) return;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 16),
            Text('Removing…'),
          ],
        ),
        duration: Duration(seconds: 15),
        behavior: SnackBarBehavior.floating,
      ),
    );

    try {
      // Set avatarUrl to null via a direct Supabase update (the
      // updateFamily helper only sends fields that are non-null, so
      // we can't use it to clear a field — we need a direct update).
      final client = ref.read(supabaseProvider);
      if (client == null) throw Exception('Not connected to server');
      await client
          .from('Family')
          .update({
            'avatarUrl': null,
            'updatedAt': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', widget.familyId);

      // Invalidate providers so the UI refreshes
      ref.invalidate(familyDetailProvider(widget.familyId));
      ref.invalidate(familyListProvider);

      // v121: Clear the centralized avatar provider
      ref.read(familyAvatarProvider(widget.familyId).notifier).clear();

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile picture removed.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Leave family dialog — confirms with the user before removing their
  /// membership. Creators are warned that they must transfer ownership
  /// or delete the family instead.
  void _showLeaveFamilyDialog(BuildContext context) {
    final detailAsync = ref.read(familyDetailProvider(widget.familyId));
    final family = detailAsync.valueOrNull?.family;
    final currentUserId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isCreator =
        family != null &&
        family.createdBy != null &&
        family.createdBy == currentUserId;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DKColors.cardColor(context),
        title: Text(
          isCreator ? 'Leave Family?' : 'Leave Family?',
          style: TextStyle(color: DKColors.textPrimary(context)),
        ),
        content: Text(
          isCreator
              ? 'You are the creator of this family. To leave, you must '
                    'transfer ownership to another admin or delete the family '
                    'from Settings. Would you like to open Settings?'
              : 'Are you sure you want to leave "${family?.name ?? 'this family'}"? '
                    'You will lose access to the family graph, members, and chat. '
                    'You can rejoin if you receive a new invite.',
          style: TextStyle(color: DKColors.textSecondary(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: DKColors.textSecondary(context)),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx, true);
              if (isCreator) {
                // Redirect creators to settings instead of leaving.
                _showFamilySettings(context);
              } else {
                // Non-creators can leave directly.
                _leaveFamily();
              }
            },
            child: Text(
              isCreator ? 'Open Settings' : 'Leave',
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  /// Calls the leave-family API and navigates back to the family list.
  Future<void> _leaveFamily() async {
    try {
      final dio = ref.read(dioProvider);
      await dio.delete('/families/${widget.familyId}/leave');
      if (mounted) {
        context.go('/families');
      }
    } catch (e) {
      if (mounted) {
        context.showSnackBar('Failed to leave family: $e', isError: true);
      }
    }
  }

  void _showFamilySettings(BuildContext context) {
    final detailAsync = ref.read(familyDetailProvider(widget.familyId));
    final family = detailAsync.valueOrNull?.family;
    final currentUserId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isCreator =
        family != null &&
        family.createdBy != null &&
        family.createdBy == currentUserId;

    // Determine current user's role from FamilyMember table
    final membershipsAsync = ref.read(
      familyMembershipsProvider(widget.familyId),
    );
    final memberships = membershipsAsync.valueOrNull ?? [];
    final currentUserMembership = memberships
        .where((m) => m.userId == currentUserId)
        .firstOrNull;
    final currentUserRole = currentUserMembership?.role;
    final isAdminOrOwner =
        isCreator || currentUserRole == 'admin' || currentUserRole == 'owner';

    // Count how many admins are in the family (to prevent sole admin from leaving)
    final adminCount = memberships.where((m) => m.isAdmin).length;
    final isOnlyAdmin =
        (currentUserMembership?.isAdmin ?? false) && adminCount <= 1;

    showModalBottomSheet(
      context: context,
      backgroundColor: DKColors.cardColor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(
          top: const Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(KinrelSpacing.base),
              child: Row(
                children: [
                  const Icon(
                    Icons.settings_outlined,
                    color: KinrelColors.purple,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Family Settings',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: DKColors.textPrimary(context),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: KinrelColors.border, height: 1),

            // Family info section
            if (family != null) ...[
              Padding(
                padding: const EdgeInsets.all(KinrelSpacing.base),
                child: Row(
                  children: [
                    DKAvatar(
                      initials: family.name.isNotEmpty
                          ? family.name[0].toUpperCase()
                          : 'F',
                      size: DKAvatarSize.md,
                      backgroundColor: KinrelColors.purple,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            family.name,
                            style: const TextStyle(
                              fontFamily: KinrelTypography.displayFont,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: KinrelColors.textWhite,
                            ),
                          ),
                          if (family.familyCode != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Code: ${family.familyCode}',
                              style: const TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 12,
                                color: KinrelColors.textSilver,
                              ),
                            ),
                          ],
                          if (family.kinFamilyId != null) ...[
                            const SizedBox(height: 2),
                            GestureDetector(
                              onTap: () {
                                Clipboard.setData(
                                  ClipboardData(text: family.kinFamilyId!),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Family ID copied: ${family.kinFamilyId}',
                                    ),
                                    behavior: SnackBarBehavior.floating,
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.copy,
                                    size: 12,
                                    color: KinrelColors.purple,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    family.kinFamilyId!,
                                    style: const TextStyle(
                                      fontFamily: KinrelTypography.monoFont,
                                      fontSize: 12,
                                      color: KinrelColors.purple,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: KinrelColors.border, height: 1),
            ],

            // Invite Members option (admin/owner only)
            if (isAdminOrOwner) ...[
              _QuickActionTile(
                icon: Icons.person_add_outlined,
                label: 'Invite Members',
                iconColor: KinrelColors.purple,
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/family/${widget.familyId}/invite');
                },
              ),
              const Divider(color: KinrelColors.border, height: 1),
            ],

            // Share option
            _QuickActionTile(
              icon: Icons.share_outlined,
              label: 'Share Family Code',
              onTap: () {
                Navigator.pop(ctx);
                _shareFamily(context);
              },
            ),

            // Copy Family ID option
            if (family?.kinFamilyId != null) ...[
              const Divider(color: KinrelColors.border, height: 1),
              _QuickActionTile(
                icon: Icons.copy_rounded,
                label: 'Copy Family ID (${family!.kinFamilyId})',
                onTap: () {
                  Navigator.pop(ctx);
                  Clipboard.setData(ClipboardData(text: family.kinFamilyId!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Family ID copied: ${family.kinFamilyId}'),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],

            // v109.9: Family Management — UNIFIED entry point for ALL
            // family-scoped admin controls (permissions, privacy, member
            // management, family preferences, activity log). The old
            // separate "Family Settings" screen has been merged into
            // Family Management.
            _QuickActionTile(
              icon: Icons.settings_outlined,
              label: 'Family Management',
              iconColor: KinrelColors.orange,
              onTap: () {
                Navigator.pop(ctx);
                context.push('/family/${widget.familyId}/management');
              },
            ),
            const Divider(color: KinrelColors.border, height: 1),

            // v109: Family Map + Memory Vault options REMOVED from the
            // Family Settings menu. These features are accessed from their
            // own dedicated sections elsewhere in the app (Family Map via
            // the hero header's right-side icon; Memory Vault via the
            // profile/home screen), not from Family Settings. The settings
            // menu should only contain family-management actions.

            // P12.6 — Story Mode (narrated family history tour)
            _QuickActionTile(
              icon: Icons.auto_stories_outlined,
              label: 'Story Mode',
              iconColor: KinrelColors.amber,
              onTap: () {
                Navigator.pop(ctx);
                context.push('/family/${widget.familyId}/story-mode');
              },
            ),
            const Divider(color: KinrelColors.border, height: 1),

            // P12.6 — Health Heritage (family health conditions)
            _QuickActionTile(
              icon: Icons.health_and_safety_outlined,
              label: 'Health Heritage',
              iconColor: KinrelColors.coral,
              onTap: () {
                Navigator.pop(ctx);
                context.push('/family/${widget.familyId}/health-heritage');
              },
            ),
            const Divider(color: KinrelColors.border, height: 1),

            // Delete option — moves family to archive (available to all members)
            const Divider(color: KinrelColors.border, height: 1),
            _QuickActionTile(
              icon: Icons.delete_outline_rounded,
              label: 'Delete Family',
              iconColor: KinrelColors.error,
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteFamily(context, family?.name ?? 'Family');
              },
            ),

            // Info: deleted families go to archive
            const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: KinrelSpacing.base,
                vertical: KinrelSpacing.sm,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 16,
                    color: KinrelColors.textDim,
                  ),
                  SizedBox(width: 8),
                  const Expanded(
                    child: const Text(
                      'Deleted families are moved to archive. You can restore or permanently delete them from there.',
                      style: const TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        color: KinrelColors.textDim,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Leave Family option (not available if user is the only admin)
            if (!isOnlyAdmin) ...[
              const Divider(color: KinrelColors.border, height: 1),
              _QuickActionTile(
                icon: Icons.exit_to_app_outlined,
                label: 'Leave Family',
                isDestructive: true,
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmLeaveFamily(context, family?.name ?? 'Family');
                },
              ),
            ] else ...[
              // Show info that sole admin must transfer role first
              const Divider(color: KinrelColors.border, height: 1),
              const Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: KinrelSpacing.base,
                  vertical: KinrelSpacing.sm,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 16,
                      color: KinrelColors.textDim,
                    ),
                    SizedBox(width: 8),
                    const Expanded(
                      child: const Text(
                        'Transfer your admin role to another member before leaving',
                        style: const TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 12,
                          color: KinrelColors.textDim,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteFamily(BuildContext context, String familyName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DKColors.cardColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
        ),
        title: Row(
          children: [
            const Icon(
              Icons.delete_outline_rounded,
              color: KinrelColors.error,
              size: 24,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'Delete "$familyName"?',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: DKColors.textPrimary(context),
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This family will be moved to archive. You can restore it or permanently delete it from the archive section.',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: DKColors.textSecondary(context),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: KinrelColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(KinrelRadius.md),
                border: Border.all(
                  color: KinrelColors.error.withValues(alpha: 0.2),
                ),
              ),
              child: const Row(
                children: [
                  const Icon(Icons.info_outline, size: 18, color: KinrelColors.error),
                  SizedBox(width: 8),
                  const Expanded(
                    child: const Text(
                      'Archived families are automatically deleted after 30 days if not restored.',
                      style: const TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: KinrelColors.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                color: DKColors.textSecondary(context),
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _performDeleteFamily(context);
            },
            child: const Text(
              'Delete',
              style: const TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontWeight: FontWeight.w600,
                color: KinrelColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _performDeleteFamily(BuildContext context) async {
    // Capture navigator, messenger, and container BEFORE async gap — the
    // widget may be disposed after deleteFamily invalidates providers and
    // the list rebuilds. ProviderContainer survives widget disposal.
    final navigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final container = ProviderScope.containerOf(context);

    unawaited(
      showDialog(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (_) => const Center(
          child: const CircularProgressIndicator(color: KinrelColors.purple),
        ),
      ),
    );

    try {
      await deleteFamilyOptimistic(
        container: container,
        familyId: widget.familyId,
      );

      // Use captured references — the original context may be unmounted now
      navigator.pop(); // Close loading dialog
      messenger.showSnackBar(
        const SnackBar(
          content: const Text(
            'Family moved to archive. You can restore it from the Archived section.',
          ),
          backgroundColor: KinrelColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      router.go('/families');
    } catch (e) {
      navigator.pop(); // Close loading dialog
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to delete: ${e.toString().split('\n').first}'),
          backgroundColor: KinrelColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _confirmLeaveFamily(BuildContext context, String familyName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DKColors.cardColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
        ),
        title: Row(
          children: [
            const Icon(
              Icons.exit_to_app_outlined,
              color: KinrelColors.warning,
              size: 24,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'Leave "$familyName"?',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: DKColors.textPrimary(context),
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You will no longer have access to this family tree. Other members will still be able to view and edit it.',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: DKColors.textSecondary(context),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: KinrelColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(KinrelRadius.md),
                border: Border.all(
                  color: KinrelColors.warning.withValues(alpha: 0.3),
                ),
              ),
              child: const Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 18,
                    color: KinrelColors.warning,
                  ),
                  SizedBox(width: 8),
                  const Expanded(
                    child: const Text(
                      'This action cannot be undone. You will need a new invitation to rejoin.',
                      style: const TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: KinrelColors.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                color: DKColors.textSecondary(context),
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop(); // Close dialog
              await _performLeaveFamily(context);
            },
            child: const Text(
              'Leave Family',
              style: const TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontWeight: FontWeight.w600,
                color: KinrelColors.warning,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _performLeaveFamily(BuildContext context) async {
    // Capture navigator and messenger BEFORE async gap — the widget may be
    // disposed after provider invalidation and navigation.
    final navigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    unawaited(
      showDialog(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (_) => const Center(
          child: const CircularProgressIndicator(color: KinrelColors.warning),
        ),
      ),
    );

    try {
      final dio = ref.read(dioProvider);
      await dio.delete('/api/families/${widget.familyId}/leave');

      // Invalidate providers
      ref.invalidate(familyListProvider);
      ref.invalidate(familyMembershipsProvider(widget.familyId));

      // Use captured references — the original context may be unmounted now
      navigator.pop(); // Close loading dialog
      messenger.showSnackBar(
        const SnackBar(
          content: const Text('You have left the family'),
          backgroundColor: KinrelColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      router.go('/');
    } catch (e) {
      navigator.pop(); // Close loading dialog
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Failed to leave family: ${e.toString().split('\n').first}',
          ),
          backgroundColor: KinrelColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

// ── Loading Widget (extracted for zero-rebuild optimization) ─────

class _FamilyDetailLoadingWidget extends ConsumerWidget {
  const _FamilyDetailLoadingWidget();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const MemberListSkeleton(itemCount: 6);
  }
}

/// Warm end-of-page closer (Peak-End Rule).
///
/// The last element a family member sees when they finish scrolling is a
/// belonging statement — "Your family is N members strong" — not utility
/// links. People disproportionately remember how an experience ENDS, so
/// the hub now closes on an emotional high note.
class _FamilyStrengthCloser extends StatelessWidget {
  const _FamilyStrengthCloser({required this.memberCount});
  final int memberCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            KinrelColors.orange.withValues(alpha: 0.10),
            KinrelColors.darkCard.withValues(alpha: 0.6),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: KinrelColors.orange.withValues(alpha: 0.22),
          width: 0.8,
        ),
      ),
      child: Column(
        children: [
          // 🧡 heart-in-circle emblem
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: KinrelColors.orange.withValues(alpha: 0.14),
              border: Border.all(
                color: KinrelColors.orange.withValues(alpha: 0.35),
                width: 1.2,
              ),
            ),
            child: const Icon(
              Icons.favorite_rounded,
              size: 22,
              color: KinrelColors.orange,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '🧡 Your family is $memberCount member${memberCount == 1 ? '' : 's'} strong',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: KinrelColors.textWhite,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Every photo, story and game you share makes it stronger.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              color: KinrelColors.textSilver,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact horizontal scrollable row of all games.
/// Replaces the previous layout where each game was a full-width card.
/// UX pass (Hick's Law): the flat 18-game scroll is now grouped into 3
/// scannable categories — Quick Play / Classic Board / Family Fun — so
/// the choice set is chunked and cognitively cheap to scan.
class _GamesRow extends ConsumerWidget {
  const _GamesRow({required this.familyId});
  final String familyId;

  // ── Hick's Law: 3 scannable category groups replace the flat 18-item
  //    scroll. Each group carries a time-to-commit hint so users can
  //    self-select by the time they have available.
  static const List<_GameEntry> _quickPlayGames = [
    _GameEntry(
      gameId: 'tictactoe',
      name: 'Tic-Tac-Toe',
      icon: Icons.grid_3x3,
      color: Color(0xFF8B5CF6),
      route: '/family/\$familyId/tictactoe/lobby',
      durationLabel: '~1 min',
      complexity: 1,
    ),
    _GameEntry(
      gameId: 'sos',
      name: 'SOS',
      icon: Icons.grid_on_rounded,
      color: Color(0xFFF59E0B),
      route: '/family/\$familyId/sos/lobby',
      durationLabel: '~2 min',
      complexity: 2,
    ),
    _GameEntry(
      gameId: 'dotsboxes',
      name: 'Dots & Boxes',
      icon: Icons.grid_on_rounded,
      color: Color(0xFF06B6D4),
      route: '/family/\$familyId/dotsboxes/lobby',
      durationLabel: '~2 min',
      complexity: 2,
    ),
    _GameEntry(
      gameId: 'chitmatch',
      name: 'TripleMatch',
      icon: Icons.style_outlined,
      color: Color(0xFFEC4899),
      route: '/family/\$familyId/chitmatch/lobby',
      durationLabel: '~2 min',
      complexity: 2,
    ),
    _GameEntry(
      gameId: 'relation-riddles',
      name: 'Riddles',
      icon: Icons.extension_outlined,
      color: Color(0xFF8B5CF6),
      route: '/family/\$familyId/relation-riddles',
      durationLabel: '~2 min',
      complexity: 1,
    ),
  ];

  static const List<_GameEntry> _classicBoardGames = [
    _GameEntry(
      gameId: 'chess',
      name: 'Chess',
      icon: Icons.castle_outlined,
      color: Color(0xFF64748B),
      route: '/family/\$familyId/chess/lobby',
      durationLabel: '~10 min',
      complexity: 3,
    ),
    _GameEntry(
      gameId: 'checkers',
      name: 'Checkers',
      icon: Icons.grid_on_outlined,
      color: Color(0xFF6366F1),
      route: '/family/\$familyId/checkers/lobby',
      durationLabel: '~8 min',
      complexity: 3,
    ),
    _GameEntry(
      gameId: 'ludo',
      name: 'Ludo',
      icon: Icons.casino_outlined,
      color: Color(0xFFE11D48),
      route: '/family/\$familyId/ludo/lobby',
      durationLabel: '~15 min',
      complexity: 2,
    ),
    _GameEntry(
      gameId: 'carrom',
      name: 'Carrom',
      icon: Icons.sports_esports_rounded,
      color: Color(0xFFF59E0B),
      route: '/family/\$familyId/carrom/lobby',
      durationLabel: '~8 min',
      complexity: 2,
    ),
    _GameEntry(
      gameId: 'bingo',
      name: 'Bingo',
      icon: Icons.grid_view_rounded,
      color: Color(0xFF06B6D4),
      route: '/family/\$familyId/bingo/lobby',
      durationLabel: '~6 min',
      complexity: 1,
    ),
  ];

  static const List<_GameEntry> _familyFunGames = [
    _GameEntry(
      gameId: 'ghost-painter',
      name: 'Ghost Painter',
      icon: Icons.brush_outlined,
      color: Color(0xFFEC4899),
      route: '/family/\$familyId/ghost-painter/draw',
      durationLabel: '~5 min',
      complexity: 2,
    ),
    _GameEntry(
      gameId: 'antakshari',
      name: 'Antakshari',
      icon: Icons.music_note_rounded,
      color: Color(0xFF8B5CF6),
      route: '/family/\$familyId/antakshari/lobby',
      durationLabel: '~5 min',
      complexity: 2,
    ),
    _GameEntry(
      gameId: 'truthordare',
      name: 'Truth or Dare',
      icon: Icons.rotate_right,
      color: Color(0xFFEF4444),
      route: '/family/\$familyId/truthordare/lobby',
      durationLabel: '~5 min',
      complexity: 1,
    ),
    _GameEntry(
      gameId: 'twotruths',
      name: 'Two Truths',
      icon: Icons.psychology,
      color: Color(0xFFD946EF),
      route: '/family/\$familyId/twotruths/lobby',
      durationLabel: '~5 min',
      complexity: 1,
    ),
    _GameEntry(
      gameId: 'nameplace',
      name: 'Name Place Animal',
      icon: Icons.abc_rounded,
      color: Color(0xFF10B981),
      route: '/family/\$familyId/nameplace/lobby',
      durationLabel: '~5 min',
      complexity: 2,
    ),
    _GameEntry(
      gameId: 'freeze-dash',
      name: 'Freeze & Dash',
      icon: Icons.directions_run_rounded,
      color: Color(0xFF10B981),
      route: '/family/\$familyId/freeze-dash/lobby',
      durationLabel: '~3 min',
      complexity: 1,
    ),
    _GameEntry(
      gameId: 'hot-seat',
      name: 'Hot Seat',
      icon: Icons.local_fire_department_outlined,
      color: Color(0xFFF59E0B),
      route: '/family/\$familyId/hot-seat',
      durationLabel: '~5 min',
      complexity: 1,
    ),
  ];

  /// Games that require download-gating (have manifests in game-assets bucket).
  /// Hot Seat and Relation Riddles are native (no download needed).
  static const Set<String> _downloadGatedGames = {
    'ghost-painter',
    'freeze-dash',
    'sos',
    'antakshari',
    'bingo',
    'checkers',
    'ludo',
    'carrom',
    'chess',
    'chitmatch',
    'nameplace',
    'tictactoe',
    'truthordare',
    'twotruths',
    'dotsboxes',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: KinrelSpacing.base,
            vertical: 8,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.sports_esports_outlined,
                size: 18,
                color: KinrelColors.orange,
              ),
              const SizedBox(width: 6),
              const Text(
                'Games',
                style: const TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                ),
              ),
              const Spacer(),
              GestureDetector(
                // "See All" opens the complete Games Catalog (AllGamesScreen)
                // — the same destination as the "Browse all games" link in the
                // Family Arena. Shows all 31 games grouped by category.
                //
                // Do NOT route to /games (GamesHubScreen / Family Arena) here:
                // this _GamesRow is itself rendered INSIDE the Family Arena
                // (via GamesSection → _PremiumGamesRow → premiumGamesRowBridge),
                // so pushing /games would push the same route the user is
                // already on and appear to do nothing.
                onTap: () =>
                    context.push('/family/$familyId/gaming/all-games'),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: const Text(
                    'See All',
                    style: const TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: KinrelColors.orange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // ── Hick's Law: 3 chunked groups, each with a time hint ──────
        _GameGroupHeader(
          emoji: '⚡',
          label: 'Quick Play',
          hint: 'under 2 min',
        ),
        _GamesGroupScroll(
          games: _quickPlayGames,
          familyId: familyId,
        ),
        _GameGroupHeader(
          emoji: '♟️',
          label: 'Classic Board',
          hint: '5+ min',
        ),
        _GamesGroupScroll(
          games: _classicBoardGames,
          familyId: familyId,
        ),
        _GameGroupHeader(
          emoji: '🎉',
          label: 'Family Fun',
          hint: 'creative & party',
        ),
        _GamesGroupScroll(
          games: _familyFunGames,
          familyId: familyId,
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Category header for a Hick's Law game group. The time hint lets users
/// self-select by the time they actually have — the core of reducing
/// choice overload.
class _GameGroupHeader extends StatelessWidget {
  const _GameGroupHeader({
    required this.emoji,
    required this.label,
    required this.hint,
  });

  final String emoji;
  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KinrelSpacing.base + 2, 6, KinrelSpacing.base, 4),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: KinrelColors.orange.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: KinrelColors.orange.withValues(alpha: 0.22),
                width: 0.6,
              ),
            ),
            child: Text(
              hint,
              style: const TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: KinrelColors.orange,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One category's horizontal game scroll. Watches the shared active-games
/// provider so every card can carry a Social Proof micro-label.
class _GamesGroupScroll extends ConsumerWidget {
  const _GamesGroupScroll({
    required this.games,
    required this.familyId,
  });

  final List<_GameEntry> games;
  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Social Proof: live active-game counts per game type.
    final activeAsync = ref.watch(familyActiveGamesProvider(familyId));
    final activeGames = activeAsync.valueOrNull ?? const <ActiveGameInfo>[];
    // Per gameType: active count + the single host name (when count == 1).
    final activeByType = <String, List<ActiveGameInfo>>{};
    for (final g in activeGames) {
      activeByType.putIfAbsent(g.gameType, () => []).add(g);
    }

    return SizedBox(
      height: 124,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.sm),
        itemCount: games.length,
        itemBuilder: (context, index) {
          final game = games[index];
          return _CompactGameCard(
            game: game,
            familyId: familyId,
            isDownloadGated: _GamesRow._downloadGatedGames.contains(game.gameId),
            activePeers: activeByType[game.gameId] ?? const [],
          );
        },
      ),
    );
  }
}

class _GameEntry {
  const _GameEntry({
    required this.gameId,
    required this.name,
    required this.icon,
    required this.color,
    required this.route,
    this.durationLabel,
    this.complexity,
  });
  final String gameId;
  final String name;
  final IconData icon;
  final Color color;
  final String route; // Contains $familyId placeholder

  /// Flow Theory: how long a typical match takes ("~2 min"). Null hides
  /// the label (defensive — every entry above sets one).
  final String? durationLabel;

  /// Flow Theory: 1–3 complexity dots. 1 = pick up instantly,
  /// 3 = needs focus.
  final int? complexity;
}

class _CompactGameCard extends ConsumerWidget {
  const _CompactGameCard({
    required this.game,
    required this.familyId,
    required this.isDownloadGated,
    this.activePeers = const [],
  });
  final _GameEntry game;
  final String familyId;
  final bool isDownloadGated;

  /// Active games of this type right now — powers the Social Proof
  /// micro-label ("👥 3 active" / "Rahul is playing").
  final List<ActiveGameInfo> activePeers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dlState = isDownloadGated
        ? ref.watch(gameDownloadStatusProvider(game.gameId))
        : null;
    final isDownloaded =
        !isDownloadGated || dlState?.status == GameDownloadStatus.downloaded;

    // Social Proof copy: a named person beats a bare count, a count
    // beats nothing.
    final hasActive = activePeers.isNotEmpty;
    final socialLabel = !hasActive
        ? null
        : activePeers.length == 1
            ? '${activePeers.first.hostUserName.split(' ').first} is playing'
            : '👥 ${activePeers.length} active';

    return GestureDetector(
      onTap: () {
        final route = game.route.replaceAll('\$familyId', familyId);
        if (isDownloaded) {
          context.push(route);
        } else {
          context.push('/games?familyId=$familyId');
        }
      },
      child: Container(
        width: 80,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 46,
                height: 46,
                child: GameIcon(
                  gameId: game.gameId,
                  size: 46,
                  color: isDownloaded ? null : KinrelColors.textDim,
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              game.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: isDownloaded
                    ? KinrelColors.textWhite
                    : KinrelColors.textDim,
              ),
            ),
            const SizedBox(height: 2),
            // Flow Theory: duration + 1–3 complexity dots, so users can
            // match a game to the time & focus they have.
            if (game.durationLabel != null || game.complexity != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (game.durationLabel != null)
                    Text(
                      game.durationLabel!,
                      style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 8.5,
                        color: KinrelColors.textDim,
                      ),
                    ),
                  if (game.durationLabel != null && game.complexity != null)
                    const SizedBox(width: 4),
                  if (game.complexity != null) ...[
                    for (var i = 0; i < 3; i++)
                      Container(
                        width: 3.5,
                        height: 3.5,
                        margin: const EdgeInsets.symmetric(horizontal: 0.7),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i < game.complexity!
                              ? KinrelColors.amber
                              : KinrelColors.amber.withValues(alpha: 0.2),
                        ),
                      ),
                  ],
                ],
              ),
            // Social Proof micro-label (Cialdini): "Rahul is playing" /
            // "👥 3 active" — others' activity makes joining feel alive.
            if (socialLabel != null) ...[
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: KinrelColors.tealAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                constraints: const BoxConstraints(maxWidth: 76),
                child: Text(
                  socialLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.tealAccent,
                  ),
                ),
              ),
            ],
            if (isDownloadGated && !isDownloaded)
              const Icon(
                Icons.download_outlined,
                size: 10,
                color: KinrelColors.textDim,
              ),
          ],
        ),
      ),
    );
  }
}

// ── Shared sub-widgets ─────────────────────────────────────────────


class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.icon,
    required this.label,
    this.isDestructive = false,
    this.iconColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isDestructive;
  final Color? iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color =
        iconColor ??
        (isDestructive ? KinrelColors.coral : KinrelColors.textSilver);
    final textColor =
        iconColor ??
        (isDestructive ? KinrelColors.coral : KinrelColors.textWhite);
    return ListTile(
      leading: Icon(icon, color: color, size: 20),
      title: Text(
        label,
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 14,
          color: textColor,
        ),
      ),
      onTap: onTap,
    );
  }
}


// ═══════════════════════════════════════════════════════════════════════
// PREMIUM FAMILY HUB — PUBLIC BRIDGES
//
// The premium redesign (lib/features/family/presentation/premium/)
// needs to access the private _GamesRow and AddPersonSheet.show from
// this file. Rather than making those public (and polluting the
// widget API), we expose two bridge functions at the file level.
// The premium sections import these bridges via a `show` clause.
// ═══════════════════════════════════════════════════════════════════════

/// Bridge to the private _GamesRow for the premium GamesSection.
Widget premiumGamesRowBridge(String familyId) {
  return _GamesRow(familyId: familyId);
}

/// Bridge to AddPersonSheet.show for the premium FamilyPulseSection.
class AddPersonSheetBridge {
  AddPersonSheetBridge._();

  static Future<void> show(
    BuildContext context, {
    required String familyId,
    Person? person,
  }) {
    return AddPersonSheet.show(
      context,
      familyId: familyId,
      existingPerson: person,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// RECENT MOMENTS SECTION ADAPTER
// Bridges crossFeatureMomentsProvider to the new RecentMomentsSection
// widget (defined in premium/family_hub_highlights.dart). Maps each
// CrossFeatureMoment to a CrossFeatureMomentLike (with a Material
// icon instead of the prior emoji) and passes the list to the
// palette-disciplined RecentMomentsSection widget.
//
// This replaces the prior _CrossFeatureMomentsCard which:
//   - Used theme.colorScheme.surfaceContainerHighest (M3 palette, not
//     the Family Hub palette)
//   - Used ✨ emoji in the header (mixed icon language)
//   - Used per-moment emojis (🎙️📸🧠 — also mixed icon language)
// All three are gone now.
// ═══════════════════════════════════════════════════════════════════════

class _RecentMomentsSectionAdapter extends ConsumerWidget {
  const _RecentMomentsSectionAdapter({required this.familyId});
  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final momentsAsync = ref.watch(crossFeatureMomentsProvider(familyId));

    return momentsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (moments) {
        if (moments.isEmpty) return const SizedBox.shrink();

        // Map CrossFeatureMoment (provider model) to
        // CrossFeatureMomentLike (render model). The render model
        // uses a single Material icon per type instead of the prior
        // per-moment emoji, enforcing single-icon-language discipline.
        final likes = moments
            .map((m) => CrossFeatureMomentLike(
                  title: m.title,
                  subtitle: m.subtitle,
                  createdAt: m.createdAt,
                  icon: _iconForType(m.type),
                ))
            .toList();

        return RecentMomentsSection(
          moments: likes,
          onViewAll: () => context.push('/family/$familyId/gaming/activity'),
        );
      },
    );
  }

  /// Single Material icon per moment type — replaces the prior emoji
  /// set (🎙️ / 📸 / 🧠 / ✨). Each type now maps to one Material icon
  /// from the same family used by the Highlights row + Quick Actions
  /// row, so the page reads as a single icon language.
  static IconData _iconForType(String type) {
    switch (type) {
      case 'oral_history':
        return Icons.mic_none_rounded;
      case 'memory_vault':
        return Icons.photo_library_outlined;
      case 'quiz_result':
        return Icons.psychology_outlined;
      default:
        return Icons.history_rounded;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SHARED LIST TILE — quick access to the errand board
// (DEPRECATED — folded into the Highlights row as the "Lists" tile.
// The class definition is kept here temporarily to avoid breaking any
// direct references; the build method above no longer instantiates
// it. Safe to delete in a follow-up cleanup once the Highlights row
// is verified to cover all entry points.)
// ═══════════════════════════════════════════════════════════════════════


// ═══════════════════════════════════════════════════════════════════════
// DISCOVERY GRID
// Wires all orphan modules into the family hub. These screens already
// work — this is purely nav wiring (Phase 15a).
//
// UX pass (Cognitive Load Theory): the most recently used tile now
// carries a "Recent" badge + emphasized styling. Recognizing where you
// were beats re-deciding where to go — prior context lowers the effort
// of the next choice instead of presenting 6 equal options every time.
// ═══════════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════
// Phase 3.30 — Quick Links row (replaces the old _DiscoveryGrid)
// A clean horizontal strip of icon-chips for the 5 remaining
// items: Achievements, Memories, Oral History, Family Intelligence,
// Activity Feed. No grouped headers — just a flat row.
// ═══════════════════════════════════════════════════════════════════════



// v118 — Full-Screen Avatar Viewer with pinch-to-zoom
// ═══════════════════════════════════════════════════════════════════════

/// A full-screen viewer for the family profile picture with pinch-to-zoom
/// support. Shown to ALL users (admin + regular) when they want to view
/// the avatar. Has NO edit controls — regular members see this directly
/// on tap; admins see it via the "View Profile Picture" menu option.
class _FullScreenAvatarViewer extends StatelessWidget {
  const _FullScreenAvatarViewer({
    required this.imageUrl,
    required this.familyName,
  });

  final String imageUrl;
  final String familyName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          familyName,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          boundaryMargin: const EdgeInsets.all(double.infinity),
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            cacheManager: KinrelImageCacheManager.instance,
            fit: BoxFit.contain,
            // Full-screen avatar viewer: cap decode width to screen
            // width × DPR so we don't hold a 4K decode in memory.
            memCacheWidth: (MediaQuery.of(context).size.width *
                    MediaQuery.of(context).devicePixelRatio)
                .toInt(),
            placeholder: (context, url) => const Center(
              child: CircularProgressIndicator(
                color: Colors.white,
              ),
            ),
            errorWidget: (_, __, ___) => const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.broken_image_outlined,
                    size: 64,
                    color: Colors.white54,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Could not load image',
                    style: TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
