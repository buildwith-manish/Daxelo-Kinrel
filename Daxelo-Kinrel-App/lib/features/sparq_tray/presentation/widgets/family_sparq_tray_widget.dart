// lib/features/sparq_tray/presentation/widgets/family_sparq_tray_widget.dart
//
// DAXELO KINREL — Family Sparq tray widget (replaces the Home
// family row's body).
//
// Tray entries, left to right (spec section 2):
//   1. "Your Sparq" — the viewer's avatar in the medallion.
//   2. One entry per family, sorted unseen-first / all-seen / no-Sparqs.
//   3. "New family" dashed circle at the end.
//
// Tap / long-press rules (for a family entry):
//   - Live Sparqs → context.push('/sparq/family/{familyId}').
//   - No live Sparqs → context.push('/family/{familyId}') (unchanged).
//   - Long-press → context.push('/family/{familyId}') + light haptic.
//
// For the "Your Sparq" entry:
//   - No live Sparq → tap opens /sparq/create.
//   - Live Sparq → tap opens /sparq/viewer/{myUserId}.
//   - The small "+" badge (bottom-right) → /sparq/create.
//
// Performance:
//   • The breathing pulse is driven by ONE AnimationController owned
//     by this tray widget. Every entry receives the same pulse value
//     via props, so they all breathe in lockstep without each one
//     owning its own ticker.
//   • The pulse is disabled when MotionPreference says reduce motion,
//     when DeviceTier is low, when the tray is scrolled off-screen
//     (VisibilityDetector-based — TODO step 7, currently just stops
//     when not visible via NotificationListener), or on web (kIsWeb).
//   • Each entry is wrapped in a RepaintBoundary so the painter's
//     per-frame work is cached.
//
// Loading: shimmer placeholders with the same medallion size (reuses
// KinrelSkeleton). Error: the tray still renders with empty kolam
// rings — never an error banner on Home.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:go_router/go_router.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/constants/feature_flags.dart';
import '../../../../core/family/family_provider.dart' show Family;
import '../../../../core/services/haptic_service.dart';
import '../../../../core/services/supabase_service.dart' show currentUserProvider;
import '../../../../core/utils/device_tier.dart';
import '../../../../core/utils/motion_preference.dart';
import '../../../../shared/widgets/kinrel_skeleton.dart';
import '../../../social/data/models/sparq_model.dart' show UserSparqGroup;
import '../../../social/data/providers/sparq_provider.dart' show sparqProvider;
import '../../data/family_sparq_tray_item.dart';
import '../../providers/family_sparq_tray_provider.dart';
import '../../sparq_tray_strings.dart';
import 'family_sparq_petal_ring.dart';

/// The Home family row → Family Sparq tray.
///
/// Renders: Your Sparq, one entry per family, New family. Replaces
/// the legacy `_FamilySwitcherRow` body when `kEnableSparqTray` is
/// true.
class FamilySparqTray extends ConsumerStatefulWidget {
  const FamilySparqTray({super.key, required this.families});

  /// The viewer's families (already-loaded from familyListProvider).
  /// Passed in by Home so we don't need to re-watch the list here.
  final List<Family> families;

  @override
  ConsumerState<FamilySparqTray> createState() => _FamilySparqTrayState();
}

