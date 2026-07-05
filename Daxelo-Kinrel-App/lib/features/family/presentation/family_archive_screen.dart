// lib/features/family/presentation/family_archive_screen.dart
//
// DAXELO KINREL — Family Archive Screen (Phase 3, KIN-06)
//
// Unifies three related-but-distinct providers under one navigational
// roof per the Definitive Audit's recommendation:
//   • Photos tab  → Memory Vault (photo storage & sync, 551-line provider)
//   • Timeline tab → Memories (family events & "On This Day", 948-line provider)
//   • Audio tab   → Oral History / Family Stories (audio recording + AI transcription)
//
// IMPORTANT: This is a PRESENTATION-LAYER unification only. The audit
// explicitly states (Section 5, KIN-24): "Do not merge the code —
// Memories and Memory Vault are architecturally distinct systems."
// This screen provides one entry point with clearly labelled tabs;
// each tab navigates to its own fully-functional screen.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../shared/widgets/dk_components.dart';

class FamilyArchiveScreen extends StatefulWidget {
  const FamilyArchiveScreen({super.key, this.familyId});

  final String? familyId;

  @override
  State<FamilyArchiveScreen> createState() => _FamilyArchiveScreenState();
}

class _FamilyArchiveScreenState extends State<FamilyArchiveScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const _tabs = [
    _ArchiveTab(
      label: 'Photos',
      subtitle: 'Family photo vault',
      icon: Icons.photo_library_outlined,
      color: Color(0xFFD4AF37), // gold
      route: '/memory-vault',
    ),
    _ArchiveTab(
      label: 'Timeline',
      subtitle: 'Events & family history',
      icon: Icons.timeline_outlined,
      color: Color(0xFF06B6D4), // cyan
      route: '/memories',
    ),
    _ArchiveTab(
      label: 'Audio',
      subtitle: 'Family stories & recordings',
      icon: Icons.mic_none_outlined,
      color: Color(0xFF8B5CF6), // purple
      route: '/oral-history',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Family Archive',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: KinrelColors.orange,
          labelColor: KinrelColors.orange,
          unselectedLabelColor: KinrelColors.textDim,
          labelStyle: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          tabs: _tabs.map((t) => Tab(text: t.label)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _tabs.map((tab) => _buildTabContent(tab)).toList(),
      ),
    );
  }

  Widget _buildTabContent(_ArchiveTab tab) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(KinrelSpacing.base),
      child: Column(
        children: [
          const SizedBox(height: 24),
          // Icon
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tab.color.withValues(alpha: 0.15),
            ),
            child: Icon(tab.icon, color: tab.color, size: 32),
          ),
          const SizedBox(height: 16),
          Text(
            tab.label,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tab.subtitle,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              color: KinrelColors.textDim,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          // Open button
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => context.push(tab.route),
              icon: Icon(tab.icon, size: 18),
              label: Text('Open ${tab.label}'),
              style: FilledButton.styleFrom(
                backgroundColor: tab.color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
                ),
              ),
            ),
          ),
          const SizedBox(height: 40),
          // Info card
          DKCard(
            backgroundColor: KinrelColors.darkCard,
            padding: KinrelSpacing.md,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: tab.color),
                    const SizedBox(width: 8),
                    Text(
                      'About ${tab.label}',
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _getAboutText(tab.label),
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    color: KinrelColors.textDim,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getAboutText(String label) {
    switch (label) {
      case 'Photos':
        return 'Store and share family photos. Photos are synced across all family members and available offline.';
      case 'Timeline':
        return 'View family events like births, marriages, and milestones. See what happened "On This Day" in your family history.';
      case 'Audio':
        return 'Record audio family stories with AI-powered transcription in multiple Indian languages. Preserve your elders\' voices for future generations.';
      default:
        return '';
    }
  }
}

class _ArchiveTab {
  const _ArchiveTab({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.route,
  });
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String route;
}
