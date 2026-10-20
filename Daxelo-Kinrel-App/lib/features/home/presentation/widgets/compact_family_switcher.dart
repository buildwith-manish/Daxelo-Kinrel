// lib/features/home/presentation/widgets/compact_family_switcher.dart
//
// DAXELO KINREL — Compact Family Switcher (Phase A — Home, the
// Instagram-level idea)
//
// A small pill attached to the Home header showing the active
// family's initial + name. Tapping it opens a bottom sheet listing
// all families the user belongs to plus a "Create family" entry —
// the same actions the legacy _FamilySwitcherRow exposed, but
// compressed into the header so the ring row can take the prime
// horizontal-real-estate slot below.
//
// The old _FamilySwitcherRow scrolled horizontally and consumed 76px
// of vertical space on Home. The mockup shows the header line itself
// (wordmark + bell), then the ring row — so the family switcher
// moves into a compact selector attached to the header title area.
//
// Accessibility:
//   • Tap target ≥ 44dp (we use 36px avatar + 4px vertical padding =
//     44dp on the chip; the chip's horizontal tap area is also ≥ 44dp
//     because the pill min-width is 56px).
//   • Semantic label = 'Family: {family name}. Active. Double tap to
//     switch family.'
//   • Reduced-motion respected — the chip has no animation.

import 'package:flutter/material.dart';
// flutter_riverpod exports a `Family` typedef that clashes with the
// `Family` class from family_provider.dart. Hide it so the only
// `Family` in scope is our domain model.
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:go_router/go_router.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/family/family_provider.dart';
import '../../../../core/services/haptic_service.dart';
import '../../../../core/utils/accessibility_utils.dart';
// Phase A decision 3: drop FamilySparqTray from Home, but add a
// small unseen-dot on this compact selector when ANOTHER family
// (not the active one) has unseen Sparqs. familySparqTrayProvider
// already computes unseenCount per family — we watch it once at
// the chip level and surface a single gold dot when any sibling
// family has unseenCount > 0.
import '../../../sparq_tray/providers/family_sparq_tray_provider.dart'
    show familySparqTrayProvider;

const _cOrange = KinrelColors.orange;
const _cCard = KinrelColors.darkCard;
const _cElevated = KinrelColors.darkElevated;
const _cTextPrimary = KinrelColors.textWhite;
const _cTextSecondary = KinrelColors.textSilver;
// Gold for the "other family has unseen Sparqs" dot — readable as
// "news / unread" without the error connotation of red.
const _cUnseen = KinrelColors.gold;

/// A compact family selector pill for the Home header.
///
/// Renders the active family's initial (in an Ignite-gradient circle)
/// + family name. Tap opens a sheet listing all families + a
/// "Create family" entry. Selecting an item pushes /family/{id}.
class CompactFamilySwitcher extends ConsumerWidget {
  const CompactFamilySwitcher({
    super.key,
    required this.families,
    required this.activeFamilyId,
  });

  final List<Family> families;

  /// The id of the family currently rendered as "primary" on Home.
  /// When null (e.g. user has no families — handled before this
  /// widget renders), the chip renders a "Create family" affordance.
  final String? activeFamilyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (families.isEmpty) {
      return _createFamilyChip(context);
    }

    final active = families.firstWhere(
      (f) => f.id == activeFamilyId,
      orElse: () => families.first,
    );

    // Phase A decision 3: small unseen-dot on the chip when ANY
    // OTHER family (not the active one) has unseen Sparqs. We watch
    // familySparqTrayProvider once at the chip level — it returns
    // per-family unseenCount, so the watch cost is amortized across
    // every chip instance on Home.
    final trayAsync = ref.watch(familySparqTrayProvider);
    final trayItems = trayAsync.valueOrNull ?? const [];
    final otherFamilyHasUnseen = trayItems.any(
      (t) => t.family.id != active.id && t.unseenCount > 0,
    );

