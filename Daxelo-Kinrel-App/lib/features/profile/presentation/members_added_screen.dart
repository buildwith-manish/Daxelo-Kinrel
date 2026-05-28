// lib/features/profile/presentation/members_added_screen.dart
//
// DAXELO KINREL — Members Added Screen
//
// Shows all members this user has added across all families.
// Loads families from profileProvider and displays member
// placeholder data from the API response.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_typography.dart';
import '../data/profile_provider.dart';

// ── Design Tokens ──────────────────────────────────────────────────
const Color _bg = Color(0xFF131416);
const Color _cardBg = Color(0xFF191B2C);
const Color _orange = Color(0xFFE8612A);
const Color _textPrimary = Color(0xFFF5F0EE);
const Color _textDim = Color(0xFF8A7A72);
const Color _borderSubtle = Color(0x0FFFFFFF);

/// Represents a member added by the current user.
class _AddedMember {
  const _AddedMember({
    required this.name,
    required this.familyName,
    required this.initials,
  });

  final String name;
  final String familyName;
  final String initials;
}

class MembersAddedScreen extends ConsumerStatefulWidget {
  const MembersAddedScreen({super.key});

  @override
  ConsumerState<MembersAddedScreen> createState() => _MembersAddedScreenState();
}

class _MembersAddedScreenState extends ConsumerState<MembersAddedScreen> {
  List<_AddedMember> _members = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    // Load profile stats and families
    await ref.read(profileProvider.notifier).loadStats();
    await ref.read(profileProvider.notifier).loadFamilies();

    if (!mounted) return;

    final families = ref.read(profileProvider).families;

    // Build members list from families data
    // For now, generate placeholder entries based on member counts
    final List<_AddedMember> members = [];

    for (final family in families) {
      // Create placeholder members for each family
      // In production, this would come from a dedicated API endpoint
      final memberCount = family.memberCount > 0 ? family.memberCount : 1;
      for (int i = 0; i < memberCount; i++) {
        final firstName =
            _placeholderNames[(family.name.hashCode + i) %
                _placeholderNames.length];
        final lastName = family.name.split(' ').first;
        members.add(
          _AddedMember(
            name: '$firstName $lastName',
            familyName: family.name,
            initials: '${firstName[0]}${lastName[0]}',
          ),
        );
      }
    }

    setState(() {
      _members = members;
      _isLoading = false;
    });
  }

  // Placeholder names for demo purposes
  static const _placeholderNames = [
    'Priya',
    'Rahul',
    'Ananya',
    'Vikram',
    'Meera',
    'Arjun',
    'Kavya',
    'Rohan',
    'Ishita',
    'Aditya',
    'Nisha',
    'Siddharth',
    'Pooja',
    'Amit',
    'Sneha',
    'Karan',
    'Divya',
    'Nikhil',
    'Swati',
    'Manish',
  ];

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(profileProvider).stats;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _textPrimary),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Members Added',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
      ),
      body: _isLoading
          ? _buildLoadingState()
          : _members.isEmpty
          ? _buildEmptyState()
          : _buildMemberList(stats),
    );
  }

  // ── Member List ──────────────────────────────────────────────────

  Widget _buildMemberList(UserStatsModel? stats) {
    return Column(
      children: [
        // ── Stats Header ───────────────────────────────────────────
        if (stats != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _borderSubtle),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.person_add_outlined,
                    color: _orange,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Total Members Added',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 12,
                          color: _textDim,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${stats.membersAdded}',
                        style: const TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: _textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${stats.familyTrees}',
                      style: const TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _orange,
                      ),
                    ),
                    const Text(
                      'families',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 11,
                        color: _textDim,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

        const SizedBox(height: 12),

        // ── Members List ───────────────────────────────────────────
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            itemCount: _members.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final member = _members[index];
              return _MemberCard(member: member);
            },
          ),
        ),
      ],
    );
  }

  // ── Empty State ──────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _orange.withValues(alpha: 0.12),
            ),
            child: const Icon(
              Icons.person_add_outlined,
              color: _orange,
              size: 36,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'You haven\'t added any members yet',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Start building your family tree by adding members',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              color: _textDim,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── Loading State ────────────────────────────────────────────────

  Widget _buildLoadingState() {
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: 5,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _borderSubtle),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: _bg, shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 120,
                      height: 14,
                      decoration: BoxDecoration(
                        color: _bg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 80,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _bg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Member Card
// ═══════════════════════════════════════════════════════════════════════

class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.member});

  final _AddedMember member;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _borderSubtle),
      ),
      child: Row(
        children: [
          // Avatar with initials
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _orange.withValues(alpha: 0.15),
              border: Border.all(
                color: _orange.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Center(
              child: Text(
                member.initials.toUpperCase(),
                style: const TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _orange,
                  height: 1,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Name and family
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.name,
                  style: const TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.park_outlined, color: _textDim, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      member.familyName,
                      style: const TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        color: _textDim,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Arrow
          Icon(Icons.chevron_right, color: _textDim, size: 18),
        ],
      ),
    );
  }
}