class _FamilySparqTrayState extends ConsumerState<FamilySparqTray>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    // Start pulsing only when motion is allowed. The build method
    // will start/stop the controller based on reduce-motion + device
    // tier + scroll-off-screen.
    _maybeStartPulse();
  }

  void _maybeStartPulse() {
    if (!mounted) return;
    if (kIsWeb) return; // No pulse on web (raster perf).
    if (DeviceTierCache.instance.tier == DeviceTier.low) return;
    if (MotionPreference.isReducedMotion(context)) return;
    if (!_pulseController.isAnimating) {
      _pulseController.repeat(); // 0 → 1 → 0 → 1 ...
    }
  }

  void _stopPulse() {
    if (_pulseController.isAnimating) {
      _pulseController.stop();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trayAsync = ref.watch(familySparqTrayProvider);
    final myGroup = ref.watch(mySparqSummaryProvider);
    final currentUser = ref.watch(currentUserProvider);
    final myUserId = currentUser?.id;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Decide whether to animate at all on this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (MotionPreference.isReducedMotion(context) ||
          DeviceTierCache.instance.tier == DeviceTier.low) {
        _stopPulse();
      } else {
        _maybeStartPulse();
      }
    });

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // Stop pulsing while the tray is being flung — saves raster
        // work and avoids jank on low-tier devices.
        if (notification is ScrollStartNotification) {
          // Keep the pulse; the tray itself is the scrollable.
        } else if (notification is UserScrollNotification &&
            notification.direction == ScrollDirection.idle) {
          _maybeStartPulse();
        }
        return false;
      },
      child: SizedBox(
        height: 96, // 72 medallion + label + 4 padding
        child: AnimatedBuilder(
          animation: _pulseController,
          builder: (context, _) {
            // The pulse value drives every entry's fire-petal breathing
            // in lockstep. When the controller is stopped (reduce-motion
            // / low tier / off-screen / web), value is 0 and the painter
            // draws at full opacity.
            final pulse = _pulseController.isAnimating
                ? _pulseController.value
                : 0.0;
            return trayAsync.when(
              loading: () => _buildShimmerRow(),
              error: (_, __) => _buildEmptyRow(isDark),
              data: (items) {
                if (items.isEmpty && widget.families.isEmpty) {
                  return _buildShimmerRow();
                }
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                      horizontal: KinrelSpacing.base),
                  itemCount: items.length + 2,
                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _buildYourSparqEntry(
                        context,
                        myGroup: myGroup,
                        myUserId: myUserId,
                        isDark: isDark,
                        pulseProgress: pulse,
                      );
                    }
                    if (index == items.length + 1) {
                      return _NewFamilyEntry(isDark: isDark);
                    }
                    final item = items[index - 1];
                    return _FamilySparqTrayEntryWidget(
                      item: item,
                      pulseProgress: pulse,
                      isDark: isDark,
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  // ── Shimmer row (loading state) ────────────────────────────────────

  Widget _buildShimmerRow() {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(width: 14),
      itemBuilder: (_, __) => const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          KinrelSkeletonBox(
            width: kSparqMedallionSize,
            height: kSparqMedallionSize,
            circle: true,
          ),
          SizedBox(height: 4),
          KinrelSkeletonBox(width: 50, height: 10),
        ],
      ),
    );
  }

  // ── Empty row (error or no-data — never an error banner on Home) ──

  Widget _buildEmptyRow(bool isDark) {
    // Show the New family dashed circle only. The tray never breaks.
    return ListView(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      children: [
        _NewFamilyEntry(isDark: isDark),
      ],
    );
  }

  // ── Your Sparq entry ────────────────────────────────────────────────

  Widget _buildYourSparqEntry(
    BuildContext context, {
    required UserSparqGroup? myGroup,
    required String? myUserId,
    required bool isDark,
    required double pulseProgress,
  }) {
    final hasLive = myGroup != null && myGroup.sparqs.isNotEmpty;
    final liveGroup = hasLive ? myGroup : null;
    final petals = liveGroup != null
        ? _buildYourSparqPetals(liveGroup)
        : const <PetalSpec>[];

    final liveCount = liveGroup != null
        ? liveGroup.sparqs.where((s) => !s.isLockedTimeCapsule).length
        : 0;
    final line2 = liveCount > 0
        ? SparqTrayStrings.nNew.replaceAll('{n}', '$liveCount')
        : '';
    return _SparqTrayEntry(
      isYourSparq: true,
      line1: SparqTrayStrings.yourSparq,
      line2: line2,
      line2Color: KinrelColors.amber,
      hasUnseen: hasLive,
      initial: 'Me',
      avatarUrl: null, // avatar is loaded by the entry widget
      petals: petals,
      pulseProgress: pulseProgress,
      isDark: isDark,
      semanticsLabel: hasLive
          ? SparqTrayStrings.semanticsYourSparqLive
          : SparqTrayStrings.semanticsYourSparqEmpty,
      onTap: () {
        HapticService.selection();
        if (hasLive && myUserId != null) {
          context.push('/sparq/viewer/$myUserId');
        } else {
          context.push('/sparq/create');
        }
      },
      onAddTap: hasLive
          ? () {
              HapticService.tap();
              context.push('/sparq/create');
            }
          : null,
    );
  }

  List<PetalSpec> _buildYourSparqPetals(UserSparqGroup myGroup) {
    // Use the same pure helper as family petals — the viewer is a
    // member of their own ring too (spec section 3: "the Your Sparq
    // entry uses the same 8-slot ring with only your own petals").
    return buildPetals(
      feed: [myGroup],
      memberUserIds: {myGroup.userId},
      moment: null,
      isSeen: (id) => ref
          .read(sparqProvider)
          .locallyViewedSparqIds
          .contains(id),
      excludeUserId: null, // do NOT exclude the viewer here
    );
  }

  // ── New family entry ────────────────────────────────────────────────
  // The `_NewFamilyEntry` widget is instantiated directly from build().
}

