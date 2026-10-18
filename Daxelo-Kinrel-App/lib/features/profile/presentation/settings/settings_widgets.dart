// lib/features/profile/presentation/settings/settings_widgets.dart
//
// DAXELO KINREL — Settings widgets (extracted from profile_screen.dart).
//
// These widgets were private (`_SettingsRow`, `_SettingsToggleRow`,
// `_SettingsSegmentedRow`, `_SettingsFontScaleRow`, `_SettingsDeleteRow`,
// `_StatCard`, `_FamilyIdRow`) inside profile_screen.dart. They are now
// PUBLIC and live here so the new Settings hub + category screens can
// reuse them without duplicating code.
//
// Behavior is identical to the originals — the same colors, padding,
// typography, and tap-target rules. The only change is the leading
// underscore was dropped.
//
// Also exposes three small public helpers used by both the new Me screen
// and the Settings screens:
//   • SettingsSectionLabel (was _buildSectionHeader)
//   • SettingsCard          (was _buildSectionCard)
//   • SettingsDivider        (was _divider)

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../shared/widgets/dk_components.dart';
import '../../../../shared/widgets/kinrel_skeleton.dart';

// ──────────────────────────────────────────────────────────────────────
//  Tokens — kept in sync with the spec's dark-theme reference values.
//  Use DKColors.* for theme-aware color lookups; this constant is only
//  for the brand accent (orange is identical in light + dark).
// ──────────────────────────────────────────────────────────────────────

const Color kSettingsOrange = Color(0xFFE8612A);

// ──────────────────────────────────────────────────────────────────────
//  Small public helpers
// ──────────────────────────────────────────────────────────────────────

/// Section label — the muted 13px orange label above each card group.
/// Mirrors the old _buildSectionHeader behavior including the fadeIn.
class SettingsSectionLabel extends StatelessWidget {
  const SettingsSectionLabel(this.title, {super.key});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: kSettingsOrange,
          letterSpacing: 0.8,
        ),
      ),
    ).animate(onPlay: (c) => c.forward()).fadeIn(duration: 300.ms);
  }
}

/// Standard settings card — solid bg + hairline border + 12px radius.
/// Mirrors the old _buildSectionCard behavior.
class SettingsCard extends StatelessWidget {
  const SettingsCard({
    super.key,
    required this.children,
    this.padding,
    this.color,
    this.border,
    this.radius = 12,
  });

  final List<Widget> children;
  final EdgeInsets? padding;
  final Color? color;
  final Color? border;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final cardBg = color ?? DKColors.cardColor(context);
    final borderSubtle =
        border ??
        (DKColors.isLight(context)
            ? const Color(0xFFE5E7EB)
            : const Color(0xFF3A3A4A));
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderSubtle),
      ),
      child: Column(children: children),
    );
  }
}

/// Hairline divider used between rows in a card. Mirrors the old
/// _divider behavior (1px hairline indented 16px each side).
class SettingsDivider extends StatelessWidget {
  const SettingsDivider({super.key, this.indent = 16});

  final double indent;

