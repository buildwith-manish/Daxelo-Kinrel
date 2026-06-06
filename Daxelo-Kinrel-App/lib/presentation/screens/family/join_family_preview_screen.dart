// lib/presentation/screens/family/join_family_preview_screen.dart
//
// DAXELO KINREL — Join Family Preview Screen
//
// States: LOADING, ERROR_EXPIRED, ERROR_MAX_USES, ERROR_ALREADY_MEMBER,
//         SUCCESS preview with Join button

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../data/models/family_invite_model.dart';
import '../../../data/repositories/family_invite_repository.dart';

enum _PreviewState { loading, errorExpired, errorMaxUses, errorAlreadyMember, success, errorGeneric }

class JoinFamilyPreviewScreen extends ConsumerStatefulWidget {
  const JoinFamilyPreviewScreen({
    super.key,
    required this.token,
  });

  final String token;

  @override
  ConsumerState<JoinFamilyPreviewScreen> createState() =>
      _JoinFamilyPreviewScreenState();
}

class _JoinFamilyPreviewScreenState
    extends ConsumerState<JoinFamilyPreviewScreen> {
  _PreviewState _state = _PreviewState.loading;
  FamilyJoinPreviewModel? _preview;
  bool _isJoining = false;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    setState(() => _state = _PreviewState.loading);
    try {
      final repo = ref.read(familyInviteRepositoryProvider);
      final preview = await repo.previewJoin(widget.token);
      if (!mounted) return;

      if (!preview.isValid) {
        if (preview.isAlreadyMember) {
          setState(() => _state = _PreviewState.errorAlreadyMember);
        } else if (preview.isMaxUsesReached) {
          setState(() => _state = _PreviewState.errorMaxUses);
        } else if (preview.isInviteExpired) {
          setState(() => _state = _PreviewState.errorExpired);
        } else {
          setState(() => _state = _PreviewState.errorGeneric);
        }
      } else {
        setState(() {
          _preview = preview;
          _state = _PreviewState.success;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _state = _PreviewState.errorGeneric);
      }
    }
  }

  Future<void> _joinFamily() async {
    setState(() => _isJoining = true);
    try {
      final repo = ref.read(familyInviteRepositoryProvider);
      await repo.joinFamily(widget.token);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully joined ${_preview?.familyName ?? 'family'}! 🧡'),
            backgroundColor: KinrelColors.darkCard,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop(true); // Return true to signal success
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isJoining = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to join family. Please try again.'),
            backgroundColor: KinrelColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
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
          'Join Family',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textWhite,
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _PreviewState.loading:
        return Center(
          child: CircularProgressIndicator(color: KinrelColors.orange),
        );
      case _PreviewState.errorExpired:
        return _buildErrorState(
          icon: Icons.event_busy_outlined,
          title: 'Invite Expired',
          subtitle: 'This invite link has expired. Please ask for a new one.',
        );
      case _PreviewState.errorMaxUses:
        return _buildErrorState(
          icon: Icons.group_off_outlined,
          title: 'Invite Limit Reached',
          subtitle: 'This invite link has reached its maximum number of uses.',
        );
      case _PreviewState.errorAlreadyMember:
        return _buildErrorState(
          icon: Icons.check_circle_outline,
          title: 'Already a Member',
          subtitle: 'You\'re already a member of this family!',
        );
      case _PreviewState.errorGeneric:
        return _buildErrorState(
          icon: Icons.error_outline,
          title: 'Invalid Invite',
          subtitle: 'This invite link is not valid. Please check the link and try again.',
          showRetry: true,
        );
      case _PreviewState.success:
        return _buildSuccessPreview();
    }
  }

  Widget _buildErrorState({
    required IconData icon,
    required String title,
    required String subtitle,
    bool showRetry = false,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KinrelColors.error.withValues(alpha: 0.1),
              ),
              child: Icon(icon, size: 40, color: KinrelColors.error),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: KinrelColors.textSilver,
              ),
            ),
            if (showRetry) ...[
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loadPreview,
                style: ElevatedButton.styleFrom(
                  backgroundColor: KinrelColors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  'Retry',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessPreview() {
    final preview = _preview!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 16),
          // Family avatar
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: KinrelColors.orange.withValues(alpha: 0.1),
              border: Border.all(
                color: KinrelColors.orange.withValues(alpha: 0.3),
                width: 2,
              ),
              image: preview.familyAvatarUrl != null
                  ? DecorationImage(
                      image: NetworkImage(preview.familyAvatarUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: preview.familyAvatarUrl != null
                ? null
                : Icon(
                    Icons.group,
                    size: 44,
                    color: KinrelColors.orange,
                  ),
          ),
          const SizedBox(height: 20),
          // Family name
          Text(
            preview.familyName,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite,
            ),
          ),
          const SizedBox(height: 4),
          // Owner name
          Text(
            'Created by ${preview.ownerName}',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              color: KinrelColors.textSilver,
            ),
          ),
          const SizedBox(height: 24),
          // Stats card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: KinrelColors.darkCard,
              borderRadius: BorderRadius.circular(KinrelRadius.lg),
              border: Border.all(color: KinrelColors.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(Icons.people_outline, '${preview.memberCount}', 'Members'),
                _buildStatItem(Icons.check_circle_outline, 'Active', 'Status'),
              ],
            ),
          ),
          const SizedBox(height: 32),
          // Join button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isJoining ? null : _joinFamily,
              style: ElevatedButton.styleFrom(
                backgroundColor: KinrelColors.orange,
                foregroundColor: Colors.white,
                disabledBackgroundColor: KinrelColors.orange.withValues(alpha: 0.6),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: _isJoining
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      'Join Family',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, size: 24, color: KinrelColors.orange),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textWhite,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 12,
            color: KinrelColors.textDim,
          ),
        ),
      ],
    );
  }
}
