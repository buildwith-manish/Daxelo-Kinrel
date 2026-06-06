// lib/presentation/screens/family/family_invite_screen.dart
//
// DAXELO KINREL — Family Invite Screen
//
// Invite Link management:
//   • Invite Link section with Copy/Share/QR Code
//   • Expiry selector: Never | 7 days | 1 day
//   • Max uses selector: Unlimited | 10 | 25 | 100
//   • Revoke button

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart' as share_plus;

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../data/models/family_invite_model.dart';
import '../../../data/repositories/family_invite_repository.dart';

class FamilyInviteScreen extends ConsumerStatefulWidget {
  const FamilyInviteScreen({
    super.key,
    required this.familyId,
    required this.familyName,
  });

  final String familyId;
  final String familyName;

  @override
  ConsumerState<FamilyInviteScreen> createState() => _FamilyInviteScreenState();
}

class _FamilyInviteScreenState extends ConsumerState<FamilyInviteScreen> {
  FamilyInviteModel? _invite;
  bool _isLoading = true;
  bool _isRevoking = false;
  int _selectedExpiry = 0; // 0 = Never, 1 = 7 days, 2 = 1 day
  int _selectedMaxUses = 0; // 0 = Unlimited, 1 = 10, 2 = 25, 3 = 100

  final _expiryOptions = [
    ('Never', null),
    ('7 days', 7),
    ('1 day', 1),
  ];

  final _maxUsesOptions = [
    ('Unlimited', null),
    ('10', 10),
    ('25', 25),
    ('100', 100),
  ];

  @override
  void initState() {
    super.initState();
    _generateInvite();
  }

  Future<void> _generateInvite() async {
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(familyInviteRepositoryProvider);
      final invite = await repo.generateInviteLink(
        widget.familyId,
        expiresInDays: _expiryOptions[_selectedExpiry].$2,
        maxUses: _maxUsesOptions[_selectedMaxUses].$2,
      );
      if (mounted) {
        setState(() {
          _invite = invite;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar('Failed to generate invite link', isError: true);
      }
    }
  }

  Future<void> _revokeLinks() async {
    // Confirm dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KinrelColors.darkCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.dialog),
          side: const BorderSide(color: KinrelColors.border),
        ),
        title: Text(
          'Revoke all invite links?',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            color: KinrelColors.textWhite,
          ),
        ),
        content: Text(
          'This will invalidate all existing invite links for ${widget.familyName}. '
          'Anyone with an old link will no longer be able to join.',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 14,
            color: KinrelColors.textSilver,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: TextStyle(color: KinrelColors.textDim)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: KinrelColors.error,
              foregroundColor: Colors.white,
            ),
            child: Text('Revoke All'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isRevoking = true);
    try {
      final repo = ref.read(familyInviteRepositoryProvider);
      await repo.revokeInviteLinks(widget.familyId);
      if (mounted) {
        setState(() {
          _invite = null;
          _isRevoking = false;
        });
        _showSnackBar('All invite links revoked');
        _generateInvite();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRevoking = false);
        _showSnackBar('Failed to revoke links', isError: true);
      }
    }
  }

  void _copyLink() {
    if (_invite == null) return;
    Clipboard.setData(ClipboardData(text: _invite!.token));
    _showSnackBar('Invite link copied!');
  }

  void _shareLink() {
    if (_invite == null) return;
    final text =
        'You\'re invited to join ${widget.familyName} on Kinrel! 🧡\n\n'
        'Use this invite token: ${_invite!.token}\n\n'
        '— Sent via Kinrel by Daxelo';
    share_plus.Share.share(text, subject: 'Family invitation — ${widget.familyName}');
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
    return Scaffold(
      backgroundColor: KinrelColors.darkBackground,
      appBar: AppBar(
        backgroundColor: KinrelColors.darkBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: KinrelColors.textWhite),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Invite to Family',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textWhite,
          ),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: KinrelColors.orange))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Invite link card
                  _buildInviteLinkCard(),
                  const SizedBox(height: 24),

                  // Expiry selector
                  _buildSectionTitle('Link Expiry'),
                  const SizedBox(height: 8),
                  _buildSelectorRow(
                    _expiryOptions.map((e) => e.$1).toList(),
                    _selectedExpiry,
                    (index) => setState(() {
                      _selectedExpiry = index;
                      _generateInvite();
                    }),
                  ),
                  const SizedBox(height: 24),

                  // Max uses selector
                  _buildSectionTitle('Max Uses'),
                  const SizedBox(height: 8),
                  _buildSelectorRow(
                    _maxUsesOptions.map((e) => e.$1).toList(),
                    _selectedMaxUses,
                    (index) => setState(() {
                      _selectedMaxUses = index;
                      _generateInvite();
                    }),
                  ),
                  const SizedBox(height: 32),

                  // Revoke button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _isRevoking ? null : _revokeLinks,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: KinrelColors.error,
                        side: BorderSide(color: KinrelColors.error.withValues(alpha: 0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isRevoking
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(KinrelColors.error),
                              ),
                            )
                          : Text(
                              'Revoke All Invite Links',
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

  Widget _buildInviteLinkCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(color: KinrelColors.orange.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.link_rounded, color: KinrelColors.orange, size: 20),
              const SizedBox(width: 8),
              Text(
                'Invite Link',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_invite != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: KinrelColors.darkElevated,
                borderRadius: BorderRadius.circular(KinrelRadius.md),
              ),
              child: Text(
                _invite!.token,
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 14,
                  color: KinrelColors.textWhite,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Info chips
            Wrap(
              spacing: 8,
              children: [
                if (_invite!.expiresAt != null)
                  _buildInfoChip(
                    Icons.schedule,
                    'Expires ${_invite!.isExpired ? 'Expired' : 'Active'}',
                    _invite!.isExpired ? KinrelColors.error : KinrelColors.success,
                  ),
                if (_invite!.maxUses != null)
                  _buildInfoChip(
                    Icons.people_outline,
                    '${_invite!.useCount}/${_invite!.maxUses} used',
                    KinrelColors.amber,
                  ),
                if (_invite!.maxUses == null)
                  _buildInfoChip(
                    Icons.all_inclusive,
                    'Unlimited uses',
                    KinrelColors.success,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _copyLink,
                    icon: Icon(Icons.copy, size: 16),
                    label: Text('Copy'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: KinrelColors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _shareLink,
                    icon: Icon(Icons.share, size: 16),
                    label: Text('Share'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: KinrelColors.orange,
                      side: BorderSide(color: KinrelColors.orange.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      // TODO: Navigate to QR code screen
                      _showSnackBar('QR Code coming soon!');
                    },
                    icon: Icon(Icons.qr_code, size: 16),
                    label: Text('QR Code'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: KinrelColors.orange,
                      side: BorderSide(color: KinrelColors.orange.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            Text(
              'Failed to generate invite link',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: KinrelColors.textDim,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontFamily: KinrelTypography.bodyFont,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: KinrelColors.orange,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildSelectorRow(
    List<String> options,
    int selectedIndex,
    ValueChanged<int> onChanged,
  ) {
    return Row(
      children: List.generate(options.length, (index) {
        final isSelected = index == selectedIndex;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(index),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? KinrelColors.orange
                    : KinrelColors.darkElevated,
                borderRadius: BorderRadius.circular(10),
                border: isSelected
                    ? null
                    : Border.all(color: KinrelColors.textDim.withValues(alpha: 0.3)),
              ),
              child: Center(
                child: Text(
                  options[index],
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? Colors.white : KinrelColors.textSilver,
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
