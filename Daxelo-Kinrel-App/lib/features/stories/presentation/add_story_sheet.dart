// lib/features/stories/presentation/add_story_sheet.dart
//
// DAXELO KINREL — Add Story Bottom Sheet
//
// Bottom sheet for creating a new story:
//   • Text, Image, and Video story types
//   • Media picker (camera/gallery) for image/video stories
//   • Audience selector (PUBLIC / FAMILY_ONLY)
//   • Gradient preview for text stories
//   • Caption input for all story types
//   • Post button
//   • Uses KinrelColors theme (dark card background, orange accents)

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../providers/stories_provider.dart';
import '../../../shared/widgets/dk_components.dart';

// ── Color shortcuts ──────────────────────────────────────────────
const _cOrange = KinrelColors.orange;

const _cCard = KinrelColors.darkCard;
const _cElevated = KinrelColors.darkElevated;
const _cTextPrimary = KinrelColors.textWhite;
const _cTextSecondary = KinrelColors.textSilver;
const _cTextDim = KinrelColors.textDim;

/// Story type options
enum _StoryType { text, image, video }

/// Audience options
enum _Audience { public, familyOnly }

/// Shows the add story bottom sheet.
Future<void> showAddStorySheet(
  BuildContext context, {
  required String familyId,
  required WidgetRef ref,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AddStorySheet(familyId: familyId),
  );
}

class _AddStorySheet extends ConsumerStatefulWidget {
  const _AddStorySheet({required this.familyId});

  final String familyId;

  @override
  ConsumerState<_AddStorySheet> createState() => _AddStorySheetState();
}

class _AddStorySheetState extends ConsumerState<_AddStorySheet> {
  final _captionController = TextEditingController();
  int _selectedGradientIndex = 0;
  bool _isPosting = false;
  _StoryType _storyType = _StoryType.text;
  _Audience _audience = _Audience.public;
  XFile? _selectedMedia; // Selected image or video file
  final _imagePicker = ImagePicker();

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  List<String> get _selectedGradient => storyGradients[_selectedGradientIndex];

  Color _hexToColor(String hex) {
    final code = hex.replaceAll('#', '');
    return Color(int.parse('FF$code', radix: 16));
  }