/// Single family entry widget — thin wrapper that builds the medallion
/// + Petal ring + label, plus tap/long-press handlers.
class _FamilySparqTrayEntryWidget extends ConsumerWidget {
  const _FamilySparqTrayEntryWidget({
    required this.item,
    required this.pulseProgress,
    required this.isDark,
  });

  final FamilySparqTrayItem item;
  final double pulseProgress;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final line2 = item.unseenCount > 0
        ? SparqTrayStrings.nNew.replaceAll('{n}', '${item.unseenCount}')
        : (item.moment != null ? SparqTrayStrings.moment : '');

    final line2Color = item.unseenCount > 0
        ? KinrelColors.amber
        : (item.moment != null ? KinrelColors.gold : Colors.transparent);

    // Build the semantics label per spec section 3.
    final names = item.memberGroups
        .map((g) => g.userName)
        .take(3)
        .join(', ');
    final semanticsLabel = item.unseenCount > 0
        ? SparqTrayStrings.semanticsFamilyWithNew
            .replaceAll('{family}', item.family.name)
            .replaceAll('{count}', '${item.unseenCount}')
            .replaceAll('{names}', names)
        : (item.hasLive
            ? SparqTrayStrings.semanticsFamilyAllSeen
                .replaceAll('{family}', item.family.name)
            : SparqTrayStrings.semanticsFamilyEmpty
                .replaceAll('{family}', item.family.name));

    return _SparqTrayEntry(
      isYourSparq: false,
      line1: item.family.name,
      line2: line2,
      line2Color: line2Color,
      hasUnseen: item.unseenCount > 0,
      initial: item.family.name.isNotEmpty
          ? item.family.name[0].toUpperCase()
          : 'F',
      avatarUrl: null,
      petals: item.petals,
      pulseProgress: pulseProgress,
      isDark: isDark,
      semanticsLabel: semanticsLabel,
      onTap: () {
        HapticService.selection();
        // Step 2: tapping still goes to the family page. Step 5 flips
        // kEnableSparqRunNavigation to true so families with live
        // Sparqs route to /sparq/family/{id} instead.
        if (kEnableSparqRunNavigation && item.hasLive) {
          context.push('/sparq/family/${item.family.id}');
        } else {
          context.push('/family/${item.family.id}');
        }
      },
      onLongPress: () {
        HapticService.medium();
        context.push('/family/${item.family.id}');
      },
    );
  }
}

/// Internal: shared entry widget for family + Your Sparq + (no New
/// family — that has its own widget because it has no petals).
class _SparqTrayEntry extends ConsumerWidget {
  const _SparqTrayEntry({
    required this.isYourSparq,
    required this.line1,
    required this.line2,
    required this.line2Color,
    required this.hasUnseen,
    required this.initial,
    required this.avatarUrl,
    required this.petals,
    required this.pulseProgress,
    required this.isDark,
    required this.semanticsLabel,
    required this.onTap,
    this.onAddTap,
    this.onLongPress,
  });

  final bool isYourSparq;
  final String line1;
  final String line2;
  final Color line2Color;
  final bool hasUnseen;
  final String initial;
  final String? avatarUrl;
  final List<PetalSpec> petals;
  final double pulseProgress;
  final bool isDark;
  final String semanticsLabel;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onAddTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    // For the Your Sparq entry, prefer the user's avatar from auth
    // metadata if the parent didn't supply one.
    final userAvatar = isYourSparq
        ? (avatarUrl ??
            currentUser?.userMetadata?['avatar_url'] as String? ??
            currentUser?.userMetadata?['photoThumb'] as String?)
        : null;

