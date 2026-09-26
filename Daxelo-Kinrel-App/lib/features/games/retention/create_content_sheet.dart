// lib/features/games/retention/create_content_sheet.dart
//
// CreateContentSheet — a bottom sheet for family members to author
// custom content for question-based games (Two Truths and a Lie,
// Truth or Dare).
//
// The content enters the family's private pool (family_custom_content
// table) and gets mixed into future rounds — attributed anonymously
// as "Someone in your family wrote this..." in-game.
//
// Includes basic content moderation: length limits + a simple profanity
// wordlist check before insert.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../shared/widgets/dk_components.dart';
import 'retention_providers.dart';

/// Profanity wordlist — a minimal set of common English profanity.
/// This is a family app, so we keep it conservative. Not exhaustive —
/// just a basic filter for a family-private content pool.
const _profanityList = {
  'fuck', 'shit', 'bitch', 'asshole', 'bastard', 'damn', 'crap',
  'dick', 'piss', 'slut', 'whore',
};

bool containsProfanity(String text) {
  final lower = text.toLowerCase();
  for (final word in _profanityList) {
    if (lower.contains(word)) return true;
  }
  return false;
}

class CreateContentSheet extends ConsumerStatefulWidget {
  const CreateContentSheet({
    super.key,
    required this.familyId,
    required this.gameType,
  });

  final String familyId;
  final String gameType; // 'twotruths' | 'truthordare'

  static void show(BuildContext context, {
    required String familyId,
    required String gameType,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CreateContentSheet(
        familyId: familyId,
        gameType: gameType,
      ),
    );
  }

  @override
  ConsumerState<CreateContentSheet> createState() =>
      _CreateContentSheetState();
}

class _CreateContentSheetState extends ConsumerState<CreateContentSheet> {
  final _ttController1 = TextEditingController();
  final _ttController2 = TextEditingController();
  final _ttController3 = TextEditingController();
  int _lieIndex = 2; // default: third statement is the lie

