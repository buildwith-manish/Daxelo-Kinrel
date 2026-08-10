import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/brand_colors.dart';
import '../../../../core/services/supabase_service.dart';
import '../../data/models/sparq_model.dart';
import '../../data/providers/sparq_provider.dart';
import '../../data/repositories/sparq_repository.dart';

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
  late AnimationController _particleController;

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
    // Particle animation controller — continuous repaint
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
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
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete Sparq', style: TextStyle(color: Colors.white, fontFamily: 'DM Sans', fontWeight: FontWeight.w600)),
        content: Text('Are you sure you want to delete this Sparq?',
            style: TextStyle(color: KinrelColors.textSilver, fontFamily: 'DM Sans')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: KinrelColors.textSilver, fontFamily: 'DM Sans')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: KinrelColors.error, fontFamily: 'DM Sans', fontWeight: FontWeight.w600)),
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

  /// Submit a text reply to the current Sparq (v91).
  /// Inserts into Supabase `SparqReply` table via SparqRepository.
  Future<void> _submitReply(SparqModel sparq) async {
    final text = _replyText?.trim();
    if (text == null || text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please type a reply first')),
      );
      return;
    }

    final client = ref.read(supabaseProvider);
    final myUserId = client?.auth.currentUser?.id;
    if (myUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to reply')),
      );
      return;
    }

    final userMeta = client?.auth.currentUser?.userMetadata;
    final myName = (userMeta?['name'] as String?) ??
        (userMeta?['full_name'] as String?) ??
        'Member';
    final myAvatar = userMeta?['avatar_url'] as String?;

    // Clear the field immediately for UX
    setState(() => _replyText = null);

    final repo = ref.read(sparqRepositoryProvider);
    final reply = await repo.replyToSparq(
      sparqId: sparq.id,
      userId: myUserId,
      userName: myName,
      userAvatarUrl: myAvatar,
      content: text,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(reply != null ? 'Reply sent!' : 'Failed to send reply'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  void dispose() {
    _progressController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  // ── Mood accent color helper ──────────────────────────────────────

  Color _getMoodAccent(String? mood) {
    switch (mood) {
      case 'happy': return const Color(0xFFFFB300);
      case 'hype': return const Color(0xFFFF5722);
      case 'love': return const Color(0xFFE91E63);
      case 'sad': return const Color(0xFF5C7AEA);
      case 'celebrate': return const Color(0xFFD4AF37);
      case 'angry': return const Color(0xFFFF1744);
      default: return KinrelColors.orange;
    }
  }

  // ── Parse color helper ─────────────────────────────────────────────

  Color _parseBackgroundColor(String? hex) {
    if (hex == null || hex.isEmpty) return const Color(0xFF1A1A1A);
    try {
      return Color(int.parse(hex.replaceFirst('#', 'FF'), radix: 16));
    } catch (_) {
      return const Color(0xFF1A1A1A);
    }
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
    final moodAccent = _getMoodAccent(sparq.mood);

    // Time capsule locked state
    if (sparq.isLockedTimeCapsule) {
      return _buildTimeCapsuleLocked(sparq, moodAccent);
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
              AnimatedBuilder(
                animation: _particleController,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _MoodParticlePainter(
                      moodColor: moodAccent,
                      time: _particleController.value,
                    ),
                    size: Size.infinite,
                  );
                },
              ),

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
                    colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 200,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.8)],
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
                        color: Colors.white.withValues(alpha: 0.15),
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
                            color: moodAccent,
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
                  _buildIntensityRingAvatar(sparq, moodAccent),
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
                            fontFamily: 'DM Sans',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Row(
                          children: [
                            Text(
                              _timeAgo(sparq.createdAt),
                              style: TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'DM Sans'),
                            ),
                            // Mood chip — no emoji, just name in accent
                            if (sparq.mood.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: moodAccent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: moodAccent.withValues(alpha: 0.3), width: 0.5),
                                ),
                                child: Text(
                                  sparq.mood[0].toUpperCase() + sparq.mood.substring(1),
                                  style: TextStyle(
                                    color: moodAccent,
                                    fontSize: 9,
                                    fontFamily: 'DM Sans',
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Close button
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.white70, size: 22),
                    onPressed: () { if (context.canPop()) { context.pop(); } else { context.go('/home'); } },
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
                  // Action buttons row — clean line icons, no emojis
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Echo button
                      _buildActionButton(
                        icon: isEchoed ? Icons.whatshot : Icons.whatshot_outlined,
                        label: 'Echo',
                        count: echoCount,
                        isActive: isEchoed,
                        accentColor: moodAccent,
                        onTap: _toggleEcho,
                      ),
                      const SizedBox(width: 20),
                      // Chain button (if allowChain)
                      if (sparq.allowChain)
                        _buildActionButton(
                          icon: Icons.link_outlined,
                          label: 'Chain',
                          count: null,
                          isActive: false,
                          accentColor: moodAccent,
                          onTap: () {
                            context.push('/sparq/create');
                          },
                        ),
                      if (sparq.allowChain)
                        const SizedBox(width: 20),
                      // Reply button (if allowReplies)
                      if (sparq.allowReplies)
                        _buildActionButton(
                          icon: Icons.chat_bubble_outline,
                          label: 'Reply',
                          count: null,
                          isActive: false,
                          accentColor: moodAccent,
                          onTap: () {
                            setState(() {});
                          },
                        ),
                      const Spacer(),
                      // Delete button (creator only)
                      IconButton(
                        icon: Icon(Icons.delete_outline, color: Colors.white38, size: 20),
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
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.06), width: 1),
                      ),
                      child: TextField(
                        onChanged: (v) => _replyText = v,
                        style: TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'DM Sans'),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          hintText: 'Reply to Sparq...',
                          hintStyle: TextStyle(color: Colors.white30, fontSize: 14, fontFamily: 'DM Sans'),
                          suffixIcon: IconButton(
                            icon: Icon(Icons.send, color: moodAccent, size: 18),
                            onPressed: () => _submitReply(sparq),
                          ),
                        ),
                      ),
                    ),
                  // Audience badge
                  if (sparq.audience == 'FAMILY_ONLY') ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: moodAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: moodAccent.withValues(alpha: 0.3), width: 0.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.family_restroom, size: 12, color: moodAccent),
                          SizedBox(width: 4),
                          Text('Family',
                            style: TextStyle(color: moodAccent, fontSize: 10, fontWeight: FontWeight.w600, fontFamily: 'DM Sans'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (sparq.audience == 'VIP') ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: moodAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: moodAccent.withValues(alpha: 0.3), width: 0.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star_outline, size: 12, color: moodAccent),
                          SizedBox(width: 4),
                          Text('VIP',
                            style: TextStyle(color: moodAccent, fontSize: 10, fontWeight: FontWeight.w600, fontFamily: 'DM Sans'),
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

  Widget _buildIntensityRingAvatar(SparqModel sparq, Color moodAccent) {
    Color ringColor;
    double ringWidth = 2.5;

    switch (sparq.intensity) {
      case 'calm':
        ringColor = const Color(0xFF5C7AEA);
        break;
      case 'fire':
        ringColor = const Color(0xFFFF1744);
        break;
      default:
        ringColor = moodAccent;
    }

    // Time capsule: gold dashed ring
    if (sparq.isTimeCapsule) {
      ringColor = const Color(0xFFD4AF37);
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
          backgroundColor: const Color(0xFF1A1A1A),
          child: Icon(Icons.person, size: 18, color: KinrelColors.textSilver.withValues(alpha: 0.5)),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // ACTION BUTTON — clean line icons, no emojis
  // ══════════════════════════════════════════════════════════════════

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required int? count,
    required bool isActive,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? accentColor.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? accentColor.withValues(alpha: 0.3) : Colors.transparent,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isActive ? accentColor : Colors.white54),
            if (count != null) ...[
              const SizedBox(width: 4),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  '$count',
                  key: ValueKey(count),
                  style: TextStyle(
                    color: isActive ? accentColor : Colors.white54,
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
                  color: isActive ? accentColor : Colors.white54,
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
  // TIME CAPSULE LOCKED STATE — no emoji
  // ══════════════════════════════════════════════════════════════════

  Widget _buildTimeCapsuleLocked(SparqModel sparq, Color moodAccent) {
    final remaining = sparq.timeUntilReveal ?? Duration.zero;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Dark mood-tinted background
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  moodAccent.withValues(alpha: 0.05),
                  const Color(0xFF080808),
                ],
              ),
            ),
          ),
          // Lock content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_clock_outlined, size: 56, color: const Color(0xFFD4AF37)),
                const SizedBox(height: 24),
                Text(
                  'Time Capsule',
                  style: TextStyle(
                    color: KinrelColors.textWhite,
                    fontFamily: 'DM Sans',
                    fontWeight: FontWeight.w600,
                    fontSize: 20,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This Sparq is locked until',
                  style: TextStyle(color: KinrelColors.textSilver, fontFamily: 'DM Sans', fontSize: 14),
                ),
                const SizedBox(height: 8),
                Text(
                  _formatDuration(remaining),
                  style: TextStyle(
                    color: const Color(0xFFD4AF37),
                    fontFamily: 'DM Sans',
                    fontWeight: FontWeight.w600,
                    fontSize: 28,
                  ),
                ),
                const SizedBox(height: 40),
                IconButton(
                  icon: Icon(Icons.close, color: KinrelColors.textSilver, size: 24),
                  onPressed: () { if (context.canPop()) { context.pop(); } else { context.go('/home'); } },
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
                  errorBuilder: (_, __, ___) => Container(color: const Color(0xFF0A0A0A)),
                )
              else
                Container(color: const Color(0xFF0A0A0A)),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
                ),
                child: Icon(Icons.play_arrow, color: Colors.white, size: 28),
              ),
              // Duration badge
              Positioned(
                bottom: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${sparq.duration ?? 0}s',
                    style: TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'DM Sans'),
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
                  fontFamily: 'DM Sans',
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
              Icon(Icons.graphic_eq, size: 56, color: _getMoodAccent(sparq.mood).withValues(alpha: 0.6)),
              SizedBox(height: 12),
              Text('Voice Note', style: TextStyle(color: Colors.white54, fontSize: 14, fontFamily: 'DM Sans')),
              SizedBox(height: 4),
              Text('${sparq.duration ?? 0}s',
                style: TextStyle(color: Colors.white38, fontSize: 12, fontFamily: 'DM Sans')),
            ],
          ),
        );
      default:
        return _buildErrorContent();
    }
  }

  Widget _buildErrorContent() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, size: 40, color: Colors.white24),
          SizedBox(height: 8),
          Text('Content unavailable', style: TextStyle(color: Colors.white24, fontFamily: 'DM Sans')),
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
// MOOD PARTICLE PAINTER — continuously animated
// ══════════════════════════════════════════════════════════════════════

class _MoodParticlePainter extends CustomPainter {
  final Color moodColor;
  final double time;

  _MoodParticlePainter({required this.moodColor, required this.time});

  @override
  void paint(Canvas canvas, Size size) {
    final particleCount = 12;
    for (int i = 0; i < particleCount; i++) {
      final seed = i * 137.508; // Golden angle
      final t = (time + seed * 0.01) % 1.0;

      final x = (seed * 7.3 + t * size.width * 0.3) % size.width;
      final y = size.height - (t * size.height);
      final opacity = (1.0 - t).clamp(0.0, 0.2);
      final radius = 1.5 + (1.0 - t) * 2.5;

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
