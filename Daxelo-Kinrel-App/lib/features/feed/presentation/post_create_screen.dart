// lib/features/feed/presentation/post_create_screen.dart
// DAXELO KINREL — Post Creation Screen
//
// Full-screen composer for creating family posts.
// Features: text input, media picker, family selector, audience toggle,
// occasion dropdown, location input.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/family/family_provider.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../memory_vault/providers/memory_vault_provider.dart';
import '../providers/post_create_provider.dart';
import '../providers/feed_provider.dart';

// ── Color shortcuts ──────────────────────────────────────────────
const _cOrange = KinrelColors.orange;
const _cBg = KinrelColors.darkBackground;
const _cCard = KinrelColors.darkCard;
const _cElevated = KinrelColors.darkElevated;
const _cTextPrimary = KinrelColors.textWhite;
const _cTextSecondary = KinrelColors.textSilver;
const _cTextDim = KinrelColors.textDim;

class PostCreateScreen extends ConsumerStatefulWidget {
  const PostCreateScreen({super.key});

  @override
  ConsumerState<PostCreateScreen> createState() => _PostCreateScreenState();
}

class _PostCreateScreenState extends ConsumerState<PostCreateScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _textController = TextEditingController();
  final _locationController = TextEditingController();
  final _maxChars = 500;

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onTextChanged);

    // Auto-select first family if none selected
    Future.microtask(() {
      final createNotifier = ref.read(postCreateProvider.notifier);
      final currentState = ref.read(postCreateProvider);
      if (currentState.selectedFamilyId == null) {
        final families = ref.read(familyListProvider).valueOrNull ?? [];
        if (families.isNotEmpty) {
          createNotifier.setSelectedFamilyId(families.first.id);
        }
      }
    });
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    ref.read(postCreateProvider.notifier).setText(_textController.text);
  }

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final create = ref.watch(postCreateProvider);
    final families = ref.watch(familyListProvider).valueOrNull ?? [];
    final user = ref.watch(currentUserProvider);

    return DKScaffold(
      backgroundColor: _cBg,
      appBar: _buildAppBar(create),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),

            // Author row + family selector
            _buildAuthorRow(user, families, create),

            const SizedBox(height: 16),

            // Text input
            _buildTextInput(create),

            const SizedBox(height: 16),

            // Image preview (if media picked)
            if (create.mediaFile != null) _buildImagePreview(create),

            const SizedBox(height: 12),

            // Media picker row
            _buildMediaPickerRow(),

            const SizedBox(height: 20),

            // Location input
            _buildLocationInput(),

            const SizedBox(height: 16),

            // Occasion selector
            _buildOccasionSelector(create),

            const SizedBox(height: 20),

            // Audience selector
            _buildAudienceSelector(create),

            const SizedBox(height: 20),

            // Save To Memories toggle (Feature 5)
            _buildSaveToMemoriesToggle(create),

            const SizedBox(height: 100), // Bottom padding
          ],
        ),
      ),
    );
  }

  // ── AppBar ─────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(PostCreateState create) {
    return AppBar(
      backgroundColor: _cBg,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.close, color: _cTextSecondary, size: 24),
        onPressed: () { if (context.canPop()) { context.pop(); } else { context.go('/home'); } },
      ),
      title: const Text(
        'New Post',
        style: TextStyle(
          fontFamily: KinrelTypography.displayFont,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: _cTextPrimary,
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: DKButton(
            label: 'Share',
            variant: DKButtonVariant.primary,
            size: DKButtonSize.sm,
            isLoading: create.isSubmitting,
            onPressed: create.hasContent && !create.isSubmitting
                ? _onShare
                : null,
          ),
        ),
      ],
    );
  }

  // ── Author Row ─────────────────────────────────────────────────

  Widget _buildAuthorRow(dynamic user, List<Family> families, PostCreateState create) {
    final userName = user?.userMetadata?['name'] as String? ??
        user?.email?.split('@').first ??
        'You';

    return Row(
      children: [
        // Avatar
        Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: KinrelGradients.igniteGradient,
          ),
          child: Center(
            child: Text(
              userName[0].toUpperCase(),
              style: const TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Name
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                userName,
                style: const TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _cTextPrimary,
                ),
              ),
              const SizedBox(height: 4),

              // Family selector dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _cElevated,
                  borderRadius: BorderRadius.circular(KinrelRadius.full),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 0.5,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: create.selectedFamilyId,
                    isDense: true,
                    icon: const Icon(Icons.expand_more, size: 16, color: _cOrange),
                    style: const TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: _cOrange,
                      fontWeight: FontWeight.w600,
                    ),
                    dropdownColor: _cElevated,
                    items: families.map((family) {
                      return DropdownMenuItem<String>(
                        value: family.id,
                        child: Text(
                          family.name,
                          style: const TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 12,
                            color: _cTextPrimary,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (familyId) {
                      if (familyId != null) {
                        ref.read(postCreateProvider.notifier).setSelectedFamilyId(familyId);
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Text Input ─────────────────────────────────────────────────

  Widget _buildTextInput(PostCreateState create) {
    return Column(
      children: [
        TextField(
          controller: _textController,
          maxLength: _maxChars,
          maxLines: 8,
          minLines: 4,
          style: const TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 16,
            color: _cTextPrimary,
            height: 1.5,
          ),
          decoration: InputDecoration(
            hintText: 'Share a moment with your family\u2026',
            hintStyle: const TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 16,
              color: _cTextDim,
            ),
            filled: true,
            fillColor: _cCard,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(KinrelRadius.lg),
              borderSide: BorderSide.none,
            ),
            counterStyle: const TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 11,
              color: _cTextDim,
            ),
          ),
        ),
      ],
    );
  }

  // ── Image Preview ──────────────────────────────────────────────

  Widget _buildImagePreview(PostCreateState create) {
    return Stack(
      children: [
        Container(
          constraints: const BoxConstraints(maxHeight: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
              width: 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            // Cross-platform image preview: load bytes via XFile.readAsBytes
            // (works on web blob URLs and native file paths), then display
            // via Image.memory. The previous Image.file(File(...)) didn't
            // work on web because dart:io can't open blob URLs returned by
            // image_picker's web implementation.
            child: FutureBuilder<List<int>>(
              future: create.mediaFile!.readAsBytes(),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done ||
                    !snapshot.hasData) {
                  return Container(
                    color: Colors.black.withValues(alpha: 0.1),
                    child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                return Image.memory(
                  Uint8List.fromList(snapshot.data!),
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (c, o, e) => Container(
                    color: Colors.black.withValues(alpha: 0.1),
                    child: const Center(
                      child: Icon(Icons.broken_image_outlined,
                          color: Colors.white54, size: 32),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        // Remove button
        Positioned(
          top: 8,
          right: 8,
          child: GestureDetector(
            onTap: () => ref.read(postCreateProvider.notifier).setMediaFile(null),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: _cBg.withValues(alpha: 0.8),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 16, color: _cTextPrimary),
            ),
          ),
        ),
      ],
    )
        .animate()
        .fadeIn(duration: 200.ms)
        .scale(begin: const Offset(0.95, 0.95), end: const Offset(1, 1));
  }

  // ── Media Picker Row ───────────────────────────────────────────

  Widget _buildMediaPickerRow() {
    return Row(
      children: [
        _MediaPickerButton(
          icon: Icons.photo_camera_outlined,
          label: 'Photo',
          onTap: _pickImage,
        ),
        const SizedBox(width: 12),
        _MediaPickerButton(
          icon: Icons.videocam_outlined,
          label: 'Video',
          onTap: _pickVideo,
        ),
        const SizedBox(width: 12),
        _MediaPickerButton(
          icon: Icons.location_on_outlined,
          label: 'Location',
          onTap: () {
            // ── Leak fix: previously FocusScope.of(context).requestFocus(FocusNode())
            // created a new FocusNode per tap that was never disposed. Use unfocus()
            // to dismiss the keyboard without leaking a FocusNode.
            FocusScope.of(context).unfocus();
          },
        ),
        const SizedBox(width: 12),
        _MediaPickerButton(
          icon: Icons.celebration_outlined,
          label: 'Occasion',
          onTap: () {
            _showOccasionPicker();
          },
        ),
      ],
    );
  }

  // ── Location Input ─────────────────────────────────────────────

  Widget _buildLocationInput() {
    return TextField(
      controller: _locationController,
      style: const TextStyle(
        fontFamily: KinrelTypography.bodyFont,
        fontSize: 14,
        color: _cTextPrimary,
      ),
      decoration: InputDecoration(
        hintText: 'Add location',
        hintStyle: const TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 14,
          color: _cTextDim,
        ),
        prefixIcon: const Icon(Icons.location_on_outlined, size: 20, color: _cTextDim),
        filled: true,
        fillColor: _cCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          borderSide: BorderSide.none,
        ),
      ),
      onChanged: (value) {
        ref.read(postCreateProvider.notifier).setLocation(value.isEmpty ? null : value);
      },
    );
  }

  // ── Occasion Selector ──────────────────────────────────────────

  Widget _buildOccasionSelector(PostCreateState create) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Occasion',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _cTextSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: PostOccasion.values.map((occasion) {
            final isSelected = create.occasion == occasion;
            return GestureDetector(
              onTap: () {
                ref.read(postCreateProvider.notifier).setOccasion(
                  isSelected ? null : occasion,
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? _cOrange.withValues(alpha: 0.15)
                      : _cElevated,
                  borderRadius: BorderRadius.circular(KinrelRadius.full),
                  border: Border.all(
                    color: isSelected
                        ? _cOrange.withValues(alpha: 0.4)
                        : Colors.white.withValues(alpha: 0.08),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  occasion.label,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isSelected ? _cOrange : _cTextDim,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Audience Selector ──────────────────────────────────────────

  Widget _buildAudienceSelector(PostCreateState create) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Audience',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _cTextSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: _cCard,
            borderRadius: BorderRadius.circular(KinrelRadius.full),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: _AudienceSegment(
                  label: 'Family Only',
                  isSelected: create.audience == PostAudience.familyOnly,
                  isFirst: true,
                  onTap: () => ref.read(postCreateProvider.notifier).setAudience(PostAudience.familyOnly),
                ),
              ),
              Expanded(
                child: _AudienceSegment(
                  label: 'Public',
                  isSelected: create.audience == PostAudience.public,
                  isFirst: false,
                  onTap: () => ref.read(postCreateProvider.notifier).setAudience(PostAudience.public),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── "Also add this to our family timeline" toggle (Feature 2) ────

  Widget _buildSaveToMemoriesToggle(PostCreateState create) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _cCard,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(
          color: create.saveToMemories
              ? _cOrange.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.06),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: create.saveToMemories
                  ? _cOrange.withValues(alpha: 0.15)
                  : _cElevated,
            ),
            child: Icon(
              Icons.timeline_rounded,
              size: 18,
              color: create.saveToMemories ? _cOrange : _cTextDim,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Also add this to our family timeline',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _cTextPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Creates a Timeline entry from this post — text + first '
                  'photo (if any). The link is one-time at creation; '
                  'editing or deleting this post later won\'t touch the '
                  'Timeline entry.',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 11,
                    color: _cTextDim,
                  ),
                ),
              ],
            ),
          ),
          // Toggle switch — defaults OFF. The user must explicitly opt in.
          Switch(
            value: create.saveToMemories,
            onChanged: (v) {
              ref.read(postCreateProvider.notifier).setSaveToMemories(v);
            },
            activeColor: _cOrange,
            inactiveThumbColor: _cTextDim,
            inactiveTrackColor: _cElevated,
          ),
        ],
      ),
    );
  }

  // ── Image/Video Pickers ────────────────────────────────────────

  Future<void> _pickImage() async {
    // Note: cancellation (image == null) returns silently WITHOUT showing
    // an error — cancelling a picker is a normal user action, not a failure.
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (image != null) {
        // Pass the XFile directly (cross-platform: works on web blob
        // URLs and native file paths). The previous File(image.path)
        // failed on web because dart:io can't open blob URLs.
        ref.read(postCreateProvider.notifier).setMediaFile(image);
      }
      // If image == null, the user cancelled — return silently (no error).
    } catch (e) {
      debugPrint('⚠️ Image picker error: $e');
      if (mounted) {
        final msg = e.toString().toLowerCase().contains('permission') ||
                e.toString().toLowerCase().contains('denied')
            ? 'Photo library permission denied. Grant access in your '
                'browser settings to attach a photo.'
            : 'Could not pick photo. Please try again. '
                '(Error: ${e.toString().length > 80 ? '${e.toString().substring(0, 80)}…' : e.toString()})';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _pickVideo() async {
    try {
      final picker = ImagePicker();
      final video = await picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: 60),
      );
      if (video != null) {
        // Pass the XFile directly (cross-platform).
        ref.read(postCreateProvider.notifier).setMediaFile(video);
      }
      // If video == null, the user cancelled — return silently (no error).
    } catch (e) {
      debugPrint('⚠️ Video picker error: $e');
      if (mounted) {
        final msg = e.toString().toLowerCase().contains('permission') ||
                e.toString().toLowerCase().contains('denied')
            ? 'Photo library permission denied. Grant access in your '
                'browser settings to attach a video.'
            : 'Could not pick video. Please try again. '
                '(Error: ${e.toString().length > 80 ? '${e.toString().substring(0, 80)}…' : e.toString()})';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _showOccasionPicker() {
    // Just focus the occasion section — the chips are already visible
    HapticFeedback.lightImpact();
  }

  // ── Share handler ──────────────────────────────────────────────

  /// Maps a [PostOccasion] to the closest Timeline entry category.
  /// Per the spec: "if the Post has any existing category/type metadata,
  /// map it to the closest Timeline category (Birth/Festival/Achievement/etc.);
  /// otherwise default to 'Custom' category, consistent with the custom-entry
  /// type already visible in the current Timeline implementation."
  static String? _mapOccasionToMemoryType(PostOccasion? occasion) {
    switch (occasion) {
      case PostOccasion.birthday:
        return 'Birth';
      case PostOccasion.anniversary:
        return 'Anniversary';
      case PostOccasion.festival:
        return 'Festival';
      case PostOccasion.achievement:
        return 'Achievement';
      case PostOccasion.other:
      case null:
        return 'Custom';
    }
  }

  Future<void> _onShare() async {
    HapticFeedback.mediumImpact();
    final create = ref.read(postCreateProvider);
    final postId = await ref.read(postCreateProvider.notifier).submit();
    if (!mounted) return;

    if (postId != null) {
      ref.invalidate(feedProvider);

      // ── Feature 2: "Also add this to our family timeline" toggle ───
      // Per the spec, when the toggle is ON we AUTO-CREATE a Timeline
      // entry using the post's content (text + the post's FIRST image
      // if it has one). We do NOT open a separate form — the toggle is
      // the only mechanism for linking the two, and the entry is
      // created automatically and silently (with a confirmation SnackBar).
      //
      // The linkage is ONE-DIRECTIONAL at creation time only: the post
      // creates a memory, not the reverse. Editing or deleting the
      // original post afterward will NOT cascade-delete the Timeline
      // entry — they're independent records after creation, linked
      // only by the `source_post_id` field on the memory row.
      //
      // Per the spec: "if the post has multiple images, use the first/
      // primary one as the Timeline entry's hero image, and the rest
      // remain part of the original post only, not duplicated into
      // Timeline." PostCreateState currently supports a single mediaFile
      // (one image per post), so the post's mediaUrl IS the first image.
      // If multi-image posts are added later, only the first URL should
      // be passed to savePostAsMemory().
      if (create.saveToMemories) {
        final postText = create.text.trim();
        final postImageUrl = create.mediaUrl; // first/primary image
        final postLocation = create.location;
        final memoryType = _mapOccasionToMemoryType(create.occasion);

        // AUTO-CREATE the Timeline entry. The post's image URL is
        // passed through as `externalImageUrl` — it's NOT re-uploaded
        // (the post upload already paid for the storage; displaying it
        // on the Timeline entry has zero marginal cost, so no quota is
        // consumed — see MemoryVaultNotifier.savePostAsMemory docs).
        await ref.read(memoryVaultProvider.notifier).savePostAsMemory(
              postId: postId,
              postText: postText,
              postImageUrl: postImageUrl,
              postDate: DateTime.now(),
              location: postLocation,
              memoryType: memoryType,
            );

        if (!mounted) return;
        // Confirm to the user that the linked Timeline entry was created.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Posted — and a Timeline entry was created from this post. '
              'View it in Memories.',
            ),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 4),
          ),
        );
        context.pop();
      } else {
        context.pop();
      }
    } else {
      final error = ref.read(postCreateProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error ?? 'Failed to share post'),
          backgroundColor: KinrelColors.error,
        ),
      );
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Helper widgets
// ═══════════════════════════════════════════════════════════════════════

class _MediaPickerButton extends StatelessWidget {
  const _MediaPickerButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _cElevated,
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.06),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: _cOrange),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _cTextSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AudienceSegment extends StatelessWidget {
  const _AudienceSegment({
    required this.label,
    required this.isSelected,
    required this.isFirst,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final bool isFirst;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? KinrelGradients.igniteGradient.colors.first.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.horizontal(
            left: isFirst ? const Radius.circular(KinrelRadius.full) : Radius.zero,
            right: isFirst ? Radius.zero : const Radius.circular(KinrelRadius.full),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected ? _cOrange : _cTextDim,
            ),
          ),
        ),
      ),
    );
  }
}
