// lib/features/family_map/widgets/map_legend_widget.dart
//
// DAXELO KINREL — Map Legend Widget (P13 upgrade).
//
// Premium collapsible bottom panel that floats above the map's bottom
// edge. Replaces the original compact legend chip with a richer panel
// that shows:
//
//   • Quick stats row (located count + cities count)
//   • Pinned / unpinned counts (original behavior preserved)
//   • Expand/collapse toggle (chevron button)
//   • When expanded:
//       - Category legend (color swatch + icon + label) for each
//         family-place type the family has
//       - Status tier legend (LIVE / RECENT / STALE / CITY-FALLBACK)
//       - Unpinned members list (tap-to-open sheet — preserved from
//         the original widget)
//
// Design language:
//   • Glass card on dark navy with a soft border, matching
//     MapControlStack + MapSearchBar.
//   • Same KinrelColors tokens as the rest of the app — no magic colors.
//   • Responsive: phone = 2 columns of categories; tablet/desktop = 4.
//
// Localization: all labels use S.of(context) with English fallbacks.
//
// Backward compat: the [MapLegendWidget] class still has the same
// constructor signature so the existing [FamilyMapScreen] integration
// keeps working. The new fields have safe defaults.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/widgets/cached_avatar.dart';
import '../../../l10n/app_localizations.dart';
import '../config/map_visual_constants.dart';
import '../data/place_models.dart';
import '../providers/family_map_provider.dart';
import 'map_initials.dart';

/// Premium collapsible bottom legend panel for the family map.
class MapLegendWidget extends StatefulWidget {
  const MapLegendWidget({
    super.key,
    required this.result,
    this.reducedMotion = false,
  });

  /// The current family map result — pins, places, unpinned members.
  final FamilyMapResult result;

  /// True when the user has enabled reduced motion.
  final bool reducedMotion;

  @override
  State<MapLegendWidget> createState() => _MapLegendWidgetState();
}

