import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/brand_colors.dart';
import '../../data/models/family_join_preview_model.dart';
import '../../data/repositories/family_invite_repository.dart';
import '../../data/providers/follow_provider.dart' hide Family;
import '../../../../core/family/family_provider.dart';

class JoinFamilyPreviewScreen extends ConsumerStatefulWidget {
  const JoinFamilyPreviewScreen({super.key, required this.token});
  final String token;

  @override
  ConsumerState<JoinFamilyPreviewScreen> createState() => _JoinFamilyPreviewScreenState();
}

class _JoinFamilyPreviewScreenState extends ConsumerState<JoinFamilyPreviewScreen> {
  FamilyJoinPreviewModel? _preview;
  bool _isLoading = true;
  bool _isJoining = false;
  String? _error;
  bool _alreadyMember = false;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    try {
      final repo = ref.read(familyInviteRepositoryProvider);
      final preview = await repo.previewFamily(widget.token);
      setState(() {
        _preview = preview;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Failed to load family info';
      });
    }
  }

  Future<void> _joinFamily() async {
    setState(() => _isJoining = true);
    try {
      await ref.read(familyInviteRepositoryProvider).joinFamily(widget.token);
      // Invalidate family list to show new family
      ref.invalidate(familyListProvider);
      setState(() => _isJoining = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Joined family!'), backgroundColor: KinrelColors.success),
        );
        context.go('/families');
      }
    } catch (e) {
      setState(() => _isJoining = false);
      if (mounted) {
        final msg = e.toString().contains('already')
            ? 'You are already a member'
            : 'Failed to join family';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: KinrelColors.error),
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
        title: Text('Join Family', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600)),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: KinrelColors.orange))
          : _error != null
              ? _buildErrorState()
              : _preview != null
                  ? _buildPreview()
                  : _buildErrorState(),
    );
  }

  Widget _buildPreview() {
    final preview = _preview!;

    if (!preview.isValid) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.link_off, size: 64, color: KinrelColors.error),
            SizedBox(height: 16),
            Text('Invalid Link', style: TextStyle(color: KinrelColors.textWhite, fontSize: 20, fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            Text('This invite link is not valid', style: TextStyle(color: KinrelColors.textSilver)),
            SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/home'),
              style: ElevatedButton.styleFrom(backgroundColor: KinrelColors.orange),
              child: Text('Go Home'),
            ),
          ],
        ),
      );
    }

    if (preview.isExpired) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.timer_off, size: 64, color: KinrelColors.warning),
            SizedBox(height: 16),
            Text('Link Expired', style: TextStyle(color: KinrelColors.textWhite, fontSize: 20, fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            Text('This invite link has expired', style: TextStyle(color: KinrelColors.textSilver)),
            SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/home'),
              style: ElevatedButton.styleFrom(backgroundColor: KinrelColors.orange),
              child: Text('Go Home'),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: KinrelColors.elevation1,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.family_restroom, size: 40, color: KinrelColors.orange),
            ),
            SizedBox(height: 24),
            Text(
              preview.familyName,
              style: TextStyle(color: KinrelColors.textWhite, fontSize: 24, fontWeight: FontWeight.w700, fontFamily: 'Outfit'),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              'Owned by ${preview.ownerName}',
              style: TextStyle(color: KinrelColors.textSilver, fontSize: 14),
            ),
            SizedBox(height: 4),
            Text(
              '${preview.memberCount} member${preview.memberCount != 1 ? 's' : ''}',
              style: TextStyle(color: KinrelColors.textDim, fontSize: 13),
            ),
            SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isJoining ? null : _joinFamily,
                style: ElevatedButton.styleFrom(
                  backgroundColor: KinrelColors.orange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                ),
                child: _isJoining
                    ? CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                    : Text('Join Family', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, fontFamily: 'Outfit')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: KinrelColors.error),
          SizedBox(height: 16),
          Text(_error ?? 'Something went wrong', style: TextStyle(color: KinrelColors.textWhite, fontSize: 16)),
          SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadPreview,
            style: ElevatedButton.styleFrom(backgroundColor: KinrelColors.orange),
            child: Text('Retry'),
          ),
        ],
      ),
    );
  }
}
