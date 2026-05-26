// lib/features/oral_history/presentation/oral_history_screen.dart
//
// DAXELO KINREL — Oral History & Story Recording Screen
//
// AI-powered story recording with transcription support.
// Category filter chips, waveform story cards, recording FAB,
// recording bottom sheet with live waveform, save dialog,
// and story detail/player with transcription.
//
// Orange K-Graph DNA: #13141E bg, #191B2C cards, #E8612A accent,
// ignite gradient (#E8612A → #F59240), glow effects.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../shared/widgets/dk_components.dart';
import '../providers/oral_history_provider.dart';

// ═══════════════════════════════════════════════════════════════════════
// Oral History Screen
// ═══════════════════════════════════════════════════════════════════════

class OralHistoryScreen extends ConsumerStatefulWidget {
  const OralHistoryScreen({super.key});

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

              // ── Search Bar ────────────────────────────────────────
              SliverToBoxAdapter(child: _buildSearchBar(state)),

              // ── Category Filter Chips ─────────────────────────────
              SliverToBoxAdapter(child: _buildCategoryChips(state)),

              // ── Stats Row ─────────────────────────────────────────
              SliverToBoxAdapter(child: _buildStatsRow(state)),

              // ── Stories List ──────────────────────────────────────
              if (filteredStories.isEmpty)
                SliverToBoxAdapter(child: _buildEmptyState())
              else
                SliverList(
                  delegate: SliverChildBuilderWithFooter(
                    childCount: filteredStories.length,
                    footer: const SizedBox(height: 120),
                    builder: (context, index) {
                      return _StoryCard(
                        story: filteredStories[index],
                        onTap: () => _openStoryDetail(filteredStories[index]),
                        onFavorite: () => ref
                            .read(oralHistoryProvider.notifier)
                            .toggleFavorite(filteredStories[index].id),
                        onLongPress: () =>
                            _showStoryOptions(filteredStories[index]),
                      );
                    },
                  ),
                ),
            ],
          ),

          // ── Recording FAB ─────────────────────────────────────────
          if (!state.recordingState.isActive)
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
      padding: EdgeInsets.fromLTRB(
        KinrelSpacing.base,
        KinrelSpacing.xl,
        KinrelSpacing.base,
        KinrelSpacing.sm,
      ),
      child: Row(
        children: [
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
          SizedBox(width: KinrelSpacing.md),
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                gradient: KinrelGradients.igniteGradient,
                borderRadius: BorderRadius.circular(KinrelRadius.full),
                boxShadow: [
                  BoxShadow(
                    color: KinrelColors.orangeGlow,
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.favorite_rounded,
                      size: 14, color: Colors.white),
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
      padding: EdgeInsets.fromLTRB(
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
      StoryCategory.family_history,
      StoryCategory.life_event,
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
        padding: EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = categories[index];
          final isActive = state.filter == category;
          final label =
              category == null ? 'All' : category.shortLabel;
          final accent =
              category?.accentColor ?? KinrelColors.orange;

          return GestureDetector(
            onTap: () => ref
                .read(oralHistoryProvider.notifier)
                .setFilter(category),
            child: AnimatedContainer(
              duration: KinrelMotion.fast,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                    Icon(category.icon, size: 14,
                        color: isActive ? accent : KinrelColors.textDim),
                    const SizedBox(width: 5),
                  ],
                  if (category == null)
                    Icon(Icons.apps_rounded, size: 14,
                        color: isActive ? accent : KinrelColors.textDim),
                  if (category == null) const SizedBox(width: 5),
                  Text(
                    label,
                    style: KinrelTypography.labelSmall.copyWith(
                      color: isActive ? accent : KinrelColors.textSilver,
                      fontWeight:
                          isActive ? FontWeight.w600 : FontWeight.w500,
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
  // Stats Row
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildStatsRow(OralHistoryState state) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        KinrelSpacing.base,
        KinrelSpacing.md,
        KinrelSpacing.base,
        KinrelSpacing.sm,
      ),
      child: Row(
        children: [
          _StatChip(
            icon: Icons.auto_stories_rounded,
            label: '${state.storyCount} Stories',
            color: KinrelColors.orange,
          ),
          const SizedBox(width: 12),
          _StatChip(
            icon: Icons.transcribe_rounded,
            label: '${state.transcribedCount} Transcribed',
            color: KinrelColors.success,
          ),
          const SizedBox(width: 12),
          _StatChip(
            icon: Icons.timer_rounded,
            label: _formatTotalDuration(state.totalDuration),
            color: KinrelColors.amber,
          ),
        ],
      ),
    );
  }

  String _formatTotalDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '${d.inMinutes}m';
  }

  // ═══════════════════════════════════════════════════════════════════
  // Empty State
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildEmptyState() {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 400,
        child: Center(
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
                  Icons.mic_rounded,
                  size: 40,
                  color: KinrelColors.orange,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'No stories found',
                style: KinrelTypography.headlineMedium.copyWith(
                  color: KinrelColors.textWhite,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Try adjusting your filters or record\nyour first family story!',
                textAlign: TextAlign.center,
                style: KinrelTypography.bodyMedium.copyWith(
                  color: KinrelColors.textSilver,
                ),
              ),
              const SizedBox(height: 24),
              DKButton(
                label: 'Record First Story',
                variant: DKButtonVariant.gradient,
                icon: Icons.mic_rounded,
                size: DKButtonSize.md,
                onPressed: () => _startRecording(),
              ),
            ],
          ),
        ),
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
            BoxShadow(
              color: KinrelColors.orangeGlowIntense,
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(KinrelRadius.full),
            onTap: () => _startRecording(),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.mic_rounded,
                      color: Colors.white, size: 22),
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
    ref.read(oralHistoryProvider.notifier).startRecording();
  }

  void _onStopRecording() {
    final duration =
        ref.read(oralHistoryProvider.notifier).stopRecording();
    _showSaveStoryDialog(duration);
  }

  void _onCancelRecording() {
    ref.read(oralHistoryProvider.notifier).stopRecording();
  }

  // ═══════════════════════════════════════════════════════════════════
  // Save Story Dialog
  // ═══════════════════════════════════════════════════════════════════

  void _showSaveStoryDialog(Duration recordedDuration) {
    final titleController = TextEditingController();
    final eraController = TextEditingController();
    final tagsController = TextEditingController();
    StoryCategory selectedCategory = StoryCategory.family_history;
    String selectedNarrator = 'Self';
    bool shouldTranscribe = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(KinrelRadius.xxl)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
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
                          borderRadius:
                              BorderRadius.circular(KinrelRadius.md),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(KinrelRadius.md),
                          borderSide: BorderSide(
                              color: KinrelColors.orange, width: 1.5),
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
                        borderRadius:
                            BorderRadius.circular(KinrelRadius.md),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedNarrator,
                          isExpanded: true,
                          dropdownColor: KinrelColors.darkElevated,
                          style: KinrelTypography.bodyMedium.copyWith(
                            color: KinrelColors.textWhite,
                          ),
                          items: [
                            'Self',
                            'Kamla Sharma (Dadi)',
                            'Ravi Sharma (Papa)',
                            'Sunita Sharma (Mummy)',
                            'Saroj Devi (Nani)',
                          ]
                              .map((n) => DropdownMenuItem(
                                    value: n,
                                    child: Text(n),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setModalState(() => selectedNarrator = v);
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
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? cat.accentColor.withValues(alpha: 0.2)
                                  : KinrelColors.darkElevated,
                              borderRadius:
                                  BorderRadius.circular(KinrelRadius.full),
                              border: Border.all(
                                color: isActive
                                    ? cat.accentColor
                                        .withValues(alpha: 0.5)
                                    : const Color(0xFF3A3A4A),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(cat.icon,
                                    size: 14,
                                    color: isActive
                                        ? cat.accentColor
                                        : KinrelColors.textDim),
                                const SizedBox(width: 4),
                                Text(
                                  cat.shortLabel,
                                  style:
                                      KinrelTypography.labelSmall.copyWith(
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
                    Text(
                      'Era / Time Period',
                      style: KinrelTypography.labelLarge.copyWith(
                        color: KinrelColors.textSilver,
                      ),
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
                          borderRadius:
                              BorderRadius.circular(KinrelRadius.md),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(KinrelRadius.md),
                          borderSide: BorderSide(
                              color: KinrelColors.orange, width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Tags Input ─────────────────────────────────
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
                          borderRadius:
                              BorderRadius.circular(KinrelRadius.md),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(KinrelRadius.md),
                          borderSide: BorderSide(
                              color: KinrelColors.orange, width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Transcribe Toggle ──────────────────────────
                    Container(
                      padding: const EdgeInsets.all(KinrelSpacing.base),
                      decoration: BoxDecoration(
                        color: KinrelColors.darkElevated,
                        borderRadius:
                            BorderRadius.circular(KinrelRadius.lg),
                        border: Border.all(
                          color: shouldTranscribe
                              ? KinrelColors.orange
                                  .withValues(alpha: 0.4)
                              : const Color(0xFF3A3A4A),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: KinrelColors.orange
                                  .withValues(alpha: 0.15),
                            ),
                            child: const Icon(
                              Icons.transcribe_rounded,
                              color: KinrelColors.orange,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'AI Transcription',
                                  style: KinrelTypography.labelLarge
                                      .copyWith(
                                    color: KinrelColors.textWhite,
                                  ),
                                ),
                                Text(
                                  'Auto-transcribe using AI',
                                  style:
                                      KinrelTypography.bodySmall.copyWith(
                                    color: KinrelColors.textSilver,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch.adaptive(
                            value: shouldTranscribe,
                            activeColor: KinrelColors.orange,
                            onChanged: (v) {
                              setModalState(() => shouldTranscribe = v);
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    // ── Save / Cancel Buttons ──────────────────────
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
                            onPressed: () {
                              final title = titleController.text.trim();
                              if (title.isEmpty) return;

                              final tags = tagsController.text
                                  .split(',')
                                  .map((t) => t.trim())
                                  .where((t) => t.isNotEmpty)
                                  .toList();

                              final story = StoryModel(
                                id: 'story-${DateTime.now().millisecondsSinceEpoch}',
                                title: title,
                                narratorId: 'self',
                                narratorName: selectedNarrator == 'Self'
                                    ? 'You'
                                    : selectedNarrator
                                        .split('(')
                                        .first
                                        .trim(),
                                familyId: 'fam-sharma',
                                audioDuration: recordedDuration,
                                language: ref
                                    .read(oralHistoryProvider)
                                    .selectedLanguage,
                                tags: tags,
                                era: eraController.text.trim().isEmpty
                                    ? null
                                    : eraController.text.trim(),
                                category: selectedCategory,
                                createdAt: DateTime.now(),
                              );

                              ref
                                  .read(oralHistoryProvider.notifier)
                                  .addStory(story);

                              if (shouldTranscribe) {
                                ref
                                    .read(oralHistoryProvider.notifier)
                                    .transcribeRecording();
                              }

                              Navigator.pop(context);
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
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(KinrelRadius.xxl)),
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
                leading: Icon(Icons.play_circle_rounded,
                    color: KinrelColors.orange),
                title: Text('Play Story',
                    style: KinrelTypography.bodyLarge.copyWith(
                        color: KinrelColors.textWhite)),
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
                    color: KinrelColors.coral),
                title: Text(
                    story.isFavorite
                        ? 'Remove from Favorites'
                        : 'Add to Favorites',
                    style: KinrelTypography.bodyLarge.copyWith(
                        color: KinrelColors.textWhite)),
                onTap: () {
                  ref
                      .read(oralHistoryProvider.notifier)
                      .toggleFavorite(story.id);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_rounded,
                    color: KinrelColors.amber),
                title: Text('Share Story',
                    style: KinrelTypography.bodyLarge.copyWith(
                        color: KinrelColors.textWhite)),
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading:
                    const Icon(Icons.delete_rounded, color: KinrelColors.error),
                title: Text('Delete Story',
                    style: KinrelTypography.bodyLarge.copyWith(
                        color: KinrelColors.error)),
                onTap: () {
                  ref
                      .read(oralHistoryProvider.notifier)
                      .deleteStory(story.id);
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
                  BoxShadow(
                    color: KinrelColors.orangeGlowSubtle,
                    blurRadius: 12,
                    offset: const Offset(0, 2),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: story.category.accentColor
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(KinrelRadius.xs),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(story.category.icon,
                          size: 12,
                          color: story.category.accentColor),
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
                        horizontal: 8, vertical: 3),
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
                      horizontal: 6, vertical: 2),
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
                  backgroundColor:
                      story.category.accentColor.withValues(alpha: 0.2),
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
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: KinrelColors.darkElevated,
                    borderRadius: BorderRadius.circular(KinrelRadius.full),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timer_rounded,
                          size: 12, color: KinrelColors.amber),
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
                // Decorative waveform
                Expanded(
                  child: _WaveformPreview(
                    accentColor: story.category.accentColor,
                    barCount: 40,
                  ),
                ),
                const SizedBox(width: 12),
                // Play button (orange gradient circle)
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: KinrelGradients.igniteGradient,
                    boxShadow: [
                      BoxShadow(
                        color: KinrelColors.orangeGlow,
                        blurRadius: 10,
                        offset: const Offset(0, 2),
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
                        borderRadius:
                            BorderRadius.circular(KinrelRadius.xs),
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

            // ── Transcription indicator ─────────────────────────────
            if (story.hasTranscription) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.transcribe_rounded,
                      size: 14, color: KinrelColors.success),
                  const SizedBox(width: 4),
                  Text(
                    'Transcribed',
                    style: KinrelTypography.labelSmall.copyWith(
                      color: KinrelColors.success,
                    ),
                  ),
                  const Spacer(),
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
  });

  final Color accentColor;
  final int barCount;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(barCount, (index) {
          // Generate pseudo-random heights
          final seed = (index * 7 + 13) % 17;
          final height = 6.0 + (seed / 17.0) * 22.0;
          final opacity = 0.3 + (seed / 17.0) * 0.5;

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
// Recording Bottom Sheet
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
    final amplitudes = widget.recordingState.amplitudes;

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
          BoxShadow(
            color: KinrelColors.orangeGlow,
            blurRadius: 20,
            offset: const Offset(0, -4),
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

          // ── Timer Display ────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Recording pulse indicator
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isPaused
                          ? KinrelColors.amber
                          : KinrelColors.coral,
                      boxShadow: [
                        BoxShadow(
                          color: (isPaused
                                  ? KinrelColors.amber
                                  : KinrelColors.coral)
                              .withValues(
                                  alpha:
                                      0.4 + _pulseController.value * 0.4),
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
                      color: KinrelColors.orange.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 16),

          // ── Language Selector ────────────────────────────────────
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: kSupportedLanguages.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final lang = kSupportedLanguages[index];
                final isActive =
                    widget.selectedLanguage == lang.code;
                return GestureDetector(
                  onTap: () => widget.onLanguageSelect(lang.code),
                  child: AnimatedContainer(
                    duration: KinrelMotion.fast,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: isActive
                          ? KinrelColors.orange.withValues(alpha: 0.2)
                          : KinrelColors.darkElevated,
                      borderRadius:
                          BorderRadius.circular(KinrelRadius.full),
                      border: Border.all(
                        color: isActive
                            ? KinrelColors.orange
                                .withValues(alpha: 0.5)
                            : const Color(0xFF3A3A4A),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        lang.nativeName,
                        style: KinrelTypography.labelSmall.copyWith(
                          color: isActive
                              ? KinrelColors.orange
                              : KinrelColors.textDim,
                          fontWeight: isActive
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                );
              },
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
                  child: const Icon(Icons.close_rounded,
                      color: KinrelColors.error, size: 24),
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
                    isPaused
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
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
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: KinrelGradients.igniteGradient,
                    boxShadow: [
                      BoxShadow(
                        color: KinrelColors.orangeGlow,
                        blurRadius: 12,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.stop_rounded,
                      color: Colors.white, size: 24),
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
// Story Detail / Player Screen
// ═══════════════════════════════════════════════════════════════════════

class _StoryDetailPlayer extends StatefulWidget {
  const _StoryDetailPlayer({
    required this.story,
    required this.onClose,
  });

  final StoryModel story;
  final VoidCallback onClose;

  @override
  State<_StoryDetailPlayer> createState() => _StoryDetailPlayerState();
}

class _StoryDetailPlayerState extends State<_StoryDetailPlayer>
    with SingleTickerProviderStateMixin {
  late AnimationController _progressController;
  double _speed = 1.0;
  bool _isPlaying = true;
  double _progress = 0.0;
  Timer? _playTimer;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: KinrelMotion.slow,
    )..forward();

    _startPlayback();
  }

  @override
  void dispose() {
    _progressController.dispose();
    _playTimer?.cancel();
    super.dispose();
  }

  void _startPlayback() {
    _playTimer?.cancel();
    _isPlaying = true;
    _playTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_isPlaying && mounted) {
        setState(() {
          _progress += (0.1 * _speed) / widget.story.audioDuration.inSeconds;
          if (_progress >= 1.0) {
            _progress = 0.0;
            _isPlaying = false;
          }
        });
      }
    });
  }

  String _formatPosition() {
    final totalMs = widget.story.audioDuration.inMilliseconds;
    final posMs = (totalMs * _progress).round();
    final d = Duration(milliseconds: posMs);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
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
                  horizontal: KinrelSpacing.base, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: widget.onClose,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: KinrelColors.darkCard,
                      ),
                      child: const Icon(Icons.arrow_back_rounded,
                          color: KinrelColors.textWhite, size: 20),
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
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: KinrelColors.darkCard,
                    ),
                    child: const Icon(Icons.share_rounded,
                        color: KinrelColors.textSilver, size: 20),
                  ),
                ],
              ),
            ),

            // ── Large Waveform Display ──────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: KinrelSpacing.xl, vertical: 24),
              child: Column(
                children: [
                  SizedBox(
                    height: 80,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: List.generate(60, (index) {
                        final seed = (index * 7 + 13) % 17;
                        final height = 12.0 + (seed / 17.0) * 56.0;
                        final isPast =
                            index / 60.0 <= _progress;

                        return Expanded(
                          child: Container(
                            margin:
                                const EdgeInsets.symmetric(horizontal: 1),
                            height: height,
                            decoration: BoxDecoration(
                              color: isPast
                                  ? KinrelColors.orange
                                  : KinrelColors.orange
                                      .withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Progress bar
                  Row(
                    children: [
                      Text(
                        _formatPosition(),
                        style: KinrelTypography.labelSmall.copyWith(
                          color: KinrelColors.orange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderThemeData(
                            activeTrackColor: KinrelColors.orange,
                            inactiveTrackColor:
                                KinrelColors.darkElevated,
                            thumbColor: KinrelColors.orange,
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6),
                          ),
                          child: Slider(
                            value: _progress,
                            onChanged: (v) {
                              setState(() => _progress = v);
                            },
                          ),
                        ),
                      ),
                      Text(
                        story.durationLabel,
                        style: KinrelTypography.labelSmall.copyWith(
                          color: KinrelColors.textSilver,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── Play/Pause/Seek Controls ────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Rewind 15s
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _progress =
                          (_progress - 15 / story.audioDuration.inSeconds)
                              .clamp(0.0, 1.0);
                    });
                  },
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: KinrelColors.darkCard,
                    ),
                    child: const Icon(Icons.replay_15_rounded,
                        color: KinrelColors.textSilver, size: 22),
                  ),
                ),
                const SizedBox(width: 20),

                // Play / Pause
                GestureDetector(
                  onTap: () {
                    setState(() => _isPlaying = !_isPlaying);
                  },
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: KinrelGradients.igniteGradient,
                      boxShadow: [
                        BoxShadow(
                          color: KinrelColors.orangeGlowIntense,
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      _isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
                const SizedBox(width: 20),

                // Forward 15s
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _progress =
                          (_progress + 15 / story.audioDuration.inSeconds)
                              .clamp(0.0, 1.0);
                    });
                  },
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: KinrelColors.darkCard,
                    ),
                    child: const Icon(Icons.forward_15_rounded,
                        color: KinrelColors.textSilver, size: 22),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Speed Control ───────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [0.5, 1.0, 1.5, 2.0].map((speed) {
                final isActive = _speed == speed;
                return GestureDetector(
                  onTap: () => setState(() => _speed = speed),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isActive
                          ? KinrelColors.orange.withValues(alpha: 0.2)
                          : KinrelColors.darkCard,
                      borderRadius: BorderRadius.circular(KinrelRadius.full),
                      border: Border.all(
                        color: isActive
                            ? KinrelColors.orange
                            : const Color(0xFF3A3A4A),
                      ),
                    ),
                    child: Text(
                      '${speed}x',
                      style: KinrelTypography.labelSmall.copyWith(
                        color: isActive
                            ? KinrelColors.orange
                            : KinrelColors.textSilver,
                        fontWeight: isActive
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // ── Scrollable Content ──────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: KinrelSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Narrator Info Card ──────────────────────────
                    Container(
                      padding: const EdgeInsets.all(KinrelSpacing.base),
                      decoration: BoxDecoration(
                        color: KinrelColors.darkCard,
                        borderRadius:
                            BorderRadius.circular(KinrelRadius.lg),
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
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
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
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: story.category.accentColor
                                  .withValues(alpha: 0.15),
                              borderRadius:
                                  BorderRadius.circular(KinrelRadius.xs),
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

                    // ── Related People Chips ────────────────────────
                    if (story.relatedPersonIds.isNotEmpty) ...[
                      Text(
                        'Related People',
                        style: KinrelTypography.labelLarge.copyWith(
                          color: KinrelColors.textSilver,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children:
                            story.relatedPersonIds.map((id) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: KinrelColors.darkCard,
                              borderRadius: BorderRadius.circular(
                                  KinrelRadius.full),
                              border: Border.all(
                                  color: const Color(0xFF3A3A4A)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                DKAvatar(
                                  initials: id
                                      .replaceAll('m', '')
                                      .toUpperCase(),
                                  size: DKAvatarSize.sm,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  id,
                                  style: KinrelTypography.labelSmall
                                      .copyWith(
                                    color: KinrelColors.textSilver,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ── Transcription Text ──────────────────────────
                    if (story.hasTranscription) ...[
                      Row(
                        children: [
                          const Icon(Icons.transcribe_rounded,
                              size: 16, color: KinrelColors.success),
                          const SizedBox(width: 6),
                          Text(
                            'AI Transcription',
                            style:
                                KinrelTypography.labelLarge.copyWith(
                              color: KinrelColors.success,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: KinrelColors.info
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(
                                  KinrelRadius.xs),
                            ),
                            child: Text(
                              story.languageName,
                              style:
                                  KinrelTypography.micro.copyWith(
                                color: KinrelColors.info,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(
                            KinrelSpacing.base),
                        decoration: BoxDecoration(
                          color: KinrelColors.darkCard,
                          borderRadius: BorderRadius.circular(
                              KinrelRadius.lg),
                          border: Border.all(
                            color: KinrelColors.success
                                .withValues(alpha: 0.15),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            // Transcription with timestamps
                            ...story.transcription!
                                .split('।')
                                .where((s) => s.trim().isNotEmpty)
                                .toList()
                                .asMap()
                                .entries
                                .map((entry) {
                              final idx = entry.key;
                              final segment = entry.value.trim();
                              final startTime =
                                  (idx * story.audioDuration.inSeconds /
                                          3)
                                      .round();
                              final startDur =
                                  Duration(seconds: startTime);
                              final m = startDur.inMinutes
                                  .remainder(60)
                                  .toString()
                                  .padLeft(2, '0');
                              final s = startDur.inSeconds
                                  .remainder(60)
                                  .toString()
                                  .padLeft(2, '0');

                              return Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 4,
                                              vertical: 2),
                                      decoration: BoxDecoration(
                                        color: KinrelColors.orange
                                            .withValues(alpha: 0.12),
                                        borderRadius:
                                            BorderRadius.circular(
                                                KinrelRadius.xs),
                                      ),
                                      child: Text(
                                        '$m:$s',
                                        style: KinrelTypography.micro
                                            .copyWith(
                                          color: KinrelColors.orange,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        segment,
                                        style: KinrelTypography
                                            .bodyMedium
                                            .copyWith(
                                          color:
                                              KinrelColors.textWhite,
                                          height: 1.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ],
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
// Stat Chip
// ═══════════════════════════════════════════════════════════════════════

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(KinrelRadius.full),
        border: Border.all(
          color: color.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: KinrelTypography.labelSmall.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SliverChildBuilderWithFooter helper
// ═══════════════════════════════════════════════════════════════════════

class SliverChildBuilderWithFooter extends SliverChildDelegate {
  SliverChildBuilderWithFooter({
    required this.childCount,
    required this.footer,
    required this.builder,
  });

  final int childCount;
  final Widget footer;
  final NullableIndexedWidgetBuilder builder;

  @override
  int get estimatedChildCount => childCount + 1;

  @override
  Widget? build(BuildContext context, int index) {
    if (index == childCount) return footer;
    if (index < childCount) return builder(context, index);
    return null;
  }

  @override
  bool shouldRebuild(covariant SliverChildBuilderWithFooter oldDelegate) {
    return childCount != oldDelegate.childCount;
  }
}
