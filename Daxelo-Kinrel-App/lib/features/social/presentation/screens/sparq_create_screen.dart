import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../../../core/constants/brand_colors.dart';
import '../../data/providers/sparq_provider.dart';

class SparqCreateScreen extends ConsumerStatefulWidget {
  const SparqCreateScreen({super.key});

  @override
  ConsumerState<SparqCreateScreen> createState() => _SparqCreateScreenState();
}

class _SparqCreateScreenState extends ConsumerState<SparqCreateScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _audience = 'PUBLIC';
  String? _text;
  String _backgroundColor = '#1A1A2E';
  File? _mediaFile;
  int? _duration;
  bool _isRecording = false;
  String _timeCapsuleDuration = '1 Day';
  bool _showSuccess = false;
  bool _showError = false;
  bool _isSubmitting = false;

  // ── Premium Dark Design Tokens ──────────────────────────────────────

  // Canvas background tones (dark-dominant)
  static const _canvasBase = Color(0xFF0A0A0A);

  // Tonal swatches for text mode — 6 soft circular options, 28dp each
  static const _bgColors = [
    '#1A1A2E', '#0F3460', '#16213E', '#1A1A2E', '#2D1B36', '#0D1B2A',
  ];

  // Mood design tokens — each mood defines accent, gradient start/end, chip border
  static const _moods = [
    _MoodOption(
      key: 'happy',
      label: 'Happy',
      accent: Color(0xFFFFB300),
      gradientStart: Color(0xFF1A1508),
      gradientEnd: Color(0xFF2A1F0A),
      chipBorder: Color(0xFFFFB300),
    ),
    _MoodOption(
      key: 'hype',
      label: 'Hype',
      accent: Color(0xFFFF5722),
      gradientStart: Color(0xFF1A0E08),
      gradientEnd: Color(0xFF2A1510),
      chipBorder: Color(0xFFFF5722),
    ),
    _MoodOption(
      key: 'love',
      label: 'Love',
      accent: Color(0xFFE91E63),
      gradientStart: Color(0xFF1A0812),
      gradientEnd: Color(0xFF2A0F1A),
      chipBorder: Color(0xFFE91E63),
    ),
    _MoodOption(
      key: 'sad',
      label: 'Sad',
      accent: Color(0xFF5C7AEA),
      gradientStart: Color(0xFF080D1A),
      gradientEnd: Color(0xFF0F152A),
      chipBorder: Color(0xFF5C7AEA),
    ),
    _MoodOption(
      key: 'celebrate',
      label: 'Celebrate',
      accent: Color(0xFFD4AF37),
      gradientStart: Color(0xFF1A1508),
      gradientEnd: Color(0xFF2A200F),
      chipBorder: Color(0xFFD4AF37),
    ),
    _MoodOption(
      key: 'angry',
      label: 'Angry',
      accent: Color(0xFFFF1744),
      gradientStart: Color(0xFF1A080A),
      gradientEnd: Color(0xFF2A0F12),
      chipBorder: Color(0xFFFF1744),
    ),
  ];

  static const _timeCapsuleOptions = ['1 Day', '1 Week', '1 Month', '1 Year'];

  // Content type mode labels — camera-app style
  static const _modeLabels = ['Image', 'Video', 'Text', 'Voice', 'Mood'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String get _currentType {
    switch (_tabController.index) {
      case 0: return 'IMAGE';
      case 1: return 'VIDEO';
      case 2: return 'TEXT';
      case 3: return 'VOICE';
      case 4: return 'TEXT'; // Mood tab creates TEXT type
      default: return 'TEXT';
    }
  }

  _MoodOption get _activeMood {
    final sparqState = ref.read(sparqProvider);
    return _moods.firstWhere(
      (m) => m.key == sparqState.selectedMood,
      orElse: () => _moods[0],
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() => _mediaFile = File(image.path));
    }
  }

  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final video = await picker.pickVideo(source: ImageSource.gallery, maxDuration: Duration(seconds: 60));
    if (video != null) {
      setState(() {
        _mediaFile = File(video.path);
        _duration = 60;
      });
    }
  }

  Future<void> _pickCamera() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      setState(() => _mediaFile = File(image.path));
    }
  }

  DateTime? _computeRevealAt() {
    if (!ref.read(sparqProvider).isTimeCapsule) return null;
    final now = DateTime.now();
    switch (_timeCapsuleDuration) {
      case '1 Day': return now.add(const Duration(days: 1));
      case '1 Week': return now.add(const Duration(days: 7));
      case '1 Month': return now.add(const Duration(days: 30));
      case '1 Year': return now.add(const Duration(days: 365));
      default: return now.add(const Duration(days: 1));
    }
  }

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);
    final success = await ref.read(sparqProvider.notifier).createSparq(
      type: _currentType,
      text: _text,
      backgroundColor: _currentType == 'TEXT' ? _backgroundColor : null,
      audience: _audience,
      mediaFile: _mediaFile,
      duration: _duration,
      revealAt: _computeRevealAt(),
    );
    if (success && mounted) {
      setState(() { _showSuccess = true; _isSubmitting = false; });
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) {
        context.pop();
      }
    } else if (mounted) {
      setState(() => _isSubmitting = false);
      _showErrorDialog(ref.read(sparqProvider).error ?? 'Failed to create Sparq');
    }
  }

  void _showErrorDialog(String errorMessage) {
    final errorCode = _mapErrorCode(errorMessage);
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded, size: 48, color: KinrelColors.warning),
            const SizedBox(height: 16),
            Text(
              _errorTitle(errorCode),
              style: const TextStyle(
                color: KinrelColors.textWhite,
                fontFamily: 'DM Sans',
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorExplanation(errorCode),
              style: TextStyle(
                color: KinrelColors.textSilver,
                fontFamily: 'DM Sans',
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _submit();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: KinrelColors.orange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Retry', style: TextStyle(fontFamily: 'DM Sans', fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.pop();
              },
              child: Text(
                'Save as Draft',
                style: TextStyle(color: KinrelColors.textSilver, fontFamily: 'DM Sans'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _mapErrorCode(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('too large') || lower.contains('file size') || lower.contains('413')) return 'FILE_TOO_LARGE';
    if (lower.contains('connection') || lower.contains('network') || lower.contains('socket')) return 'NO_CONNECTION';
    if (lower.contains('unsupported') || lower.contains('format') || lower.contains('415')) return 'UNSUPPORTED_FORMAT';
    if (lower.contains('upload')) return 'UPLOAD_FAILED';
    return 'SERVER_ERROR';
  }

  String _errorTitle(String code) {
    switch (code) {
      case 'FILE_TOO_LARGE': return 'File Too Large';
      case 'NO_CONNECTION': return 'No Connection';
      case 'UNSUPPORTED_FORMAT': return 'Unsupported Format';
      case 'UPLOAD_FAILED': return 'Upload Failed';
      default: return 'Something Went Wrong';
    }
  }

  String _errorExplanation(String code) {
    switch (code) {
      case 'FILE_TOO_LARGE': return 'Your media file exceeds the 50MB limit. Try compressing it or choosing a smaller file.';
      case 'NO_CONNECTION': return 'Check your internet connection and try again. Your Sparq will be saved as a draft.';
      case 'UNSUPPORTED_FORMAT': return 'This file format isn\'t supported. Please use JPG, PNG, MP4, or MOV.';
      case 'UPLOAD_FAILED': return 'The upload couldn\'t complete. Please retry or save as draft.';
      default: return 'An unexpected error occurred. Please try again or save your Sparq as a draft.';
    }
  }

  // ── Helper ──────────────────────────────────────────────────────────

  Color _parseColor(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', 'FF'), radix: 16));
    } catch (_) {
      return const Color(0xFF1A1A2E);
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final sparqState = ref.watch(sparqProvider);
    final screenHeight = MediaQuery.of(context).size.height;
    final canvasHeight = screenHeight * 0.60;

    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      appBar: AppBar(
        backgroundColor: const Color(0xFF080808),
        elevation: 0,
        centerTitle: false,
        title: Text(
          'Create Sparq',
          style: TextStyle(
            fontFamily: 'DM Sans',
            fontWeight: FontWeight.w600,
            color: KinrelColors.textWhite,
            fontSize: 18,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: KinrelColors.textSilver, size: 20),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          // ── Mode Indicator Line (camera-app style) ───────────────
          _buildModeIndicator(),
          const SizedBox(height: 12),

          // ── Scrollable Content ───────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Canvas (60% screen height) ─────────────────────
                  _buildCanvas(canvasHeight, sparqState),
                  const SizedBox(height: 20),

                  // ── Control Rail ───────────────────────────────────
                  _buildControlRail(sparqState),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          // ── Fixed Bottom CTA ─────────────────────────────────────
          _buildBottomCTA(sparqState),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════
  // MODE INDICATOR — minimal animated label, camera-app style
  // ════════════════════════════════════════════════════════════════════

  Widget _buildModeIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: List.generate(_modeLabels.length, (index) {
          final isActive = _tabController.index == index;
          return GestureDetector(
            onTap: () {
              _tabController.animateTo(index);
              setState(() {});
            },
            child: Padding(
              padding: const EdgeInsets.only(right: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                    style: TextStyle(
                      fontFamily: 'DM Sans',
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                      fontSize: isActive ? 13 : 12,
                      color: isActive ? KinrelColors.textWhite : KinrelColors.textDim,
                      letterSpacing: isActive ? 1.2 : 0.5,
                    ),
                    child: Text(
                      _modeLabels[index].toUpperCase(),
                    ),
                  ),
                  const SizedBox(height: 6),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                    width: isActive ? 20 : 0,
                    height: 2,
                    decoration: BoxDecoration(
                      color: isActive ? _activeMood.accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════
  // CANVAS — two-zone: top 60% live canvas
  // ════════════════════════════════════════════════════════════════════

  Widget _buildCanvas(double height, SparqState sparqState) {
    final mood = _activeMood;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [mood.gradientStart, mood.gradientEnd],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFFFFFFF).withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: KeyedSubtree(
              key: ValueKey(_tabController.index),
              child: _buildCanvasContent(height, sparqState),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCanvasContent(double height, SparqState sparqState) {
    final currentTabIndex = _tabController.index;

    if (currentTabIndex == 4) return _buildMoodCanvas(sparqState);
    if (currentTabIndex == 2) return _buildTextCanvas();
    if (currentTabIndex == 3) return _buildVoiceCanvas();

    if (_mediaFile != null) {
      if (currentTabIndex == 1) return _buildVideoPreview();
      return _buildImagePreview();
    }

    return _buildEmptyCanvas();
  }

  // ── Empty Canvas — single tap target, minimal ─────────────────────

  Widget _buildEmptyCanvas() {
    return GestureDetector(
      onTap: _tabController.index == 1 ? _pickVideo : _pickImage,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Clean line-art glyph — 2dp stroke, rounded caps
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: KinrelColors.textSilver.withValues(alpha: 0.2),
                  width: 1.5,
                ),
              ),
              child: Icon(
                _tabController.index == 1 ? Icons.videocam_outlined : Icons.add_photo_alternate_outlined,
                color: KinrelColors.textSilver.withValues(alpha: 0.4),
                size: 24,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Tap to add',
              style: TextStyle(
                color: KinrelColors.textSilver.withValues(alpha: 0.5),
                fontFamily: 'DM Sans',
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Image Preview ──────────────────────────────────────────────────

  Widget _buildImagePreview() {
    return Stack(
      fit: StackFit.expand,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
          builder: (context, value, child) {
            return Opacity(
              opacity: value,
              child: Transform.scale(
                scale: 0.85 + (0.15 * value),
                child: child,
              ),
            );
          },
          child: Image.file(_mediaFile!, fit: BoxFit.cover, width: double.infinity, height: double.infinity),
        ),
        // X button top-right
        Positioned(
          top: 12,
          right: 12,
          child: GestureDetector(
            onTap: () => setState(() => _mediaFile = null),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.close, color: Colors.white, size: 16),
            ),
          ),
        ),
      ],
    );
  }

  // ── Video Preview ──────────────────────────────────────────────────

  Widget _buildVideoPreview() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(_mediaFile!, fit: BoxFit.cover, width: double.infinity, height: double.infinity),
        Container(color: Colors.black.withValues(alpha: 0.3)),
        // Play button
        Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1),
            ),
            child: Icon(Icons.play_arrow, color: Colors.white, size: 28),
          ),
        ),
        // Duration badge
        Positioned(
          bottom: 12,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${_duration ?? 0}s',
              style: TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'DM Sans'),
            ),
          ),
        ),
        // X button
        Positioned(
          top: 12,
          right: 12,
          child: GestureDetector(
            onTap: () => setState(() { _mediaFile = null; _duration = null; }),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.close, color: Colors.white, size: 16),
            ),
          ),
        ),
      ],
    );
  }

  // ── Text Canvas ────────────────────────────────────────────────────

  Widget _buildTextCanvas() {
    return Container(
      color: _parseColor(_backgroundColor),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Expanded(
            child: TextField(
              onChanged: (v) => setState(() => _text = v),
              maxLines: null,
              expands: true,
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w600,
                fontFamily: 'DM Sans',
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'say something real',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontFamily: 'DM Sans',
                  fontWeight: FontWeight.w300,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Tonal pill-strip — 6 swatches, 28dp, active 34dp with ring
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _bgColors.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final color = _bgColors[index];
                final isSelected = color == _backgroundColor;
                return GestureDetector(
                  onTap: () => setState(() => _backgroundColor = color),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: isSelected ? 34 : 28,
                    height: isSelected ? 34 : 28,
                    decoration: BoxDecoration(
                      color: _parseColor(color),
                      shape: BoxShape.circle,
                      border: isSelected
                          ? Border.all(color: Colors.white, width: 2)
                          : Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1),
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

  // ── Voice Canvas — minimal mic glyph, breathing pulse ─────────────

  Widget _buildVoiceCanvas() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Breathing pulse mic
          GestureDetector(
            onTapDown: (_) => setState(() => _isRecording = true),
            onTapUp: (_) => setState(() {
              _isRecording = false;
              _duration = 10;
            }),
            child: _buildMicWithPulse(),
          ),
          const SizedBox(height: 16),
          Text(
            _isRecording ? 'Release to stop' : 'HOLD TO RECORD',
            style: TextStyle(
              color: _isRecording ? KinrelColors.error : KinrelColors.textSilver.withValues(alpha: 0.4),
              fontSize: 11,
              fontFamily: 'DM Sans',
              fontWeight: FontWeight.w400,
              letterSpacing: _isRecording ? 0 : 2.0,
            ),
          ),
          if (_isRecording) ...[
            const SizedBox(height: 8),
            Text(
              'Max 60s',
              style: TextStyle(
                color: KinrelColors.textDim,
                fontSize: 10,
                fontFamily: 'DM Sans',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMicWithPulse() {
    if (!_isRecording) {
      return Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF1A1A1A),
          border: Border.all(color: KinrelColors.textSilver.withValues(alpha: 0.15), width: 1),
        ),
        child: Icon(Icons.mic_none_outlined, color: KinrelColors.textSilver.withValues(alpha: 0.5), size: 28),
      );
    }

    // Recording state — breathing pulse
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Radial pulse ring
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.6, end: 1.0),
            duration: const Duration(milliseconds: 1200),
            curve: Curves.easeInOut,
            builder: (context, value, child) {
              return Container(
                width: 96 * value,
                height: 96 * value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: KinrelColors.error.withValues(alpha: 0.08 * value),
                  border: Border.all(
                    color: KinrelColors.error.withValues(alpha: 0.15 * value),
                    width: 1,
                  ),
                ),
              );
            },
            onEnd: () => setState(() {}),
            child: const SizedBox.shrink(),
          ),
          // Core mic circle
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: KinrelColors.error.withValues(alpha: 0.15),
              border: Border.all(color: KinrelColors.error, width: 1.5),
            ),
            child: Icon(Icons.mic, color: KinrelColors.error, size: 28),
          ),
        ],
      ),
    );
  }

  // ── Mood Canvas — display typography, no emoji ─────────────────────

  Widget _buildMoodCanvas(SparqState sparqState) {
    final selectedMood = _moods.firstWhere(
      (m) => m.key == sparqState.selectedMood,
      orElse: () => _moods[0],
    );

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Large display typography — mood name in accent color
          Text(
            selectedMood.label.toUpperCase(),
            style: TextStyle(
              color: selectedMood.accent,
              fontFamily: 'DM Sans',
              fontWeight: FontWeight.w700,
              fontSize: 48,
              letterSpacing: 4,
              shadows: [
                Shadow(
                  color: selectedMood.accent.withValues(alpha: 0.3),
                  blurRadius: 24,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'your vibe for this sparq',
            style: TextStyle(
              color: KinrelColors.textSilver.withValues(alpha: 0.5),
              fontFamily: 'DM Sans',
              fontWeight: FontWeight.w400,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════
  // CONTROL RAIL — bottom 40% configuration
  // ════════════════════════════════════════════════════════════════════

  Widget _buildControlRail(SparqState sparqState) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Mood Selector ──────────────────────────────────────
          _buildMoodSelector(sparqState),
          const SizedBox(height: 20),

          // ── Intensity Slider ───────────────────────────────────
          _buildIntensitySlider(sparqState),
          const SizedBox(height: 20),

          // ── Audience Selector ──────────────────────────────────
          _buildAudienceSelector(),
          const SizedBox(height: 20),

          // ── Feature Toggles ───────────────────────────────────
          _buildFeatureToggles(sparqState),
          const SizedBox(height: 8),

          // ── Expiry Hint ───────────────────────────────────────
          Center(
            child: Text(
              'Expires in 24h',
              style: TextStyle(
                color: KinrelColors.textDim,
                fontFamily: 'DM Sans',
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════
  // MOOD SELECTOR — horizontal capsule chips, no emoji
  // ════════════════════════════════════════════════════════════════════

  Widget _buildMoodSelector(SparqState sparqState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _moods.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final mood = _moods[index];
              final isSelected = sparqState.selectedMood == mood.key;
              return GestureDetector(
                onTap: () {
                  ref.read(sparqProvider.notifier).setSelectedMood(mood.key);
                  // Trigger canvas pulse to acknowledge change
                  setState(() {});
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  height: 44,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? mood.accent.withValues(alpha: 0.25)
                        : const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: isSelected ? mood.accent.withValues(alpha: 0.5) : const Color(0xFFFFFFFF).withValues(alpha: 0.06),
                      width: 1,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      mood.label,
                      style: TextStyle(
                        color: isSelected ? mood.accent : KinrelColors.textSilver.withValues(alpha: 0.5),
                        fontFamily: 'DM Sans',
                        fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════
  // INTENSITY SLIDER — gradient track, clean thumb, inline labels
  // ════════════════════════════════════════════════════════════════════

  Widget _buildIntensitySlider(SparqState sparqState) {
    final intensity = sparqState.selectedIntensity;
    final mood = _activeMood;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Track with gradient from neutral to mood accent
        SizedBox(
          height: 28,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Custom gradient track
              Container(
                height: 4,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF2A2A2A),
                      mood.accent.withValues(alpha: 0.6),
                      mood.accent,
                    ],
                  ),
                ),
              ),
              // Slider overlay
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4,
                  thumbColor: Colors.white,
                  overlayColor: Colors.white.withValues(alpha: 0.08),
                  activeTrackColor: Colors.transparent,
                  inactiveTrackColor: Colors.transparent,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 8,
                    elevation: 2,
                  ),
                ),
                child: Slider(
                  value: intensity,
                  onChanged: (v) => ref.read(sparqProvider.notifier).setSelectedIntensity(v),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // Inline labels — Subtle / Intense
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Subtle',
              style: TextStyle(
                color: KinrelColors.textDim,
                fontSize: 11,
                fontFamily: 'DM Sans',
                fontWeight: FontWeight.w400,
              ),
            ),
            Text(
              'Intense',
              style: TextStyle(
                color: mood.accent.withValues(alpha: 0.6),
                fontSize: 11,
                fontFamily: 'DM Sans',
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════
  // AUDIENCE SELECTOR — segmented toggle bar (iOS-style, darker)
  // ════════════════════════════════════════════════════════════════════

  Widget _buildAudienceSelector() {
    final segments = [
      _SegmentData(key: 'PUBLIC', label: 'Everyone'),
      _SegmentData(key: 'FAMILY_ONLY', label: 'Family'),
      _SegmentData(key: 'VIP', label: 'VIP'),
    ];

    final descriptions = {
      'PUBLIC': 'All your followers can see this Sparq',
      'FAMILY_ONLY': 'Only family members will see this',
      'VIP': 'Only your closest connections',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Segmented control
        Container(
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFFFFFFF).withValues(alpha: 0.06), width: 1),
          ),
          child: Row(
            children: segments.map((seg) {
              final isActive = _audience == seg.key;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _audience = seg.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                    decoration: BoxDecoration(
                      color: isActive ? _activeMood.accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Center(
                      child: Text(
                        seg.label,
                        style: TextStyle(
                          color: isActive ? Colors.white : KinrelColors.textSilver.withValues(alpha: 0.5),
                          fontFamily: 'DM Sans',
                          fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        // Description line
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            descriptions[_audience] ?? '',
            key: ValueKey(_audience),
            style: TextStyle(
              color: KinrelColors.textDim,
              fontFamily: 'DM Sans',
              fontSize: 11,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════
  // FEATURE TOGGLES — compact inline rows with hairline dividers
  // ════════════════════════════════════════════════════════════════════

  Widget _buildFeatureToggles(SparqState sparqState) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFFFFF).withValues(alpha: 0.06), width: 1),
      ),
      child: Column(
        children: [
          _buildToggleRow(
            label: 'Time Capsule',
            value: sparqState.isTimeCapsule,
            onChanged: (v) => ref.read(sparqProvider.notifier).setTimeCapsule(v),
          ),
          Divider(height: 1, color: const Color(0xFFFFFFFF).withValues(alpha: 0.08)),
          _buildToggleRow(
            label: 'Allow Chain',
            value: sparqState.allowChain,
            onChanged: (v) => ref.read(sparqProvider.notifier).setAllowChain(v),
          ),
          Divider(height: 1, color: const Color(0xFFFFFFFF).withValues(alpha: 0.08)),
          _buildToggleRow(
            label: 'Allow Replies',
            value: sparqState.allowReplies,
            onChanged: (v) => ref.read(sparqProvider.notifier).setAllowReplies(v),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleRow({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: value ? KinrelColors.textWhite : KinrelColors.textSilver.withValues(alpha: 0.6),
              fontFamily: 'DM Sans',
              fontWeight: FontWeight.w400,
              fontSize: 13,
            ),
          ),
          // Minimal pill toggle
          GestureDetector(
            onTap: () => onChanged(!value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              width: 40,
              height: 22,
              decoration: BoxDecoration(
                color: value ? _activeMood.accent : const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(11),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 18,
                  height: 18,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════
  // BOTTOM CTA — Ignite Sparq, gradient fill, spring press animation
  // ════════════════════════════════════════════════════════════════════

  Widget _buildBottomCTA(SparqState sparqState) {
    final mood = _activeMood;

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF080808),
        border: Border(
          top: BorderSide(color: const Color(0xFFFFFFFF).withValues(alpha: 0.06), width: 1),
        ),
      ),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _showSuccess = true),
        onTapUp: (_) async {
          setState(() => _showSuccess = false);
          await _submit();
        },
        onTapCancel: () => setState(() => _showSuccess = false),
        child: AnimatedScale(
          scale: _showSuccess ? 0.96 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: Container(
            height: 56,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [mood.accent, mood.accent.withValues(alpha: 0.7)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: _isSubmitting
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      'Ignite Sparq',
                      style: TextStyle(
                        color: Colors.white,
                        fontFamily: 'DM Sans',
                        fontWeight: FontWeight.w500,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// DATA CLASSES
// ══════════════════════════════════════════════════════════════════════

class _MoodOption {
  final String key;
  final String label;
  final Color accent;
  final Color gradientStart;
  final Color gradientEnd;
  final Color chipBorder;

  const _MoodOption({
    required this.key,
    required this.label,
    required this.accent,
    required this.gradientStart,
    required this.gradientEnd,
    required this.chipBorder,
  });
}

class _SegmentData {
  final String key;
  final String label;

  const _SegmentData({required this.key, required this.label});
}