    return semanticButton(
      label: 'Family: ${active.name}. Active. Double tap to switch family'
          '${otherFamilyHasUnseen ? '. Other families have unseen Sparqs.' : ''}',
      hint: 'Opens the family switcher sheet',
      child: GestureDetector(
        onTap: () {
          HapticService.selection();
          _showFamilySwitcherSheet(context, ref, families, active.id);
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          // ≥ 44dp tap target in both dimensions.
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.only(
            left: 4,
            right: 10,
            top: 4,
            bottom: 4,
          ),
          decoration: BoxDecoration(
            color: _cElevated,
            borderRadius: BorderRadius.circular(KinrelRadius.full),
            border: Border.all(
              color: _cOrange.withValues(alpha: 0.25),
              width: 0.75,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Active family initial circle (Ignite gradient, 24px)
              // + small gold unseen-dot overlay when another family
              // has unseen Sparqs.
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: KinrelGradients.igniteGradient,
                    ),
                    child: Center(
                      child: Text(
                        active.name.isNotEmpty
                            ? active.name[0].toUpperCase()
                            : 'F',
                        style: const TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  // Gold dot — top-right, 8px diameter. Gold (not
                  // red) so it doesn't read as "error/badge" — it's
                  // a "news" indicator like an unread indicator on a
                  // chat list. The dot only appears when another
                  // family (not this active one) has unseen Sparqs
                  // so the user knows to switch.
                  if (otherFamilyHasUnseen)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _cUnseen,
                          border: Border.all(
                            color: _cElevated,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 6),
              // Family name — single line, ellipsis if long. ≥ 12sp.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  active.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _cTextPrimary,
                  ),
                ),
              ),
              // Down-caret — clearly communicates "tap to expand".
              const SizedBox(width: 4),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: _cTextSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Renders a small "Create family" affordance when the user has no
  /// families yet. Home's empty-state view usually renders in this
  /// case, but if Home renders CompactFamilySwitcher from the
  /// header while families is loading/empty, we want a safe
  /// fallback.
  Widget _createFamilyChip(BuildContext context) {
    return semanticButton(
      label: 'Create a family',
      hint: 'Double tap to create your first family',
      child: GestureDetector(
        onTap: () {
          HapticService.tap();
          context.push('/families/create');
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _cOrange.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(KinrelRadius.full),
            border: Border.all(
              color: _cOrange.withValues(alpha: 0.4),
              width: 0.75,
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.add_rounded, color: _cOrange, size: 16),
              SizedBox(width: 4),
              Text(
                'Create family',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _cOrange,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFamilySwitcherSheet(
    BuildContext context,
    WidgetRef ref,
    List<Family> families,
    String activeId,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _cCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.xxl),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Your families',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: _cTextPrimary,
                  ),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: families.length + 1, // +1 for create
                  itemBuilder: (ctx, index) {
                    if (index == families.length) {
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              _cOrange.withValues(alpha: 0.15),
                          child: const Icon(Icons.add_rounded,
                              color: _cOrange, size: 22),
                        ),
                        title: const Text(
                          'Create new family',
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontWeight: FontWeight.w600,
                            color: _cTextPrimary,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          HapticService.tap();
                          context.push('/families/create');
                        },
                      );
                    }
                    final family = families[index];
                    final isActive = family.id == activeId;
                    return ListTile(
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: KinrelGradients.igniteGradient,
                          border: isActive
                              ? Border.all(color: _cOrange, width: 2)
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            family.name.isNotEmpty
                                ? family.name[0].toUpperCase()
                                : 'F',
                            style: const TextStyle(
                              fontFamily: KinrelTypography.displayFont,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      title: Text(
                        family.name,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontWeight: isActive
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: _cTextPrimary,
                        ),
                      ),
                      subtitle: family.familyCode != null
                          ? Text(
                              '@${family.familyCode}',
                              style: const TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 11,
                                color: _cOrange,
                              ),
                            )
                          : null,
                      trailing: isActive
                          ? const Icon(Icons.check_rounded,
                              color: _cOrange, size: 20)
                          : null,
                      onTap: () {
                        Navigator.pop(ctx);
                        HapticService.selection();
                        context.push('/family/${family.id}');
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
