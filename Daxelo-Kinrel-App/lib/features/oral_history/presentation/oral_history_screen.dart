import 'package:kinrel/core/widgets/global_error_widget.dart';
// lib/features/oral_history/presentation/oral_history_screen.dart
//
// DAXELO KINREL — Oral History & Story Recording Screen
//
// Family voice-note recording. Captures family narratives, traditions,
// recipes, wisdom, and migration stories as audio recordings persisted
// to Supabase Storage with metadata in the AncestralMemory table.
//
// v93 (transcription removal + recording/playback correctness):
//   - Transcription UI REMOVED: the "Transcribed" badge on cards, the
//     "X Transcribed" dashboard stat, the "AI Transcription" toggle in
//     the save dialog, the transcript view in the story detail player,
//     and the "Translate to English" toggle are all gone. The language
//     tag (HI/EN) is KEPT — it labels what language the recording is
//     in, independent of transcription (useful metadata on its own).
//   - Recording: real mic permission flow via permission_handler with
//     an actionable error banner if denied. Real waveform via the
//     record package's onAmplitudeChanged stream. Real upload to
//     Supabase Storage on save, with retry on failure.
//   - Playback: REAL audio playback via just_audio (see
//     oral_history_audio_player.dart) — streams the actual stored
//     audio file, discovers the real duration via durationStream,
//     tracks the real position via positionStream, surfaces buffering
//     and error states. Replaces the previous fake Timer-based
//     "playback" that simulated progress with no actual audio.
//   - Empty states: two distinct states (zero-total vs zero-filtered)
//     using the shared KinrelEmptyState "invitation to act" pattern.
//     Stats dashboard only renders when there are stories; Languages
//     and Categories charts compute from filteredStories so no zero-
//     width placeholder bars; Most Played hidden until at least one
//     story has been played.
//   - Seed data: the "Sharma family" demo stories (How Dada Built
//     Sharma Haveli, Dadi's Secret Ghevar Recipe, The Night We Left
//     Lahore, etc.) are NOT loaded by default — real families see the
//     empty-state invitation-to-act. Demo data is available via
//     `OralHistoryNotifier.loadDemoData()` for tests/debug only.
//
// Orange K-Graph DNA: #13141E bg, #191B2C cards, #E8612A accent,
// ignite gradient (#E8612A → #F59240), glow effects.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_tokens.dart' show AppMotion;
import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../shared/widgets/animated_preview_card.dart';
import '../../../shared/widgets/app_scroll_safe_area.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../../shared/widgets/kinrel_empty_state.dart';
import '../providers/oral_history_provider.dart';
import 'oral_history_audio_player.dart';

// ═══════════════════════════════════════════════════════════════════════
// Oral History Screen
// ═══════════════════════════════════════════════════════════════════════

class OralHistoryScreen extends ConsumerStatefulWidget {
  const OralHistoryScreen({super.key, this.familyId = ''});

  /// v96: the familyId for the current family context, passed via
  /// the route's query parameter (`/oral-history?familyId=...`). Used
  /// by the back button to navigate to `/family/$familyId` (Family
  /// Space). Empty string if no familyId was passed (the back button
  /// falls back to `context.pop()` in that case).
  final String familyId;

  @override
  ConsumerState<OralHistoryScreen> createState() => _OralHistoryScreenState();
}

