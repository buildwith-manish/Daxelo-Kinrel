// lib/features/family/presentation/join_family_screen.dart
//
// DAXELO KINREL — Join Family Screen
//
// Allows users to join a family using a KIN-XXXXXXXX Family ID.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/family/family_id_provider.dart';
import '../../../core/family/family_provider.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../../core/extensions/context_extensions.dart';

// ── Design Tokens ──────────────────────────────────────────────────
const Color _bg = Color(0xFF131416);
const Color _cardBg = Color(0xFF191B2C);
const Color _orange = Color(0xFFE8612A);
const Color _textPrimary = Color(0xFFF5F0EE);
const Color _textSecondary = Color(0xFFC9B4A8);
const Color _textDim = Color(0xFF8A7A72);
const Color _borderSubtle = Color(0x0FFFFFFF);
const Color _errorColor = Color(0xFFF04E2A);

class JoinFamilyScreen extends ConsumerStatefulWidget {
  const JoinFamilyScreen({super.key});

  @override
  ConsumerState<JoinFamilyScreen> createState() => _JoinFamilyScreenState();
}

class _JoinFamilyScreenState extends ConsumerState<JoinFamilyScreen> {
  final _familyIdController = TextEditingController();
  final _familyIdFocusNode = FocusNode();
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    // Auto-focus the input field
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _familyIdFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _familyIdController.dispose();
    _familyIdFocusNode.dispose();
    super.dispose();
  }

  bool _isValidFamilyIdFormat(String input) {
    final normalized = input.trim().toUpperCase();
    return RegExp(r'^KIN-[A-Z0-9]{8}$').hasMatch(normalized);
  }

  String _normalizeFamilyId(String input) {
    // Auto-add KIN- prefix if user types just the code part
    var text = input.trim().toUpperCase();
    if (text.isNotEmpty && !text.startsWith('KIN-')) {
      if (RegExp(r'^[A-Z0-9]+$').hasMatch(text) && text.length <= 8) {
        text = 'KIN-$text';
        _familyIdController.text = text;
        _familyIdController.selection = TextSelection.fromPosition(
          TextPosition(offset: text.length),
        );
      }
    }
    return text;
  }

  void _searchFamily() {
    final input = _normalizeFamilyId(_familyIdController.text);
    if (input.isEmpty) return;

    if (!_isValidFamilyIdFormat(input)) {
      context.showSnackBar('Invalid Family ID format. Use KIN-XXXXXXXX', isError: true);
      return;
    }

    setState(() => _hasSearched = true);
    ref.read(familyIdProvider.notifier).searchByFamilyId(input);
  }

  Future<void> _joinFamily() async {
    final searchResult = ref.read(familyIdProvider).searchResult;
    if (searchResult == null || !searchResult.found || searchResult.kinFamilyId == null) return;

    final success = await ref.read(familyIdProvider.notifier).joinByFamilyId(
      searchResult.kinFamilyId!,
    );

    if (mounted) {
      if (success) {
        // Invalidate family list to refresh
        ref.invalidate(familyListProvider);
        context.showSnackBar('Successfully joined ${searchResult.name ?? 'family'}!');
        context.go('/families');
      } else {
        final error = ref.read(familyIdProvider).error ?? 'Failed to join family';
        context.showSnackBar(error, isError: true);
      }
    }
  }

  void _pasteFromClipboard() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    if (clipboardData?.text != null) {
      final text = clipboardData!.text!.trim().toUpperCase();
      _familyIdController.text = text;
      _normalizeFamilyId(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final familyIdState = ref.watch(familyIdProvider);

    return DKScaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Join Family',
          style: const TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(KinrelSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),

            // ── Header Illustration ──────────────────────────────────
            Center(
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _orange.withValues(alpha: 0.1),
                  border: Border.all(color: _orange.withValues(alpha: 0.3), width: 2),
                ),
                child: Icon(
                  Icons.family_restroom_rounded,
                  size: 40,
                  color: _orange,
                ),
              ),
            )
            .animate(onPlay: (c) => c.forward())
            .fadeIn(duration: 500.ms)
            .scale(begin: Offset(0.8, 0.8), end: Offset(1.0, 1.0), duration: 400.ms),

            const SizedBox(height: 24),

            // ── Title ────────────────────────────────────────────────
            Center(
              child: Text(
                'Enter Family ID',
                style: const TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
            ),

            const SizedBox(height: 8),

            Center(
              child: Text(
                'Ask a family member for their Family ID\n(Format: KIN-XXXXXXXX)',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  color: _textDim,
                  height: 1.5,
                ),
              ),
            ),

            const SizedBox(height: 32),

            // ── Family ID Input ──────────────────────────────────────
            TextField(
              controller: _familyIdController,
              focusNode: _familyIdFocusNode,
              onChanged: (value) {
                _normalizeFamilyId(value);
                // Reset search when input changes
                if (_hasSearched) {
                  ref.read(familyIdProvider.notifier).resetSearch();
                  setState(() => _hasSearched = false);
                }
              },
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _searchFamily(),
              textCapitalization: TextCapitalization.characters,
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _textPrimary,
                letterSpacing: 2,
              ),
              decoration: InputDecoration(
                hintText: 'KIN-XXXXXXXX',
                hintStyle: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 18,
                  color: _textDim.withValues(alpha: 0.4),
                  letterSpacing: 2,
                ),
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(left: 16, right: 8),
                  child: Icon(
                    Icons.qr_code_rounded,
                    color: _orange,
                    size: 24,
                  ),
                ),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_familyIdController.text.isNotEmpty)
                      IconButton(
                        icon: Icon(Icons.clear, color: _textDim, size: 20),
                        onPressed: () {
                          _familyIdController.clear();
                          ref.read(familyIdProvider.notifier).resetSearch();
                          setState(() => _hasSearched = false);
                        },
                      ),
                    IconButton(
                      icon: Icon(Icons.paste_rounded, color: _textDim, size: 20),
                      tooltip: 'Paste from clipboard',
                      onPressed: _pasteFromClipboard,
                    ),
                  ],
                ),
                filled: true,
                fillColor: _cardBg,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(KinrelRadius.xl),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(KinrelRadius.xl),
                  borderSide: BorderSide(color: _orange, width: 1.5),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ── Search Button ────────────────────────────────────────
            DKButton(
              label: 'Search Family',
              variant: DKButtonVariant.primary,
              size: DKButtonSize.lg,
              fullWidth: true,
              icon: Icons.search_rounded,
              isLoading: familyIdState.isSearching,
              onPressed: _searchFamily,
            ),

            const SizedBox(height: 24),

            // ── Error Message ────────────────────────────────────────
            if (familyIdState.error != null && _hasSearched)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _errorColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(KinrelRadius.lg),
                  border: Border.all(color: _errorColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: _errorColor, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        familyIdState.error!,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 13,
                          color: _errorColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // ── Search Result Card ───────────────────────────────────
            if (familyIdState.searchResult != null && _hasSearched)
              _buildSearchResultCard(familyIdState),

            const SizedBox(height: 32),

            // ── Info Section ─────────────────────────────────────────
            _buildInfoSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResultCard(FamilyIdState state) {
    final result = state.searchResult!;

    if (!result.found) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
          border: Border.all(color: _borderSubtle),
        ),
        child: Column(
          children: [
            Icon(Icons.search_off_rounded, size: 48, color: _textDim),
            const SizedBox(height: 12),
            Text(
              'Family Not Found',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              result.message ?? 'No family found with this ID',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: _textDim,
              ),
            ),
          ],
        ),
      );
    }

    // Family found - show info card
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(color: _orange.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Family header
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: KinrelColors.amber.withValues(alpha: 0.15),
                ),
                child: Center(
                  child: Icon(Icons.group, color: KinrelColors.amber, size: 24),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.name ?? 'Family',
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      result.kinFamilyId ?? '',
                      style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 12,
                        color: _orange,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Divider
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Divider(color: _borderSubtle, height: 1),
          ),

          // Family details
          if (result.description != null && result.description!.isNotEmpty) ...[
            Text(
              result.description!,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: _textSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
          ],

          // Stats row
          Row(
            children: [
              _buildStatChip(Icons.people_outline, '${result.memberCount ?? 0} members'),
              const SizedBox(width: 14),
              if (result.region != null)
                _buildStatChip(Icons.location_on_outlined, result.region!),
            ],
          ),

          const SizedBox(height: 20),

          // Join button
          DKButton(
            label: 'Join Family',
            variant: DKButtonVariant.gradient,
            size: DKButtonSize.lg,
            fullWidth: true,
            icon: Icons.group_add_rounded,
            isLoading: state.isJoining,
            onPressed: _joinFamily,
          ),
        ],
      ),
    )
    .animate(onPlay: (c) => c.forward())
    .fadeIn(duration: 300.ms)
    .slideY(begin: 0.05, end: 0, duration: 300.ms);
  }

  Widget _buildStatChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: _textDim),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 12,
            color: _textDim,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(color: _borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: _orange, size: 18),
              const SizedBox(width: 8),
              Text(
                'How to get a Family ID',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildInfoStep('1', 'Ask a family member for the Family ID'),
          const SizedBox(height: 6),
          _buildInfoStep('2', 'Enter the KIN-XXXXXXXX code above'),
          const SizedBox(height: 6),
          _buildInfoStep('3', 'Review the family info and tap Join'),
        ],
      ),
    );
  }

  Widget _buildInfoStep(String number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _orange.withValues(alpha: 0.15),
          ),
          child: Center(
            child: Text(
              number,
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _orange,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              color: _textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