  @override
  Widget build(BuildContext context) {
    final borderSubtle =
        DKColors.isLight(context)
            ? const Color(0xFFE5E7EB)
            : const Color(0xFF3A3A4A);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: indent),
      child: Divider(height: 1, thickness: 0.5, color: borderSubtle),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
//  Settings Row (chevron)
// ──────────────────────────────────────────────────────────────────────

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    this.badge,
    this.iconColor,
    this.labelColor,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final int? badge;
  final Color? iconColor;
  final Color? labelColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final effectiveIconColor =
        iconColor ??
        (DKColors.isLight(context)
            ? const Color(0xFF6B7280)
            : const Color(0xFF8A7A72));
    final effectiveLabelColor = labelColor ?? DKColors.textPrimary(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Icon(icon, color: effectiveIconColor, size: 20),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: effectiveLabelColor,
                            ),
                          ),
                        ),
                        if (badge != null && badge! > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: kSettingsOrange,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${badge!}',
                              style: const TextStyle(
                                fontFamily: KinrelTypography.displayFont,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 12,
                          color: DKColors.isLight(context)
                              ? const Color(0xFF6B7280)
                              : const Color(0xFF8A7A72),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              trailing ??
                  Icon(
                    Icons.chevron_right,
                    color: DKColors.isLight(context)
                        ? const Color(0xFF9CA3AF)
                        : const Color(0xFF8A7A72),
                    size: 20,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
//  Settings Toggle Row
// ──────────────────────────────────────────────────────────────────────

class SettingsToggleRow extends ConsumerWidget {
  const SettingsToggleRow({
    super.key,
    required this.icon,
    required this.label,
    required this.provider,
    this.onChanged,
  });

  final IconData icon;
  final String label;
  final StateProvider<bool> provider;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(provider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(
            icon,
            color: DKColors.isLight(context)
                ? const Color(0xFF6B7280)
                : const Color(0xFF8A7A72),
            size: 20,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: DKColors.textPrimary(context),
              ),
            ),
          ),
          SizedBox(
            height: 28,
            child: Switch(
              value: value,
              onChanged: (v) {
                ref.read(provider.notifier).state = v;
                onChanged?.call(v);
              },
              activeThumbColor: Colors.white,
              activeTrackColor: kSettingsOrange.withValues(alpha: 0.5),
              thumbColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return Colors.white;
                return const Color(0xFF9E9E9E);
              }),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
//  Settings Segmented Row (theme picker pattern)
// ──────────────────────────────────────────────────────────────────────

class SettingsSegmentedRow<T> extends StatelessWidget {
  const SettingsSegmentedRow({
    super.key,
    required this.icon,
    required this.label,
    required this.segments,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final Map<T, String> segments;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(
            icon,
            color: DKColors.isLight(context)
                ? const Color(0xFF6B7280)
                : const Color(0xFF8A7A72),
            size: 20,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: DKColors.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: DKColors.elevatedColor(context),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: segments.entries.map((entry) {
                      final isSelected = entry.key == value;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => onChanged(entry.key),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            decoration: BoxDecoration(
                              color: isSelected ? kSettingsOrange : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              entry.value,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: isSelected
                                    ? Colors.white
                                    : (DKColors.isLight(context)
                                          ? const Color(0xFF6B7280)
                                          : const Color(0xFF8A7A72)),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
//  Settings Font Scale Row
// ──────────────────────────────────────────────────────────────────────

class SettingsFontScaleRow extends StatelessWidget {
  const SettingsFontScaleRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  static const _sizes = [0.85, 1.0, 1.15];
  static const _labels = ['Small', 'Medium', 'Large'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(
            icon,
            color: DKColors.isLight(context)
                ? const Color(0xFF6B7280)
                : const Color(0xFF8A7A72),
            size: 20,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: DKColors.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: DKColors.elevatedColor(context),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: List.generate(_sizes.length, (i) {
                      final isSelected = (value - _sizes[i]).abs() < 0.01;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => onChanged(_sizes[i]),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            decoration: BoxDecoration(
                              color: isSelected ? kSettingsOrange : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _labels[i],
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: isSelected
                                    ? Colors.white
                                    : (DKColors.isLight(context)
                                          ? const Color(0xFF6B7280)
                                          : const Color(0xFF8A7A72)),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
//  Settings Delete Row (danger styling)
// ──────────────────────────────────────────────────────────────────────

class SettingsDeleteRow extends StatelessWidget {
  const SettingsDeleteRow({super.key, required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              const Icon(
                Icons.delete_outline,
                color: KinrelColors.error,
                size: 20,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: KinrelColors.error,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: DKColors.isLight(context)
                    ? const Color(0xFF9CA3AF)
                    : const Color(0xFF8A7A72),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
//  Stat Card (Me screen — 3-column stats row uses this)
// ──────────────────────────────────────────────────────────────────────

class SettingsStatCard extends StatelessWidget {
  const SettingsStatCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String? value; // null = loading
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cardBg = DKColors.cardColor(context);
    final borderColor = DKColors.borderColor(context);
    final textPrimary = DKColors.textPrimary(context);
    final textDim = DKColors.isLight(context)
        ? const Color(0xFF6B7280)
        : const Color(0xFF8A7A72);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: kSettingsOrange, size: 20),
            const SizedBox(height: 8),
            if (value != null)
              Text(
                value!,
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              )
            else
              const KinrelSkeletonBox(width: 48, height: 22, radius: 4),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11,
                color: textDim,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
//  Family ID Row (KIN family ID display + copy/QR/share)
//  ──────────────────────────────────────────────────────────────────────
//
//  Kept in this widgets file (not settings-only) because the new Me
//  screen's "My families" section and the My Families screen both
//  render it. Behavior is unchanged from the original _FamilyIdRow.

class FamilyIdRow extends StatelessWidget {
  const FamilyIdRow({
    super.key,
    required this.familyName,
    this.kinFamilyId,
    required this.familyId,
    this.onCopy,
    this.onQR,
    this.onShare,
  });

  final String familyName;
  final String? kinFamilyId;
  final String familyId;
  final VoidCallback? onCopy;
  final VoidCallback? onQR;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final hasKinId = kinFamilyId != null && kinFamilyId!.isNotEmpty;

    return InkWell(
      onTap: hasKinId ? onCopy : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Family icon
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: kSettingsOrange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.family_restroom_rounded,
                size: 18,
                color: kSettingsOrange,
              ),
            ),
            const SizedBox(width: 12),

            // Family name + ID
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    familyName,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: DKColors.textPrimary(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  if (hasKinId)
                    Text(
                      kinFamilyId!,
                      style: const TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: kSettingsOrange,
                        letterSpacing: 1,
                      ),
                    )
                  else
                    Text(
                      'No Family ID assigned',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        color: DKColors.isLight(context)
                            ? const Color(0xFF6B7280)
                            : const Color(0xFF8A7A72),
                      ),
                    ),
                ],
              ),
            ),

            // Action buttons
            if (hasKinId) ...[
              SizedBox(
                width: 36,
                height: 36,
                child: IconButton(
                  icon: Icon(
                    Icons.qr_code_rounded,
                    color: DKColors.isLight(context)
                        ? const Color(0xFF6B7280)
                        : const Color(0xFF8A7A72),
                    size: 20,
                  ),
                  onPressed: onQR,
                  padding: EdgeInsets.zero,
                  tooltip: 'Show QR code',
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 36,
                height: 36,
                child: IconButton(
                  icon: Icon(
                    Icons.share_outlined,
                    color: DKColors.isLight(context)
                        ? const Color(0xFF6B7280)
                        : const Color(0xFF8A7A72),
                    size: 20,
                  ),
                  onPressed: onShare,
                  padding: EdgeInsets.zero,
                  tooltip: 'Share invite link',
                ),
              ),
            ] else ...[
              Icon(
                Icons.chevron_right,
                color: DKColors.isLight(context)
                    ? const Color(0xFF9CA3AF)
                    : const Color(0xFF8A7A72),
                size: 20,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