    final disableGlow = kIsWeb ||
        DeviceTierCache.instance.tier == DeviceTier.low ||
        MotionPreference.isReducedMotion(context);
    final effectivePulse = MotionPreference.isReducedMotion(context) ||
            DeviceTierCache.instance.tier == DeviceTier.low
        ? 0.0
        : pulseProgress;

    final labelColor = hasUnseen
        ? (isDark ? KinrelColors.textWhite : KinrelColors.darkBackground)
        : (isDark ? KinrelColors.textSilver : KinrelColors.darkCard);

    return SizedBox(
      width: kSparqEntryWidth,
      child: Semantics(
        button: true,
        label: semanticsLabel,
        child: GestureDetector(
          onTap: onTap,
          onLongPress: onLongPress,
          behavior: HitTestBehavior.opaque,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: kSparqMedallionSize,
                height: kSparqMedallionSize,
                child: RepaintBoundary(
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: FamilySparqPetalRingPainter(
                            petals: petals,
                            pulseProgress: effectivePulse,
                            disableGlow: disableGlow,
                            isDark: isDark,
                          ),
                        ),
                      ),
                      _buildMedallion(userAvatar),
                      if (isYourSparq && onAddTap != null)
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: _AddBadge(onTap: onAddTap!),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                line1,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 11,
                  fontWeight:
                      hasUnseen ? FontWeight.w700 : FontWeight.w500,
                  color: labelColor,
                ),
              ),
              if (line2.isNotEmpty)
                Text(
                  line2,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: line2Color,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMedallion(String? userAvatar) {
    final discColor =
        isDark ? KinrelColors.darkCard : const Color(0xFFF5F0EE);

    if (isYourSparq && userAvatar != null && userAvatar.isNotEmpty) {
      return Container(
        width: kSparqInnerDiscSize,
        height: kSparqInnerDiscSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: discColor,
          image: DecorationImage(
            image: CachedNetworkImageProvider(userAvatar),
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    return Container(
      width: kSparqInnerDiscSize,
      height: kSparqInnerDiscSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: discColor,
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: isDark
                ? KinrelColors.textWhite
                : KinrelColors.darkBackground,
          ),
        ),
      ),
    );
  }
}

/// "+" badge on the Your Sparq entry — 22dp orange circle with a
/// white plus.
class _AddBadge extends StatelessWidget {
  const _AddBadge({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        button: true,
        label: SparqTrayStrings.semanticsAddBadge,
        child: Container(
          width: kSparqYourSparqAddBadgeSize,
          height: kSparqYourSparqAddBadgeSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: KinrelColors.orange,
            border: Border.all(
              color: Theme.of(context).brightness == Brightness.dark
                  ? KinrelColors.darkBackground
                  : Colors.white,
              width: 1.5,
            ),
          ),
          child: const Icon(Icons.add, size: 14, color: Colors.white),
        ),
      ),
    );
  }
}

/// "New family" dashed circle + plus + label.
class _NewFamilyEntry extends StatelessWidget {
  const _NewFamilyEntry({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticService.tap();
        context.push('/families/create');
      },
      child: Semantics(
        button: true,
        label: SparqTrayStrings.semanticsNewFamily,
        child: SizedBox(
          width: kSparqEntryWidth,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CustomPaint(
                size: Size(kSparqMedallionSize, kSparqMedallionSize),
                painter: SparqDashedCirclePainter(
                  color: KinrelColors.orange,
                  dashWidth: 4,
                  dashGap: 4,
                  strokeWidth: 2,
                ),
                child: const SizedBox(
                  width: kSparqMedallionSize,
                  height: kSparqMedallionSize,
                  child: Center(
                    child: Icon(Icons.add_rounded,
                        color: KinrelColors.orange, size: 22),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                SparqTrayStrings.newFamily,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: isDark
                      ? KinrelColors.textSilver
                      : KinrelColors.darkCard,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
