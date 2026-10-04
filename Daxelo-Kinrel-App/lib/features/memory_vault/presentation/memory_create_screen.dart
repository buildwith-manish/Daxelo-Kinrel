// lib/features/memory_vault/presentation/memory_create_screen.dart
//
// DAXELO KINREL — Memory Create Screen
//
// Production-ready memory composer with:
//   - Image picker (camera or gallery)
//   - Mandatory crop editor (4:3 or 1:1, with rotate/zoom/pan)
//   - Automatic compression (<3 MB) before upload
//   - Cover image preview with Replace / Remove actions
//   - Title / Description / Location / Memory Type / Date / Members
//   - Optional prefill from a Post (Feature 5 — Save Post As Memory)
//
// This screen is opened in two flows:
//   1. Direct: from Memories FAB → "+ Add Memory"
//   2. Post → Memory: from Post Create "Save To Memories" toggle, or
//      from the post card ⋮ menu "Save As Memory"
//
// When opened from a post, the post's image + caption + date are
// prefilled, and `sourcePostId` is passed so the resulting memory
// row references the original post (Feature 6).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/services/haptic_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../family/presentation/widgets/memory_crop_editor.dart';
import '../data/memory_model.dart';
import '../providers/memory_vault_provider.dart';

// ── Color shortcuts ──────────────────────────────────────────────
const _cOrange = KinrelColors.orange;
const _cBg = KinrelColors.darkBackground;
const _cCard = KinrelColors.darkCard;
const _cElevated = KinrelColors.darkElevated;
const _cTextPrimary = KinrelColors.textWhite;
const _cTextSecondary = KinrelColors.textSilver;
const _cTextDim = KinrelColors.textDim;

/// Memory type presets — matches the existing timeline event types.
const _memoryTypes = [
  ('Festival', Icons.festival_rounded, KinrelColors.orange),
  ('Birth', Icons.child_care_rounded, KinrelColors.orange),
  ('Marriage', Icons.favorite_rounded, KinrelColors.amber),
  ('Anniversary', Icons.celebration_rounded, KinrelColors.gold),
  ('Graduation', Icons.school_rounded, KinrelColors.info),
  ('Achievement', Icons.emoji_events_rounded, KinrelColors.brightGold),
  ('Migration', Icons.flight_takeoff_rounded, KinrelColors.success),
  ('Memorial', Icons.auto_awesome_rounded, KinrelColors.textSilver),
  ('Custom', Icons.bookmark_rounded, KinrelColors.textDim),
];

/// Arguments passed to [MemoryCreateScreen] when opened from a post.
class MemoryCreateArgs {
  const MemoryCreateArgs({
    this.sourcePostId,
    this.prefillImageUrl,
    this.prefillTitle,
    this.prefillDescription,
    this.prefillDate,
    this.prefillLocation,
  });

  /// FK back to the post this memory was created from (Feature 6).
  final String? sourcePostId;

  /// If provided, used directly as the cover image (the post's image URL).
  /// No file picker is opened — the user can replace it via the
  /// Replace button.
  final String? prefillImageUrl;

  /// Prefilled title (e.g. truncated post text).
  final String? prefillTitle;

  /// Prefilled description (e.g. full post text).
  final String? prefillDescription;

  /// Prefilled date (e.g. post createdAt).
  final DateTime? prefillDate;

  /// Prefilled location (e.g. post location).
  final String? prefillLocation;
}

class MemoryCreateScreen extends ConsumerStatefulWidget {
  const MemoryCreateScreen({super.key, this.args});

  final MemoryCreateArgs? args;

  @override
  ConsumerState<MemoryCreateScreen> createState() => _MemoryCreateScreenState();
}

