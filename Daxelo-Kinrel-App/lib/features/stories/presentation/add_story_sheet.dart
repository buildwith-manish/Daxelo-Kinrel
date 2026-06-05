// lib/features/stories/presentation/add_story_sheet.dart
//
// DAXELO KINREL — Add Story Bottom Sheet
//
// Bottom sheet for creating a new text story:
//   • Text input field for caption
//   • Gradient preview showing what the story will look like
//   • Gradient color picker (curated Kinrel presets)
//   • Post button
//   • Uses KinrelColors theme (dark card background, orange accents)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../providers/stories_provider.dart';
import '../../../shared/widgets/dk_components.dart';

// ── Color shortcuts ──────────────────────────────────────────────
const _cOrange = KinrelColors.orange;
const _cBg = KinrelColors.darkBackground;
const _cCard = KinrelColors.darkCard;
const _cElevated = KinrelColors.darkElevated;
const _cTextPrimary = KinrelColors.textWhite;
const _cTextSecondary = KinrelColors.textSilver;
const _cTextDim = KinrelColors.textDim;

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

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  List<String> get _selectedGradient => storyGradients[_selectedGradientIndex];

  Color _hexToColor(String hex) {
    final code = hex.replaceAll('#', '');
    return Color(int.parse('FF$code', radix: 32));
  }

  Future<void> _postStory() async {
    final caption = _captionController.text.trim();
    if (caption.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please enter a caption for your story'),
          backgroundColor: _cCard,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isPosting = true);

    try {
      await ref.read(createStoryProvider(CreateStoryParams(
        familyId: widget.familyId,
        type: 'text',
        caption: caption,
        gradientColors: _selectedGradient,
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
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
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

          // Story preview
          _buildStoryPreview(),

          const SizedBox(height: 16),

          // Gradient picker
          _buildGradientPicker(),

          const SizedBox(height: 16),

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
                hintText: 'What\'s on your mind?',
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
                onPressed: _captionController.text.trim().isEmpty
                    ? null
                    : _postStory,
                fullWidth: true,
                icon: Icons.auto_awesome_rounded,
              ),
            ),
          ),

          SizedBox(height: 16 + bottomInset),
        ],
      ),
    );
  }

  // ── Story preview ────────────────────────────────────────────────

  Widget _buildStoryPreview() {
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
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: _cTextPrimary,
                  height: 1.4,
                  textAlign: TextAlign.center,
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
}
