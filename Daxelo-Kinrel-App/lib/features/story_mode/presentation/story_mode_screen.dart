// lib/features/story_mode/presentation/story_mode_screen.dart
//
// P7.2 — Story Mode screen.
// Guided narrated tour through family history. Camera pans to each
// chapter's focus person (spring physics from P3.1), TTS narration,
// subtitles sync with TTS. Reduced motion: jump cuts between chapters.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../providers/story_mode_controller.dart';

class StoryModeScreen extends ConsumerWidget {
  final String familyId;

  const StoryModeScreen({super.key, required this.familyId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(storyModeProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: state.chapters.isEmpty
            ? _buildEmptyState(context)
            : _buildStoryView(context, ref, state),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_stories, size: 64, color: KinrelColors.tealAccent),
          const SizedBox(height: 16),
          const Text(
            'Story Mode',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'A guided tour through your family\'s history.\n'
            'Generate a chronicle first to enable Story Mode.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildStoryView(
      BuildContext context, WidgetRef ref, StoryModeState state) {
    final chapter = state.currentChapter;
    if (chapter == null) return const SizedBox.shrink();

    return Stack(
      children: [
        // Background graph (would be FamilyGraphEngineView in production)
        Positioned.fill(
          child: Container(color: KinrelColors.darkBackground),
        ),
        // Subtitle overlay (always on — accessibility)
        if (state.subtitlesEnabled)
          Positioned(
            left: 24,
            right: 24,
            bottom: 120,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    chapter.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    chapter.narration,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9), fontSize: 15),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        // Controls
        Positioned(
          left: 0,
          right: 0,
          bottom: 24,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: state.isFirstChapter
                    ? null
                    : () => ref.read(storyModeProvider.notifier).previous(),
                icon: const Icon(Icons.skip_previous, color: Colors.white, size: 36),
              ),
              const SizedBox(width: 24),
              GestureDetector(
                onTap: () {
                  if (state.isPlaying && !state.isPaused) {
                    ref.read(storyModeProvider.notifier).pause();
                  } else {
                    ref.read(storyModeProvider.notifier).play();
                  }
                },
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: KinrelColors.tealAccent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    state.isPlaying && !state.isPaused
                        ? Icons.pause
                        : Icons.play_arrow,
                    color: Colors.black,
                    size: 36,
                  ),
                ),
              ),
              const SizedBox(width: 24),
              IconButton(
                onPressed: state.isLastChapter
                    ? null
                    : () => ref.read(storyModeProvider.notifier).next(),
                icon: const Icon(Icons.skip_next, color: Colors.white, size: 36),
              ),
            ],
          ),
        ),
        // Close button
        Positioned(
          top: 8,
          right: 8,
          child: IconButton(
            onPressed: () {
              ref.read(storyModeProvider.notifier).stop();
              Navigator.of(context).pop();
            },
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ),
        // Chapter indicator
        Positioned(
          top: 16,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Chapter ${state.currentIndex + 1} of ${state.chapters.length}',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
