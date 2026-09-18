// lib/features/games/shared/widgets/lobby_kit/lobby_sections.dart
//
// Lobby building blocks — the shared settings vocabulary used by all 14
// multiplayer game lobby setup screens.
//
// UX laws applied:
//   • Hick's Law  — every control is grouped under a short mono overline
//     label (GAME MODE / BEST OF / …) so choices arrive in small,
//     well-scoped groups instead of one long anonymous form.
//   • Fitts's Law — all tappable targets are ≥ 48px tall and generously
//     padded; selected states are unmistakable (brand-orange border +
//     tinted fill) so a glance confirms the current choice.
//   • Consistency — identical spacing, typography and selection language
//     across every game, so learning one lobby teaches all fourteen.

import 'package:flutter/material.dart';

import '../../../../../core/constants/brand_colors.dart';
import '../../../../../core/constants/brand_spacing.dart';
import '../../../../../core/constants/brand_typography.dart';
import '../../../game_motion_tokens.dart';

/// A labeled group of setup controls.
///
/// Renders the mono overline label used across every lobby
/// (`GAME MODE`, `MAX PLAYERS`, `SELECT OPPONENT`, …) plus an optional
/// helper caption, then the group's child content.
class LobbySection extends StatelessWidget {
  const LobbySection({
    super.key,
    required this.label,
    this.caption,
    required this.child,
  });

  final String label;
  final String? caption;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontFamily: KinrelTypography.monoFont,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textDim,
            letterSpacing: 1.2,
          ),
        ),
        if (caption != null) ...[
          const SizedBox(height: 3),
          Text(
            caption!,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 11,
              color: KinrelColors.textDim.withValues(alpha: 0.75),
              height: 1.3,
            ),
          ),
        ],
        const SizedBox(height: KinrelSpacing.sm),
        child,
      ],
    );
  }
}

/// One selectable option inside a [LobbyChoiceGrid].
class LobbyOption<T> {
  const LobbyOption({
    required this.value,
    required this.label,
    this.caption,
    this.icon,
    this.emoji,
  });

  final T value;
  final String label;

  /// Optional one-line explainer rendered under the label.
  final String? caption;

  final IconData? icon;

  /// Emoji instead of a Material icon (RedLight callers/maps).
  final String? emoji;
}

/// Large-tap-target choice selector — the unified replacement for the
/// per-game `_modeSelector()` copies. Renders a wrapping grid of pills,
/// each ≥ 48px tall, with an unmistakable selected state.
class LobbyChoiceGrid<T> extends StatelessWidget {
  const LobbyChoiceGrid({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  final List<LobbyOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: KinrelSpacing.sm,
      runSpacing: KinrelSpacing.sm,
      children: [
        for (final option in options)
          _ChoicePill(
            option: option,
            isSelected: option.value == selected,
            onTap: () {
              GameMotionTokens.tap();
              onSelect(option.value);
            },
          ),
      ],
    );
  }
}

