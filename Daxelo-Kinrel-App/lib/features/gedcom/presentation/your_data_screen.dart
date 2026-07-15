// lib/features/gedcom/presentation/your_data_screen.dart
//
// P12.6 Batch 3 — "Your Family, Your Data" trust/privacy screen.
//
// Per kinrel_final_audited_prompt_v2.md §6.1:
//   - What's stored, where, one-tap export
//   - Shares the GEDCOM export pipeline from §5.1

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';

class YourDataScreen extends StatelessWidget {
  const YourDataScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KinrelColors.darkBackground,
      appBar: AppBar(
        backgroundColor: KinrelColors.darkCard,
        title: const Text('Your Family, Your Data'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Hero section
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  KinrelColors.orange.withValues(alpha: 0.15),
                  KinrelColors.darkCard,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.shield_outlined,
                  color: KinrelColors.orange,
                  size: 32,
                ),
                const SizedBox(height: 12),
                Text(
                  'Your data belongs to your family',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Kinrel stores your family tree, relationships, and memories '
                  'so your family can stay connected. You control what\'s shared '
                  'and can export everything at any time.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFFC9B4A8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // What's stored
          _SectionHeader(title: 'What we store'),
          const SizedBox(height: 8),
          _DataCard(
            icon: Icons.family_restroom,
            title: 'Family tree data',
            description:
                'Names, relationships, birth years, and family structure. '
                'Stored in Supabase with Row-Level Security — only your family members can see it.',
          ),
          const SizedBox(height: 8),
          _DataCard(
            icon: Icons.photo_library_outlined,
            title: 'Memories & photos',
            description:
                'Photos, stories, and voice notes you add. Stored in '
                'Supabase Storage with family-scoped access.',
          ),
          const SizedBox(height: 8),
          _DataCard(
            icon: Icons.location_on_outlined,
            title: 'Location (optional)',
            description:
                'Live location sharing is OFF by default. When you turn it on, '
                'it\'s only shared with family members you\'ve authorized, and expires after 24 hours.',
          ),
          const SizedBox(height: 24),

          // What we DON'T store
          _SectionHeader(title: 'What we don\'t store'),
          const SizedBox(height: 8),
          _DataCard(
            icon: Icons.block,
            title: 'No DNA or health data',
            description:
                'Kinrel does not collect, store, or process DNA or health data.',
            iconColor: Colors.green,
          ),
          const SizedBox(height: 8),
          _DataCard(
            icon: Icons.block,
            title: 'No third-party tracking',
            description:
                'No Facebook Pixel, no Google Analytics, no third-party ad tracking. '
                'Your family data stays in Kinrel.',
            iconColor: Colors.green,
          ),
          const SizedBox(height: 24),

          // Export section
          _SectionHeader(title: 'Export your data'),
          const SizedBox(height: 8),
          _DataCard(
            icon: Icons.download_outlined,
            title: 'GEDCOM export',
            description:
                'Export your family tree in GEDCOM 5.5.1 format — the universal '
                'standard for genealogy data. Only names, gender, birth year, and relationships '
                'are included. Private members are excluded.',
            onTap: () => context.push('/family//gedcom'),
          ),
          const SizedBox(height: 8),
          _DataCard(
            icon: Icons.delete_outline,
            title: 'Delete your account',
            description:
                'Permanently delete your account and all associated data. '
                'This cannot be undone. Family data added by others remains in the family tree.',
            onTap: () => context.push('/profile/delete-account'),
            iconColor: Colors.red,
          ),
          const SizedBox(height: 32),

          // Footer
          Center(
            child: Text(
              'Kinrel — A living Family Atlas\nYour family, your data, your control.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: const Color(0xFF8A8296)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: KinrelColors.orange,
      ),
    );
  }
}

class _DataCard extends StatelessWidget {
  const _DataCard({
    required this.icon,
    required this.title,
    required this.description,
    this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KinrelColors.darkCard,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: iconColor ?? KinrelColors.orange, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFC9B4A8),
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(
                  Icons.chevron_right,
                  color: const Color(0xFF8A8296),
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