class _OralHistoryScreenState extends ConsumerState<OralHistoryScreen>
    with TickerProviderStateMixin {
  late AnimationController _fabController;
  StoryModel? _selectedStory;
  bool _showPlayer = false;

  @override
  void initState() {
    super.initState();
    _fabController = AnimationController(
      vsync: this,
      duration: KinrelMotion.slow,
    )..forward();

    // ── Database wiring: auto-load stories from Supabase ────────────
    // Pre-fix, the provider started empty and never fetched — saved
    // stories were invisible across sessions. Now we load on screen
    // open so previously-recorded stories reappear.
    if (widget.familyId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref
            .read(oralHistoryProvider.notifier)
            .loadStories(familyId: widget.familyId);
      });
    }
  }

  @override
  void dispose() {
    _fabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(oralHistoryProvider);
    final filteredStories = state.filteredStories;

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      body: Stack(
        children: [
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ── Header ────────────────────────────────────────────
              SliverToBoxAdapter(child: _buildHeader(state)),

              // ── Recording error banner (mic denied / upload failed) ─
              // v93: surfaces a clear, actionable error from the
              // recording state. The user can dismiss or "Open Settings"
              // (for permanently-denied mic permission) or "Retry" (for
              // transient errors like upload failure).
              if (state.recordingState.error != null)
                SliverToBoxAdapter(
                  child: _RecordingErrorBanner(
                    message: state.recordingState.error!,
                    isPermissionDenied: state.recordingState.permissionDenied,
                    onDismiss: () => ref
                        .read(oralHistoryProvider.notifier)
                        .clearRecordingError(),
                    onOpenSettings: () => openAppSettings(),
                    onRetry: () => _startRecording(),
                  ),
                ),

              // ── Search Bar (only when there are stories OR an active
              //    filter/search — for a brand-new family with zero
              //    stories, the empty state invites the user to record
              //    their first memory instead of presenting unpopulated
              //    search UI). ─────────────────────────────────────────
              if (state.hasStories || state.pillsActive)
                SliverToBoxAdapter(child: _buildSearchBar(state)),

              // ── Category Filter Chips ─────────────────────────────
              if (state.hasStories || state.pillsActive)
                SliverToBoxAdapter(child: _buildCategoryChips(state)),

              // ── Dashboard (only when there are stories — for a
              //    brand-new family with zero stories, the empty state
              //    replaces the dashboard+list layout entirely, no
              //    all-zero stats dashboard above an empty list). ───
              if (state.hasStories)
                SliverToBoxAdapter(child: _buildDashboard(state)),

              // ── Recently Added (only when there are stories) ─────
              if (state.hasStories)
                SliverToBoxAdapter(child: _buildRecentlyAdded(state)),

              // ── Stories List ──────────────────────────────────────
              // Two distinct empty states:
              //   • !hasStories → "No stories yet — record your family's
              //     first memory" (invitation to act)
              //   • hasStories && filteredStories.isEmpty → "No stories
              //     match your filters" (clear path back to all stories)
              if (!state.hasStories)
                SliverToBoxAdapter(child: _buildEmptyStateZeroStories())
              else if (filteredStories.isEmpty)
                SliverToBoxAdapter(child: _buildEmptyStateFiltered(state))
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    return _StoryCard(
                      story: filteredStories[index],
                      onTap: () => _openStoryDetail(filteredStories[index]),
                      onFavorite: () => ref
                          .read(oralHistoryProvider.notifier)
                          .toggleFavorite(filteredStories[index].id),
                      onLongPress: () =>
                          _showStoryOptions(filteredStories[index]),
                    );
                  }, childCount: filteredStories.length),
                ),

              // ── Scroll safe-area padding ──────────────────────────
              // Shared widget — encodes the ADR-007 pattern so the last
              // card never clips under the FAB or the gesture-nav inset.
              // chromeHeight 56 = FAB only (no floating nav on this
              // screen). See lib/shared/widgets/app_scroll_safe_area.dart.
              AppScrollSafeArea.sliver(chromeHeight: 56),
            ],
          ),

          // ── Recording FAB ─────────────────────────────────────────
          // v96: HIDE the FAB when the family has ZERO stories (true
          // empty state) — the empty-state block's own "Record First
          // Story" CTA is the only add action shown in that case,
          // avoiding redundancy. Once at least one story exists
          // (populated list OR filtered-empty), the FAB reappears so
          // the user can record more from anywhere on the screen.
          // Also hidden while a recording session is active (the
          // recording bottom sheet replaces the FAB in that case).
          if (!state.recordingState.isActive && state.hasStories)
            Positioned(
              right: KinrelSpacing.base,
              bottom: MediaQuery.of(context).padding.bottom + 24,
              child: _buildRecordingFAB(),
            ),

          // ── Recording Bottom Sheet ────────────────────────────────
          if (state.recordingState.isActive)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _RecordingBottomSheet(
                recordingState: state.recordingState,
                selectedLanguage: state.selectedLanguage,
                onPause: () =>
                    ref.read(oralHistoryProvider.notifier).pauseRecording(),
                onResume: () =>
                    ref.read(oralHistoryProvider.notifier).resumeRecording(),
                onStop: () => _onStopRecording(),
                onCancel: () => _onCancelRecording(),
                onLanguageSelect: (code) => ref
                    .read(oralHistoryProvider.notifier)
                    .setSelectedLanguage(code),
              ),
            ),

          // ── Story Detail / Player ─────────────────────────────────
          if (_showPlayer && _selectedStory != null)
            Positioned.fill(
              child: _StoryDetailPlayer(
                story: _selectedStory!,
                onClose: () {
                  setState(() {
                    _showPlayer = false;
                    _selectedStory = null;
                  });
                },
              ),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Header
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildHeader(OralHistoryState state) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KinrelSpacing.base,
        KinrelSpacing.xl,
        KinrelSpacing.base,
        KinrelSpacing.sm,
      ),
      child: Row(
        children: [
          // v96: Back button — navigates to the Family Space screen
          // for the current family context. Uses context.go (not
          // context.pop) so it always lands on the correct Family
          // Space screen regardless of navigation history. Falls
          // back to context.pop() if no familyId was passed.
          GestureDetector(
            onTap: () {
              if (widget.familyId.isNotEmpty) {
                context.go('/family/${widget.familyId}');
              } else if (context.canPop()) {
                context.pop();
              }
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: KinrelColors.darkCard,
              ),
              child: const Icon(
                Icons.arrow_back_rounded,
                color: KinrelColors.textWhite,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: KinrelSpacing.sm),
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: KinrelColors.orange.withValues(alpha: 0.15),
            ),
            child: const Icon(
              Icons.mic_rounded,
              color: KinrelColors.orange,
              size: 22,
            ),
          ),
          const SizedBox(width: KinrelSpacing.md),
          Expanded(
            child: Text(
              'Oral History',
              style: KinrelTypography.headlineLarge.copyWith(
                color: KinrelColors.textWhite,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          // Favorite count
          if (state.favoriteCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                gradient: KinrelGradients.igniteGradient,
                borderRadius: BorderRadius.circular(KinrelRadius.full),
                boxShadow: [
                  const BoxShadow(
                    color: KinrelColors.orangeGlow,
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.favorite_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${state.favoriteCount}',
                    style: KinrelTypography.labelSmall.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Search Bar
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildSearchBar(OralHistoryState state) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KinrelSpacing.base,
        KinrelSpacing.sm,
        KinrelSpacing.base,
        KinrelSpacing.sm,
      ),
      child: DKSearchField(
        hint: 'Search stories, narrators, tags...',
        onChanged: (query) =>
            ref.read(oralHistoryProvider.notifier).setSearchQuery(query),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Category Filter Chips
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildCategoryChips(OralHistoryState state) {
    final categories = [
      null, // All
      StoryCategory.familyHistory,
      StoryCategory.lifeEvent,
      StoryCategory.tradition,
      StoryCategory.recipe,
      StoryCategory.wisdom,
      StoryCategory.migration,
      StoryCategory.celebration,
    ];

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = categories[index];
          final isActive = state.filter == category;
          final label = category == null ? 'All' : category.shortLabel;
          final accent = category?.accentColor ?? KinrelColors.orange;

          return GestureDetector(
            onTap: () =>
                ref.read(oralHistoryProvider.notifier).setFilter(category),
            child: AnimatedContainer(
              duration: KinrelMotion.fast,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isActive
                    ? accent.withValues(alpha: 0.2)
                    : KinrelColors.darkCard,
                borderRadius: BorderRadius.circular(KinrelRadius.full),
                border: Border.all(
                  color: isActive
                      ? accent.withValues(alpha: 0.5)
                      : const Color(0xFF3A3A4A),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (category != null) ...[
                    Icon(
                      category.icon,
                      size: 14,
                      color: isActive ? accent : KinrelColors.textDim,
                    ),
                    const SizedBox(width: 5),
                  ],
                  if (category == null)
                    Icon(
                      Icons.apps_rounded,
                      size: 14,
                      color: isActive ? accent : KinrelColors.textDim,
                    ),
                  if (category == null) const SizedBox(width: 5),
                  Text(
                    label,
                    style: KinrelTypography.labelSmall.copyWith(
                      color: isActive ? accent : KinrelColors.textSilver,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Story Collection Dashboard
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildDashboard(OralHistoryState state) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KinrelSpacing.base,
        KinrelSpacing.md,
        KinrelSpacing.base,
        KinrelSpacing.sm,
      ),
      child: Container(
        padding: const EdgeInsets.all(KinrelSpacing.base),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
          border: Border.all(color: const Color(0xFF3A3A4A), width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Stats Row ────────────────────────────────────────
            // v93: removed "Transcribed" stat (transcription soft-disabled).
            // Replaced with "Narrators" stat (number of distinct family
            // members who've recorded) — a more meaningful metric that
            // gives the user a sense of how many voices are preserved
            // in their family's oral history. Three stats keeps the
            // balanced row layout (no awkward gap from a missing card).
            Row(
              children: [
                _DashboardStat(
                  icon: Icons.auto_stories_rounded,
                  value: '${state.storyCount}',
                  label: 'Stories',
                  color: KinrelColors.orange,
                ),
                const SizedBox(width: 16),
                _DashboardStat(
                  icon: Icons.timer_rounded,
                  value: _formatTotalDuration(state.totalDuration),
                  label: 'Total Time',
                  color: KinrelColors.amber,
                ),
                const SizedBox(width: 16),
                _DashboardStat(
                  icon: Icons.record_voice_over_rounded,
                  value: '${state.narratorCount}',
                  label: 'Narrators',
                  color: KinrelColors.success,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Language Distribution ─────────────────────────────
            // v93: languageDistribution now computes from filteredStories,
            // so this only renders for languages that have at least one
            // story in the current filter context — no zero-width bars.
            if (state.languageDistribution.isNotEmpty) ...[
              Text(
                'Languages',
                style: KinrelTypography.labelMedium.copyWith(
                  color: KinrelColors.textSilver,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              _LanguageDistributionChart(
                distribution: state.languageDistribution,
              ),
              const SizedBox(height: 16),
            ],

            // ── Category Distribution ─────────────────────────────
            if (state.categoryDistribution.isNotEmpty) ...[
              Text(
                'Categories',
                style: KinrelTypography.labelMedium.copyWith(
                  color: KinrelColors.textSilver,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              _CategoryDistributionChart(
                distribution: state.categoryDistribution,
              ),
              const SizedBox(height: 12),
            ],

            // ── Most Played ───────────────────────────────────────
            // v93: hidden entirely until at least one story has been
            // played at least once (per the brief — no 0-plays
            // placeholder). Uses [state.hasPlayedStory] which checks
            // whether any story has playCount > 0.
            if (state.hasPlayedStory && state.mostPlayedStory != null) ...[
              const Divider(color: Color(0xFF2A2A3D), height: 1),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(
                    Icons.trending_up_rounded,
                    size: 16,
                    color: KinrelColors.brightGold,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Most Played',
                    style: KinrelTypography.labelMedium.copyWith(
                      color: KinrelColors.brightGold,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _openStoryDetail(state.mostPlayedStory!),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: KinrelColors.darkElevated,
                    borderRadius: BorderRadius.circular(KinrelRadius.md),
                    border: Border.all(
                      color: KinrelColors.brightGold.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: KinrelGradients.igniteGradient,
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              state.mostPlayedStory!.title,
                              style: KinrelTypography.labelMedium.copyWith(
                                color: KinrelColors.textWhite,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${state.mostPlayedStory!.playCount} plays • ${state.mostPlayedStory!.narratorName}',
                              style: KinrelTypography.labelSmall.copyWith(
                                color: KinrelColors.textDim,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Recently Added Horizontal Scroll
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildRecentlyAdded(OralHistoryState state) {
    if (state.recentlyAdded.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KinrelSpacing.base,
        KinrelSpacing.sm,
        0,
        KinrelSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: KinrelSpacing.base),
            child: Text(
              'Recently Added',
              style: KinrelTypography.labelLarge.copyWith(
                color: KinrelColors.textSilver,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 100,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: state.recentlyAdded.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final story = state.recentlyAdded[index];
                return GestureDetector(
                  onTap: () => _openStoryDetail(story),
                  child: Container(
                    width: 200,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: KinrelColors.darkCard,
                      borderRadius: BorderRadius.circular(KinrelRadius.md),
                      border: Border.all(
                        color: story.category.accentColor.withValues(
                          alpha: 0.2,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              story.category.icon,
                              size: 12,
                              color: story.category.accentColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              story.category.shortLabel,
                              style: KinrelTypography.micro.copyWith(
                                color: story.category.accentColor,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              story.durationLabel,
                              style: KinrelTypography.micro.copyWith(
                                color: KinrelColors.textDim,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          story.title,
                          style: KinrelTypography.labelMedium.copyWith(
                            color: KinrelColors.textWhite,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          story.narratorName,
                          style: KinrelTypography.labelSmall.copyWith(
                            color: KinrelColors.textDim,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Empty States
  // ═══════════════════════════════════════════════════════════════════

  /// Zero-total empty state: the family has NO stories at all (the
  /// production default for a brand-new family — see `OralHistoryNotifier`
  /// doc). Uses the shared [KinrelEmptyState] widget which follows the
  /// app-wide "invitation to act" pattern (matching the family list,
  /// presence strip, and memories empty states).
  ///
  /// v95 (animated preview card): the static icon is replaced with
  /// a small, animated live preview of what an Oral History story card
  /// looks like. The preview demonstrates the format with a subtle
  /// waveform-pulse animation (bars gently rising and falling in a
  /// loose rhythm) instead of the Memories screen's photo crossfade
  /// — because Oral History is audio content, not photo content.
  /// The animation respects the platform reduced-motion accessibility
  /// setting (AppMotion.reducedMotion) by showing a single static
  /// waveform shape instead of pulsing. The preview card is wrapped
  /// in a RepaintBoundary so the continuous animation doesn't cause
  /// frame drops elsewhere on the screen (per the jank-audit
  /// principles already established in this app).
  Widget _buildEmptyStateZeroStories() {
    // Returns a BOX widget (not a sliver) — the caller wraps it in
    // SliverToBoxAdapter(child: ...) in the build method's slivers
    // list. The previous version returned SliverToBoxAdapter(...) here,
    // which produced SliverToBoxAdapter(child: SliverToBoxAdapter(...))
    // — a sliver-in-a-box-slot that renders nothing (the inner sliver
    // gets zero size). This is the root cause of the blank-screen bug.
    return KinrelEmptyState(
      // v95: pass an animated preview card as the illustration
      // instead of a static icon. The KinrelEmptyState widget
      // renders the illustration in place of the default icon
      // circle. The preview card is wrapped in a RepaintBoundary
      // so the continuous waveform pulse doesn't cause Flutter to
      // repaint the entire empty state on every animation tick.
      illustration: RepaintBoundary(
        child: _AnimatedStoryPreviewCard(
          reducedMotion: AppMotion.reducedMotion(context),
        ),
      ),
      // `icon` is still required by KinrelEmptyState (used as a
      // fallback if illustration is null). We pass a sensible
      // default that matches the previous static state.
      icon: Icons.mic_rounded,
      title: 'No Stories Yet',
      subtitle:
          "Record your family's first memory — a grandparent's voice, "
          'a treasured recipe, a story from the past — to start building '
          'your oral history together.',
      actionLabel: 'Record First Story',
      onAction: () => _startRecording(),
    );
  }

  /// Zero-filtered empty state: the family HAS stories but the current
  /// category filter or search query returns no matches. Distinct from
  /// the zero-total state — the CTA offers a clear path back (clear the
  /// filter/search) so the user isn't stuck on a dead-end screen.
  Widget _buildEmptyStateFiltered(OralHistoryState state) {
    final hasCategoryFilter = state.filter != null;
    final hasSearch = state.searchQuery.isNotEmpty;
    final title = hasCategoryFilter && hasSearch
        ? 'No Stories Match'
        : hasCategoryFilter
            ? 'No ${state.filter!.label} Stories'
            : 'No Stories Found';
    final subtitle = hasCategoryFilter && hasSearch
        ? "No stories tagged '${state.filter!.label}' match "
            "'${state.searchQuery}'. Try clearing the filter or search."
        : hasCategoryFilter
            ? "No stories in the '${state.filter!.label}' category yet. "
                'Try a different category or clear the filter to see all stories.'
            : "No stories match '${state.searchQuery}'. "
                'Try a different search term.';

    // Returns a BOX widget (not a sliver) — see the note in
    // _buildEmptyStateZeroStories above for the root-cause explanation
    // of the previous SliverToBoxAdapter(child: SliverToBoxAdapter(...))
    // double-wrap that rendered nothing.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: KinrelColors.orange.withValues(alpha: 0.1),
            ),
            child: const Icon(
              Icons.search_off_rounded,
              size: 40,
              color: KinrelColors.orange,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: KinrelTypography.headlineMedium.copyWith(
              color: KinrelColors.textWhite,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: KinrelTypography.bodyMedium.copyWith(
              color: KinrelColors.textSilver,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          DKButton(
            label: 'Clear Filters',
            variant: DKButtonVariant.secondary,
            icon: Icons.close_rounded,
            size: DKButtonSize.md,
            onPressed: () {
              ref.read(oralHistoryProvider.notifier).setFilter(null);
              ref.read(oralHistoryProvider.notifier).setSearchQuery('');
            },
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Recording FAB
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildRecordingFAB() {
    return ScaleTransition(
      scale: CurvedAnimation(
        parent: _fabController,
        curve: KinrelMotion.spring,
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(KinrelRadius.full),
          gradient: KinrelGradients.igniteGradient,
          boxShadow: [
            const BoxShadow(
              color: KinrelColors.orangeGlowIntense,
              blurRadius: 20,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(KinrelRadius.full),
            onTap: () => _startRecording(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.mic_rounded, color: Colors.white, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Record Story',
                    style: KinrelTypography.labelLarge.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Recording Flow
  // ═══════════════════════════════════════════════════════════════════

  void _startRecording() {
    // v93: clear any previous error so the recording UI doesn't show
    // a stale error banner from a previous failed attempt.
    ref.read(oralHistoryProvider.notifier).clearRecordingError();
    ref.read(oralHistoryProvider.notifier).startRecording();
  }

  void _onStopRecording() async {
    final notifier = ref.read(oralHistoryProvider.notifier);
    // Show saving animation while the user transitions from the
    // recording bottom sheet to the save dialog. The actual upload
    // happens later when the user taps "Save Story" in the dialog.
    notifier.setRecordingSaving(true);
    await Future.delayed(const Duration(milliseconds: 800));
    notifier.setRecordingSaving(false);
    final duration = await notifier.stopRecording();
    _showSaveStoryDialog(duration);
  }

  void _onCancelRecording() {
    // v93: cancel (not stop) — the user explicitly chose not to save,
    // so delete the orphaned recording file and reset state. This
    // prevents the working directory from accumulating orphaned .m4a
    // files from abandoned recording sessions.
    ref.read(oralHistoryProvider.notifier).cancelRecording();
  }

  // ═══════════════════════════════════════════════════════════════════
  // Save Story Dialog
  // ═══════════════════════════════════════════════════════════════════

  void _showSaveStoryDialog(Duration recordedDuration) {
    final titleController = TextEditingController();
    final eraController = TextEditingController();
    final tagsController = TextEditingController();
    StoryCategory selectedCategory = StoryCategory.familyHistory;
    String selectedNarrator = 'Self';
    // v93: removed `shouldTranscribe` flag (transcription soft-disabled).

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.xxl),
        ),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            // Auto-suggest era based on narrator
            final suggestedEra = suggestedEraForNarrator(selectedNarrator);
            // Suggested tags based on category
            final suggestedTags = suggestedTagsForCategory(selectedCategory);

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(KinrelSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Handle ──────────────────────────────────────
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFF3A3A4A),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Title ──────────────────────────────────────
                    Text(
                      'Save Story',
                      style: KinrelTypography.headlineLarge.copyWith(
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Duration: ${_formatDuration(recordedDuration)}',
                      style: KinrelTypography.bodyMedium.copyWith(
                        color: KinrelColors.orange,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── Story Title Input ──────────────────────────
                    Text(
                      'Story Title',
                      style: KinrelTypography.labelLarge.copyWith(
                        color: KinrelColors.textSilver,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: titleController,
                      style: KinrelTypography.bodyLarge.copyWith(
                        color: KinrelColors.textWhite,
                      ),
                      decoration: InputDecoration(
                        hintText: 'e.g., How Dadi Came to Jaipur',
                        hintStyle: KinrelTypography.bodyMedium.copyWith(
                          color: KinrelColors.textDim,
                        ),
                        filled: true,
                        fillColor: KinrelColors.darkElevated,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(KinrelRadius.md),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(KinrelRadius.md),
                          borderSide: const BorderSide(
                            color: KinrelColors.orange,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Narrator Selector ──────────────────────────
                    Text(
                      'Narrator',
                      style: KinrelTypography.labelLarge.copyWith(
                        color: KinrelColors.textSilver,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: KinrelColors.darkElevated,
                        borderRadius: BorderRadius.circular(KinrelRadius.md),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedNarrator,
                          isExpanded: true,
                          dropdownColor: KinrelColors.darkElevated,
                          style: KinrelTypography.bodyMedium.copyWith(
                            color: KinrelColors.textWhite,
                          ),
                          items:
                              [
                                    'Self',
                                    'Kamla Sharma (Dadi)',
                                    'Ravi Sharma (Papa)',
                                    'Sunita Sharma (Mummy)',
                                    'Saroj Devi (Nani)',
                                  ]
                                  .map(
                                    (n) => DropdownMenuItem(
                                      value: n,
                                      child: Text(n),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setModalState(() {
                                selectedNarrator = v;
                                // Auto-suggest era
                                final era = suggestedEraForNarrator(v);
                                if (era != null && eraController.text.isEmpty) {
                                  eraController.text = era;
                                }
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Category Selector ──────────────────────────
                    Text(
                      'Category',
                      style: KinrelTypography.labelLarge.copyWith(
                        color: KinrelColors.textSilver,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: StoryCategory.values.map((cat) {
                        final isActive = selectedCategory == cat;
                        return GestureDetector(
                          onTap: () {
                            setModalState(() => selectedCategory = cat);
                          },
                          child: AnimatedContainer(
                            duration: KinrelMotion.fast,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? cat.accentColor.withValues(alpha: 0.2)
                                  : KinrelColors.darkElevated,
                              borderRadius: BorderRadius.circular(
                                KinrelRadius.full,
                              ),
                              border: Border.all(
                                color: isActive
                                    ? cat.accentColor.withValues(alpha: 0.5)
                                    : const Color(0xFF3A3A4A),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  cat.icon,
                                  size: 14,
                                  color: isActive
                                      ? cat.accentColor
                                      : KinrelColors.textDim,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  cat.shortLabel,
                                  style: KinrelTypography.labelSmall.copyWith(
                                    color: isActive
                                        ? cat.accentColor
                                        : KinrelColors.textSilver,
                                    fontWeight: isActive
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // ── Era Input ──────────────────────────────────
                    Row(
                      children: [
                        Text(
                          'Era / Time Period',
                          style: KinrelTypography.labelLarge.copyWith(
                            color: KinrelColors.textSilver,
                          ),
                        ),
                        if (suggestedEra != null) ...[
                          const Spacer(),
                          GestureDetector(
                            onTap: () {
                              setModalState(() {
                                eraController.text = suggestedEra;
                              });
                            },
                            child: Text(
                              'Suggested: $suggestedEra',
                              style: KinrelTypography.labelSmall.copyWith(
                                color: KinrelColors.orange,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: eraController,
                      style: KinrelTypography.bodyLarge.copyWith(
                        color: KinrelColors.textWhite,
                      ),
                      decoration: InputDecoration(
                        hintText: 'e.g., 1960s, Partition Era, 2020s',
                        hintStyle: KinrelTypography.bodyMedium.copyWith(
                          color: KinrelColors.textDim,
                        ),
                        filled: true,
                        fillColor: KinrelColors.darkElevated,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(KinrelRadius.md),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(KinrelRadius.md),
                          borderSide: const BorderSide(
                            color: KinrelColors.orange,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Tags Input with Suggestions ────────────────
                    Text(
                      'Tags (comma separated)',
                      style: KinrelTypography.labelLarge.copyWith(
                        color: KinrelColors.textSilver,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: tagsController,
                      style: KinrelTypography.bodyLarge.copyWith(
                        color: KinrelColors.textWhite,
                      ),
                      decoration: InputDecoration(
                        hintText: 'e.g., family, Jaipur, tradition',
                        hintStyle: KinrelTypography.bodyMedium.copyWith(
                          color: KinrelColors.textDim,
                        ),
                        filled: true,
                        fillColor: KinrelColors.darkElevated,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(KinrelRadius.md),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(KinrelRadius.md),
                          borderSide: const BorderSide(
                            color: KinrelColors.orange,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Suggested tags
                    Text(
                      'Suggested:',
                      style: KinrelTypography.labelSmall.copyWith(
                        color: KinrelColors.textDim,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: suggestedTags.map((tag) {
                        return GestureDetector(
                          onTap: () {
                            final current = tagsController.text;
                            final existing = current
                                .split(',')
                                .map((t) => t.trim())
                                .where((t) => t.isNotEmpty)
                                .toList();
                            if (!existing.contains(tag)) {
                              tagsController.text = existing.isEmpty
                                  ? tag
                                  : '$current, $tag';
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: KinrelColors.orange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(
                                KinrelRadius.full,
                              ),
                              border: Border.all(
                                color: KinrelColors.orange.withValues(
                                  alpha: 0.2,
                                ),
                              ),
                            ),
                            child: Text(
                              '+ $tag',
                              style: KinrelTypography.micro.copyWith(
                                color: KinrelColors.orange,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),

                    // v93: removed "AI Transcription" toggle (transcription
                    // is soft-disabled). The save dialog now goes straight
                    // from the language picker to the Save/Cancel buttons.
                    const SizedBox(height: 28),

                    // ── Save / Cancel Buttons ──────────────────────
                    // v93: Save now calls OralHistoryNotifier.saveStory
                    // which uploads the recorded audio to Supabase
                    // Storage 'voice-messages' bucket, inserts an
                    // AncestralMemory row, and adds the story to the
                    // in-memory list. On failure, recordingState.error
                    // is set and the recording error banner surfaces
                    // with a retry path (no silent data loss).
                    Row(
                      children: [
                        Expanded(
                          child: DKButton(
                            label: 'Cancel',
                            variant: DKButtonVariant.secondary,
                            size: DKButtonSize.lg,
                            onPressed: () => Navigator.pop(context),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DKButton(
                            label: 'Save Story',
                            variant: DKButtonVariant.gradient,
                            icon: Icons.save_rounded,
                            size: DKButtonSize.lg,
                            onPressed: () async {
                              final title = titleController.text.trim();
                              if (title.isEmpty) return;

                              final tags = tagsController.text
                                  .split(',')
                                  .map((t) => t.trim())
                                  .where((t) => t.isNotEmpty)
                                  .toList();

                              final narratorName = selectedNarrator == 'Self'
                                  ? 'You'
                                  : selectedNarrator.split('(').first.trim();

                              // Close the bottom sheet immediately so
                              // the user sees the upload progress on the
                              // main screen. The actual upload happens
                              // in saveStory() — on success, the story
                              // appears in the list; on failure, the
                              // recording error banner surfaces with a
                              // retry path.
                              Navigator.pop(context);

                              // Show the saving indicator while uploading.
                              ref
                                  .read(oralHistoryProvider.notifier)
                                  .setRecordingSaving(true);

                              final savedStory = await ref
                                  .read(oralHistoryProvider.notifier)
                                  .saveStory(
                                    title: title,
                                    narratorName: narratorName,
                                    category: selectedCategory,
                                    recordedDuration: recordedDuration,
                                    description: null,
                                    era: eraController.text.trim().isEmpty
                                        ? null
                                        : eraController.text.trim(),
                                    tags: tags,
                                    // ── Database wiring: pass the familyId ──
                                    // Pre-fix, familyId was NOT passed, so
                                    // saveStory always fell into the
                                    // "skip DB insert, in-memory only" branch.
                                    // Now the story persists to AncestralMemory.
                                    familyId: widget.familyId,
                                  );

                              // setRecordingSaving(false) is called by
                              // saveStory on both success (resets
                              // recordingState) and failure (sets error).
                              // If saveStory returned null, the error is
                              // already in recordingState.error and the
                              // banner will show. No silent failure.
                              if (savedStory == null) {
                                // Recording state already has error set —
                                // the banner surfaces it with retry.
                                debugPrint(
                                    '⚠️ OralHistory: saveStory returned null — error banner will show');
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Story Detail / Player
  // ═══════════════════════════════════════════════════════════════════

  void _openStoryDetail(StoryModel story) {
    // v93: play count is now incremented by OralHistoryAudioPlayer when
    // the user actually taps Play (not when they just open the detail).
    // Previously this incremented on every detail-open which inflated
    // the count even when the user backed out without listening.
    setState(() {
      _selectedStory = story;
      _showPlayer = true;
    });
  }

  // ═══════════════════════════════════════════════════════════════════
  // Story Options (Long Press)
  // ═══════════════════════════════════════════════════════════════════

  void _showStoryOptions(StoryModel story) {
    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.xxl),
        ),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(KinrelSpacing.base),
                child: Text(
                  story.title,
                  style: KinrelTypography.headlineMedium.copyWith(
                    color: KinrelColors.textWhite,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Divider(color: Color(0xFF2A2A3D), height: 1),
              ListTile(
                leading: const Icon(
                  Icons.play_circle_rounded,
                  color: KinrelColors.orange,
                ),
                title: Text(
                  'Play Story',
                  style: KinrelTypography.bodyLarge.copyWith(
                    color: KinrelColors.textWhite,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _openStoryDetail(story);
                },
              ),
              ListTile(
                leading: Icon(
                  story.isFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: KinrelColors.coral,
                ),
                title: Text(
                  story.isFavorite
                      ? 'Remove from Favorites'
                      : 'Add to Favorites',
                  style: KinrelTypography.bodyLarge.copyWith(
                    color: KinrelColors.textWhite,
                  ),
                ),
                onTap: () {
                  ref
                      .read(oralHistoryProvider.notifier)
                      .toggleFavorite(story.id);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.share_rounded,
                  color: KinrelColors.amber,
                ),
                title: Text(
                  'Share Story',
                  style: KinrelTypography.bodyLarge.copyWith(
                    color: KinrelColors.textWhite,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _shareStory(story);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_rounded,
                  color: KinrelColors.error,
                ),
                title: Text(
                  'Delete Story',
                  style: KinrelTypography.bodyLarge.copyWith(
                    color: KinrelColors.error,
                  ),
                ),
                onTap: () {
                  ref.read(oralHistoryProvider.notifier).deleteStory(story.id);
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Share Story
  // ═══════════════════════════════════════════════════════════════════

  void _shareStory(StoryModel story) {
    final shareText =
        '''
🎙️ ${story.title}

Narrated by: ${story.narratorName}
Duration: ${story.durationLabel}
Category: ${story.category.label}
${story.era != null ? 'Era: ${story.era}' : ''}
Language: ${story.languageName}
${story.audioUrl != null ? '\nListen: ${story.audioUrl}' : ''}

Shared via Daxelo KinRel — Family Oral History
''';

    Share.share(shareText, subject: story.title);
  }

  // ═══════════════════════════════════════════════════════════════════
  // Utility
  // ═══════════════════════════════════════════════════════════════════

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _formatTotalDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '${d.inMinutes}m';
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Recording Error Banner (v93)
// ═══════════════════════════════════════════════════════════════════════
//
// Surfaces a clear, actionable error from the recording state:
//   • Mic permission denied → "Open Settings" button (permanently denied)
//     or "Retry" button (soft denial)
//   • Upload failed → "Retry" button (transient error)
//   • No recording found → "Record Again" button (calls onRetry which
//     re-invokes _startRecording)
//
// The banner replaces the previous silent failure mode where mic
// permission denial or upload failure left the user with no clear path
// forward (the recording just didn't start or the story just didn't
// save, with no message).

class _RecordingErrorBanner extends StatelessWidget {
  const _RecordingErrorBanner({
    required this.message,
    required this.isPermissionDenied,
    required this.onDismiss,
    required this.onOpenSettings,
    required this.onRetry,
  });

  final String message;
  final bool isPermissionDenied;
  final VoidCallback onDismiss;
  final VoidCallback onOpenSettings;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KinrelSpacing.base,
        KinrelSpacing.sm,
        KinrelSpacing.base,
        KinrelSpacing.sm,
      ),
      child: Container(
        padding: const EdgeInsets.all(KinrelSpacing.base),
        decoration: BoxDecoration(
          color: KinrelColors.coral.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
          border: Border.all(
            color: KinrelColors.coral.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: KinrelColors.coral,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message,
                    style: KinrelTypography.bodySmall.copyWith(
                      color: KinrelColors.textWhite,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Retry button — always shown (works for transient
                      // errors and for soft permission denials where the
                      // user can re-grant permission via the system dialog).
                      GestureDetector(
                        onTap: onRetry,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: KinrelColors.orange.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(KinrelRadius.full),
                          ),
                          child: Text(
                            'Retry',
                            style: KinrelTypography.labelSmall.copyWith(
                              color: KinrelColors.orange,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      // Open Settings — only shown when permission is
                      // permanently denied (the user must grant mic
                      // access in device Settings, not via a retry).
                      if (isPermissionDenied) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: onOpenSettings,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: KinrelColors.darkElevated,
                              borderRadius: BorderRadius.circular(KinrelRadius.full),
                              border: Border.all(
                                color: const Color(0xFF3A3A4A),
                              ),
                            ),
                            child: Text(
                              'Open Settings',
                              style: KinrelTypography.labelSmall.copyWith(
                                color: KinrelColors.textSilver,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Dismiss (x) — clears the error so the banner goes away
            // without retrying (the user can ignore the failure and
            // continue using the rest of the screen).
            GestureDetector(
              onTap: onDismiss,
              child: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: KinrelColors.textDim,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Dashboard Stat Widget
// ═══════════════════════════════════════════════════════════════════════

class _DashboardStat extends StatelessWidget {
  const _DashboardStat({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 4),
            Text(
              value,
              style: KinrelTypography.headlineSmall.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              label,
              style: KinrelTypography.micro.copyWith(
                color: KinrelColors.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Language Distribution Chart
// ═══════════════════════════════════════════════════════════════════════

class _LanguageDistributionChart extends StatelessWidget {
  const _LanguageDistributionChart({required this.distribution});

  final Map<String, int> distribution;

  @override
  Widget build(BuildContext context) {
    if (distribution.isEmpty) return const SizedBox.shrink();
    final maxCount = distribution.values.reduce((a, b) => a > b ? a : b);
    final entries = distribution.entries.toList();

    return Column(
      children: entries.map((entry) {
        final lang = kSupportedLanguages
            .where((l) => l.code == entry.key)
            .firstOrNull;
        final name = lang?.name ?? entry.key;
        final ratio = entry.value / maxCount;
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              SizedBox(
                width: 60,
                child: Text(
                  name,
                  style: KinrelTypography.labelSmall.copyWith(
                    color: KinrelColors.textDim,
                  ),
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      height: 14,
                      decoration: BoxDecoration(
                        color: KinrelColors.darkElevated,
                        borderRadius: BorderRadius.circular(7),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: ratio,
                      child: Container(
                        height: 14,
                        decoration: BoxDecoration(
                          gradient: KinrelGradients.igniteGradient,
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${entry.value}',
                style: KinrelTypography.micro.copyWith(
                  color: KinrelColors.orange,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Category Distribution Chart
// ═══════════════════════════════════════════════════════════════════════

class _CategoryDistributionChart extends StatelessWidget {
  const _CategoryDistributionChart({required this.distribution});

  final Map<StoryCategory, int> distribution;

  @override
  Widget build(BuildContext context) {
    if (distribution.isEmpty) return const SizedBox.shrink();
    final total = distribution.values.fold(0, (a, b) => a + b);

    return Row(
      children: distribution.entries.map((entry) {
        final ratio = entry.value / total;
        return Expanded(
          flex: (ratio * 100).round().clamp(1, 100),
          child: Container(
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: entry.key.accentColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Story Card
// ═══════════════════════════════════════════════════════════════════════

class _StoryCard extends StatelessWidget {
  const _StoryCard({
    required this.story,
    required this.onTap,
    required this.onFavorite,
    required this.onLongPress,
  });

  final StoryModel story;
  final VoidCallback onTap;
  final VoidCallback onFavorite;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            margin: const EdgeInsets.fromLTRB(
              KinrelSpacing.base,
              KinrelSpacing.sm,
              KinrelSpacing.base,
              KinrelSpacing.sm,
            ),
            padding: const EdgeInsets.all(KinrelSpacing.base),
            decoration: BoxDecoration(
              color: KinrelColors.darkCard,
              borderRadius: BorderRadius.circular(KinrelRadius.lg),
              border: story.isFavorite
                  ? Border.all(
                      color: KinrelColors.orange.withValues(alpha: 0.35),
                      width: 1.5,
                    )
                  : null,
              boxShadow: story.isFavorite
                  ? [
                      const BoxShadow(
                        color: KinrelColors.orangeGlowSubtle,
                        blurRadius: 12,
                        offset: Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Top Row: Category + Era + Favorite ──────────────────
                Row(
                  children: [
                    // Category tag
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: story.category.accentColor.withValues(
                          alpha: 0.15,
                        ),
                        borderRadius: BorderRadius.circular(KinrelRadius.xs),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            story.category.icon,
                            size: 12,
                            color: story.category.accentColor,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            story.category.shortLabel,
                            style: KinrelTypography.micro.copyWith(
                              color: story.category.accentColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Era tag
                    if (story.era != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: KinrelColors.amber.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(KinrelRadius.xs),
                        ),
                        child: Text(
                          story.era!,
                          style: KinrelTypography.micro.copyWith(
                            color: KinrelColors.amber,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    const Spacer(),
                    // Language indicator
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: KinrelColors.info.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(KinrelRadius.xs),
                      ),
                      child: Text(
                        story.language.toUpperCase(),
                        style: KinrelTypography.micro.copyWith(
                          color: KinrelColors.info,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Favorite heart
                    GestureDetector(
                      onTap: onFavorite,
                      child: Icon(
                        story.isFavorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 20,
                        color: story.isFavorite
                            ? KinrelColors.coral
                            : KinrelColors.textDim,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // ── Story Title ─────────────────────────────────────────
                Text(
                  story.title,
                  style: KinrelTypography.headlineSmall.copyWith(
                    color: KinrelColors.textWhite,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),

                // ── Narrator + Duration ─────────────────────────────────
                Row(
                  children: [
                    DKAvatar(
                      initials: story.narratorInitials,
                      size: DKAvatarSize.sm,
                      backgroundColor: story.category.accentColor.withValues(
                        alpha: 0.2,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        story.narratorName,
                        style: KinrelTypography.bodyMedium.copyWith(
                          color: KinrelColors.textSilver,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Duration badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: KinrelColors.darkElevated,
                        borderRadius: BorderRadius.circular(KinrelRadius.full),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.timer_rounded,
                            size: 12,
                            color: KinrelColors.amber,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            story.durationLabel,
                            style: KinrelTypography.labelSmall.copyWith(
                              color: KinrelColors.amber,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // ── Waveform Preview + Play Button ──────────────────────
                Row(
                  children: [
                    // Waveform from story data
                    Expanded(
                      child: _WaveformPreview(
                        accentColor: story.category.accentColor,
                        barCount: 40,
                        waveformData: story.effectiveWaveformData.sublist(
                          0,
                          40.clamp(0, story.effectiveWaveformData.length),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Play button
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: KinrelGradients.igniteGradient,
                        boxShadow: [
                          BoxShadow(
                            color: KinrelColors.orangeGlow,
                            blurRadius: 10,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ],
                ),

                // ── Tags Row ────────────────────────────────────────────
                if (story.tags.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 22,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: story.tags.length > 4 ? 4 : story.tags.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 4),
                      itemBuilder: (context, index) {
                        final tag = story.tags[index];
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            color: KinrelColors.darkElevated,
                            borderRadius: BorderRadius.circular(
                              KinrelRadius.xs,
                            ),
                          ),
                          child: Text(
                            '#$tag',
                            style: KinrelTypography.micro.copyWith(
                              color: KinrelColors.textDim,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],

                // ── Play count row ──────────────────────────────────────
                // v93: removed the "Transcribed" badge (transcription
                // soft-disabled). The play count is now the only
                // engagement metric shown on the card. The count
                // reflects real playback events persisted to
                // AncestralMemory.listenCount (see
                // OralHistoryNotifier.incrementPlayCount).
                if (story.playCount > 0) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.headphones_rounded,
                        size: 14,
                        color: KinrelColors.textDim,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Played ${story.playCount}x',
                        style: KinrelTypography.labelSmall.copyWith(
                          color: KinrelColors.textDim,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        )
        .animate()
        .fadeIn(duration: KinrelMotion.normal)
        .slideX(begin: 0.05, end: 0, duration: KinrelMotion.normal);
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Waveform Preview (Decorative)
// ═══════════════════════════════════════════════════════════════════════

class _WaveformPreview extends StatelessWidget {
  const _WaveformPreview({
    required this.accentColor,
    this.barCount = 30,
    this.waveformData = const [],
  });

  final Color accentColor;
  final int barCount;
  final List<double> waveformData;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(barCount, (index) {
          double height;
          double opacity;
          if (index < waveformData.length) {
            height = 6.0 + waveformData[index] * 22.0;
            opacity = 0.3 + waveformData[index] * 0.5;
          } else {
            // Generate pseudo-random heights
            final seed = (index * 7 + 13) % 17;
            height = 6.0 + (seed / 17.0) * 22.0;
            opacity = 0.3 + (seed / 17.0) * 0.5;
          }

          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              height: height,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: opacity),
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Recording Bottom Sheet (Enhanced)
// ═══════════════════════════════════════════════════════════════════════

class _RecordingBottomSheet extends StatefulWidget {
  const _RecordingBottomSheet({
    required this.recordingState,
    required this.selectedLanguage,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onCancel,
    required this.onLanguageSelect,
  });

  final RecordingState recordingState;
  final String selectedLanguage;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;
  final VoidCallback onCancel;
  final ValueChanged<String> onLanguageSelect;

  @override
  State<_RecordingBottomSheet> createState() => _RecordingBottomSheetState();
}

class _RecordingBottomSheetState extends State<_RecordingBottomSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPaused = widget.recordingState.isPaused;
    final isSaving = widget.recordingState.isSaving;
    final amplitudes = widget.recordingState.amplitudes;

    if (isSaving) {
      return Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 40,
          top: 24,
          left: KinrelSpacing.base,
          right: KinrelSpacing.base,
        ),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(KinrelRadius.xxl),
          ),
          border: Border.all(color: KinrelColors.orange.withValues(alpha: 0.2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation(KinrelColors.orange),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Saving...',
              style: KinrelTypography.labelLarge.copyWith(
                color: KinrelColors.orange,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 16,
        top: 16,
        left: KinrelSpacing.base,
        right: KinrelSpacing.base,
      ),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.xxl),
        ),
        border: Border.all(color: KinrelColors.orange.withValues(alpha: 0.2)),
        boxShadow: [
          const BoxShadow(
            color: KinrelColors.orangeGlow,
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF3A3A4A),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Timer Display with Quality ────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Recording pulse indicator
              KinrelAnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isPaused ? KinrelColors.amber : KinrelColors.coral,
                      boxShadow: [
                        BoxShadow(
                          color:
                              (isPaused
                                      ? KinrelColors.amber
                                      : KinrelColors.coral)
                                  .withValues(
                                    alpha: 0.4 + _pulseController.value * 0.4,
                                  ),
                          blurRadius: 6 + _pulseController.value * 6,
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(width: 12),
              Text(
                widget.recordingState.durationLabel,
                style: KinrelTypography.displaySmall.copyWith(
                  color: KinrelColors.orange,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                isPaused ? 'PAUSED' : 'RECORDING',
                style: KinrelTypography.overline.copyWith(
                  color: isPaused ? KinrelColors.amber : KinrelColors.coral,
                ),
              ),
              const SizedBox(width: 12),
              // Quality indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: widget.recordingState.quality.color.withValues(
                    alpha: 0.15,
                  ),
                  borderRadius: BorderRadius.circular(KinrelRadius.xs),
                ),
                child: Text(
                  widget.recordingState.quality.label,
                  style: KinrelTypography.micro.copyWith(
                    color: widget.recordingState.quality.color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Live Waveform Visualization ──────────────────────────
          SizedBox(
            height: 60,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: List.generate(50, (index) {
                double barHeight;
                if (index < amplitudes.length) {
                  barHeight = 8.0 + amplitudes[index] * 44.0;
                } else {
                  barHeight = 8.0;
                }

                return Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    height: barHeight,
                    decoration: BoxDecoration(
                      color: isPaused
                          ? KinrelColors.amber.withValues(alpha: 0.4)
                          : KinrelColors.orange.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 16),

          // ── Language Selector Dropdown ────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: KinrelColors.darkElevated,
              borderRadius: BorderRadius.circular(KinrelRadius.md),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: widget.selectedLanguage,
                isExpanded: true,
                dropdownColor: KinrelColors.darkElevated,
                style: KinrelTypography.bodyMedium.copyWith(
                  color: KinrelColors.textWhite,
                ),
                icon: const Icon(
                  Icons.language_rounded,
                  color: KinrelColors.orange,
                  size: 20,
                ),
                items: kSupportedLanguages
                    .map(
                      (lang) => DropdownMenuItem(
                        value: lang.code,
                        child: Text('${lang.nativeName} (${lang.name})'),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) widget.onLanguageSelect(v);
                },
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── Controls Row ─────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Cancel
              GestureDetector(
                onTap: widget.onCancel,
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: KinrelColors.error.withValues(alpha: 0.15),
                    border: Border.all(
                      color: KinrelColors.error.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    color: KinrelColors.error,
                    size: 24,
                  ),
                ),
              ),

              // Pause / Resume
              GestureDetector(
                onTap: isPaused ? widget.onResume : widget.onPause,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: KinrelColors.amber.withValues(alpha: 0.15),
                    border: Border.all(
                      color: KinrelColors.amber.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Icon(
                    isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    color: KinrelColors.amber,
                    size: 32,
                  ),
                ),
              ),

              // Stop & Save
              GestureDetector(
                onTap: widget.onStop,
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: KinrelGradients.igniteGradient,
                    boxShadow: [
                      BoxShadow(
                        color: KinrelColors.orangeGlow,
                        blurRadius: 12,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.stop_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Story Detail / Player Screen (v93: real audio + no transcription)
// ═══════════════════════════════════════════════════════════════════════
//
// v93 (transcription removal + recording/playback correctness):
//   - Replaces the fake Timer-based "playback" with the real
//     OralHistoryAudioPlayer widget (just_audio under the hood).
//     The player streams the actual stored audio file from
//     story.audioUrl, discovers the real duration via durationStream,
//     tracks the real position via positionStream, surfaces buffering
//     and error states, and supports real seek/speed control.
//   - Removes the entire transcription section: the "AI Transcription"
//     header, the language badge, the detected-language confidence
//     badge, the language-detection progress indicator, the code-
//     switching indicator, the Copy/Share/Translate buttons row, the
//     timestamped segments with confidence colors, the side-by-side
//     original+English view, and the translation progress indicator.
//   - Removes the _showTranslation, _copyTranscription,
//     _buildOriginalTranscription, _buildSideBySideTranscription
//     methods (no longer needed).
//   - Keeps: the top bar (back + title + share), the narrator info
//     card, the tags row, the description (if present), and the
//     play count display.

class _StoryDetailPlayer extends ConsumerStatefulWidget {
  const _StoryDetailPlayer({required this.story, required this.onClose});

  final StoryModel story;
  final VoidCallback onClose;

  @override
  ConsumerState<_StoryDetailPlayer> createState() => _StoryDetailPlayerState();
}

class _StoryDetailPlayerState extends ConsumerState<_StoryDetailPlayer>
    with SingleTickerProviderStateMixin {
  late AnimationController _progressController;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: KinrelMotion.slow,
    )..forward();
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  void _shareStory() {
    final story = widget.story;
    final shareText =
        '''
🎙️ ${story.title}

Narrated by: ${story.narratorName}
Duration: ${story.durationLabel}
Category: ${story.category.label}
${story.era != null ? 'Era: ${story.era}' : ''}
Language: ${story.languageName}
${story.audioUrl != null ? '\nListen: ${story.audioUrl}' : ''}

Shared via Daxelo KinRel — Family Oral History
''';

    Share.share(shareText, subject: story.title);
  }

  @override
  Widget build(BuildContext context) {
    final story = widget.story;

    return Container(
          decoration: const BoxDecoration(
            gradient: KinrelGradients.darkBgGradient,
          ),
          child: SafeArea(
            child: Column(
              children: [
                // ── Top Bar ─────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KinrelSpacing.base,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: widget.onClose,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: KinrelColors.darkCard,
                          ),
                          child: const Icon(
                            Icons.arrow_back_rounded,
                            color: KinrelColors.textWhite,
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          story.title,
                          style: KinrelTypography.headlineSmall.copyWith(
                            color: KinrelColors.textWhite,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Share button
                      GestureDetector(
                        onTap: _shareStory,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: KinrelColors.darkCard,
                          ),
                          child: const Icon(
                            Icons.share_rounded,
                            color: KinrelColors.textSilver,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Real Audio Player (v93: replaces fake Timer playback) ─
                // The OralHistoryAudioPlayer widget streams the actual
                // stored audio file from story.audioUrl via just_audio,
                // discovers the real duration, tracks the real position,
                // surfaces buffering/error states, and supports real
                // seek + speed control. The waveform uses real recorded
                // amplitudes (from the `record` package's onAmplitudeChanged
                // stream during recording) — falls back to a clearly
                // decorative deterministic visualization for legacy/demo
                // rows that don't have real amplitude data.
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KinrelSpacing.xl,
                    vertical: 24,
                  ),
                  child: OralHistoryAudioPlayer(story: story),
                ),

                // ── Scrollable Content ──────────────────────────────────
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: KinrelSpacing.xl,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Narrator Info Card ──────────────────────────
                        Container(
                          padding: const EdgeInsets.all(KinrelSpacing.base),
                          decoration: BoxDecoration(
                            color: KinrelColors.darkCard,
                            borderRadius: BorderRadius.circular(
                              KinrelRadius.lg,
                            ),
                          ),
                          child: Row(
                            children: [
                              DKAvatar(
                                initials: story.narratorInitials,
                                size: DKAvatarSize.md,
                                showGlow: true,
                                borderColor: KinrelColors.orange,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      story.narratorName,
                                      style: KinrelTypography.labelLarge
                                          .copyWith(
                                            color: KinrelColors.textWhite,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    Text(
                                      'Narrator',
                                      style: KinrelTypography.bodySmall
                                          .copyWith(
                                            color: KinrelColors.textSilver,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: story.category.accentColor.withValues(
                                    alpha: 0.15,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    KinrelRadius.xs,
                                  ),
                                ),
                                child: Text(
                                  story.category.shortLabel,
                                  style: KinrelTypography.labelSmall.copyWith(
                                    color: story.category.accentColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ── Tags ────────────────────────────────────────
                        if (story.tags.isNotEmpty) ...[
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: story.tags.map((tag) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: KinrelColors.darkElevated,
                                  borderRadius: BorderRadius.circular(
                                    KinrelRadius.full,
                                  ),
                                  border: Border.all(
                                    color: const Color(0xFF3A3A4A),
                                  ),
                                ),
                                child: Text(
                                  '#$tag',
                                  style: KinrelTypography.micro.copyWith(
                                    color: KinrelColors.textDim,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // ── Description (if present) ──────────────────────
                        if (story.description != null &&
                            story.description!.isNotEmpty) ...[
                          Text(
                            story.description!,
                            style: KinrelTypography.bodyMedium.copyWith(
                              color: KinrelColors.textSilver,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // ── Play Count + Language tag ─────────────────────
                        // v93: replaces the "Transcribed" indicator. The
                        // play count reflects real playback events persisted
                        // to AncestralMemory.listenCount (see
                        // OralHistoryNotifier.incrementPlayCount). Only
                        // shown when the story has been played at least
                        // once — no "Played 0x" placeholder. The language
                        // tag (HI/EN) is KEPT — it labels what language
                        // the recording is in, independent of transcription
                        // (useful metadata on its own per the audit brief).
                        Row(
                          children: [
                            if (story.playCount > 0) ...[
                              const Icon(
                                Icons.headphones_rounded,
                                size: 14,
                                color: KinrelColors.textDim,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Played ${story.playCount}x',
                                style: KinrelTypography.labelSmall.copyWith(
                                  color: KinrelColors.textDim,
                                ),
                              ),
                            ],
                            const Spacer(),
                            // Language tag (kept — useful metadata).
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: KinrelColors.info.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(
                                  KinrelRadius.xs,
                                ),
                              ),
                              child: Text(
                                story.language.toUpperCase(),
                                style: KinrelTypography.micro.copyWith(
                                  color: KinrelColors.info,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        )
        .animate()
        .fadeIn(duration: KinrelMotion.normal)
        .slideY(begin: 0.1, end: 0, duration: KinrelMotion.normal);
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Animated Story Preview Card (v95)
// ═══════════════════════════════════════════════════════════════════════
//
// A small, animated live preview of what an Oral History story card
// looks like — used in the Oral History empty state to demonstrate
// the feature in action rather than showing a static icon.
//
// DESIGN
// ──────
// The preview card is styled identically to a real story card
// (matching KinrelColors.darkCard + KinrelRadius.lg, category tag,
// narrator avatar, duration badge, waveform visualization already
// established in the populated view via _StoryCard). The card shell
// (container + title/description layout) is delegated to the shared
// [AnimatedPreviewCard] widget — the same shell the Memories &
// Timeline preview card uses — so the two empty states share one
// coherent design language.
//
// The placeholder content is deliberately generic and clearly
// illustrative:
//   • Avatar: a soft gradient circle with a microphone icon (NOT an
//     initial that could be mistaken for a real person's name)
//   • Title: "A story waiting to be told" (a generic, clearly-
//     illustrative phrase demonstrating the breadth of what can be
//     recorded, rather than a specific fabricated story title)
//   • Duration badge: shows "0:00" with an audio-waveform icon
//     (clearly a placeholder, not a fake specific duration like
//     "12:34" that could read as real data)
//   • Category tag: cycles through 2-3 of the real category types
//     (Family, Recipe, Wisdom) every ~5 seconds during the
//     animation — clearly illustrative/rotating, not presented as
//     one fixed fake story. The cycling is subtle and slow.
//
// ANIMATION
// ────────
// Rather than photo crossfading (which doesn't fit audio content),
// the waveform bars animate with a gentle, slow pulsing/breathing
// motion — bars subtly rising and falling in a loose rhythm. This
// suggests "this is where your recording's waveform will appear"
// WITHOUT implying actual audio is playing (no progress indicator,
// no play-state visual, since nothing is actually playing). The
// pulse uses a [Timer.periodic] at ~1.6s per cycle with a sine-wave
// amplitude envelope, so the motion reads as ambient breathing
// rather than an attention-grabbing loop.
//
// REDUCED MOTION
// ──────────────
// When [reducedMotion] is true (the platform accessibility setting
// is on, per AppMotion.reducedMotion), the Timer is never started —
// the waveform bars are shown at varied but FIXED heights (a single
// static waveform shape), not pulsing. The card is still visible
// (the user still sees what a story card looks like) — only the
// pulse animation is suppressed.
//
// PERFORMANCE
// ───────────
// The parent wraps this widget in a RepaintBoundary so the
// continuous waveform pulse doesn't cause Flutter to repaint the
// entire empty state on every animation tick. The animation is
// lightweight (only the bar heights change; the rest of the card is
// static). The Timer is cancelled on dispose so the widget doesn't
// keep ticking when the empty state is scrolled off-screen or the
// screen is popped.
//
// CONSISTENCY WITH MEMORIES EMPTY STATE
// ─────────────────────────────────────
// Reuses the same [AnimatedPreviewCard] shell as the Memories &
// Timeline preview card, with slot-based content (header + mediaArea
// + title + description) and the same reduced-motion passthrough.
// The two empty states share one coherent design language — same
// card chrome, same sizing (240px width), same typography — only the
// animated media area differs (photo crossfade for Memories, waveform
// pulse for Oral History) because the content types differ.

class _AnimatedStoryPreviewCard extends StatefulWidget {
  const _AnimatedStoryPreviewCard({
    this.reducedMotion = false,
  });

  /// Whether the user has requested reduced motion. When true, the
  /// card shows a single static waveform shape instead of pulsing.
  /// Defaults to false — the parent should pass
  /// `AppMotion.reducedMotion(context)`.
  final bool reducedMotion;

  @override
  State<_AnimatedStoryPreviewCard> createState() =>
      _AnimatedStoryPreviewCardState();
}

class _AnimatedStoryPreviewCardState
    extends State<_AnimatedStoryPreviewCard>
    with SingleTickerProviderStateMixin {
  /// Drives the waveform pulse. A single [AnimationController] that
  /// runs continuously (0 → 1 → 0 → 1 → ...) with a sine curve so
  /// the bars breathe in and out gently.
  late final AnimationController _pulseController;

  /// Drives the category tag cycling. Restarts when the user toggles
  /// reduced-motion off (so the cycle resumes from the current
  /// category, not from the beginning).
  Timer? _categoryTimer;

  /// Index of the currently-shown placeholder category.
  /// Cycles 0 → 1 → 2 → 0 → ...
  int _currentCategoryIndex = 0;

  /// The 2-3 illustrative placeholder categories. These are REAL
  /// [StoryCategory] values (Family, Recipe, Wisdom) — cycling
  /// through them showcases the variety of categories available,
  /// which the brief explicitly allows: "can cycle through 2-3 of
  /// the real category types ... since it's clearly illustrative/
  /// rotating rather than presented as one fixed fake story."
  ///
  /// v95 (demo-style content): each category is paired with a full,
  /// complete illustrative title + description matching the spirit
  /// of the original demo data — specific, legible phrases like
  /// "Grandma's secret ghevar recipe" and "The night we left Lahore"
  /// — not generic placeholder text like "A story waiting to be
  /// told". The scenes are clearly illustrative (they cycle, and the
  /// empty-state headline/subtitle makes it clear this is a preview).
  static const _placeholderScenes = <_StoryPlaceholderScene>[
    _StoryPlaceholderScene(
      category: StoryCategory.familyHistory,
      title: 'The night we left Lahore',
      description: 'Saroj Devi recounts the family\'s journey during Partition.',
      durationLabel: '23:15',
    ),
    _StoryPlaceholderScene(
      category: StoryCategory.recipe,
      title: "Grandma's secret ghevar recipe",
      description: 'Kamla shares the recipe passed down through four generations.',
      durationLabel: '8:22',
    ),
    _StoryPlaceholderScene(
      category: StoryCategory.wisdom,
      title: "Nani Ma's wisdom on raising children",
      description: 'Saroj Devi shares her philosophy on family and patience.',
      durationLabel: '15:08',
    ),
  ];

  /// Convenience getter for the currently-active placeholder scene.
  _StoryPlaceholderScene get _currentScene =>
      _placeholderScenes[_currentCategoryIndex];

  /// The base waveform shape — 30 bars at varied but fixed heights.
  /// These heights are the "resting" state of the pulse: when the
  /// pulse animation runs, each bar's height oscillates around its
  /// base height. When reduced-motion is on, the bars stay at these
  /// fixed heights (a single static waveform shape).
  ///
  /// The values are deterministic (generated from a fixed seed) so
  /// the static shape is consistent across renders — not random
  /// per build, which would look jittery.
  static final List<double> _baseWaveform = _generateBaseWaveform(30);

  @override
  void initState() {
    super.initState();
    // The pulse runs at ~1.6s per cycle (1700ms). Slow and ambient,
    // matching the Memories preview card's restraint.
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    );
    _startAnimationsIfNeeded();
  }

  @override
  void didUpdateWidget(_AnimatedStoryPreviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reducedMotion != oldWidget.reducedMotion) {
      if (widget.reducedMotion) {
        _stopAnimations();
      } else {
        _startAnimationsIfNeeded();
      }
    }
  }

  void _startAnimationsIfNeeded() {
    if (widget.reducedMotion) return;
    _pulseController.repeat(reverse: true);
    // Cycle the category tag every ~5 seconds. Slow and subtle —
    // the cycling is clearly illustrative, not attention-grabbing.
    _categoryTimer?.cancel();
    _categoryTimer = Timer.periodic(
      const Duration(milliseconds: 5000),
      (_) {
        if (!mounted) return;
        setState(() {
          _currentCategoryIndex =
              (_currentCategoryIndex + 1) % _placeholderScenes.length;
        });
      },
    );
  }

  void _stopAnimations() {
    _pulseController.stop();
    _categoryTimer?.cancel();
    _categoryTimer = null;
  }

  @override
  void dispose() {
    _stopAnimations();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scene = _currentScene;

    return AnimatedPreviewCard(
      reducedMotion: widget.reducedMotion,
      accentColor: scene.category.accentColor,
      header: _StoryPreviewHeader(
        category: scene.category,
        durationLabel: scene.durationLabel,
      ),
      mediaArea: _StoryWaveformPulse(
        accentColor: scene.category.accentColor,
        baseWaveform: _baseWaveform,
        pulseAnimation: widget.reducedMotion ? null : _pulseController,
      ),
      title: scene.title,
      description: scene.description,
    );
  }
}

/// The header row for the Oral History preview card — a category tag
/// (icon + short label) on the left, a duration badge on the right.
/// Matches the real `_StoryCard`'s top-row layout so the preview
/// reads as a real story card.
class _StoryPreviewHeader extends StatelessWidget {
  const _StoryPreviewHeader({
    required this.category,
    this.durationLabel = '0:00',
  });

  final StoryCategory category;

  /// v95: now shows the scene's illustrative duration (e.g. "23:15",
  /// "8:22") to match the demo-style content, instead of the
  /// generic "0:00" placeholder. Defaults to "0:00" for backward
  /// compat if a caller doesn't pass it.
  final String durationLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Category tag — matches _StoryCard's category tag styling.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: category.accentColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(KinrelRadius.xs),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(category.icon, size: 12, color: category.accentColor),
              const SizedBox(width: 3),
              Text(
                category.shortLabel,
                style: KinrelTypography.micro.copyWith(
                  color: category.accentColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        // Duration badge — matches _StoryCard's duration badge styling.
        // Shows the scene's illustrative duration (e.g. "23:15") to
        // read as a real story card, not a generic "0:00" placeholder.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: KinrelColors.darkElevated,
            borderRadius: BorderRadius.circular(KinrelRadius.full),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.graphic_eq_rounded,
                size: 12,
                color: KinrelColors.amber,
              ),
              const SizedBox(width: 3),
              Text(
                durationLabel,
                style: KinrelTypography.labelSmall.copyWith(
                  color: KinrelColors.amber,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// v95: a placeholder scene for the Oral History preview card — pairs
/// a [StoryCategory] with full, complete illustrative title +
/// description + duration label. Used by `_AnimatedStoryPreviewCard`
/// to cycle through demo-style examples matching the original demo
/// data (The night we left Lahore / Grandma's secret ghevar recipe /
/// Nani Ma's wisdom on raising children).
@immutable
class _StoryPlaceholderScene {
  const _StoryPlaceholderScene({
    required this.category,
    required this.title,
    required this.description,
    required this.durationLabel,
  });

  final StoryCategory category;
  final String title;
  final String description;
  final String durationLabel;
}

/// The animated waveform area for the Oral History preview card — a
/// row of bars that gently pulse (rise and fall) to suggest "this is
/// where your recording's waveform will appear" without implying
/// actual audio is playing. When [pulseAnimation] is null (reduced-
/// motion mode), the bars are shown at their fixed base heights — a
/// single static waveform shape.
///
/// The bars use the same styling as the real [_WaveformPreview] widget
/// (accent color with varying opacity, 1.5px border radius) so the
/// preview reads as a real story card's waveform.
class _StoryWaveformPulse extends StatelessWidget {
  const _StoryWaveformPulse({
    required this.accentColor,
    required this.baseWaveform,
    this.pulseAnimation,
  });

  /// The accent color for the waveform bars. Matches the cycling
  /// category's accent color so the waveform color rotates with
  /// the category tag.
  final Color accentColor;

  /// The base (resting) heights of the bars, 0.0–1.0. When
  /// [pulseAnimation] is null, the bars render at these heights
  /// (a single static waveform shape). When [pulseAnimation] is
  /// non-null, each bar's height oscillates around its base height
  /// following the pulse animation's value.
  final List<double> baseWaveform;

  /// The pulse animation driving the bar heights. When null
  /// (reduced-motion mode), the bars are static. When non-null,
  /// the parent is responsible for starting/stopping the animation
  /// controller.
  final Animation<double>? pulseAnimation;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(baseWaveform.length, (index) {
          final baseHeight = baseWaveform[index];

          if (pulseAnimation == null) {
            // Reduced-motion: static bars at their base heights.
            return Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 1),
                height: 6.0 + baseHeight * 36.0,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.35 + baseHeight * 0.5),
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            );
          }

          // Animated: each bar oscillates around its base height.
          // The phase offset (index * 0.15) makes adjacent bars pulse
          // slightly out of sync, so the motion reads as a loose
          // "breathing" rhythm rather than all bars moving in unison
          // (which would look mechanical).
          return AnimatedBuilder(
            animation: pulseAnimation!,
            builder: (context, _) {
              // The pulse animation's value goes 0→1→0→1 with
              // repeat(reverse: true) — a triangle wave. We convert
              // it to a smooth sine envelope (0.0–1.0) so the bars
              // breathe rather than jump. Each bar has a phase offset
              // (index * 0.15, wrapped to 0..1) so adjacent bars don't
              // move in lockstep.
              //
              // `t` is the animation value (0..1, 0..1, 0..1, ...).
              // `phase` is the per-bar phase offset (0..1).
              // The sine wave: sin((t + phase) * 2π), mapped -1..1 to 0..1.
              final t = pulseAnimation!.value;
              final phase = (index * 0.15) % 1.0;
              final sineValue =
                  math.sin((t + phase) * 2 * math.pi);
              final envelope = (1 + sineValue) / 2;

              // The bar height oscillates between ~50% and ~100% of
              // its base height — a gentle pulse, not a full collapse.
              final pulseFactor = 0.5 + 0.5 * envelope;
              final height = 6.0 + baseHeight * 36.0 * pulseFactor;
              final opacity = 0.3 + baseHeight * pulseFactor * 0.5;

              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  height: height,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: opacity),
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}

/// Generates the base (resting) waveform shape — 30 bars at varied
/// but deterministic heights (0.0–1.0). Deterministic so the static
/// shape is consistent across renders (not random per build, which
/// would look jittery).
List<double> _generateBaseWaveform(int barCount) {
  // The shape should look like a real audio waveform — varied, with
  // some tall bars and some short bars, not a uniform sine wave.
  // We use a deterministic mix of sine waves at different frequencies
  // for a natural-looking but consistent shape.
  return List.generate(barCount, (i) {
    // Three sine waves at different frequencies + phases, mixed
    // and normalized to 0..1. The result is clamped to a reasonable
    // range so the bars are visible but not all the same height.
    final low = 0.5 + 0.5 * math.sin(i * 0.4);
    final mid = 0.5 + 0.5 * math.sin(i * 1.7 + 1.0);
    final high = 0.5 + 0.5 * math.sin(i * 3.3 + 2.0);
    final mixed = (low * 0.5 + mid * 0.3 + high * 0.2);
    return (0.15 + mixed * 0.7).clamp(0.15, 0.95);
  });
}

