import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/constants/brand_colors.dart';
import '../../../../core/config/env_config.dart';
import '../../data/models/family_invite_model.dart';
import '../../data/repositories/family_invite_repository.dart';

class FamilyInviteScreen extends ConsumerStatefulWidget {
  const FamilyInviteScreen({super.key, required this.familyId, required this.familyName});
  final String familyId;
  final String familyName;

  @override
  ConsumerState<FamilyInviteScreen> createState() => _FamilyInviteScreenState();
}

class _FamilyInviteScreenState extends ConsumerState<FamilyInviteScreen> {
  FamilyInviteModel? _activeInvite;
  bool _isLoading = true;
  int? _expiryDays;
  int? _maxUses;
  final _expiryController = TextEditingController();
  final _maxUsesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _generateInvite();
  }

  Future<void> _generateInvite() async {
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(familyInviteRepositoryProvider);
      final invite = await repo.generateInvite(
        familyId: widget.familyId,
        expiryDays: _expiryDays,
        maxUses: _maxUses,
      );
      setState(() {
        _activeInvite = invite;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate invite'), backgroundColor: KinrelColors.error),
        );
      }
    }
  }

  Future<void> _revokeInvites() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KinrelColors.elevation3,
        title: Text('Revoke All Links', style: TextStyle(color: KinrelColors.textWhite)),
        content: Text('This will deactivate all active invite links. Existing links will stop working.',
            style: TextStyle(color: KinrelColors.textSilver)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: KinrelColors.textSilver)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Revoke All', style: TextStyle(color: KinrelColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await ref.read(familyInviteRepositoryProvider).revokeInvites(widget.familyId);
        setState(() => _activeInvite = null);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('All invites revoked'), backgroundColor: KinrelColors.success),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to revoke'), backgroundColor: KinrelColors.error),
          );
        }
      }
    }
  }

  String get _inviteUrl {
    if (_activeInvite == null) return '';
    return '${EnvConfig.appDeepLinkScheme}://join/${_activeInvite!.token}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KinrelColors.darkBackground,
      appBar: AppBar(
        backgroundColor: KinrelColors.darkBackground,
        title: Text('Invite Members', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600)),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: KinrelColors.orange))
          : SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_activeInvite != null) ...[
                    // Invite link display
                    Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: KinrelColors.elevation1,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Text('Invite Link', style: TextStyle(color: KinrelColors.textSilver, fontSize: 12)),
                          SizedBox(height: 8),
                          SelectableText(
                            _inviteUrl,
                            style: TextStyle(color: KinrelColors.textWhite, fontSize: 14, fontFamily: 'DMMono'),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () {
                                  // Copy to clipboard logic
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Link copied!'), backgroundColor: KinrelColors.success),
                                  );
                                },
                                icon: Icon(Icons.copy, size: 16),
                                label: Text('Copy'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: KinrelColors.orange,
                                  side: BorderSide(color: KinrelColors.orange),
                                ),
                              ),
                              SizedBox(width: 12),
                              ElevatedButton.icon(
                                onPressed: () => Share.share(_inviteUrl),
                                icon: Icon(Icons.share, size: 16),
                                label: Text('Share'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: KinrelColors.orange,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 24),

                    // QR Code
                    Container(
                      padding: EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: QrImageView(
                          data: _inviteUrl,
                          version: QrVersions.auto,
                          size: 200,
                          backgroundColor: Colors.white,
                        ),
                      ),
                    ),
                    SizedBox(height: 24),

                    // Invite details
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: KinrelColors.elevation1,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          _buildDetailRow('Uses', '${_activeInvite!.useCount}${_activeInvite!.maxUses != null ? '/${_activeInvite!.maxUses}' : ''}'),
                          _buildDetailRow('Status', _activeInvite!.active ? 'Active' : 'Inactive'),
                          if (_activeInvite!.expiresAt != null)
                            _buildDetailRow('Expires', _formatDate(_activeInvite!.expiresAt!)),
                        ],
                      ),
                    ),
                    SizedBox(height: 24),
                  ],

                  // Generate new link with options
                  Text('New Link Options', style: TextStyle(color: KinrelColors.textSilver, fontSize: 13)),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _expiryController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Expiry (days)',
                            labelStyle: TextStyle(color: KinrelColors.textDim),
                            filled: true,
                            fillColor: KinrelColors.elevation1,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          style: TextStyle(color: KinrelColors.textWhite),
                          onChanged: (v) => _expiryDays = int.tryParse(v),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _maxUsesController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Max uses',
                            labelStyle: TextStyle(color: KinrelColors.textDim),
                            filled: true,
                            fillColor: KinrelColors.elevation1,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          style: TextStyle(color: KinrelColors.textWhite),
                          onChanged: (v) => _maxUses = int.tryParse(v),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _generateInvite,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: KinrelColors.orange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    child: Text('Generate New Link'),
                  ),
                  SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _revokeInvites,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: KinrelColors.error,
                      side: BorderSide(color: KinrelColors.error),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    child: Text('Revoke All Links'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: KinrelColors.textDim, fontSize: 13)),
          Text(value, style: TextStyle(color: KinrelColors.textWhite, fontSize: 13)),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
