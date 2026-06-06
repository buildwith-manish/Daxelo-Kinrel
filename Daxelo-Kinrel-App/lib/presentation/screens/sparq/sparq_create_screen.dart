// lib/presentation/screens/sparq/sparq_create_screen.dart
//
// DAXELO KINREL — Sparq Create Screen
//
// Create a new Sparq (ephemeral story):
//   • TabBar: Image | Video | Text | Voice (orange indicator)
//   • IMAGE TAB: camera/gallery picker
//   • VIDEO TAB: record (max 60s) or gallery pick
//   • TEXT TAB: text field + 6 color circles for background
//   • VOICE TAB: record button with waveform
//   • BOTTOM: Audience toggle [Everyone] [Family Only] + Send button

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../providers/sparq_provider.dart';

/// Available background colors for text sparqs.
const _textBgColors = [
  '#E8612A', // Kinrel Orange
  '#C44A18', // Ember
  '#F59240', // Amber
  '#131416', // Dark
  '#191B2C', // Dark Card
  '#2E8B57', // Festival Green
];

class SparqCreateScreen extends ConsumerStatefulWidget {
  const SparqCreateScreen({super.key});

  @override
  ConsumerState<SparqCreateScreen> createState() => _SparqCreateScreenState();
}

class _SparqCreateScreenState extends ConsumerState<SparqCreateScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _textController = TextEditingController();
  int _selectedBgColorIndex = 0;
  String _audience = 'PUBLIC';
  File? _selectedMedia;
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _textController.dispose();
    super.dispose();
  }

  String get _currentType {
    switch (_tabController.index) {
      case 0:
        return 'IMAGE';
      case 1:
        return 'VIDEO';
      case 2:
        return 'TEXT';
      case 3:
        return 'VOICE';
      default:
        return 'TEXT';
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1080,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (image != null) {
      setState(() => _selectedMedia = File(image.path));
    }
  }

  Future<void> _takePhoto() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1080,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (image != null) {
      setState(() => _selectedMedia = File(image.path));
    }
  }

  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final video = await picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: 60),
    );
    if (video != null) {
      setState(() => _selectedMedia = File(video.path));
    }
  }

  Future<void> _recordVideo() async {
    final picker = ImagePicker();
    final video = await picker.pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(seconds: 60),
    );
    if (video != null) {
      setState(() => _selectedMedia = File(video.path));
    }
  }

  Future<void> _sendSparq() async {
    final notifier = ref.read(sparqProvider.notifier);
    final type = _currentType;

    // Validation
    if (type == 'IMAGE' && _selectedMedia == null) {
      _showSnackBar('Please select an image');
      return;
    }
    if (type == 'VIDEO' && _selectedMedia == null) {
      _showSnackBar('Please select or record a video');
      return;
    }
    if (type == 'TEXT' && _textController.text.trim().isEmpty) {
      _showSnackBar('Please enter some text');
      return;
    }

    final result = await notifier.createSparq(
      type: type,
      audience: _audience,
      mediaFile: (type == 'IMAGE' || type == 'VIDEO') ? _selectedMedia : null,
      text: type == 'TEXT' ? _textController.text.trim() : null,
      bgColor: type == 'TEXT' ? _textBgColors[_selectedBgColorIndex] : null,
    );

    if (mounted) {
      if (result != null) {
        Navigator.of(context).pop();
        _showSnackBar('Sparq created! 🧡');
      } else {
        _showSnackBar('Failed to create Sparq', isError: true);
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? KinrelColors.error : KinrelColors.darkCard,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sparqState = ref.watch(sparqProvider);

    return Scaffold(
      backgroundColor: KinrelColors.darkBackground,
      appBar: AppBar(
        backgroundColor: KinrelColors.darkBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: KinrelColors.textWhite),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Create Sparq',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textWhite,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: KinrelColors.orange,
          indicatorWeight: 3,
          labelColor: KinrelColors.orange,
          unselectedLabelColor: KinrelColors.textDim,
          labelStyle: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            fontWeight: FontWeight.w400,
          ),
          tabs: const [
            Tab(text: 'Image'),
            Tab(text: 'Video'),
            Tab(text: 'Text'),
            Tab(text: 'Voice'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildImageTab(),
                _buildVideoTab(),
                _buildTextTab(),
                _buildVoiceTab(),
              ],
            ),
          ),
          // Bottom: Audience + Send
          _buildBottomBar(sparqState.isCreating),
        ],
      ),
    );
  }

  // ── Image Tab ────────────────────────────────────────────────────

  Widget _buildImageTab() {
    return Center(
      child: _selectedMedia != null
          ? Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(KinrelRadius.lg),
                  child: Image.file(
                    _selectedMedia!,
                    fit: BoxFit.contain,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                ),
                Positioned(
                  top: 16,
                  right: 16,
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedMedia = null),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black54,
                      ),
                      child: Icon(Icons.close, color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ],
            )
          : Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.image_outlined, size: 64, color: KinrelColors.textDim),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildPickerButton(Icons.camera_alt, 'Camera', _takePhoto),
                      const SizedBox(width: 20),
                      _buildPickerButton(Icons.photo_library, 'Gallery', _pickImage),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  // ── Video Tab ────────────────────────────────────────────────────

  Widget _buildVideoTab() {
    return Center(
      child: _selectedMedia != null
          ? Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.videocam, size: 64, color: KinrelColors.orange),
                      const SizedBox(height: 12),
                      Text(
                        'Video selected',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 16,
                          color: KinrelColors.textWhite,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 16,
                  right: 16,
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedMedia = null),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black54,
                      ),
                      child: Icon(Icons.close, color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ],
            )
          : Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.videocam_outlined, size: 64, color: KinrelColors.textDim),
                  const SizedBox(height: 8),
                  Text(
                    'Max 60 seconds',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      color: KinrelColors.textDim,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildPickerButton(Icons.videocam, 'Record', _recordVideo),
                      const SizedBox(width: 20),
                      _buildPickerButton(Icons.video_library, 'Gallery', _pickVideo),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  // ── Text Tab ────────────────────────────────────────────────────

  Widget _buildTextTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Background color selector
          SizedBox(
            height: 48,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_textBgColors.length, (index) {
                final isSelected = index == _selectedBgColorIndex;
                final color = Color(
                  int.parse('FF${_textBgColors[index].replaceAll('#', '')}', radix: 16),
                );
                return GestureDetector(
                  onTap: () => setState(() => _selectedBgColorIndex = index),
                  child: Container(
                    width: 40,
                    height: 40,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                      border: isSelected
                          ? Border.all(color: Colors.white, width: 3)
                          : Border.all(
                              color: KinrelColors.textDim.withValues(alpha: 0.3),
                              width: 1,
                            ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 24),
          // Text input
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Color(
                  int.parse(
                    'FF${_textBgColors[_selectedBgColorIndex].replaceAll('#', '')}',
                    radix: 16,
                  ),
                ),
                borderRadius: BorderRadius.circular(KinrelRadius.lg),
              ),
              child: TextField(
                controller: _textController,
                maxLines: null,
                expands: true,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  height: 1.4,
                ),
                decoration: InputDecoration(
                  hintText: 'Type something...',
                  hintStyle: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white54,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(24),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Voice Tab ────────────────────────────────────────────────────

  Widget _buildVoiceTab() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Waveform placeholder
          Container(
            width: 240,
            height: 60,
            decoration: BoxDecoration(
              color: KinrelColors.darkElevated,
              borderRadius: BorderRadius.circular(KinrelRadius.xl),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                30,
                (i) => Container(
                  width: 3,
                  height: 12.0 + (i % 7) * 5.0,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: _isRecording
                        ? KinrelColors.orange
                        : KinrelColors.textDim.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
          // Record button
          GestureDetector(
            onTapDown: (_) => setState(() => _isRecording = true),
            onTapUp: (_) => setState(() => _isRecording = false),
            onTapCancel: () => setState(() => _isRecording = false),
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isRecording
                    ? KinrelColors.error
                    : KinrelColors.orange,
                boxShadow: [
                  BoxShadow(
                    color: (_isRecording ? KinrelColors.error : KinrelColors.orange)
                        .withValues(alpha: 0.4),
                    blurRadius: 20,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Icon(
                _isRecording ? Icons.stop : Icons.mic,
                size: 32,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _isRecording ? 'Recording...' : 'Tap & hold to record',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              color: _isRecording ? KinrelColors.error : KinrelColors.textDim,
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom bar ──────────────────────────────────────────────────

  Widget _buildBottomBar(bool isCreating) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        border: Border(top: BorderSide(color: KinrelColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Audience toggle
            Container(
              decoration: BoxDecoration(
                color: KinrelColors.darkElevated,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildAudienceChip('PUBLIC', 'Everyone'),
                  _buildAudienceChip('FAMILY_ONLY', 'Family Only'),
                ],
              ),
            ),
            const Spacer(),
            // Send button
            GestureDetector(
              onTap: isCreating ? null : _sendSparq,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: isCreating ? null : KinrelGradients.igniteGradient,
                  color: isCreating ? KinrelColors.textDim : null,
                ),
                child: isCreating
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.send_rounded, color: Colors.white, size: 22),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudienceChip(String value, String label) {
    final isSelected = _audience == value;
    return GestureDetector(
      onTap: () => setState(() => _audience = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? KinrelColors.orange : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : KinrelColors.textDim,
          ),
        ),
      ),
    );
  }

  // ── Helper ────────────────────────────────────────────────────────

  Widget _buildPickerButton(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        decoration: BoxDecoration(
          color: KinrelColors.darkElevated,
          borderRadius: BorderRadius.circular(KinrelRadius.xl),
          border: Border.all(color: KinrelColors.orange.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: KinrelColors.orange, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textWhite,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