  /// Pick an image from gallery or camera.
  Future<void> _pickImage(ImageSource source) async {
    try {
      final xFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1080,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (xFile != null) {
        setState(() {
          _selectedMedia = xFile;
          _storyType = _StoryType.image;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick image: $e'),
            backgroundColor: KinrelColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Pick a video from gallery or camera.
  Future<void> _pickVideo(ImageSource source) async {
    try {
      final xFile = await _imagePicker.pickVideo(
        source: source,
        maxDuration: const Duration(seconds: 30),
      );
      if (xFile != null) {
        setState(() {
          _selectedMedia = xFile;
          _storyType = _StoryType.video;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick video: $e'),
            backgroundColor: KinrelColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Clear selected media and return to text mode.
  void _clearMedia() {
    setState(() {
      _selectedMedia = null;
      _storyType = _StoryType.text;
    });
  }

  Future<void> _postStory() async {
    if (_storyType == _StoryType.text && _captionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please enter a caption for your story'),
          backgroundColor: _cCard,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if ((_storyType == _StoryType.image || _storyType == _StoryType.video) &&
        _selectedMedia == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please select a photo or video'),
          backgroundColor: _cCard,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isPosting = true);

    try {
      final typeStr = _storyType == _StoryType.video ? 'video' : _storyType == _StoryType.image ? 'image' : 'text';
      final mediaUrl = _selectedMedia?.path ?? '';
      final gradientColors = _storyType == _StoryType.text ? _selectedGradient : null;

      await ref.read(createStoryProvider(CreateStoryParams(
        familyId: widget.familyId,
        type: typeStr,
        caption: _captionController.text.trim().isEmpty ? null : _captionController.text.trim(),
        mediaUrl: mediaUrl.isNotEmpty ? mediaUrl : null,
        gradientColors: gradientColors,
        audience: _audience == _Audience.familyOnly ? 'FAMILY_ONLY' : 'PUBLIC',
      )).future);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Story posted!'),
            backgroundColor: _cCard,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to post story: $e'),
            backgroundColor: KinrelColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: _cCard,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: KinrelSpacing.base,
                vertical: 12,
              ),
              child: Row(
                children: [
                  Text(
                    'Add Story',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: _cTextPrimary,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(
                      Icons.close_rounded,
                      color: _cTextSecondary,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),

            // Story type selector
            _buildStoryTypeSelector(),

            const SizedBox(height: 12),

            // Story preview (text gradient or media preview)
            _buildStoryPreview(),

            const SizedBox(height: 12),

            // Media picker buttons (for image/video types)
            if (_storyType != _StoryType.text) _buildMediaPicker(),

            // Gradient picker (only for text type)
            if (_storyType == _StoryType.text) _buildGradientPicker(),

            const SizedBox(height: 12),

            // Audience selector
            _buildAudienceSelector(),

            const SizedBox(height: 12),

            // Caption input
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: KinrelSpacing.base,
              ),
              child: TextField(
                controller: _captionController,
                maxLines: 3,
                minLines: 1,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 16,
                  color: _cTextPrimary,
                ),
                decoration: InputDecoration(
                  hintText: _storyType == _StoryType.video
                      ? 'Add a caption (optional)...'
                      : "What's on your mind?",
                  hintStyle: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 16,
                    color: _cTextDim,
                  ),
                  filled: true,
                  fillColor: _cElevated,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(KinrelRadius.md),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(KinrelRadius.md),
                    borderSide: BorderSide(color: _cOrange, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),

            const SizedBox(height: 16),

            // Post button
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: KinrelSpacing.base,
              ),
              child: SizedBox(
                width: double.infinity,
                child: DKButton(
                  label: 'Post Story',
                  variant: DKButtonVariant.gradient,
                  isLoading: _isPosting,
                  onPressed: _canPost() ? _postStory : null,
                  fullWidth: true,
                  icon: Icons.auto_awesome_rounded,
                ),
              ),
            ),

            SizedBox(height: 16 + bottomInset),
          ],
        ),
      ),
    );
  }

  bool _canPost() {
    if (_storyType == _StoryType.text) {
      return _captionController.text.trim().isNotEmpty;
    }
    return _selectedMedia != null;
  }

  // ── Story type selector ──────────────────────────────────────────

  Widget _buildStoryTypeSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: Row(
        children: [
          _buildTypeChip('Text', _StoryType.text, Icons.text_fields_rounded),
          const SizedBox(width: 8),
          _buildTypeChip('Photo', _StoryType.image, Icons.photo_camera_rounded),
          const SizedBox(width: 8),
          _buildTypeChip('Video', _StoryType.video, Icons.videocam_rounded),
        ],
      ),
    );
  }

  Widget _buildTypeChip(String label, _StoryType type, IconData icon) {
    final isSelected = _storyType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _storyType = type;
            if (type == _StoryType.text) {
              _selectedMedia = null;
            }
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? _cOrange.withValues(alpha: 0.2) : _cElevated,
            borderRadius: BorderRadius.circular(KinrelRadius.md),
            border: isSelected
                ? Border.all(color: _cOrange, width: 1.5)
                : Border.all(color: Colors.white10, width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: isSelected ? _cOrange : _cTextSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? _cOrange : _cTextSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Story preview ────────────────────────────────────────────────

  Widget _buildStoryPreview() {
    // Show media preview if an image/video is selected
    if (_selectedMedia != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
        child: AspectRatio(
          aspectRatio: 9 / 16,
          child: Stack(
            children: [
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.black,
                ),
                clipBehavior: Clip.antiAlias,
                child: _storyType == _StoryType.video
                    ? Stack(
                        alignment: Alignment.center,
                        children: [
                          Image.file(
                            File(_selectedMedia!.path),
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            errorBuilder: (_, __, ___) => Container(
                              color: _cElevated,
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.videocam_rounded, size: 48, color: _cTextSecondary),
                                    const SizedBox(height: 8),
                                    Text('Video Preview', style: TextStyle(color: _cTextSecondary, fontSize: 14)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.3),
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(12),
                            child: Icon(Icons.play_arrow_rounded, size: 36, color: _cTextPrimary),
                          ),
                        ],
                      )
                    : Image.file(
                        File(_selectedMedia!.path),
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        errorBuilder: (_, __, ___) => Container(
                          color: _cElevated,
                          child: Center(
                            child: Icon(Icons.broken_image_rounded, size: 48, color: _cTextSecondary),
                          ),
                        ),
                      ),
              ),
              // Clear media button
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: _clearMedia,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(6),
                    child: Icon(Icons.close_rounded, size: 18, color: _cTextPrimary),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Text story preview with gradient
    final caption = _captionController.text.isEmpty
        ? 'Your story preview...'
        : _captionController.text;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: AspectRatio(
        aspectRatio: 9 / 16,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: _selectedGradient.map(_hexToColor).toList(),
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                caption,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: _cTextPrimary,
                  height: 1.4,
                ),
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Media picker ────────────────────────────────────────────────

  Widget _buildMediaPicker() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _storyType == _StoryType.video ? 'Select video' : 'Select photo',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: _cTextSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildMediaSourceButton(
                  icon: Icons.photo_library_rounded,
                  label: 'Gallery',
                  onTap: () => _storyType == _StoryType.video
                      ? _pickVideo(ImageSource.gallery)
                      : _pickImage(ImageSource.gallery),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMediaSourceButton(
                  icon: Icons.photo_camera_rounded,
                  label: 'Camera',
                  onTap: () => _storyType == _StoryType.video
                      ? _pickVideo(ImageSource.camera)
                      : _pickImage(ImageSource.camera),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMediaSourceButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: _cElevated,
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          border: Border.all(color: Colors.white10, width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: _cOrange),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _cTextPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Gradient picker ──────────────────────────────────────────────

  Widget _buildGradientPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
          child: Text(
            'Choose background',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: _cTextSecondary,
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
            itemCount: storyGradients.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final gradient = storyGradients[index];
              final isSelected = index == _selectedGradientIndex;

              return GestureDetector(
                onTap: () => setState(() => _selectedGradientIndex = index),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: gradient.map(_hexToColor).toList(),
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: isSelected
                        ? Border.all(color: _cOrange, width: 3)
                        : Border.all(color: Colors.white24, width: 1),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: _cOrange.withValues(alpha: 0.4),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Audience selector ──────────────────────────────────────────

  Widget _buildAudienceSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Who can see this story?',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: _cTextSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _audience = _Audience.public),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    decoration: BoxDecoration(
                      color: _audience == _Audience.public
                          ? _cOrange.withValues(alpha: 0.2)
                          : _cElevated,
                      borderRadius: BorderRadius.circular(KinrelRadius.md),
                      border: _audience == _Audience.public
                          ? Border.all(color: _cOrange, width: 1.5)
                          : Border.all(color: Colors.white10, width: 1),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.public_rounded, size: 16, color: _audience == _Audience.public ? _cOrange : _cTextSecondary),
                        const SizedBox(width: 6),
                        Text(
                          'Everyone',
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 13,
                            fontWeight: _audience == _Audience.public ? FontWeight.w600 : FontWeight.w500,
                            color: _audience == _Audience.public ? _cOrange : _cTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _audience = _Audience.familyOnly),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    decoration: BoxDecoration(
                      color: _audience == _Audience.familyOnly
                          ? _cOrange.withValues(alpha: 0.2)
                          : _cElevated,
                      borderRadius: BorderRadius.circular(KinrelRadius.md),
                      border: _audience == _Audience.familyOnly
                          ? Border.all(color: _cOrange, width: 1.5)
                          : Border.all(color: Colors.white10, width: 1),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.family_restroom_rounded, size: 16, color: _audience == _Audience.familyOnly ? _cOrange : _cTextSecondary),
                        const SizedBox(width: 6),
                        Text(
                          'Family Only',
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 13,
                            fontWeight: _audience == _Audience.familyOnly ? FontWeight.w600 : FontWeight.w500,
                            color: _audience == _Audience.familyOnly ? _cOrange : _cTextSecondary,
                          ),
                        ),
                      ],
                    ),
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