class _ChoicePill extends StatelessWidget {
  const _ChoicePill({
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  final LobbyOption option;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = isSelected ? KinrelColors.textWhite : KinrelColors.textDim;
    final lead = isSelected ? KinrelColors.orange : KinrelColors.textDim;

    return Material(
      color: isSelected
          ? KinrelColors.orange.withValues(alpha: 0.10)
          : KinrelColors.darkCard,
      borderRadius: BorderRadius.circular(KinrelRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: KinrelSpacing.md,
            vertical: 13,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KinrelRadius.md),
            border: Border.all(
              color: isSelected
                  ? KinrelColors.orange
                  : KinrelColors.border,
              width: isSelected ? 1.5 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: KinrelColors.orangeGlow,
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (option.emoji != null) ...[
                    Text(option.emoji!,
                        style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 6),
                  ] else if (option.icon != null) ...[
                    Icon(option.icon, size: 17, color: lead),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    option.label,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: fg,
                    ),
                  ),
                ],
              ),
              if (option.caption != null) ...[
                const SizedBox(height: 3),
                Text(
                  option.caption!,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 10,
                    color: fg.withValues(alpha: 0.65),
                    height: 1.25,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact numeric pill row (BEST OF 1/3/5, max players 6/8/12, auto-close
/// 3/5/10/15 min…). Mono numerals in ≥ 44px targets.
class LobbyNumberRow extends StatelessWidget {
  const LobbyNumberRow({
    super.key,
    required this.numbers,
    required this.selected,
    required this.onSelect,
    this.suffix,
  });

  final List<int> numbers;
  final int selected;
  final ValueChanged<int> onSelect;

  /// Optional suffix inside the pill ('' or 'min').
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: KinrelSpacing.sm,
      runSpacing: KinrelSpacing.sm,
      children: [
        for (final n in numbers)
          _NumberPill(
            label: '$n${suffix ?? ''}',
            isSelected: n == selected,
            onTap: () {
              GameMotionTokens.tap();
              onSelect(n);
            },
          ),
      ],
    );
  }
}

class _NumberPill extends StatelessWidget {
  const _NumberPill({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? KinrelColors.orange.withValues(alpha: 0.10)
          : KinrelColors.darkCard,
      borderRadius: BorderRadius.circular(KinrelRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        child: Container(
          constraints: const BoxConstraints(minWidth: 64),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KinrelRadius.md),
            border: Border.all(
              color: isSelected ? KinrelColors.orange : KinrelColors.border,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: isSelected
                    ? KinrelColors.orange
                    : KinrelColors.textDim,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Labelled slider with a live value chip (turn timer, round limit, call
/// speed…). Keeps the current value visible at a glance.
class LobbySliderRow extends StatelessWidget {
  const LobbySliderRow({
    super.key,
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
  });

  final String label;
  final String valueLabel;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final int? divisions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: KinrelColors.textWhite,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: KinrelColors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(KinrelRadius.full),
                border:
                    Border.all(color: KinrelColors.orange.withValues(alpha: 0.5)),
              ),
              child: Text(
                valueLabel,
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.orange,
                ),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            activeTrackColor: KinrelColors.orange,
            inactiveTrackColor: KinrelColors.darkElevated,
            thumbColor: KinrelColors.amber,
            overlayColor: KinrelColors.orangeGlow,
          ),
          child: Slider(
            value: value.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: divisions,
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
      ],
    );
  }
}

/// Compact switch row (spectators, team mode, elimination…).
/// Large visual row = large tap area; the switch itself is secondary.
class LobbySwitchRow extends StatelessWidget {
  const LobbySwitchRow({
    super.key,
    required this.icon,
    required this.label,
    this.caption,
    required this.value,
    required this.onChanged,
    this.accentColor,
  });

  final IconData icon;
  final String label;
  final String? caption;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? KinrelColors.orange;
    final stateColor = value ? accent : KinrelColors.textDim;

    return Material(
      color: KinrelColors.darkCard,
      borderRadius: BorderRadius.circular(KinrelRadius.md),
      child: InkWell(
        onTap: onChanged == null
            ? null
            : () {
                GameMotionTokens.tap();
                onChanged!(!value);
              },
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: KinrelSpacing.md,
            vertical: KinrelSpacing.sm + 2,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KinrelRadius.md),
            border: Border.all(
              color: value
                  ? accent.withValues(alpha: 0.5)
                  : KinrelColors.border,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: stateColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(KinrelRadius.sm),
                ),
                child: Icon(icon, size: 17, color: stateColor),
              ),
              const SizedBox(width: KinrelSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    if (caption != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        caption!,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 10.5,
                          color: KinrelColors.textDim,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Switch.adaptive(
                value: value,
                onChanged: onChanged == null
                    ? null
                    : (v) {
                        GameMotionTokens.tap();
                        onChanged!(v);
                      },
                activeColor: accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small accent-tinted inline note (mode explainer, team note…).
/// Replaces the old per-game description cards.
class LobbyInfoNote extends StatelessWidget {
  const LobbyInfoNote({super.key, required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.md,
        vertical: KinrelSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: KinrelColors.orange),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11.5,
                color: KinrelColors.textDim,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
