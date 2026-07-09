import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/constants/brand_colors.dart';
import '../../../../core/config/env_config.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../data/repositories/search_repository.dart';
import '../../../family/presentation/add_member_source.dart';
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

  // Direct invite by username search
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  List<KinrelUser> _searchResults = [];
  bool _isSearching = false;
  bool _hasSearched = false;
  KinrelUser? _selectedUser;
  bool _isSendingDirect = false;

  @override
  void initState() {
    super.initState();
    _generateInvite();
  }

  @override
  void dispose() {
    _expiryController.dispose();
    _maxUsesController.dispose();
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Debounced username search — reuses the existing
  /// SearchRepository.searchKinrelUsers RPC (fn_search_kinrel_users),
  /// the same API used by the "Find on Kinrel" add-member flow.
  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      _performSearch(_searchController.text);
    });
  }

  Future<void> _performSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _searchResults = [];
        _hasSearched = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _hasSearched = true;
    });

    try {
      final repo = ref.read(searchRepositoryProvider);
      final results = await repo.searchKinrelUsers(trimmed, limit: 20);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  /// Send a direct invite to the selected Kinrel user.
  /// Generates an invite link via the RPC, then inserts a Notification
  /// row for the target user so they see a family invite in-app.
  Future<void> _sendDirectInvite() async {
    if (_selectedUser == null) return;

    setState(() => _isSendingDirect = true);
    try {
      final repo = ref.read(familyInviteRepositoryProvider);
      // Generate the invite link.
      final invite = await repo.generateInvite(familyId: widget.familyId);
      final inviteUrl =
          '${EnvConfig.appDeepLinkScheme}://join/${invite.token}';

      // Insert a notification for the target user so they see the
      // family invite in their notifications feed.
      final client = ref.read(supabaseProvider);
      if (client != null) {
        await client.from('Notification').insert({
          'id': 'notif_${DateTime.now().millisecondsSinceEpoch}_${_selectedUser!.id}',
          'userId': _selectedUser!.id,
          'eventType': 'family_invite',
          'title': '${widget.familyName} invited you',
          'body':
              'You have been invited to join ${widget.familyName} on Daxelo Kinrel.',
          'familyId': widget.familyId,
          'actionUrl': inviteUrl,
          'priority': 'high',
          'read': false,
        });
      }

      setState(() => _isSendingDirect = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invite sent to ${_selectedUser!.name}'),
            backgroundColor: KinrelColors.success,
          ),
        );
        // Reset selection + search.
        _searchController.clear();
        setState(() {
          _selectedUser = null;
          _searchResults = [];
          _hasSearched = false;
        });
      }
    } catch (e) {
      setState(() => _isSendingDirect = false);
      if (mounted) {
        final errorMsg = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: KinrelColors.error,
          ),
        );
      }
    }
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
        // Surface the specific error from the repository instead of
        // the generic "Failed to generate invite" — the repository
        // now catches PostgrestException and returns a friendly message.
        final errorMsg = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: KinrelColors.error,
          ),
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

                  // ── Direct invite by Kinrel username search ──────────
                  // Search for existing Kinrel users by username, select
                  // one, then send them an in-app invite notification.
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: KinrelColors.elevation1,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: KinrelColors.orange.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.person_add_outlined,
                                size: 18, color: KinrelColors.orange),
                            SizedBox(width: 8),
                            Text(
                              'Invite directly',
                              style: TextStyle(
                                color: KinrelColors.textWhite,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Search for a Kinrel user by username',
                          style: TextStyle(
                            color: KinrelColors.textDim,
                            fontSize: 12,
                          ),
                        ),
                        SizedBox(height: 12),

                        // ── Selected user chip (shown after selection) ──
                        if (_selectedUser != null) ...[
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: KinrelColors.orange
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: KinrelColors.orange
                                    .withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: KinrelColors.orange
                                      .withValues(alpha: 0.2),
                                  backgroundImage: _selectedUser!
                                          .avatarUrl !=
                                      null
                                      ? NetworkImage(
                                          _selectedUser!.avatarUrl!)
                                      : null,
                                  child: _selectedUser!.avatarUrl == null
                                      ? Text(
                                          _selectedUser!.name.isNotEmpty
                                              ? _selectedUser!.name[0]
                                                  .toUpperCase()
                                              : '?',
                                          style: TextStyle(
                                              color: KinrelColors.orange,
                                              fontSize: 14),
                                        )
                                      : null,
                                ),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _selectedUser!.name,
                                        style: TextStyle(
                                          color: KinrelColors.textWhite,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (_selectedUser!.username != null)
                                        Text(
                                          '@${_selectedUser!.username}',
                                          style: TextStyle(
                                            color: KinrelColors.textDim,
                                            fontSize: 11,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => setState(() {
                                    _selectedUser = null;
                                  }),
                                  child: Icon(Icons.close,
                                      size: 18,
                                      color: KinrelColors.textDim),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 12),
                        ] else ...[
                          // ── Search field ──────────────────────────────
                          TextField(
                            controller: _searchController,
                            onChanged: (_) => _onSearchChanged(),
                            decoration: InputDecoration(
                              hintText: '@username or name',
                              hintStyle: TextStyle(
                                  color: KinrelColors.textDim),
                              prefixIcon: Icon(Icons.search,
                                  size: 18,
                                  color: KinrelColors.textDim),
                              filled: true,
                              fillColor: KinrelColors.darkBackground,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                            style: TextStyle(
                                color: KinrelColors.textWhite,
                                fontSize: 14),
                          ),

                          // ── Search results list ──────────────────────
                          if (_isSearching)
                            Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Center(
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: KinrelColors.orange,
                                  ),
                                ),
                              ),
                            )
                          else if (_hasSearched &&
                              _searchResults.isEmpty)
                            Padding(
                              padding: EdgeInsets.only(top: 12),
                              child: Center(
                                child: Text(
                                  'No user found with that username',
                                  style: TextStyle(
                                    color: KinrelColors.textDim,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            )
                          else if (_searchResults.isNotEmpty)
                            Container(
                              margin: EdgeInsets.only(top: 8),
                              constraints: BoxConstraints(maxHeight: 200),
                              decoration: BoxDecoration(
                                color: KinrelColors.darkBackground,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: KinrelColors.textWhite
                                      .withValues(alpha: 0.06),
                                ),
                              ),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: _searchResults.length,
                                itemBuilder: (context, index) {
                                  final user = _searchResults[index];
                                  return InkWell(
                                    onTap: () {
                                      setState(() {
                                        _selectedUser = user;
                                        _searchController.clear();
                                        _searchResults = [];
                                        _hasSearched = false;
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(8),
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 8),
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 16,
                                            backgroundColor: KinrelColors
                                                .orange
                                                .withValues(alpha: 0.2),
                                            backgroundImage: user
                                                        .avatarUrl !=
                                                    null
                                                ? NetworkImage(
                                                    user.avatarUrl!)
                                                : null,
                                            child: user.avatarUrl == null
                                                ? Text(
                                                    user.name.isNotEmpty
                                                        ? user.name[0]
                                                            .toUpperCase()
                                                        : '?',
                                                    style: TextStyle(
                                                        color: KinrelColors
                                                            .orange,
                                                        fontSize: 14),
                                                  )
                                                : null,
                                          ),
                                          SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment
                                                      .start,
                                              children: [
                                                Text(
                                                  user.name,
                                                  style: TextStyle(
                                                    color: KinrelColors
                                                        .textWhite,
                                                    fontSize: 13,
                                                    fontWeight:
                                                        FontWeight.w600,
                                                  ),
                                                ),
                                                if (user.username !=
                                                    null)
                                                  Text(
                                                    '@${user.username}',
                                                    style: TextStyle(
                                                      color: KinrelColors
                                                          .textDim,
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          SizedBox(height: 12),
                        ],

                        // ── Send Invite button ──────────────────────────
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: (_isSendingDirect ||
                                    _selectedUser == null)
                                ? null
                                : _sendDirectInvite,
                            icon: _isSendingDirect
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Icon(Icons.send, size: 16),
                            label: Text(_isSendingDirect
                                ? 'Sending...'
                                : 'Send Invite'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: KinrelColors.orange,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 24),

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
