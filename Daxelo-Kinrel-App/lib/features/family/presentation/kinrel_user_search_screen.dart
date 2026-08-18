// lib/features/family/presentation/kinrel_user_search_screen.dart
//
// DAXELO KINREL — Find on Kinrel Search Screen
//
// Lets the user search ALL Kinrel users (not just their own family
// members) via the `fn_search_kinrel_users` Supabase RPC. When the
// user taps a result, the selected [KinrelUser] is passed back via
// [onUserSelected] and the AddPersonSheet opens at Step 2 (Relationship).
//
// Used by the "Find on Kinrel" option in the Add Member flow.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/family/family_provider.dart' show familyLinkedUserIdsProvider;
import '../../../data/repositories/search_repository.dart';
import 'add_member_source.dart';
import 'package:go_router/go_router.dart';

/// A full-screen search screen that queries ALL Kinrel users.
///
/// [onUserSelected] is called when the user taps a search result.
/// The screen pops itself before calling the callback.
class KinrelUserSearchScreen extends ConsumerStatefulWidget {
  const KinrelUserSearchScreen({
    super.key,
    required this.familyId,
    required this.onUserSelected,
  });

  final String familyId;
  final void Function(KinrelUser user) onUserSelected;

  @override
  ConsumerState<KinrelUserSearchScreen> createState() =>
      _KinrelUserSearchScreenState();
}

class _KinrelUserSearchScreenState
    extends ConsumerState<KinrelUserSearchScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  List<KinrelUser> _results = [];
  bool _isLoading = false;
  bool _hasSearched = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _performSearch(_searchController.text);
    });
  }

  Future<void> _performSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _results = [];
        _hasSearched = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _hasSearched = true;
    });

    try {
      final repo = ref.read(searchRepositoryProvider);
      final results = await repo.searchKinrelUsers(trimmed, limit: 30);
      if (mounted) {
        setState(() {
          _results = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search failed: $e')),
        );
      }
    }
  }

  void _selectUser(KinrelUser user) {
    Navigator.of(context).pop();
    widget.onUserSelected(user);
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
          onPressed: () { if (context.canPop()) { context.pop(); } else { context.go('/home'); } },
        ),
        title: Text(
          'Find on Kinrel',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textWhite,
          ),
        ),
      ),
      body: Column(
        children: [
          // Search bar
          _buildSearchBar(),

          // Results
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.all(KinrelSpacing.base),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.xl),
        border: Border.all(color: KinrelColors.darkElevated),
      ),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onSubmitted: (value) => _performSearch(value),
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 16,
          color: KinrelColors.textWhite,
        ),
        decoration: InputDecoration(
          hintText: 'Search by name or @username',
          hintStyle: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 15,
            color: KinrelColors.textDim,
          ),
          prefixIcon: const Icon(Icons.search,
              color: KinrelColors.orange, size: 22),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear,
                      color: KinrelColors.textDim, size: 20),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _results = [];
                      _hasSearched = false;
                    });
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: KinrelColors.orange),
      );
    }

    if (!_hasSearched) {
      return _buildEmptyState(
        icon: Icons.search,
        title: 'Search for Kinrel users',
        subtitle: 'Find people by name or @username to add to your family',
      );
    }

    if (_results.isEmpty) {
      return _buildEmptyState(
        icon: Icons.person_search,
        title: 'No users found',
        subtitle: 'Try a different name or username',
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.base, vertical: KinrelSpacing.sm),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final user = _results[index];
        // v5.42: Check if this user is already a family member.
        // If so, render the card with an "Already Added" badge and
        // disable the tap action.
        final existingIds =
            ref.watch(familyLinkedUserIdsProvider(widget.familyId));
        final isAlreadyAdded = existingIds.contains(user.id);
        return _KinrelUserCard(
          user: user,
          isAlreadyAdded: isAlreadyAdded,
          onTap: isAlreadyAdded ? null : () => _selectUser(user),
        );
      },
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KinrelSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KinrelColors.orange.withValues(alpha: 0.12),
              ),
              child: Icon(icon, color: KinrelColors.orange, size: 32),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: KinrelColors.textDim,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// _KinrelUserCard — search result card
// ═══════════════════════════════════════════════════════════════════════

class _KinrelUserCard extends StatelessWidget {
  const _KinrelUserCard({
    required this.user,
    required this.onTap,
    this.isAlreadyAdded = false,
  });

  final KinrelUser user;
  final VoidCallback? onTap;
  final bool isAlreadyAdded;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isAlreadyAdded
            ? KinrelColors.darkCard.withValues(alpha: 0.5)
            : KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(
          color: isAlreadyAdded
              ? KinrelColors.textDim.withValues(alpha: 0.2)
              : KinrelColors.darkElevated,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Avatar
                _buildAvatar(),

                const SizedBox(width: 14),

                // Name + subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name
                      Text(
                        user.name,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: KinrelColors.textWhite,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      // Username + KIN ID
                      Row(
                        children: [
                          if (user.username != null &&
                              user.username!.isNotEmpty)
                            Flexible(
                              child: Text(
                                '@${user.username}',
                                style: TextStyle(
                                  fontFamily: KinrelTypography.monoFont,
                                  fontSize: 13,
                                  color: KinrelColors.orange,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          if (user.username != null &&
                              user.username!.isNotEmpty)
                            const SizedBox(width: 8),
                          Text(
                            user.displayId,
                            style: TextStyle(
                              fontFamily: KinrelTypography.monoFont,
                              fontSize: 12,
                              color: KinrelColors.textDim,
                            ),
                          ),
                        ],
                      ),
                      if (user.bio != null && user.bio!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          user.bio!,
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 12,
                            color: KinrelColors.textDim,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Add button or "Already Added" badge
                if (isAlreadyAdded)
                  // v5.42: Disabled state for existing family members.
                  // The user cannot accidentally re-add them.
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: KinrelColors.textDim.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(KinrelRadius.md),
                      border: Border.all(
                        color: KinrelColors.textDim.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle,
                          size: 14,
                          color: KinrelColors.textDim,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Already Added',
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: KinrelColors.textDim,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: KinrelColors.orange,
                      borderRadius: BorderRadius.circular(KinrelRadius.md),
                    ),
                    child: Text(
                      'Add',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    final hasPhoto = user.avatarUrl != null && user.avatarUrl!.isNotEmpty;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: KinrelColors.orange.withValues(alpha: 0.12),
      ),
      child: hasPhoto
          ? ClipOval(
              child: Image.network(
                user.avatarUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildInitials(),
              ),
            )
          : _buildInitials(),
    );
  }

  Widget _buildInitials() {
    return Center(
      child: Text(
        user.initials,
        style: TextStyle(
          fontFamily: KinrelTypography.displayFont,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: KinrelColors.orange,
        ),
      ),
    );
  }
}
