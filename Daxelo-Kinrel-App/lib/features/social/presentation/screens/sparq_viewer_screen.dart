import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/brand_colors.dart';
import '../../data/models/sparq_model.dart';
import '../../data/providers/sparq_provider.dart';

class SparqViewerScreen extends ConsumerStatefulWidget {
  const SparqViewerScreen({super.key, required this.userId});
  final String userId;

  @override
  ConsumerState<SparqViewerScreen> createState() => _SparqViewerScreenState();
}

class _SparqViewerScreenState extends ConsumerState<SparqViewerScreen>
    with TickerProviderStateMixin {
  int _currentIndex = 0;
  double _progress = 0.0;
  late AnimationController _progressController;
  bool _isPaused = false;
  List<SparqModel> _sparqs = [];
  String? _replyText;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(vsync: this);
    _progressController.addListener(() {
      setState(() => _progress = _progressController.value);
    });
    _progressController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _goToNext();
      }
    });
    _loadSparqs();
  }

  Future<void> _loadSparqs() async {
    try {
      final sparqs = await ref.read(userSparqsProvider(widget.userId).future);
      if (mounted && sparqs.isNotEmpty) {
        setState(() => _sparqs = sparqs);
        _startProgress();
      }
    } catch (e) {
      if (mounted) context.pop();
    }
  }

  void _startProgress() {
    if (_currentIndex >= _sparqs.length) {
      context.pop();
      return;
    }
    final sparq = _sparqs[_currentIndex];
    final durationMs = sparq.autoAdvanceDuration * 1000;
    _progressController.duration = Duration(milliseconds: durationMs);
    _progressController.forward(from: 0);
    // Mark as viewed
    ref.read(sparqProvider.notifier).markSparqViewed(sparq.id, sparq.userId);
    ref.read(sparqProvider.notifier).markLocalViewed(sparq.id);
  }

  void _goToNext() {
    if (_currentIndex < _sparqs.length - 1) {
      setState(() => _currentIndex++);
      _startProgress();
    } else {
      context.pop();
    }
  }

  void _goToPrevious() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      _startProgress();
    }
  }

  void _togglePause() {
    if (_isPaused) {
      _progressController.forward();
    } else {
      _progressController.stop();
    }
    setState(() => _isPaused = !_isPaused);
  }

  Future<void> _deleteSparq() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KinrelColors.elevation3,
        title: Text('Delete Sparq', style: TextStyle(color: Colors.white)),
        content: Text('Are you sure you want to delete this Sparq?',
            style: TextStyle(color: KinrelColors.textSilver)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: KinrelColors.textSilver)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: KinrelColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(sparqProvider.notifier).deleteSparq(_sparqs[_currentIndex].id);
      if (_sparqs.length <= 1) {
        context.pop();
      } else {
        setState(() {
          _sparqs.removeAt(_currentIndex);
          if (_currentIndex >= _sparqs.length) _currentIndex = _sparqs.length - 1;
        });
        _startProgress();
      }
    }
  }

  Future<void> _toggleEcho() async {
    if (_sparqs.isEmpty) return;
    final sparq = _sparqs[_currentIndex];
    HapticFeedback.mediumImpact();
    await ref.read(sparqProvider.notifier).toggleEcho(sparq.id);
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_sparqs.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: KinrelColors.orange)),
      );
    }

    final sparq = _sparqs[_currentIndex];
    final sparqState = ref.watch(sparqProvider);
    final isEchoed = sparqState.echoedSparqs[sparq.id] ?? false;
    final echoCount = sparqState.echoCounts[sparq.id] ?? sparq.echoCount;

    // Time capsule locked state
    if (sparq.isLockedTimeCapsule) {
      return _buildTimeCapsuleLocked(sparq);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
            context.pop();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Full-screen content ─────────────────────────────
            _buildSparqContent(sparq),

            // ── Mood particles overlay ──────────────────────────
            if (sparq.mood.isNotEmpty)
              _buildMoodParticles(sparq),

            // ── Gradient overlays (top/bottom) ──────────────────
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 120,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black.withValues(alpha: 0.6), Colors.transparent],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 180,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)],
                  ),
                ),
              ),
            ),

            // ── Progress bars at top ────────────────────────────
            Positioned(
              top: MediaQuery.of(context).padding.top + 4,
              left: 8,
              right: 8,
              child: Row(
                children: List.generate(_sparqs.length, (i) {
                  return Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(1),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: i < _currentIndex
                            ? 1.0
                            : i == _currentIndex
                                ? _progress
                                : 0.0,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),

            // ── User info row ───────────────────────────────────
            Positioned(
              top: MediaQuery.of(context).padding.top + 14,
              left: 8,
              right: 8,
              child: Row(
                children: [
                  // Avatar with intensity ring
                  _buildIntensityRingAvatar(sparq),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sparq.userId,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Outfit',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Row(
                          children: [
                            Text(
                              _timeAgo(sparq.createdAt),
                              style: TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'DM Sans'),
                            ),
                            // Mood badge
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: sparq.moodColor.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                sparq.moodEmoji,
                                style: TextStyle(fontSize: 10),
                              ),
                            ),
                            // Intensity badge
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: sparq.intensityColor.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                sparq.intensity == 'fire' ? '🔥' : sparq.intensity == 'calm' ? '🌊' : '🌤️',
                                style: TextStyle(fontSize: 10),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Close button
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.white, size: 24),
                    onPressed: () => context.pop(),
                  ),
                ],
              ),
            ),

            // ── Tap areas (left 30% → prev, right 70% → next) ──
            Positioned.fill(
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: GestureDetector(
                      onTap: _goToPrevious,
                      onLongPress: _togglePause,
                    ),
                  ),
                  Expanded(
                    flex: 7,
                    child: GestureDetector(
                      onTap: _goToNext,
                      onLongPress: _togglePause,
                    ),
                  ),
                ],
              ),
            ),

            // ── Bottom section: actions + reply ──────────────────
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 16,
              left: 16,
              right: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Action buttons row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Echo button
                      _buildActionButton(
                        emoji: '🔥',
                        label: 'Echo',
                        count: echoCount,
                        isActive: isEchoed,
                        onTap: _toggleEcho,
                      ),
                      const SizedBox(width: 20),
                      // Chain button (if allowChain)
                      if (sparq.allowChain)
                        _buildActionButton(
                          emoji: '🔗',
                          label: 'Chain',
                          count: null,
                          isActive: false,
                          onTap: () {
                            // Navigate to create screen for chaining
                            context.push('/sparq/create');
                          },
                        ),
                      if (sparq.allowChain)
                        const SizedBox(width: 20),
                      // Reply button (if allowReplies)
                      if (sparq.allowReplies)
                        _buildActionButton(
                          emoji: '💬',
                          label: 'Reply',
                          count: null,
                          isActive: false,
                          onTap: () {
                            // Focus reply field
                            setState(() {});
                          },
                        ),
                      const Spacer(),
                      // Delete button (creator only — shown for own sparqs)
                      IconButton(
                        icon: Icon(Icons.delete_outline, color: Colors.white54, size: 22),
                        onPressed: _deleteSparq,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Reply field
                  if (sparq.allowReplies)
                    Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: TextField(
                        onChanged: (v) => _replyText = v,
                        style: TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'DM Sans'),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          hintText: 'Reply to Sparq...',
                          hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                          suffixIcon: IconButton(
                            icon: Icon(Icons.send, color: KinrelColors.orange, size: 20),
                            onPressed: () {
                              // TODO: implement reply submission
                              _replyText = null;
                            },
                          ),
                        ),
                      ),
                    ),
                  // Family badge
                  if (sparq.audience == 'FAMILY_ONLY') ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: KinrelColors.orange.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: KinrelColors.orange, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.family_restroom, size: 14, color: KinrelColors.orange),
                          SizedBox(width: 4),
                          Text('Family',
                            style: TextStyle(color: KinrelColors.orange, fontSize: 11, fontWeight: FontWeight.w600),
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
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // INTENSITY RING AVATAR
  // ══════════════════════════════════════════════════════════════════

  Widget _buildIntensityRingAvatar(SparqModel sparq) {
    Color ringColor;
    double ringWidth = 2.5;

    switch (sparq.intensity) {
      case 'calm':
        ringColor = const Color(0xFF2196F3);
        break;
      case 'fire':
        ringColor = const Color(0xFFFF1744);
        break;
      default:
        ringColor = const Color(0xFFFF9800);
    }

    // Time capsule: gold dashed ring
    if (sparq.isTimeCapsule) {
      ringColor = const Color(0xFFFFD700);
    }

    return CustomPaint(
      painter: _IntensityRingPainter(
        ringColor: ringColor,
        ringWidth: ringWidth,
        intensity: sparq.intensity,
        isTimeCapsule: sparq.isTimeCapsule,
      ),
      child: Padding(
        padding: EdgeInsets.all(ringWidth + 1.5),
        child: CircleAvatar(
          radius: 18,
          backgroundColor: KinrelColors.elevation2,
          child: Icon(Icons.person, size: 18, color: KinrelColors.textSilver),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // ACTION BUTTON
  // ══════════════════════════════════════════════════════════════════

  Widget _buildActionButton({
    required String emoji,
    required String label,
    required int? count,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? KinrelColors.orange.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: TextStyle(fontSize: 16)),
            if (count != null) ...[
              const SizedBox(width: 4),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  '$count',
                  key: ValueKey(count),
                  style: TextStyle(
                    color: isActive ? KinrelColors.orange : Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'DM Sans',
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? KinrelColors.orange : Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'DM Sans',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // MOOD PARTICLES
  // ══════════════════════════════════════════════════════════════════

  Widget _buildMoodParticles(SparqModel sparq) {
    return CustomPaint(
      painter: _MoodParticlePainter(
        moodColor: sparq.moodColor,
        time: DateTime.now().millisecondsSinceEpoch % 60000 / 60000,
      ),
      size: Size.infinite,
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // TIME CAPSULE LOCKED STATE
  // ══════════════════════════════════════════════════════════════════

  Widget _buildTimeCapsuleLocked(SparqModel sparq) {
    final remaining = sparq.timeUntilReveal ?? Duration.zero;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Blurred background
          Container(
            decoration: BoxDecoration(
              color: sparq.moodColor.withValues(alpha: 0.1),
            ),
            child: BackdropFilter(
              filter: ColorFilter.mode(Colors.black.withValues(alpha: 0.7), BlendMode.srcOver),
              child: Container(),
            ),
          ),
          // Lock content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_clock, size: 64, color: Color(0xFFFFD700)),
                const SizedBox(height: 20),
                Text(
                  '🕰️ Time Capsule',
                  style: TextStyle(
                    color: KinrelColors.textWhite,
                    fontFamily: 'Outfit',
                    fontWeight: FontWeight.w600,
                    fontSize: 22,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This Sparq is locked until',
                  style: TextStyle(color: KinrelColors.textSilver, fontFamily: 'DM Sans', fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDuration(remaining),
                  style: TextStyle(
                    color: Color(0xFFFFD700),
                    fontFamily: 'Outfit',
                    fontWeight: FontWeight.w600,
                    fontSize: 28,
                  ),
                ),
                const SizedBox(height: 40),
                IconButton(
                  icon: Icon(Icons.close, color: KinrelColors.textSilver, size: 28),
                  onPressed: () => context.pop(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // CONTENT BUILDERS
  // ══════════════════════════════════════════════════════════════════

  Widget _buildSparqContent(SparqModel sparq) {
    switch (sparq.type) {
      case 'IMAGE':
        if (sparq.mediaUrl != null && sparq.mediaUrl!.isNotEmpty) {
          return Center(
            child: Image.network(sparq.mediaUrl!, fit: BoxFit.cover, width: double.infinity, height: double.infinity,
              errorBuilder: (_, __, ___) => _buildErrorContent(),
            ),
          );
        }
        return _buildErrorContent();
      case 'VIDEO':
        return Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (sparq.thumbnailUrl != null && sparq.thumbnailUrl!.isNotEmpty)
                Image.network(sparq.thumbnailUrl!, fit: BoxFit.cover, width: double.infinity, height: double.infinity,
                  errorBuilder: (_, __, ___) => Container(color: KinrelColors.elevation1),
                )
              else
                Container(color: KinrelColors.elevation1),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.play_arrow, color: Colors.white, size: 36),
              ),
              // Duration badge
              Positioned(
                bottom: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${sparq.duration ?? 0}s',
                    style: TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'DM Sans'),
                  ),
                ),
              ),
            ],
          ),
        );
      case 'TEXT':
        return Container(
          color: _parseBackgroundColor(sparq.backgroundColor),
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                sparq.text ?? '',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Outfit',
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      case 'VOICE':
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.graphic_eq, size: 64, color: KinrelColors.orange),
              SizedBox(height: 12),
              Text('Voice Note', style: TextStyle(color: Colors.white54, fontSize: 14)),
              SizedBox(height: 4),
              Text('${sparq.duration ?? 0}s',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ),
        );
      default:
        return _buildErrorContent();
    }
  }

  Color _parseBackgroundColor(String? hex) {
    if (hex == null || hex.isEmpty) return KinrelColors.elevation1;
    try {
      return Color(int.parse(hex.replaceFirst('#', 'FF'), radix: 16));
    } catch (_) {
      return KinrelColors.elevation1;
    }
  }

  Widget _buildErrorContent() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image, size: 48, color: Colors.white38),
          SizedBox(height: 8),
          Text('Content unavailable', style: TextStyle(color: Colors.white38)),
        ],
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _formatDuration(Duration d) {
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h remaining';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m remaining';
    if (d.inMinutes > 0) return '${d.inMinutes}m remaining';
    return 'Revealing soon...';
  }
}

// ══════════════════════════════════════════════════════════════════════
// INTENSITY RING PAINTER
// ══════════════════════════════════════════════════════════════════════

class _IntensityRingPainter extends CustomPainter {
  final Color ringColor;
  final double ringWidth;
  final String intensity;
  final bool isTimeCapsule;

  _IntensityRingPainter({
    required this.ringColor,
    required this.ringWidth,
    required this.intensity,
    required this.isTimeCapsule,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - ringWidth) / 2;

    final paint = Paint()
      ..color = ringColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth
      ..strokeCap = StrokeCap.round;

    if (isTimeCapsule) {
      // Dashed ring for time capsule
      _drawDashedCircle(canvas, center, radius, paint);
    } else {
      canvas.drawCircle(center, radius, paint);
    }
  }

  void _drawDashedCircle(Canvas canvas, Offset center, double radius, Paint paint) {
    const dashCount = 12;
    const dashAngle = 3.14159 * 2 / dashCount;
    const sweepAngle = dashAngle * 0.6;
    for (int i = 0; i < dashCount; i++) {
      final startAngle = i * dashAngle;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _IntensityRingPainter oldDelegate) {
    return ringColor != oldDelegate.ringColor ||
        ringWidth != oldDelegate.ringWidth ||
        intensity != oldDelegate.intensity ||
        isTimeCapsule != oldDelegate.isTimeCapsule;
  }
}

// ══════════════════════════════════════════════════════════════════════
// MOOD PARTICLE PAINTER
// ══════════════════════════════════════════════════════════════════════

class _MoodParticlePainter extends CustomPainter {
  final Color moodColor;
  final double time;

  _MoodParticlePainter({required this.moodColor, required this.time});

  @override
  void paint(Canvas canvas, Size size) {
    final particleCount = 8;
    for (int i = 0; i < particleCount; i++) {
      final seed = i * 137.508; // Golden angle
      final t = (time + seed * 0.01) % 1.0;

      final x = (seed * 7.3 + t * size.width * 0.3) % size.width;
      final y = size.height - (t * size.height);
      final opacity = (1.0 - t).clamp(0.0, 0.3);
      final radius = 2.0 + (1.0 - t) * 3.0;

      final paint = Paint()
        ..color = moodColor.withValues(alpha: opacity)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MoodParticlePainter oldDelegate) {
    return time != oldDelegate.time || moodColor != oldDelegate.moodColor;
  }
}