class _MemoryCreateScreenState extends ConsumerState<MemoryCreateScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();

  /// Cover image bytes (after crop + compression). null = no image.
  Uint8List? _imageBytes;

  /// When [MemoryCreateArgs.prefillImageUrl] is set, we display that
  /// URL as the cover preview but don't have bytes to upload — the
  /// memory is created with `image_url = prefillImageUrl` and
  /// `image_storage_key = null` (we don't own the storage object).
  String? _prefillImageUrl;

  DateTime _selectedDate = DateTime.now();
  String? _selectedMemoryType;
  final List<String> _selectedMemberIds = [];
  final Set<String> _selectedMemberNames = {};
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final args = widget.args;
    if (args != null) {
      if (args.prefillTitle != null) {
        _titleController.text = args.prefillTitle!;
      }
      if (args.prefillDescription != null) {
        _descriptionController.text = args.prefillDescription!;
      }
      if (args.prefillLocation != null) {
        _locationController.text = args.prefillLocation!;
      }
      if (args.prefillDate != null) {
        _selectedDate = args.prefillDate!;
      }
      _prefillImageUrl = args.prefillImageUrl;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final vault = ref.watch(memoryVaultProvider);
    final families = ref.watch(familyListProvider).valueOrNull ?? [];
    final user = ref.watch(currentUserProvider);

    return DKScaffold(
      backgroundColor: _cBg,
      appBar: _buildAppBar(),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),

            // Author row + family selector
            _buildAuthorRow(user, families),

            const SizedBox(height: 16),

            // Cover image section (picker / preview)
            _buildCoverSection(),

            const SizedBox(height: 20),

            // Title input
            _buildTitleInput(),

            const SizedBox(height: 16),

            // Description / Story input
            _buildDescriptionInput(),

            const SizedBox(height: 16),

            // Location input
            _buildLocationInput(),

            const SizedBox(height: 16),

            // Date picker
            _buildDatePicker(),

            const SizedBox(height: 20),

            // Memory type chips
            _buildMemoryTypeSelector(),

            const SizedBox(height: 20),

            // Members selector
            _buildMembersSelector(),

            // If created from a post — show source badge
            if (widget.args?.sourcePostId != null) ...[
              const SizedBox(height: 20),
              _buildFromPostBadge(),
            ],

            const SizedBox(height: 100), // Bottom padding
          ],
        ),
      ),
      // Submit button at the bottom
      bottomNavigationBar: _buildBottomBar(vault),
    );
  }

  // ── AppBar ─────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _cBg,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.close, color: _cTextSecondary, size: 24),
        onPressed: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/memories');
          }
        },
      ),
      title: const Text(
        'New Memory',
        style: TextStyle(
          fontFamily: KinrelTypography.displayFont,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: _cTextPrimary,
        ),
      ),
    );
  }

  // ── Author Row ─────────────────────────────────────────────────

  Widget _buildAuthorRow(dynamic user, List<Family> families) {
    final userName = user?.userMetadata?['name'] as String? ??
        user?.email?.split('@').first ??
        'You';

    return Row(
      children: [
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
              if (families.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _cElevated,
                    borderRadius: BorderRadius.circular(KinrelRadius.full),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    families.first.name,
                    style: const TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: _cOrange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Cover Section ──────────────────────────────────────────────

  Widget _buildCoverSection() {
    final hasImage = _imageBytes != null || _prefillImageUrl != null;

    if (!hasImage) {
      // Picker prompt
      return GestureDetector(
        onTap: _showImageSourceSheet,
        child: Container(
          width: double.infinity,
          height: 220,
          decoration: BoxDecoration(
            color: _cCard,
            borderRadius: BorderRadius.circular(KinrelRadius.lg),
            border: Border.all(
              color: _cOrange.withValues(alpha: 0.3),
              width: 1.5,
              style: BorderStyle.solid,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _cOrange.withValues(alpha: 0.12),
                ),
                child: const Icon(
                  Icons.add_photo_alternate_rounded,
                  size: 32,
                  color: _cOrange,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Add Cover Photo',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _cTextPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Take a photo or pick from gallery',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  color: _cTextDim,
                ),
              ),
            ],
          ),
        ),
      ).animate().fadeIn(duration: 200.ms).scale(
            begin: const Offset(0.98, 0.98),
            end: const Offset(1, 1),
          );
    }

    // Image preview with Replace / Remove
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
          child: _imageBytes != null
              ? Image.memory(
                  _imageBytes!,
                  width: double.infinity,
                  height: 240,
                  fit: BoxFit.cover,
                )
              : (_prefillImageUrl != null && _prefillImageUrl!.isNotEmpty)
                  ? Image.network(
                      _prefillImageUrl!,
                      width: double.infinity,
                      height: 240,
                      fit: BoxFit.cover,
                      errorBuilder: (c, o, e) => Container(
                        height: 240,
                        color: _cElevated,
                        child: const Center(
                          child: Icon(Icons.broken_image_outlined,
                              color: _cTextDim, size: 32),
                        ),
                      ),
                    )
                  : Container(
                      height: 240,
                      color: _cElevated,
                      child: const Center(
                        child: Icon(Icons.image_outlined,
                            color: _cTextDim, size: 32),
                      ),
                    ),
        ),
        // Gradient overlay for action buttons
        Positioned(
          top: 8,
          right: 8,
          child: Row(
            children: [
              _CoverActionButton(
                icon: Icons.swap_horiz_rounded,
                label: 'Replace',
                onTap: _showImageSourceSheet,
              ),
              const SizedBox(width: 8),
              _CoverActionButton(
                icon: Icons.delete_outline_rounded,
                label: 'Remove',
                onTap: () {
                  HapticService.tap();
                  setState(() {
                    _imageBytes = null;
                    _prefillImageUrl = null;
                  });
                },
                isDestructive: true,
              ),
            ],
          ),
        ),
      ],
    ).animate().fadeIn(duration: 200.ms).scale(
          begin: const Offset(0.98, 0.98),
          end: const Offset(1, 1),
        );
  }

  // ── Title Input ────────────────────────────────────────────────

  Widget _buildTitleInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Title',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _cTextSecondary,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _titleController,
          maxLength: 80,
          style: const TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 16,
            color: _cTextPrimary,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: 'e.g. Diwali Celebration',
            hintStyle: const TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 16,
              color: _cTextDim,
              fontWeight: FontWeight.w500,
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

  // ── Description / Story Input ──────────────────────────────────

  Widget _buildDescriptionInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Story',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _cTextSecondary,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _descriptionController,
          maxLines: 4,
          minLines: 2,
          style: const TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 14,
            color: _cTextPrimary,
            height: 1.5,
          ),
          decoration: InputDecoration(
            hintText: 'Tell the story behind this memory...',
            hintStyle: const TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              color: _cTextDim,
            ),
            filled: true,
            fillColor: _cCard,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(KinrelRadius.lg),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }

  // ── Location Input ─────────────────────────────────────────────

  Widget _buildLocationInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Location',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _cTextSecondary,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _locationController,
          style: const TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 14,
            color: _cTextPrimary,
          ),
          decoration: InputDecoration(
            hintText: 'e.g. Jaipur',
            hintStyle: const TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              color: _cTextDim,
            ),
            prefixIcon: const Icon(Icons.location_on_outlined,
                size: 20, color: _cTextDim),
            filled: true,
            fillColor: _cCard,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(KinrelRadius.md),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }

  // ── Date Picker ────────────────────────────────────────────────

  Widget _buildDatePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Date',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _cTextSecondary,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _pickDate,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: _cCard,
              borderRadius: BorderRadius.circular(KinrelRadius.md),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_rounded,
                    size: 18, color: _cOrange),
                const SizedBox(width: 10),
                Text(
                  _formatDate(_selectedDate),
                  style: const TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    color: _cTextPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                const Icon(Icons.expand_more,
                    size: 18, color: _cTextDim),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Memory Type Selector ───────────────────────────────────────

  Widget _buildMemoryTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Memory Type',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _cTextSecondary,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _memoryTypes.map((t) {
            final (label, icon, color) = t;
            final isSelected = _selectedMemoryType == label;
            return GestureDetector(
              onTap: () {
                HapticService.tap();
                setState(() {
                  _selectedMemoryType = isSelected ? null : label;
                });
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? color.withValues(alpha: 0.15)
                      : _cElevated,
                  borderRadius: BorderRadius.circular(KinrelRadius.full),
                  border: Border.all(
                    color: isSelected
                        ? color.withValues(alpha: 0.4)
                        : Colors.white.withValues(alpha: 0.06),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 14, color: isSelected ? color : _cTextDim),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isSelected ? color : _cTextDim,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Members Selector ────────────────────────────────────────────

  Widget _buildMembersSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Members',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _cTextSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _cCard,
                  borderRadius: BorderRadius.circular(KinrelRadius.md),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.people_outline_rounded,
                        size: 18, color: _cOrange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _selectedMemberNames.isEmpty
                            ? 'Add family members'
                            : '${_selectedMemberNames.length} member${_selectedMemberNames.length == 1 ? '' : 's'}: ${_selectedMemberNames.take(3).join(', ')}${_selectedMemberNames.length > 3 ? '...' : ''}',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 13,
                          color: _selectedMemberNames.isEmpty
                              ? _cTextDim
                              : _cTextPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.add, size: 18, color: _cOrange),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── From-Post Badge ─────────────────────────────────────────────

  Widget _buildFromPostBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _cOrange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(
          color: _cOrange.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.bookmark_rounded, size: 16, color: _cOrange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Created from a Post — link will be saved with this memory.',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: _cOrange.withValues(alpha: 0.9),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom Bar (Submit) ────────────────────────────────────────

  Widget _buildBottomBar(MemoryVaultState vault) {
    final canSubmit = _titleController.text.trim().isNotEmpty &&
        !vault.isUploading &&
        !_isSubmitting;

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(
            KinrelSpacing.base, 12, KinrelSpacing.base, 12),
        decoration: BoxDecoration(
          color: _cBg,
          border: Border(
            top: BorderSide(
              color: Colors.white.withValues(alpha: 0.06),
              width: 0.5,
            ),
          ),
        ),
        child: DKButton(
          label: vault.isUploading
              ? (vault.uploadProgress ?? 'Saving...')
              : 'Save Memory',
          variant: DKButtonVariant.gradient,
          size: DKButtonSize.lg,
          isLoading: vault.isUploading || _isSubmitting,
          onPressed: canSubmit ? _onSubmit : null,
        ),
      ),
    );
  }

  // ── Image Source Sheet (camera / gallery) ──────────────────────

  Future<void> _showImageSourceSheet() async {
    HapticService.tap();
    await showModalBottomSheet(
      context: context,
      backgroundColor: _cCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.xxl),
        ),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Add Cover Photo',
                style: KinrelTypography.headlineSmall.copyWith(
                  color: _cTextPrimary,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded,
                  color: _cOrange),
              title: const Text('Take Photo',
                  style: TextStyle(color: _cTextPrimary)),
              onTap: () {
                Navigator.pop(context);
                _pickAndCrop(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: _cOrange),
              title: const Text('Choose From Gallery',
                  style: TextStyle(color: _cTextPrimary)),
              onTap: () {
                Navigator.pop(context);
                _pickAndCrop(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndCrop(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 95, // we'll recompress after crop
      );
      if (image == null) return;

      final bytes = await File(image.path).readAsBytes();
      if (!mounted) return;

      // Mandatory crop editor
      final result = await MemoryCropEditor.show(
        context,
        imageBytes: bytes,
        initialRatio: MemoryCropRatio.fourThree,
      );

      if (result == null) return;
      if (!mounted) return;

      setState(() {
        _imageBytes = result.bytes;
        _prefillImageUrl = null; // clear any prefill — bytes take priority
      });

      // Optional: log size for debugging
      debugPrint('🖼 Memory cover: ${result.sizeKb}KB, '
          '${result.width}×${result.height} (${result.ratio.label})');
    } catch (e) {
      debugPrint('⚠️ Image pick/crop error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not pick image')),
        );
      }
    }
  }

  // ── Date Picker ────────────────────────────────────────────────

  Future<void> _pickDate() async {
    HapticService.tap();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: _cOrange,
              onPrimary: Colors.white,
              surface: _cCard,
              onSurface: _cTextPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  // ── Submit ─────────────────────────────────────────────────────

  Future<void> _onSubmit() async {
    HapticService.mediumImpact();
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    setState(() => _isSubmitting = true);

    final notifier = ref.read(memoryVaultProvider.notifier);

    final memory = await notifier.createMemory(
      title: title,
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      location: _locationController.text.trim().isEmpty
          ? null
          : _locationController.text.trim(),
      memoryType: _selectedMemoryType,
      date: _selectedDate,
      memberIds: _selectedMemberIds,
      imageBytes: _imageBytes,
      imageExtension: 'jpg',
      sourcePostId: widget.args?.sourcePostId,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (memory != null) {
      // Success — go back to memories screen
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/memories');
      }
    } else {
      final error = ref.read(memoryVaultProvider).error;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error ?? 'Failed to save memory'),
            backgroundColor: KinrelColors.error,
          ),
        );
      }
    }
  }

  // ── Helpers ────────────────────────────────────────────────────

  String _formatDate(DateTime date) {
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month]} ${date.year}';
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Helper widgets
// ═══════════════════════════════════════════════════════════════════════

class _CoverActionButton extends StatelessWidget {
  const _CoverActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final color =
        isDestructive ? KinrelColors.error : _cTextPrimary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(KinrelRadius.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
