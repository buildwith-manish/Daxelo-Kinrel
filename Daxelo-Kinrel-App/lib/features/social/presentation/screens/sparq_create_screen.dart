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
  String _backgroundColor = '#E8612A';
  File? _mediaFile;
  int? _duration;
  bool _isRecording = false;
  String _timeCapsuleDuration = '1 Day';
  bool _showSuccess = false;
  bool _showError = false;

  static const _bgColors = [
    '#E8612A', '#C44A18', '#F59240', '#3B82F6', '#4CAF7A',
    '#8B5CF6', '#EF4444', '#1A1A2E', '#16213E', '#0F3460',
  ];

  static const _moods = [
    _MoodOption(key: 'happy', emoji: '😊', label: 'Happy', color: Color(0xFFFFB300)),
    _MoodOption(key: 'hype', emoji: '🔥', label: 'Hype', color: Color(0xFFFF5722)),
    _MoodOption(key: 'love', emoji: '💝', label: 'Love', color: Color(0xFFE91E63)),
    _MoodOption(key: 'sad', emoji: '😢', label: 'Sad', color: Color(0xFF2196F3)),
    _MoodOption(key: 'celebrate', emoji: '🎉', label: 'Celebrate', color: Color(0xFF9C27B0)),
    _MoodOption(key: 'angry', emoji: '😤', label: 'Angry', color: Color(0xFFFF1744)),
  ];

  static const _timeCapsuleOptions = ['1 Day', '1 Week', '1 Month', '1 Year'];

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
      setState(() => _showSuccess = true);
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) {
        context.pop();
      }
    } else if (mounted) {
      _showErrorDialog(ref.read(sparqProvider).error ?? 'Failed to create Sparq');
    }
  }

  void _showErrorDialog(String errorMessage) {
    final errorCode = _mapErrorCode(errorMessage);
    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.elevation3,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
              style: TextStyle(
                color: KinrelColors.textWhite,
                fontFamily: 'Outfit',
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                child: Text('Retry', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                // Save as draft — for now just go back
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

  @override
  Widget build(BuildContext context) {
    final sparqState = ref.watch(sparqProvider);
    final screenHeight = MediaQuery.of(context).size.height;
    final canvasHeight = screenHeight * 0.55;

    return Scaffold(
      backgroundColor: const Color(0xFF131416),
      appBar: AppBar(
        backgroundColor: const Color(0xFF131416),
        elevation: 0,
        title: Text('Create Sparq', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: KinrelColors.textWhite),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Scrollable Tab Bar ─────────────────────────────────
            _buildTabBar(),
            const SizedBox(height: 16),

            // ── Canvas (55% screen height) ─────────────────────────
            _buildCanvas(canvasHeight, sparqState),
            const SizedBox(height: 20),

            // ── Mood Selector ──────────────────────────────────────
            _buildMoodSelector(sparqState),
            const SizedBox(height: 20),

            // ── Intensity Meter ────────────────────────────────────
            _buildIntensityMeter(sparqState),
            const SizedBox(height: 20),

            // ── Audience Selector ──────────────────────────────────
            _buildAudienceSelector(),
            const SizedBox(height: 20),

            // ── Quick Toggles ─────────────────────────────────────
            _buildQuickToggles(sparqState),
            const SizedBox(height: 20),

            // ── Expiry Hint ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Sparq expires in 24h ⏱️',
                style: TextStyle(
                  color: KinrelColors.textDim,
                  fontFamily: 'DM Sans',
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 12),

            // ── Enhanced Post Button ───────────────────────────────
            _buildPostButton(sparqState),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // TAB BAR
  // ══════════════════════════════════════════════════════════════════

  Widget _buildTabBar() {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 5,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final isSelected = _tabController.index == index;
          final tabs = [
            _TabData(icon: Icons.image, label: 'Image'),
            _TabData(icon: Icons.videocam, label: 'Video'),
            _TabData(icon: Icons.text_fields, label: 'Text'),
            _TabData(icon: Icons.mic, label: 'Voice'),
            _TabData(icon: Icons.emoji_emotions, label: 'Mood 🎭'),
          ];
          final tab = tabs[index];
          return GestureDetector(
            onTap: () {
              _tabController.animateTo(index);
              setState(() {});
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: isSelected
                    ? const LinearGradient(
                        colors: [Color(0xFFFF5722), Color(0xFFFF1744)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      )
                    : null,
                color: isSelected ? null : KinrelColors.elevation1,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(tab.icon, size: 18, color: isSelected ? Colors.white : KinrelColors.textSilver),
                  const SizedBox(width: 6),
                  Text(
                    tab.label,
                    style: TextStyle(
                      color: isSelected ? Colors.white : KinrelColors.textSilver,
                      fontFamily: 'DM Sans',
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
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

  // ══════════════════════════════════════════════════════════════════
  // CANVAS
  // ══════════════════════════════════════════════════════════════════

  Widget _buildCanvas(double height, SparqState sparqState) {
    final intensityColor = sparqState.intensityLabel == 'calm'
        ? const Color(0xFF2196F3)
        : sparqState.intensityLabel == 'fire'
            ? const Color(0xFFFF1744)
            : const Color(0xFFFF9800);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: intensityColor.withValues(alpha: 0.6),
            width: 1.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: _buildCanvasContent(height, sparqState),
        ),
      ),
    );
  }

  Widget _buildCanvasContent(double height, SparqState sparqState) {
    final currentTabIndex = _tabController.index;

    // Mood tab
    if (currentTabIndex == 4) {
      return _buildMoodCanvas(sparqState);
    }

    // Text tab
    if (currentTabIndex == 2) {
      return _buildTextCanvas();
    }

    // Voice tab
    if (currentTabIndex == 3) {
      return _buildVoiceCanvas();
    }

    // Image / Video tab with media selected
    if (_mediaFile != null) {
      if (currentTabIndex == 1) {
        return _buildVideoPreview();
      }
      return _buildImagePreview();
    }

    // Empty state for Image / Video
    return _buildEmptyCanvas();
  }

  Widget _buildEmptyCanvas() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.85, end: 1.0),
            duration: const Duration(milliseconds: 1200),
            curve: Curves.elasticOut,
            builder: (context, scale, child) {
              return Transform.scale(scale: scale, child: child);
            },
            child: Icon(Icons.local_fire_department, size: 56, color: KinrelColors.orange.withValues(alpha: 0.5)),
          ),
          const SizedBox(height: 12),
          Text(
            'Bring Your Sparq Alive',
            style: TextStyle(
              color: KinrelColors.textWhite,
              fontFamily: 'Outfit',
              fontWeight: FontWeight.w600,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildMiniAction(Icons.camera_alt, 'Camera', _pickCamera),
              const SizedBox(width: 16),
              _buildMiniAction(Icons.photo_library, 'Gallery', _tabController.index == 1 ? _pickVideo : _pickImage),
              const SizedBox(width: 16),
              _buildMiniAction(Icons.create, 'Create', () {
                _tabController.animateTo(2);
                setState(() {});
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniAction(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: KinrelColors.elevation2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: KinrelColors.orange.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: KinrelColors.orange),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: KinrelColors.textSilver,
                fontFamily: 'DM Sans',
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Animated image entry
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
        // Floating edit tools (frosted glass)
        Positioned(
          bottom: 16,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.edit, size: 16, color: Colors.white70),
                const SizedBox(width: 6),
                Text('Tap to edit', style: TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'DM Sans')),
              ],
            ),
          ),
        ),
        // X button top-right
        Positioned(
          top: 12,
          right: 12,
          child: GestureDetector(
            onTap: () => setState(() => _mediaFile = null),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.close, color: Colors.white, size: 18),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVideoPreview() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Thumbnail
        Image.file(_mediaFile!, fit: BoxFit.cover, width: double.infinity, height: double.infinity),
        // Dark overlay
        Container(color: Colors.black.withValues(alpha: 0.3)),
        // Play button
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.play_arrow, color: Colors.white, size: 36),
          ),
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
              '${_duration ?? 0}s',
              style: TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'DM Sans'),
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
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.close, color: Colors.white, size: 18),
            ),
          ),
        ),
      ],
    );
  }

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
                fontFamily: 'Outfit',
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'Type something...',
                hintStyle: TextStyle(color: Colors.white54),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _bgColors.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final color = _bgColors[index];
                final isSelected = color == _backgroundColor;
                return GestureDetector(
                  onTap: () => setState(() => _backgroundColor = color),
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: _parseColor(color),
                      shape: BoxShape.circle,
                      border: isSelected
                          ? Border.all(color: Colors.white, width: 3)
                          : null,
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

  Widget _buildVoiceCanvas() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTapDown: (_) => setState(() => _isRecording = true),
            onTapUp: (_) => setState(() {
              _isRecording = false;
              _duration = 10;
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 80, height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isRecording ? KinrelColors.error : KinrelColors.orange,
                boxShadow: _isRecording
                    ? [BoxShadow(color: KinrelColors.error.withValues(alpha: 0.4), blurRadius: 20, spreadRadius: 4)]
                    : null,
              ),
              child: Icon(
                _isRecording ? Icons.stop : Icons.mic,
                color: Colors.white,
                size: 36,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _isRecording ? 'Release to stop' : 'Hold to record (max 60s)',
            style: TextStyle(color: KinrelColors.textSilver, fontSize: 13, fontFamily: 'DM Sans'),
          ),
        ],
      ),
    );
  }

  Widget _buildMoodCanvas(SparqState sparqState) {
    final selectedMood = _moods.firstWhere(
      (m) => m.key == sparqState.selectedMood,
      orElse: () => _moods[0],
    );
    return Container(
      color: selectedMood.color.withValues(alpha: 0.15),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              selectedMood.emoji,
              style: TextStyle(fontSize: 64),
            ),
            const SizedBox(height: 12),
            Text(
              '${selectedMood.label} Sparq',
              style: TextStyle(
                color: selectedMood.color,
                fontFamily: 'Outfit',
                fontWeight: FontWeight.w600,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Select a mood below to customize',
              style: TextStyle(
                color: KinrelColors.textSilver,
                fontFamily: 'DM Sans',
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // MOOD SELECTOR
  // ══════════════════════════════════════════════════════════════════

  Widget _buildMoodSelector(SparqState sparqState) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '✨ Set Your Sparq Mood',
            style: TextStyle(
              color: KinrelColors.textWhite,
              fontFamily: 'Outfit',
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _moods.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final mood = _moods[index];
                final isSelected = sparqState.selectedMood == mood.key;
                return GestureDetector(
                  onTap: () => ref.read(sparqProvider.notifier).setSelectedMood(mood.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    width: 64,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? mood.color.withValues(alpha: 0.25)
                          : mood.color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? mood.color : Colors.transparent,
                        width: isSelected ? 2 : 0,
                      ),
                      boxShadow: isSelected
                          ? [BoxShadow(color: mood.color.withValues(alpha: 0.3), blurRadius: 12, spreadRadius: 2)]
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedScale(
                          scale: isSelected ? 1.1 : 1.0,
                          duration: const Duration(milliseconds: 250),
                          child: Text(mood.emoji, style: TextStyle(fontSize: 24)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          mood.label,
                          style: TextStyle(
                            color: isSelected ? Colors.white : KinrelColors.textSilver.withValues(alpha: 0.6),
                            fontSize: 10,
                            fontFamily: 'DM Sans',
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
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

  // ══════════════════════════════════════════════════════════════════
  // INTENSITY METER
  // ══════════════════════════════════════════════════════════════════

  Widget _buildIntensityMeter(SparqState sparqState) {
    final intensity = sparqState.selectedIntensity;
    final label = sparqState.intensityLabel;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '🌡️ Sparq Intensity',
            style: TextStyle(
              color: KinrelColors.textWhite,
              fontFamily: 'Outfit',
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 16),
          Stack(
            clipBehavior: Clip.none,
            children: [
              // Gradient track background
              Container(
                height: 8,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2196F3), Color(0xFFFF9800), Color(0xFFFF1744)],
                  ),
                ),
              ),
              // Slider
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 8,
                  thumbColor: Colors.white,
                  overlayColor: Colors.white.withValues(alpha: 0.1),
                  activeTrackColor: Colors.transparent,
                  inactiveTrackColor: Colors.transparent,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
                ),
                child: Slider(
                  value: intensity,
                  onChanged: (v) => ref.read(sparqProvider.notifier).setSelectedIntensity(v),
                ),
              ),
              // Floating badge above thumb
              Positioned(
                left: (intensity * (MediaQuery.of(context).size.width - 80)) - 20,
                top: -28,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    key: ValueKey(label),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: label == 'calm'
                          ? const Color(0xFF2196F3)
                          : label == 'fire'
                              ? const Color(0xFFFF1744)
                              : const Color(0xFFFF9800),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      label == 'calm' ? '😐 Calm' : label == 'fire' ? '🔥 Fire' : '🌤️ Warm',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontFamily: 'DM Sans',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('😐 Calm', style: TextStyle(color: Color(0xFF2196F3), fontSize: 11, fontFamily: 'DM Sans')),
              Text('🔥 Fire', style: TextStyle(color: Color(0xFFFF1744), fontSize: 11, fontFamily: 'DM Sans')),
            ],
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // AUDIENCE SELECTOR
  // ══════════════════════════════════════════════════════════════════

  Widget _buildAudienceSelector() {
    final audiences = [
      _AudienceOption(
        key: 'PUBLIC',
        icon: Icons.public,
        title: 'Everyone',
        subtitle: 'All your followers can see',
      ),
      _AudienceOption(
        key: 'FAMILY_ONLY',
        icon: Icons.family_restroom,
        title: 'Family Only',
        subtitle: 'Only family members can see',
      ),
      _AudienceOption(
        key: 'VIP',
        icon: Icons.star,
        title: '⭐ VIP Circle',
        subtitle: 'Only your closest connections',
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Audience',
            style: TextStyle(
              color: KinrelColors.textWhite,
              fontFamily: 'Outfit',
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          ...audiences.map((aud) {
            final isSelected = _audience == aud.key;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () => setState(() => _audience = aud.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  height: 72,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? KinrelColors.orange.withValues(alpha: 0.1)
                        : KinrelColors.elevation1,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? KinrelColors.orange : KinrelColors.elevation2,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Icon(aud.icon, color: isSelected ? KinrelColors.orange : KinrelColors.textSilver, size: 24),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                aud.title,
                                style: TextStyle(
                                  color: isSelected ? KinrelColors.textWhite : KinrelColors.textSilver,
                                  fontFamily: 'Outfit',
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                aud.subtitle,
                                style: TextStyle(
                                  color: KinrelColors.textDim,
                                  fontFamily: 'DM Sans',
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                          color: isSelected ? KinrelColors.orange : KinrelColors.textDim,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // QUICK TOGGLES
  // ══════════════════════════════════════════════════════════════════

  Widget _buildQuickToggles(SparqState sparqState) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildToggleCard(
                  emoji: '🕰️',
                  label: 'Time Capsule',
                  value: sparqState.isTimeCapsule,
                  onChanged: (v) => ref.read(sparqProvider.notifier).setTimeCapsule(v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildToggleCard(
                  emoji: '🔗',
                  label: 'Allow Chain',
                  value: sparqState.allowChain,
                  onChanged: (v) => ref.read(sparqProvider.notifier).setAllowChain(v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildToggleCard(
                  emoji: '💬',
                  label: 'Allow Replies',
                  value: sparqState.allowReplies,
                  onChanged: (v) => ref.read(sparqProvider.notifier).setAllowReplies(v),
                ),
              ),
            ],
          ),
          // Time capsule duration pills (shown when enabled)
          if (sparqState.isTimeCapsule) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: _timeCapsuleOptions.map((opt) {
                final isSelected = _timeCapsuleDuration == opt;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: GestureDetector(
                    onTap: () => setState(() => _timeCapsuleDuration = opt),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? KinrelColors.orange : KinrelColors.elevation2,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        opt,
                        style: TextStyle(
                          color: isSelected ? Colors.white : KinrelColors.textSilver,
                          fontSize: 12,
                          fontFamily: 'DM Sans',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildToggleCard({
    required String emoji,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: value ? KinrelColors.orange.withValues(alpha: 0.15) : KinrelColors.elevation1,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: value ? KinrelColors.orange.withValues(alpha: 0.4) : KinrelColors.elevation2,
            width: 1,
          ),
        ),
        child: Column(
          children: [
            Text(emoji, style: TextStyle(fontSize: 20)),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: value ? KinrelColors.textWhite : KinrelColors.textSilver,
                fontSize: 10,
                fontFamily: 'DM Sans',
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                value ? Icons.toggle_on : Icons.toggle_off,
                key: ValueKey(value),
                color: value ? KinrelColors.orange : KinrelColors.textDim,
                size: 28,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // POST BUTTON
  // ══════════════════════════════════════════════════════════════════

  Widget _buildPostButton(SparqState sparqState) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          decoration: BoxDecoration(
            gradient: _showSuccess
                ? LinearGradient(colors: [KinrelColors.success, KinrelColors.success])
                : const LinearGradient(
                    colors: [Color(0xFFFF5722), Color(0xFFFF1744)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: (_showSuccess ? KinrelColors.success : const Color(0xFFFF5722)).withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: sparqState.isCreating ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: sparqState.isCreating
                  ? Row(
                      key: const ValueKey('loading'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildFlameDot(0),
                        const SizedBox(width: 6),
                        _buildFlameDot(1),
                        const SizedBox(width: 6),
                        _buildFlameDot(2),
                        const SizedBox(width: 12),
                        Text('Igniting...', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600, fontSize: 16)),
                      ],
                    )
                  : _showSuccess
                      ? Row(
                          key: const ValueKey('success'),
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle, size: 20),
                            const SizedBox(width: 8),
                            Text('Sparq Ignited!', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600, fontSize: 16)),
                          ],
                        )
                      : Row(
                          key: const ValueKey('idle'),
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('🔥 Ignite the Sparq', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600, fontSize: 16)),
                          ],
                        ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFlameDot(int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.4, end: 1.0),
      duration: Duration(milliseconds: 600 + (index * 200)),
      curve: Curves.easeInOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════════════════════════

  Color _parseColor(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', 'FF'), radix: 16));
    } catch (_) {
      return KinrelColors.orange;
    }
  }
}

// ── Data Classes ──────────────────────────────────────────────────────

class _MoodOption {
  final String key;
  final String emoji;
  final String label;
  final Color color;
  const _MoodOption({required this.key, required this.emoji, required this.label, required this.color});
}

class _TabData {
  final IconData icon;
  final String label;
  const _TabData({required this.icon, required this.label});
}

class _AudienceOption {
  final String key;
  final IconData icon;
  final String title;
  final String subtitle;
  const _AudienceOption({required this.key, required this.icon, required this.title, required this.subtitle});
}
