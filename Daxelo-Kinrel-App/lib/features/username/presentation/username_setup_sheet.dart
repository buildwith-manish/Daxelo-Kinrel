// lib/features/username/presentation/username_setup_sheet.dart
//
// DAXELO KINREL — Username Setup Bottom Sheet
//
// Shown once if user has no @username. Instagram-style onboarding
// with real-time availability check and auto-generated suggestions.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/utils/api_error_mapper.dart';
import '../providers/username_provider.dart';
import '../../../core/services/supabase_service.dart';

// ── Color shortcuts ──────────────────────────────────────────────
const _cOrange = KinrelColors.orange;
const _cCard = KinrelColors.darkCard;
const _cElevated = KinrelColors.darkElevated;
const _cTextPrimary = KinrelColors.textWhite;
const _cTextSecondary = KinrelColors.textSilver;
const _cTextDim = KinrelColors.textDim;
const _cSuccess = KinrelColors.success;

/// Show the username setup bottom sheet.
/// Returns true if username was successfully set.
Future<bool> showUsernameSetupSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const _UsernameSetupSheet(),
  ).then((result) => result ?? false);
}

class _UsernameSetupSheet extends ConsumerStatefulWidget {
  const _UsernameSetupSheet();

  @override
  ConsumerState<_UsernameSetupSheet> createState() =>
      _UsernameSetupSheetState();
}

class _UsernameSetupSheetState extends ConsumerState<_UsernameSetupSheet> {
  final _controller = TextEditingController();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    final username = _controller.text.trim().toLowerCase();
    ref.read(usernameProvider.notifier).checkAvailability(username);
  }

  bool get _canConfirm {
    final state = ref.read(usernameProvider);
    return state.availability == UsernameAvailability.available &&
        _controller.text.trim().isNotEmpty &&
        !_isSubmitting;
  }

  Future<void> _confirm() async {
    if (!_canConfirm) return;

    setState(() => _isSubmitting = true);

    final success = await ref
        .read(usernameProvider.notifier)
        .setUserUsername(_controller.text.trim().toLowerCase());

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _isSubmitting = false);
      // Try to map API errors to field-specific messages
      final fieldErrors = mapApiError('Failed to set username');
      final message = fieldErrors?['form'] ?? 'Failed to set username. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: KinrelColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final checkState = ref.watch(usernameProvider);
    final user = ref.watch(currentUserProvider);
    final displayName = user?.userMetadata?['name'] as String? ?? '';
    final suggestions = UsernameValidator.generateSuggestions(
      displayName.isNotEmpty ? displayName : 'user',
    );

    return Container(
      decoration: BoxDecoration(
        color: _cCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: KinrelSpacing.base,
        right: KinrelSpacing.base,
        top: KinrelSpacing.xl,
        bottom: MediaQuery.of(context).viewInsets.bottom + KinrelSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Title
          Text(
            'Choose your @username',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: _cTextPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'This is how others find you on Daxelo Kinrel',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              color: _cTextSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),

          // Username input field with @ prefix
          Container(
            decoration: BoxDecoration(
              color: _cElevated,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _getBorderColor(checkState.availability),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                // @ prefix
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text(
                    '@',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: _cOrange,
                    ),
                  ),
                ),
                // Input
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    keyboardType: TextInputType.text,
                    textCapitalization: TextCapitalization.none,
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: _cTextPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'username',
                      hintStyle: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: _cTextDim.withValues(alpha: 0.4),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 14,
                      ),
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _confirm(),
                  ),
                ),
                // Status indicator
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: _buildStatusIndicator(checkState.availability),
                ),
              ],
            ),
          ),

          // Status text
          const SizedBox(height: 8),
          _buildStatusText(checkState),

          // Suggestions
          if (suggestions.isNotEmpty && _controller.text.isEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Suggestions',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: _cTextDim,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: suggestions.map((suggestion) {
                return GestureDetector(
                  onTap: () {
                    _controller.text = suggestion;
                    _controller.selection = TextSelection.fromPosition(
                      TextPosition(offset: suggestion.length),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _cOrange.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _cOrange.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      '@$suggestion',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: _cOrange,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 28),

          // Confirm button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _canConfirm ? _confirm : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _cOrange,
                disabledBackgroundColor: _cOrange.withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _isSubmitting
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'Confirm',
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(UsernameAvailability availability) {
    switch (availability) {
      case UsernameAvailability.checking:
        return SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: _cOrange),
        );
      case UsernameAvailability.available:
        return Icon(Icons.check_circle_rounded, size: 22, color: _cSuccess);
      case UsernameAvailability.taken:
        return Icon(Icons.cancel_rounded, size: 22, color: KinrelColors.error);
      case UsernameAvailability.invalid:
        return Icon(
          Icons.error_outline_rounded,
          size: 22,
          color: KinrelColors.warning,
        );
      case UsernameAvailability.initial:
        return SizedBox.shrink();
    }
  }

  Widget _buildStatusText(UsernameCheckState state) {
    String text;
    Color color;

    switch (state.availability) {
      case UsernameAvailability.available:
        text = 'Available!';
        color = _cSuccess;
        break;
      case UsernameAvailability.taken:
        text = 'Already taken';
        color = KinrelColors.error;
        break;
      case UsernameAvailability.invalid:
        text =
            '3-20 chars, lowercase letters, numbers, _ only, starts with a letter';
        color = _cTextDim;
        break;
      case UsernameAvailability.checking:
        text = 'Checking...';
        color = _cTextDim;
        break;
      case UsernameAvailability.initial:
        return SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 12,
          color: color,
          fontWeight:
              state.availability == UsernameAvailability.available ||
                  state.availability == UsernameAvailability.taken
              ? FontWeight.w600
              : FontWeight.w400,
        ),
      ),
    );
  }

  Color _getBorderColor(UsernameAvailability availability) {
    switch (availability) {
      case UsernameAvailability.available:
        return _cSuccess;
      case UsernameAvailability.taken:
        return KinrelColors.error;
      case UsernameAvailability.invalid:
        return KinrelColors.warning.withValues(alpha: 0.4);
      case UsernameAvailability.checking:
        return _cOrange.withValues(alpha: 0.3);
      case UsernameAvailability.initial:
        return Colors.white.withValues(alpha: 0.06);
    }
  }
}
