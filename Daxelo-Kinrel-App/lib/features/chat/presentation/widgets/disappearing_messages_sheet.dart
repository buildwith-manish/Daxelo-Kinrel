// lib/features/chat/presentation/widgets/disappearing_messages_sheet.dart
//
// DAXELO KINREL — Disappearing Messages Sheet (Tier 2 chat feature)
//
// A modal bottom sheet for enabling/disappearing messages per chat.
// Reached from the chat header's "more" menu → "Disappearing messages".
//
// Options:
//   • Off (default)
//   • 24 hours
//   • 7 days
//   • 90 days
//
// On select: calls fn_set_disappearing_messages RPC which upserts the
// caller's ChatSettings row. The nightly pg_cron job (03:00 UTC) then
// soft-deletes (appends to deletedForMe) any message older than the
// threshold for this chat.
//
// v1: any family member can enable/disable. A future v2 could require
// admin consent or both-party consent for 1:1 families.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/services/supabase_service.dart';

class DisappearingMessagesSheet extends ConsumerStatefulWidget {
  const DisappearingMessagesSheet({
    super.key,
    required this.familyId,
  });

  final String familyId;

  /// Opens the sheet. Returns true if the setting changed, false if
  /// the user dismissed without changing.
  static Future<bool> show(
    BuildContext context, {
    required String familyId,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: DisappearingMessagesSheet(familyId: familyId),
      ),
    );
    return result ?? false;
  }

  @override
  ConsumerState<DisappearingMessagesSheet> createState() =>
      _DisappearingMessagesSheetState();
}

class _DisappearingMessagesSheetState
    extends ConsumerState<DisappearingMessagesSheet> {
  int? _currentHours;
  int? _selectedHours;
  bool _isLoading = true;
  bool _isSaving = false;

  static const _options = <_DisappearingOption>[
    _DisappearingOption(hours: null, label: 'Off', description: 'Keep all messages'),
    _DisappearingOption(hours: 24, label: '24 hours', description: 'Messages disappear after a day'),
    _DisappearingOption(hours: 168, label: '7 days', description: 'Messages disappear after a week'),
    _DisappearingOption(hours: 2160, label: '90 days', description: 'Messages disappear after 3 months'),
  ];

  @override
  void initState() {
    super.initState();
    _loadCurrent();
  }

  Future<void> _loadCurrent() async {
    final client = ref.read(supabaseProvider);
    if (client == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final response = await client!.rpc(
        'fn_get_disappearing_messages',
        params: {'p_family_id': widget.familyId},
      ).timeout(const Duration(seconds: 8));
      final result = response as Map<String, dynamic>?;
      final hours = result?['disappearingAfterHours'] as int?;
      if (mounted) {
        setState(() {
          _currentHours = hours;
          _selectedHours = hours;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    if (_selectedHours == _currentHours || _isSaving) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() => _isSaving = true);

    final client = ref.read(supabaseProvider);
    try {
      await client?.rpc(
        'fn_set_disappearing_messages',
        params: {
          'p_family_id': widget.familyId,
          'p_after_hours': _selectedHours,
        },
      ).timeout(const Duration(seconds: 8));
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: KinrelColors.textDim.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Title
            Row(
              children: [
                Icon(Icons.timer_outlined,
                    size: 22, color: KinrelColors.ember),
                const SizedBox(width: 10),
                Text(
                  'Disappearing messages',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Messages older than the selected duration are automatically removed from your view. The nightly cleanup runs at 03:00 UTC.',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12.5,
                color: KinrelColors.textDim,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            // Options
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: CircularProgressIndicator(color: KinrelColors.ember),
                ),
              )
            else
              ..._options.map((opt) => _optionRow(opt)),
            const SizedBox(height: 12),
            // Save button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isLoading || _isSaving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: KinrelColors.ember,
                  disabledBackgroundColor:
                      KinrelColors.ember.withValues(alpha: 0.35),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        _selectedHours == _currentHours ? 'Done' : 'Save',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _optionRow(_DisappearingOption opt) {
    final selected = _selectedHours == opt.hours;
    return InkWell(
      onTap: () => setState(() => _selectedHours = opt.hours),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            // Radio dot
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? KinrelColors.ember
                      : Colors.white.withValues(alpha: 0.25),
                  width: 1.8,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: KinrelColors.ember,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    opt.label,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                  Text(
                    opt.description,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 11.5,
                      color: KinrelColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_rounded,
                  size: 18, color: KinrelColors.ember),
          ],
        ),
      ),
    );
  }
}

class _DisappearingOption {
  const _DisappearingOption({
    required this.hours,
    required this.label,
    required this.description,
  });
  final int? hours;
  final String label;
  final String description;
}
