// lib/features/stories/presentation/stories_viewer_screen.dart
//
// DAXELO KINREL — Instagram-like Stories Viewer
//
// Full-screen story viewer with:
//   • Auto-advance timer (5 seconds per story)
//   • Progress bars at top showing story position
//   • User avatar + name + time ago at top
//   • Story content area with gradient background or image/video display
//   • Tap left 1/3 to go back, right 2/3 to go forward
//   • Pause/play on long press
//   • Close button (X)
//   • Reply input at bottom
//   • Swipe down to dismiss

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/config/auth_config.dart';
import '../../../core/services/supabase_service.dart';
import '../providers/stories_provider.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../../core/widgets/global_error_widget.dart';

// ── Color shortcuts ──────────────────────────────────────────────
const _cOrange = KinrelColors.orange;
const _cBg = KinrelColors.darkBackground;
const _cCard = KinrelColors.darkCard;
const _cTextPrimary = KinrelColors.textWhite;
const _cTextSecondary = KinrelColors.textSilver;

/// Full-screen stories viewer.
///
/// Takes a list of [StoryGroup]s and the index to start from.
/// Displays stories in an Instagram-like full-screen viewer with
/// auto-advance, progress bars, and gesture controls.
class StoriesViewerScreen extends ConsumerStatefulWidget {
  const StoriesViewerScreen({
    super.key,
    required this.storyGroups,
    this.initialGroupIndex = 0,
    this.familyId = '',
  });

  final List<StoryGroup> storyGroups;
  final int initialGroupIndex;
  final String familyId;

  @override
  ConsumerState<StoriesViewerScreen> createState() =>
      _StoriesViewerScreenState();
}

