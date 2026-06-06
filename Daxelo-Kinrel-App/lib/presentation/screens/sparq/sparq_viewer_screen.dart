// lib/presentation/screens/sparq/sparq_viewer_screen.dart
//
// DAXELO KINREL — Sparq Viewer Screen
//
// Full-screen story viewer (dark background):
//   • Progress bars for each sparq
//   • IMAGE: CachedNetworkImage, VIDEO: video_player, TEXT: colored bg+text, VOICE: waveform+audio
//   • Tap left → prev, tap right → next, swipe down → close, swipe left/right → next/prev user
//   • Auto advance: 5s for image/text, full duration for video/voice
//   • Mark as viewed on show

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../data/models/sparq_model.dart';
import '../../providers/sparq_provider.dart';

class SparqViewerScreen extends ConsumerStatefulWidget {
  const SparqViewerScreen({
    super.key,
    required this.groups,
    this.initialGroupIndex = 0,
  });

  final List<UserSparqGroup> groups;
  final int initialGroupIndex;

  @override
  ConsumerState<SparqViewerScreen> createState() => _SparqViewerScreenState();
}

class _SparqViewerScreenState extends ConsumerState<SparqViewerScreen>
    with TickerProviderStateMixin {
  late int _currentGroupIndex;
  late int _currentSparqIndex;
  late AnimationController _progressController;
  Timer? _autoAdvanceTimer;
  bool _isPaused = false;

  @override
  void initState() {
    super.initState();
    _currentGroupIndex = widget.initialGroupIndex;
    _currentSparqIndex = 0;

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..addStatusListener(_onProgressStatusChanged);

    _startSparq();
  }

  @override
  void dispose() {
    _autoAdvanceTimer?.cancel();
    _progressController.dispose();
    super.dispose();
  }

  // ── Sparq lifecycle ──────────────────────────────────────────────

  void _startSparq() {
    if (!mounted) return;
    _markViewed();

    final sparq = _currentSparq;
    final duration = Duration(seconds: sparq?.autoAdvanceSeconds ?? 5);

    _progressController.duration = duration;
    _progressController.reset();
    _progressController.forward();

    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = Timer(duration, _advanceToNextSparq);
  }

  void _pauseSparq() {
    if (_isPaused) return;
    _isPaused = true;
    _progressController.stop();
    _autoAdvanceTimer?.cancel();
  }

  void _resumeSparq() {
    if (!_isPaused) return;
    _isPaused = false;
    _progressController.forward();
    final remainingFraction = 1.0 - _progressController.value;
    final totalMs = (_progressController.duration?.inMilliseconds ?? 5000);
    final remainingMs = (totalMs * remainingFraction).round();
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = Timer(Duration(milliseconds: remainingMs), _advanceToNextSparq);
  }

  void _onProgressStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _advanceToNextSparq();
    }
  }

  void _advanceToNextSparq() {
    if (!mounted) return;
    final group = _currentGroup;
    if (group == null) {
      Navigator.of(context).pop();
      return;
    }

    if (_currentSparqIndex < group.sparqs.length - 1) {
      setState(() => _currentSparqIndex++);
      _startSparq();
    } else if (_currentGroupIndex < widget.groups.length - 1) {
      setState(() {
        _currentGroupIndex++;
        _currentSparqIndex = 0;
      });
      _startSparq();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _goToPreviousSparq() {
    if (_currentSparqIndex > 0) {
      setState(() => _currentSparqIndex--);
      _startSparq();
    } else if (_currentGroupIndex > 0) {
      setState(() {
        _currentGroupIndex--;
        _currentSparqIndex = 0;
      });
      _startSparq();
    }
  }

  void _markViewed() {
    final sparq = _currentSparq;
    if (sparq == null || sparq.viewed) return;
    ref.read(sparqProvider.notifier).markViewed(sparq.id);
  }

  // ── Helpers ──────────────────────────────────────────────────────

  UserSparqGroup? get _currentGroup {
    if (_currentGroupIndex < widget.groups.length) {
      return widget.groups[_currentGroupIndex];
    }
    return null;
  }

  SparqModel? get _currentSparq {
    final group = _currentGroup;
    if (group != null && _currentSparqIndex < group.sparqs.length) {
      return group.sparqs[_currentSparqIndex];
    }
    return null;
  }

  Color _parseBgColor(String? hexColor) {
    if (hexColor == null || hexColor.isEmpty) return KinrelColors.darkBackground;
    final code = hexColor.replaceAll('#', '');
    return Color(int.parse('FF$code', radix: 16));
  }

  // ── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final group = _currentGroup;
    final sparq = _currentSparq;
    if (group == null || sparq == null) return const SizedBox.shrink();

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
            Navigator.of(context).pop();
          }
        },
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity == null) return;
          if (details.primaryVelocity! < -300) {
            // Swipe left → next user
            _advanceToNextSparq();
          } else if (details.primaryVelocity! > 300) {
            // Swipe right → prev user
            _goToPreviousSparq();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Content
            _buildSparqContent(sparq),
            // Gradient overlay
            _buildGradientOverlay(),
            // Top bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildTopBar(group, sparq),
            ),
            // Tap zones
            _buildTapZones(),
          ],
        ),
      ),
    );
  }

  // ── Content ────────────────────────────────────────────────────────

  Widget _buildSparqContent(SparqModel sparq) {
    switch (sparq.type) {
      case 'IMAGE':
        return Container(
          color: KinrelColors.darkBackground,
          child: Center(
            child: CachedNetworkImage(
              imageUrl: sparq.mediaUrl ?? '',
              fit: BoxFit.contain,
              placeholder: (_, __) => Center(
                child: CircularProgressIndicator(
                  color: KinrelColors.orange,
                ),
              ),
              errorWidget: (_, __, ___) => _buildTextContent(sparq),
            ),
          ),
        );
      case 'VIDEO':
        // Video player placeholder — full integration would use video_player
        return Container(
          color: KinrelColors.darkBackground,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.play_circle_outline, size: 64, color: KinrelColors.orange),
                const SizedBox(height: 12),
                Text(
                  'Video Sparq',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 16,
                    color: KinrelColors.textSilver,
                  ),
                ),
              ],
            ),
          ),
        );
      case 'VOICE':
        // Voice waveform placeholder
        return Container(
          decoration: BoxDecoration(
            gradient: KinrelGradients.deepFireGradient,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.graphic_eq, size: 64, color: KinrelColors.orange),
                const SizedBox(height: 16),
                Container(
                  width: 200,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: _buildWaveform(),
                ),
                if (sparq.duration != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${sparq.duration}s',
                    style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 14,
                      color: KinrelColors.textSilver,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      case 'TEXT':
      default:
        return _buildTextContent(sparq);
    }
  }

  Widget _buildTextContent(SparqModel sparq) {
    return Container(
      decoration: BoxDecoration(
        color: sparq.bgColor != null ? _parseBgColor(sparq.bgColor) : null,
        gradient: sparq.bgColor == null ? KinrelGradients.igniteGradient : null,
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            sparq.text ?? '',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.4,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWaveform() {
    // Simple waveform bars placeholder
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        20,
        (i) => Container(
          width: 4,
          height: 10 + (i % 5) * 5.0,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: KinrelColors.orange.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  // ── Gradient overlay ────────────────────────────────────────────

  Widget _buildGradientOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Column(
          children: [
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

  // ── Top bar ──────────────────────────────────────────────────────

  Widget _buildTopBar(UserSparqGroup group, SparqModel sparq) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildProgressBars(group.sparqs.length),
            const SizedBox(height: 12),
            _buildUserInfoRow(group, sparq),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBars(int total) {
    return Row(
      children: List.generate(total, (index) {
        final isCurrent = index == _currentSparqIndex;
        final isPast = index < _currentSparqIndex;

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
                  ? AnimatedBuilder(
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

  Widget _buildUserInfoRow(UserSparqGroup group, SparqModel sparq) {
    return Row(
      children: [
        SparqRingAvatar(
          userId: group.userId,
          imageUrl: group.user.avatarUrl,
          initials: group.initials,
          size: 36,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                group.user.name ?? group.user.username ?? 'User',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textWhite,
                ),
              ),
              Text(
                sparq.timeAgo,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 11,
                  color: KinrelColors.textSilver,
                ),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: () {
            if (_isPaused) {
              _resumeSparq();
            } else {
              _pauseSparq();
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
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
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
              onTapDown: (_) => _pauseSparq(),
              onTapUp: (_) {
                _resumeSparq();
                _goToPreviousSparq();
              },
              onTapCancel: () => _resumeSparq(),
              child: const SizedBox.expand(),
            ),
          ),
          // Right 2/3 — go forward
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTapDown: (_) => _pauseSparq(),
              onTapUp: (_) {
                _resumeSparq();
                _advanceToNextSparq();
              },
              onTapCancel: () => _resumeSparq(),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }
}