class _MapLegendWidgetState extends State<MapLegendWidget> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    final result = widget.result;
    final isWide = MediaQuery.of(context).size.width >= 720;
    final categoryCols = isWide
        ? MapVisualConstants.legendCategoryColumnsWide
        : MapVisualConstants.legendCategoryColumnsNarrow;

    // Distinct place types present in the family's places list (sorted
    // by their PlaceType.values index for a stable display order).
    final placeTypes = <PlaceType>{};
    for (final p in result.places) {
      placeTypes.add(p.placeType);
    }
    final types = placeTypes.toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    return Positioned(
      left: MapVisualConstants.legendPanelHorizontalMargin,
      right: MapVisualConstants.legendPanelHorizontalMargin,
      bottom: MapVisualConstants.legendPanelBottomInset,
      child: AnimatedContainer(
        duration: MapVisualConstants.legendExpandDuration,
        curve: Curves.easeOutCubic,
        constraints: BoxConstraints(
          maxHeight: _expanded
              ? MediaQuery.of(context).size.height *
                  MapVisualConstants.legendExpandedMaxFraction
              : MapVisualConstants.legendCollapsedHeight,
        ),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(
            MapVisualConstants.legendPanelRadius,
          ),
          border: Border.all(color: KinrelColors.darkElevated, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: KinrelColors.orangeGlowSubtle,
              blurRadius: 14,
              spreadRadius: 0,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(
            MapVisualConstants.legendPanelRadius,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header row (always visible) ─────────────────────────
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(
                      MapVisualConstants.legendPanelRadius,
                    ),
                    topRight: Radius.circular(
                      MapVisualConstants.legendPanelRadius,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: KinrelSpacing.md,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        // Quick stat: located count with a warm pulse dot.
                        _QuickStat(
                          icon: Icons.people_alt_rounded,
                          iconColor: KinrelColors.orange,
                          count: result.pins.length,
                          label: l10n?.familyMapLegendPinned ??
                              'located',
                        ),
                        const SizedBox(width: 12),
                        _QuickStat(
                          icon: Icons.location_city_rounded,
                          iconColor: const Color(0xFF4ED9C7),
                          count: result.distinctCityCount,
                          label: l10n?.familyMapLegendCities ??
                              'cities',
                        ),
                        const Spacer(),
                        // Expand / collapse chevron.
                        AnimatedRotation(
                          duration: MapVisualConstants.legendExpandDuration,
                          turns: _expanded ? 0.5 : 0.0,
                          child: Icon(
                            Icons.keyboard_arrow_up_rounded,
                            color: KinrelColors.textSilver,
                            size: 22,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Expanded content ────────────────────────────────────
              if (_expanded)
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      KinrelSpacing.md,
                      0,
                      KinrelSpacing.md,
                      KinrelSpacing.md,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Status tier legend.
                        _SectionTitle(
                          title: l10n?.familyMapLegendStatusTitle ??
                              'Status tiers',
                        ),
                        const SizedBox(height: 6),
                        _StatusTierLegend(),
                        const SizedBox(height: 14),

                        // Category legend.
                        if (types.isNotEmpty) ...[
                          _SectionTitle(
                            title: l10n?.familyMapLegendCategoriesTitle ??
                                'Place categories',
                          ),
                          const SizedBox(height: 6),
                          GridView.count(
                            crossAxisCount: categoryCols,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            childAspectRatio: 3.0,
                            crossAxisSpacing: 6,
                            mainAxisSpacing: 6,
                            children: [
                              for (final t in types)
                                _CategorySwatch(placeType: t),
                            ],
                          ),
                          const SizedBox(height: 14),
                        ],

                        // Unpinned members section (only if there are any).
                        if (result.unpinnedCount > 0) ...[
                          _SectionTitle(
                            title: l10n?.familyMapLegendUnpinnedTitle ??
                                'Not on map',
                          ),
                          const SizedBox(height: 6),
                          _UnpinnedRow(
                            count: result.unpinnedCount,
                            onTap: () =>
                                _showUnpinnedSheetFromLegend(context),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      )
          .animate(onPlay: (c) => c.forward())
          .fadeIn(
            duration: widget.reducedMotion ? 1.ms : 500.ms,
            delay: widget.reducedMotion ? 0.ms : 280.ms,
          )
          .slideY(
            begin: 0.2,
            end: 0,
            duration: widget.reducedMotion ? 1.ms : 380.ms,
          ),
    );
  }

  void _showUnpinnedSheetFromLegend(BuildContext context) {
    final result = widget.result;
    if (result.unpinnedCount == 0) return;
    final l10n = S.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.all(KinrelSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: EdgeInsets.only(bottom: KinrelSpacing.lg),
                    decoration: BoxDecoration(
                      color: KinrelColors.darkElevated,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Row(
                    children: [
                      Icon(
                        Icons.location_off_rounded,
                        size: 20,
                        color: KinrelColors.textDim,
                      ),
                      SizedBox(width: KinrelSpacing.sm),
                      Expanded(
                        child: Text(
                          l10n?.familyMapUnpinnedCount(result.unpinnedCount) ??
                              '${result.unpinnedCount} member${result.unpinnedCount == 1 ? '' : 's'} without map pin',
                          style: TextStyle(
                            fontFamily: KinrelTypography.displayFont,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: KinrelColors.textWhite,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: KinrelSpacing.sm),
                  Text(
                    l10n?.familyMapAddCityPrompt ??
                        'Add a city to these members to see them on the map.',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      color: KinrelColors.textSilver,
                    ),
                  ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.4,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.symmetric(horizontal: KinrelSpacing.xl),
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: result.unpinnedMembers.length,
                separatorBuilder: (_, __) =>
                    Divider(color: KinrelColors.darkElevated, height: 1),
                itemBuilder: (context, index) {
                  final member = result.unpinnedMembers[index];
                  return ListTile(
                    contentPadding: EdgeInsets.symmetric(
                      vertical: KinrelSpacing.xs,
                    ),
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: KinrelColors.darkElevated,
                      ),
                      child: member.photoUrl != null &&
                              member.photoUrl!.isNotEmpty
                          ? ClipOval(
                              child: CachedAvatar(
                                imageUrl: member.photoUrl,
                                radius: 17,
                              ),
                            )
                          : Center(
                              child: Text(
                                initials(member.name),
                                style: TextStyle(
                                  fontFamily: KinrelTypography.displayFont,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: KinrelColors.textSilver,
                                  height: 1,
                                ),
                              ),
                            ),
                    ),
                    title: Text(
                      member.name,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    subtitle: Text(
                      member.city.isEmpty
                          ? (l10n?.familyMapNoCitySet ?? 'No city set')
                          : (l10n?.familyMapCityNotFound(member.city) ??
                              '${member.city} (not found)'),
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        color: KinrelColors.textDim,
                      ),
                    ),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: KinrelColors.textDim,
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push('/member/${member.personId}');
                    },
                  );
                },
              ),
            ),
            SizedBox(height: KinrelSpacing.xl),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────

class _QuickStat extends StatelessWidget {
  const _QuickStat({
    required this.icon,
    required this.iconColor,
    required this.count,
    required this.label,
  });

  final IconData icon;
  final Color iconColor;
  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: iconColor.withValues(alpha: 0.18),
            border: Border.all(color: iconColor.withValues(alpha: 0.55), width: 1),
          ),
          child: Icon(icon, size: 14, color: iconColor),
        ),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
                height: 1.0,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 10,
                color: KinrelColors.textDim,
                height: 1.0,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        fontFamily: KinrelTypography.bodyFont,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: KinrelColors.textDim,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _StatusTierLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    final tiers = <_TierMeta>[
      _TierMeta(
        color: MapVisualConstants.tierLiveColor,
        label: l10n?.familyMapLegendTierLive ?? 'Live',
        description: l10n?.familyMapLegendTierLiveDesc ?? '< 2 min ago',
      ),
      _TierMeta(
        color: MapVisualConstants.tierRecentColor,
        label: l10n?.familyMapLegendTierRecent ?? 'Recent',
        description: l10n?.familyMapLegendTierRecentDesc ?? '< 15 min ago',
      ),
      _TierMeta(
        color: MapVisualConstants.tierStaleColor,
        label: l10n?.familyMapLegendTierStale ?? 'Stale',
        description: l10n?.familyMapLegendTierStaleDesc ?? '< 1 hour ago',
      ),
      _TierMeta(
        color: MapVisualConstants.tierCityFallbackColor,
        label: l10n?.familyMapLegendTierCity ?? 'City',
        description: l10n?.familyMapLegendTierCityDesc ?? 'city centroid',
      ),
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      children: [
        for (final t in tiers)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: t.color,
                  boxShadow: [
                    BoxShadow(
                      color: t.color.withValues(alpha: 0.55),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              Text(
                t.label,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textWhite,
                ),
              ),
              const SizedBox(width: 3),
              Text(
                '· ${t.description}',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 10,
                  color: KinrelColors.textDim,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _TierMeta {
  const _TierMeta({
    required this.color,
    required this.label,
    required this.description,
  });
  final Color color;
  final String label;
  final String description;
}

class _CategorySwatch extends StatelessWidget {
  const _CategorySwatch({required this.placeType});
  final PlaceType placeType;

  @override
  Widget build(BuildContext context) {
    final meta = _categoryMeta(placeType);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: meta.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: meta.color.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(meta.icon, size: 12, color: meta.color),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              placeType.semanticLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                color: KinrelColors.textSilver,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryMeta {
  const _CategoryMeta({required this.icon, required this.color});
  final IconData icon;
  final Color color;
}

_CategoryMeta _categoryMeta(PlaceType t) {
  switch (t) {
    case PlaceType.currentHome:
      return const _CategoryMeta(
        icon: Icons.home_rounded,
        color: Color(0xFFE8612A),
      );
    case PlaceType.childhoodHome:
      return const _CategoryMeta(
        icon: Icons.bungalow_rounded,
        color: Color(0xFFF59240),
      );
    case PlaceType.ancestralHome:
      return const _CategoryMeta(
        icon: Icons.account_balance_rounded,
        color: Color(0xFFB8901F),
      );
    case PlaceType.birthplace:
      return const _CategoryMeta(
        icon: Icons.child_care_rounded,
        color: Color(0xFFF5B841),
      );
    case PlaceType.wedding:
      return const _CategoryMeta(
        icon: Icons.favorite_rounded,
        color: Color(0xFFE8612A),
      );
    case PlaceType.memorial:
      return const _CategoryMeta(
        icon: Icons.local_florist_rounded,
        color: Color(0xFFF59240),
      );
    case PlaceType.familyBusiness:
      return const _CategoryMeta(
        icon: Icons.storefront_rounded,
        color: Color(0xFFD85720),
      );
    case PlaceType.school:
      return const _CategoryMeta(
        icon: Icons.school_rounded,
        color: Color(0xFF4E6984),
      );
    case PlaceType.vacationHome:
      return const _CategoryMeta(
        icon: Icons.beach_access_rounded,
        color: Color(0xFF4E6984),
      );
    case PlaceType.familyTemple:
      return const _CategoryMeta(
        icon: Icons.temple_buddhist_rounded,
        color: Color(0xFFE8612A),
      );
    case PlaceType.grandparentsHome:
      return const _CategoryMeta(
        icon: Icons.elderly_rounded,
        color: Color(0xFFF59240),
      );
    case PlaceType.importantPlace:
      return const _CategoryMeta(
        icon: Icons.star_rounded,
        color: Color(0xFFE8612A),
      );
  }
}

class _UnpinnedRow extends StatelessWidget {
  const _UnpinnedRow({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: KinrelColors.darkElevated.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: KinrelColors.darkElevated),
        ),
        child: Row(
          children: [
            Icon(
              Icons.location_off_rounded,
              size: 14,
              color: KinrelColors.textDim,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n?.familyMapNotPinned(count) ?? '$count not pinned',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  color: KinrelColors.textSilver,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: KinrelColors.textDim,
            ),
          ],
        ),
      ),
    );
  }
}