  final _tdController = TextEditingController();
  bool _isTruth = true;

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _ttController1.dispose();
    _ttController2.dispose();
    _ttController3.dispose();
    _tdController.dispose();
    super.dispose();
  }

  bool _validate() {
    if (widget.gameType == 'twotruths') {
      final t1 = _ttController1.text.trim();
      final t2 = _ttController2.text.trim();
      final t3 = _ttController3.text.trim();
      if (t1.isEmpty || t2.isEmpty || t3.isEmpty) {
        _error = 'All three statements are required';
        return false;
      }
      if (t1.length > 200 || t2.length > 200 || t3.length > 200) {
        _error = 'Each statement must be under 200 characters';
        return false;
      }
      for (final t in [t1, t2, t3]) {
        if (containsProfanity(t)) {
          _error = 'Please keep it family-friendly 🙂';
          return false;
        }
      }
    } else if (widget.gameType == 'truthordare') {
      final text = _tdController.text.trim();
      if (text.isEmpty) {
        _error = 'Please write a truth or dare';
        return false;
      }
      if (text.length > 300) {
        _error = 'Must be under 300 characters';
        return false;
      }
      if (containsProfanity(text)) {
        _error = 'Please keep it family-friendly 🙂';
        return false;
      }
    }
    _error = null;
    return true;
  }

  Future<void> _submit() async {
    if (!_validate()) {
      setState(() {});
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    Map<String, dynamic> contentJson;
    if (widget.gameType == 'twotruths') {
      final statements = [
        _ttController1.text.trim(),
        _ttController2.text.trim(),
        _ttController3.text.trim(),
      ];
      contentJson = {
        'statements': statements,
        'lieIndex': _lieIndex,
      };
    } else {
      contentJson = {
        'text': _tdController.text.trim(),
        'type': _isTruth ? 'truth' : 'dare',
      };
    }

    final success = await submitCustomContent(
      ref: ref,
      familyId: widget.familyId,
      gameType: widget.gameType,
      contentJson: contentJson,
    );

    if (mounted) {
      setState(() => _submitting = false);
      if (success) {
        // ── Success: invalidate the customContentProvider so the new
        // content appears in the family content list immediately. The
        // provider is autoDispose, so invalidating here triggers a
        // re-fetch the next time any consumer reads it (and the user
        // is about to navigate back to a screen that does).
        ref.invalidate(customContentProvider(
          (familyId: widget.familyId, gameType: widget.gameType),
        ));
        Navigator.of(context).maybePop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Added to your family\'s content pool! 🎉'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        setState(() => _error = 'Couldn\'t save — try again');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: KinrelColors.darkSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(KinrelSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.gameType == 'twotruths'
                    ? 'Create Your Own Two Truths and a Lie'
                    : 'Create Your Own Truth or Dare',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: KinrelColors.textWhite,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Your family will see this anonymously as "Someone in your family wrote this..."',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  color: KinrelColors.textDim,
                ),
              ),
              const SizedBox(height: 20),
              if (widget.gameType == 'twotruths')
                _buildTwoTruthsForm()
              else
                _buildTruthOrDareForm(),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: KinrelColors.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: KinrelColors.error,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              DKButton(
                label: 'Add to family pool',
                variant: DKButtonVariant.primary,
                fullWidth: true,
                isLoading: _submitting,
                onPressed: _submit,
              ),
              const SizedBox(height: 8),
              DKButton(
                label: 'Cancel',
                variant: DKButtonVariant.secondary,
                fullWidth: true,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTwoTruthsForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Write two truths and one lie. Mark which one is the lie.',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            color: KinrelColors.textSilver,
          ),
        ),
        const SizedBox(height: 12),
        _StatementField(
          controller: _ttController1,
          label: 'Statement 1',
          isLie: _lieIndex == 0,
          onTapLie: () => setState(() => _lieIndex = 0),
        ),
        const SizedBox(height: 8),
        _StatementField(
          controller: _ttController2,
          label: 'Statement 2',
          isLie: _lieIndex == 1,
          onTapLie: () => setState(() => _lieIndex = 1),
        ),
        const SizedBox(height: 8),
        _StatementField(
          controller: _ttController3,
          label: 'Statement 3',
          isLie: _lieIndex == 2,
          onTapLie: () => setState(() => _lieIndex = 2),
        ),
      ],
    );
  }

  Widget _buildTruthOrDareForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Type toggle
        Row(
          children: [
            _TypeChip(
              label: 'Truth',
              selected: _isTruth,
              onTap: () => setState(() => _isTruth = true),
            ),
            const SizedBox(width: 8),
            _TypeChip(
              label: 'Dare',
              selected: !_isTruth,
              onTap: () => setState(() => _isTruth = false),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _tdController,
          maxLength: 300,
          maxLines: 3,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 14,
            color: KinrelColors.textWhite,
          ),
          decoration: InputDecoration(
            counterText: '',
            hintText: _isTruth
                ? 'e.g. "I once met a famous cricket player"'
                : 'e.g. "Do your best dance move for 10 seconds"',
            hintStyle: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              color: KinrelColors.textDim.withValues(alpha: 0.6),
            ),
            filled: true,
            fillColor: KinrelColors.darkCard,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(KinrelRadius.md),
              borderSide: BorderSide(color: KinrelColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(KinrelRadius.md),
              borderSide:
                  const BorderSide(color: KinrelColors.orange, width: 1.4),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatementField extends StatelessWidget {
  const _StatementField({
    required this.controller,
    required this.label,
    required this.isLie,
    required this.onTapLie,
  });

  final TextEditingController controller;
  final String label;
  final bool isLie;
  final VoidCallback onTapLie;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textSilver,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onTapLie,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isLie
                      ? KinrelColors.error.withValues(alpha: 0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isLie
                        ? KinrelColors.error.withValues(alpha: 0.5)
                        : KinrelColors.border,
                  ),
                ),
                child: Text(
                  isLie ? '← This is the LIE' : 'Mark as lie',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isLie ? KinrelColors.error : KinrelColors.textDim,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          maxLength: 200,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 14,
            color: KinrelColors.textWhite,
          ),
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: KinrelColors.darkCard,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(KinrelRadius.md),
              borderSide: BorderSide(color: KinrelColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(KinrelRadius.md),
              borderSide:
                  const BorderSide(color: KinrelColors.orange, width: 1.4),
            ),
          ),
        ),
      ],
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? KinrelColors.orange.withValues(alpha: 0.16)
              : KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? KinrelColors.orange
                : Colors.white.withValues(alpha: 0.07),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
            color: selected ? KinrelColors.orange : KinrelColors.textDim,
          ),
        ),
      ),
    );
  }
}