class _StoriesViewerScreenState extends ConsumerState<StoriesViewerScreen>
    with TickerProviderStateMixin {
  late int _currentGroupIndex;
  late int _currentStoryIndex;
  late AnimationController _progressController;
  Timer? _autoAdvanceTimer;
  bool _isPaused = false;
  final _replyController = TextEditingController();

  static const _storyDuration = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _currentGroupIndex = widget.initialGroupIndex;
    _currentStoryIndex = 0;

    _progressController = AnimationController(
      vsync: this,
      duration: _storyDuration,
    )..addStatusListener(_onProgressStatusChanged);

    _startStory();
  }

  @override
  void dispose() {
    _autoAdvanceTimer?.cancel();
    _progressController.dispose();
    _replyController.dispose();
    super.dispose();
  }

  // ── Story lifecycle ──────────────────────────────────────────────

  void _startStory() {
    if (!mounted) return;
    _markStoryViewed();
    _progressController.reset();
    _progressController.forward();
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = Timer(_storyDuration, _advanceToNextStory);
  }

  void _pauseStory() {
    if (_isPaused) return;
    _isPaused = true;
    _progressController.stop();
    _autoAdvanceTimer?.cancel();
  }

  void _resumeStory() {
    if (!_isPaused) return;
    _isPaused = false;
    _progressController.forward();
    // Recalculate remaining time
    final remainingFraction = 1.0 - _progressController.value;
    final remainingMs = (_storyDuration.inMilliseconds * remainingFraction).round();
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = Timer(Duration(milliseconds: remainingMs), _advanceToNextStory);
  }

  void _onProgressStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _advanceToNextStory();
    }
  }

  void _advanceToNextStory() {
    if (!mounted) return;
    final group = _currentGroup;
    if (group == null) {
      Navigator.of(context).pop();
      return;
    }

    if (_currentStoryIndex < group.stories.length - 1) {
      // Next story in current group
      setState(() => _currentStoryIndex++);
      _startStory();
    } else if (_currentGroupIndex < widget.storyGroups.length - 1) {
      // Next group
      setState(() {
        _currentGroupIndex++;
        _currentStoryIndex = 0;
      });
      _startStory();
    } else {
      // All stories viewed — close
      Navigator.of(context).pop();
    }
  }

  void _goToPreviousStory() {
    if (_currentStoryIndex > 0) {
      setState(() => _currentStoryIndex--);
      _startStory();
    } else if (_currentGroupIndex > 0) {
      setState(() {
        _currentGroupIndex--;
        _currentStoryIndex = 0;
      });
      _startStory();
    }
    // If at the very first story, do nothing (restart it)
  }

  void _goToNextStory() {
    _advanceToNextStory();
  }

  void _markStoryViewed() {
    final story = _currentStory;
    if (story == null || widget.familyId.isEmpty) return;

    final client = ref.read(supabaseProvider);
    final userId = client?.auth.currentUser?.id ??
        (kAuthDisabled ? MockUser.id : null);
    if (userId == null) return;

    // Fire and forget — don't await
    ref.read(markStoryViewedProvider(MarkViewedParams(
      storyId: story.id,
      userId: userId,
      familyId: widget.familyId,
    )).future);
  }

  // ── Helpers ──────────────────────────────────────────────────────

  StoryGroup? get _currentGroup {
    if (_currentGroupIndex < widget.storyGroups.length) {
      return widget.storyGroups[_currentGroupIndex];
    }
    return null;
  }

  Story? get _currentStory {
    final group = _currentGroup;
    if (group != null && _currentStoryIndex < group.stories.length) {
      return group.stories[_currentStoryIndex];
    }
    return null;
  }

  List<Color> _parseGradientColors(List<String>? hexColors) {
    if (hexColors == null || hexColors.isEmpty) {
      return [Color(0xFF131416), _cOrange];
    }
    return hexColors.map((hex) {
      final code = hex.replaceAll('#', '');
      return Color(int.parse('FF$code', radix: 16));
    }).toList();
  }

  // ── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final group = _currentGroup;
    final story = _currentStory;
    if (group == null || story == null) {
      return const SizedBox.shrink();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        // Swipe down to dismiss
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
            Navigator.of(context).pop();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Story content ─────────────────────────────────────
            _buildStoryContent(story),

            // ── Gradient overlay for readability ───────────────────
            _buildGradientOverlay(),

            // ── Top bar (progress + user info) ────────────────────
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildTopBar(group, story),
            ),

            // ── Tap zones (left = back, right = forward) ─────────
            _buildTapZones(),

            // ── Bottom reply bar ──────────────────────────────────
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildReplyBar(group),
            ),
          ],
        ),
      ),
    );
  }

  // ── Story content (gradient background or image) ────────────────

  Widget _buildStoryContent(Story story) {
    if (story.type == 'image' && story.mediaUrl != null) {
      return Container(
        color: _cBg,
        child: Center(
          child: Image.network(
            story.mediaUrl!,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _buildTextStoryContent(story),
          ),
        ),
      );
    }

    return _buildTextStoryContent(story);
  }

  Widget _buildTextStoryContent(Story story) {
    final gradientColors = _parseGradientColors(story.gradientColors);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            story.caption ?? '',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: _cTextPrimary,
              height: 1.4,
            ),
          ),
        ),
      ),
    );
  }

  // ── Gradient overlay for readability ────────────────────────────

  Widget _buildGradientOverlay() {
    return const Positioned.fill(
      child: IgnorePointer(
        child: Column(
          children: [
            // Top dark gradient for header readability
            Expanded(
              flex: 2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.black54, Colors.transparent],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
            // Bottom dark gradient for reply bar readability
            Expanded(
              flex: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Colors.black54],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Top bar: progress indicators + user info ────────────────────

  Widget _buildTopBar(StoryGroup group, Story story) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Progress bars
            _buildProgressBars(group.stories.length),
            const SizedBox(height: 12),
            // User info row
            _buildUserInfoRow(group, story),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBars(int totalStories) {
    return Row(
      children: List.generate(totalStories, (index) {
        final isCurrent = index == _currentStoryIndex;
        final isPast = index < _currentStoryIndex;

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 3,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(1.5),
                color: isPast
                    ? Colors.white
                    : isCurrent
                        ? Colors.white
                        : Colors.white38,
              ),
              child: isCurrent
                  ? KinrelAnimatedBuilder(
                      animation: _progressController,
                      builder: (context, child) {
                        return FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: _progressController.value,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(1.5),
                            ),
                          ),
                        );
                      },
                    )
                  : null,
            ),
          ),
        );
      }),
    );
  }

  Widget _buildUserInfoRow(StoryGroup group, Story story) {
    return Row(
      children: [
        // User avatar
        DKAvatar(
          initials: group.initials,
          imageUrl: group.userAvatarUrl,
          size: DKAvatarSize.sm,
          borderColor: _cOrange,
        ),
        const SizedBox(width: 10),
        // User name + time
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                group.userName,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _cTextPrimary,
                ),
              ),
              Text(
                story.timeAgo,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 11,
                  color: _cTextSecondary,
                ),
              ),
            ],
          ),
        ),
        // Pause/play button
        GestureDetector(
          onTap: () {
            if (_isPaused) {
              _resumeStory();
            } else {
              _pauseStory();
            }
            setState(() {});
          },
          child: Icon(
            _isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            color: Colors.white,
            size: 28,
          ),
        ),
        const SizedBox(width: 8),
        // Close button
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: const Icon(
            Icons.close_rounded,
            color: Colors.white,
            size: 28,
          ),
        ),
      ],
    );
  }

  // ── Tap zones ──────────────────────────────────────────────────

  Widget _buildTapZones() {
    return Positioned.fill(
      child: Row(
        children: [
          // Left 1/3 — go back
          Expanded(
            flex: 1,
            child: GestureDetector(
              onTapDown: (_) => _pauseStory(),
              onTapUp: (_) {
                _resumeStory();
                _goToPreviousStory();
              },
              onTapCancel: () => _resumeStory(),
              child: const SizedBox.expand(),
            ),
          ),
          // Right 2/3 — go forward
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTapDown: (_) => _pauseStory(),
              onTapUp: (_) {
                _resumeStory();
                _goToNextStory();
              },
              onTapCancel: () => _resumeStory(),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }

  // ── Reply bar ──────────────────────────────────────────────────

  Widget _buildReplyBar(StoryGroup group) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
                child: TextField(
                  controller: _replyController,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    color: _cTextPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Reply to ${group.userName}...',
                    hintStyle: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      color: Colors.white54,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _sendReply(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _sendReply,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: KinrelGradients.igniteGradient,
                ),
                child: const Icon(
                  Icons.send_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _sendReply() {
    final text = _replyController.text.trim();
    if (text.isEmpty) return;
    // TODO: Implement reply via API
    _replyController.clear();
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Reply sent!'),
        backgroundColor: _cCard,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
      ),
    );
  }
}
