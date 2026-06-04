// lib/features/profile/presentation/relations_screen.dart
//
// DAXELO KINREL — Relations Screen
//
// Shows all relationships this user has created across
// families. Displays Person A → relationship type → Person B
// with the associated family name. Uses placeholder data
// until a dedicated API endpoint is available.

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

/// A single relationship entry.
class _RelationshipEntry {
  const _RelationshipEntry({
    required this.personA,
    required this.relationshipType,
    required this.personB,
    required this.familyName,
    required this.familyId,
  });

  final String personA;
  final String relationshipType;
  final String personB;
  final String familyName;
  final String familyId;
}

class RelationsScreen extends ConsumerStatefulWidget {
  const RelationsScreen({super.key});

  @override
  ConsumerState<RelationsScreen> createState() => _RelationsScreenState();
}

class _RelationsScreenState extends ConsumerState<RelationsScreen> {
  List<_RelationshipEntry> _relationships = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRelationships();
  }

  Future<void> _loadRelationships() async {
    // Load families to generate relationship placeholder data
    await ref.read(profileProvider.notifier).loadFamilies();
    await ref.read(profileProvider.notifier).loadStats();

    if (!mounted) return;

    final families = ref.read(profileProvider).families;

    // Build placeholder relationships from family data
    // In production, this would come from a dedicated API endpoint
    final List<_RelationshipEntry> relationships = [];

    for (final family in families) {
      // Generate placeholder relationship entries for each family
      final count = family.memberCount > 1 ? family.memberCount - 1 : 3;
      for (int i = 0; i < count; i++) {
        final personA =
            _placeholderNames[(family.name.hashCode + i * 2) %
                _placeholderNames.length];
        final personB =
            _placeholderNames[(family.name.hashCode + i * 2 + 1) %
                _placeholderNames.length];
        final relType =
            _relationshipTypes[(family.name.hashCode + i) %
                _relationshipTypes.length];

        relationships.add(
          _RelationshipEntry(
            personA: personA,
            relationshipType: relType,
            personB: personB,
            familyName: family.name,
            familyId: family.id,
          ),
        );
      }
    }

    // If no families, add demo data
    if (families.isEmpty) {
      relationships.addAll(const [
        _RelationshipEntry(
          personA: 'Rajesh Sharma',
          relationshipType: 'Father',
          personB: 'Vikram Sharma',
          familyName: 'Sharma Family',
          familyId: 'demo1',
        ),
        _RelationshipEntry(
          personA: 'Priya Sharma',
          relationshipType: 'Mother',
          personB: 'Ananya Sharma',
          familyName: 'Sharma Family',
          familyId: 'demo1',
        ),
        _RelationshipEntry(
          personA: 'Vikram Sharma',
          relationshipType: 'Brother',
          personB: 'Arjun Sharma',
          familyName: 'Sharma Family',
          familyId: 'demo1',
        ),
        _RelationshipEntry(
          personA: 'Meera Patel',
          relationshipType: 'Sister',
          personB: 'Rohan Patel',
          familyName: 'Patel Family',
          familyId: 'demo2',
        ),
        _RelationshipEntry(
          personA: 'Karan Patel',
          relationshipType: 'Uncle',
          personB: 'Rohan Patel',
          familyName: 'Patel Family',
          familyId: 'demo2',
        ),
      ]);
    }

    setState(() {
      _relationships = relationships;
      _isLoading = false;
    });
  }

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

  static const _relationshipTypes = [
    'Father',
    'Mother',
    'Brother',
    'Sister',
    'Son',
    'Daughter',
    'Uncle',
    'Aunt',
    'Cousin',
    'Grandfather',
    'Grandmother',
    'Husband',
    'Wife',
  ];

  IconData _relationshipIcon(String type) {
    switch (type.toLowerCase()) {
      case 'father':
      case 'grandfather':
        return Icons.male;
      case 'mother':
      case 'grandmother':
        return Icons.female;
      case 'brother':
      case 'son':
        return Icons.boy;
      case 'sister':
      case 'daughter':
        return Icons.girl;
      case 'husband':
      case 'wife':
        return Icons.favorite;
      case 'uncle':
      case 'aunt':
        return Icons.family_restroom;
      case 'cousin':
        return Icons.people;
      default:
        return Icons.link;
    }
  }

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
          'Relationships',
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
          : _relationships.isEmpty
          ? _buildEmptyState()
          : _buildRelationshipList(stats),
    );
  }

  // ── Relationship List ────────────────────────────────────────────

  Widget _buildRelationshipList(UserStatsModel? stats) {
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
                    Icons.share_outlined,
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
                        'Total Relationships',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 12,
                          color: _textDim,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${stats.relations}',
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

        // ── Relationship Cards List ────────────────────────────────
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            itemCount: _relationships.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final rel = _relationships[index];
              return _RelationshipCard(
                entry: rel,
                icon: _relationshipIcon(rel.relationshipType),
              );
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
            child: const Icon(Icons.share_outlined, color: _orange, size: 36),
          ),
          const SizedBox(height: 16),
          const Text(
            "You haven't created any relationships yet",
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
            'Start connecting family members to build your tree',
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
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 160,
                      height: 14,
                      decoration: BoxDecoration(
                        color: _bg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 90,
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
// Relationship Card
// ═══════════════════════════════════════════════════════════════════════

class _RelationshipCard extends StatelessWidget {
  const _RelationshipCard({required this.entry, required this.icon});

  final _RelationshipEntry entry;
  final IconData icon;

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
          // Relationship type icon
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: _orange, size: 18),
          ),
          const SizedBox(width: 12),

          // Relationship chain
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Person A → relationship → Person B
                RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _textPrimary,
                      height: 1.4,
                    ),
                    children: [
                      TextSpan(
                        text: entry.personA,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _textPrimary,
                        ),
                      ),
                      TextSpan(
                        text: '  →  ',
                        style: TextStyle(
                          fontFamily: KinrelTypography.monoFont,
                          fontSize: 11,
                          color: _textDim,
                        ),
                      ),
                      TextSpan(
                        text: entry.relationshipType,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _orange,
                        ),
                      ),
                      TextSpan(
                        text: '  →  ',
                        style: TextStyle(
                          fontFamily: KinrelTypography.monoFont,
                          fontSize: 11,
                          color: _textDim,
                        ),
                      ),
                      TextSpan(
                        text: entry.personB,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _textPrimary,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),

                // Family name
                Row(
                  children: [
                    Icon(Icons.park_outlined, color: _textDim, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      entry.familyName,
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
