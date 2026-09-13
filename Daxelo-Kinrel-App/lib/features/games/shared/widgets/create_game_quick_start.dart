// lib/features/games/shared/widgets/create_game_quick_start.dart
//
// CreateGameQuickStart — universal one-tap room creation widget for
// every multiplayer game.
//
// Replaces the previous setup view that had 5+ form fields visible at
// once (game mode, max players, turn timer, round limit, rules card).
// Most users just want to start a room — they don't care about tuning
// these settings.
//
// New flow:
//   ┌────────────────────────────────────┐
//   │       [Game Icon]                  │
//   │       Antakshari                   │
//   │       Sing together as a family   │
//   │                                    │
//   │   [    Create Game    ▶  ]        │  ← primary action
//   │                                    │
//   │   ⚙ Advanced Settings             │  ← collapsible
//   └────────────────────────────────────┘
//
// When the user taps "Advanced Settings", the advanced options expand:
//   • Game mode (if applicable)
//   • Max players
//   • Turn timer
//   • Round limit
//   • Spectators enabled toggle
//
// Usage:
//   CreateGameQuickStart(
//     gameName: 'Antakshari',
//     gameDescription: 'Sing together as a family',
//     gameIcon: Icons.mic,
//     isLoading: _creating,
//     onCreate: () => notifier.createGame(mode: _mode, maxPlayers: _maxPlayers, ...),
//     advancedSettings: [
//       QuickStartSetting.dropdown(...),
//       QuickStartSetting.slider(...),
//       QuickStartSetting.toggle(...),
//     ],
//   )

import 'package:flutter/material.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../shared/widgets/dk_components.dart';

/// One advanced setting item rendered inside the collapsed panel.
abstract class QuickStartSetting {
  const QuickStartSetting();

  /// Build the widget for this setting.
  Widget build(BuildContext context);
}

/// A dropdown picker (e.g. Game Mode).
class DropdownSetting extends QuickStartSetting {
  const DropdownSetting({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.icon,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: KinrelColors.textDim),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textDim,
              ),
            ),
          ],
        ),
        const SizedBox(height: KinrelSpacing.sm),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: options.map((opt) {
            final selected = opt == value;
            return GestureDetector(
              onTap: () => onChanged(opt),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: KinrelSpacing.md, vertical: 6),
                decoration: BoxDecoration(
                  color: KinrelColors.darkCard,
                  borderRadius: BorderRadius.circular(KinrelRadius.md),
                  border: Border.all(
                    color: selected
                        ? KinrelColors.orange
                        : KinrelColors.border,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Text(
                  opt,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    color: selected
                        ? KinrelColors.orange
                        : KinrelColors.textDim,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

/// A slider (e.g. Turn Timer, Max Players, Round Limit).
class SliderSetting extends QuickStartSetting {
  const SliderSetting({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.labelBuilder,
    required this.onChanged,
    this.icon,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) labelBuilder;
  final ValueChanged<double> onChanged;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: KinrelColors.textDim),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textDim,
              ),
            ),
            const Spacer(),
            Text(
              labelBuilder(value),
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: KinrelColors.orange,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          activeColor: KinrelColors.orange,
          label: labelBuilder(value),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// A boolean toggle (e.g. Spectators enabled).
class ToggleSetting extends QuickStartSetting {
  const ToggleSetting({
    required this.label,
    required this.value,
    required this.onChanged,
    this.icon,
    this.subtitle,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData? icon;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: KinrelColors.textDim),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textDim,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 10,
                    color: KinrelColors.textDim.withValues(alpha: 0.7),
                  ),
                ),
            ],
          ),
        ),
        Switch.adaptive(
          value: value,
          activeColor: KinrelColors.orange,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Universal one-tap room creation widget.
class CreateGameQuickStart extends StatefulWidget {
  const CreateGameQuickStart({
    super.key,
    required this.gameName,
    required this.gameDescription,
    required this.gameIcon,
    required this.isLoading,
    required this.onCreate,
    this.advancedSettings = const [],
    this.familyMemberCount,
  });

  final String gameName;
  final String gameDescription;
  final IconData gameIcon;
  final bool isLoading;

  /// Called when the user taps "Create Game".
  final VoidCallback onCreate;

  /// Advanced settings shown when the user expands the panel. If empty,
  /// the "Advanced Settings" toggle is hidden entirely (true one-tap flow).
  final List<QuickStartSetting> advancedSettings;

  /// Optional family member count — used to suggest a smart default max
  /// players (shown as a hint chip below the create button).
  final int? familyMemberCount;

  @override
  State<CreateGameQuickStart> createState() => _CreateGameQuickStartState();
}

class _CreateGameQuickStartState extends State<CreateGameQuickStart> {
  bool _advancedOpen = false;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(KinrelSpacing.base),
      children: [
        const SizedBox(height: KinrelSpacing.xl),

        // Game icon (large, centered)
        Center(
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  KinrelColors.orange.withValues(alpha: 0.25),
                  KinrelColors.orange.withValues(alpha: 0.05),
                ],
              ),
              shape: BoxShape.circle,
              border: Border.all(
                color: KinrelColors.orange.withValues(alpha: 0.4),
                width: 1.5,
              ),
            ),
            child: Icon(
              widget.gameIcon,
              size: 40,
              color: KinrelColors.orange,
            ),
          ),
        ),
        const SizedBox(height: KinrelSpacing.md),

        // Game name
        Center(
          child: Text(
            widget.gameName,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: KinrelColors.textWhite,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: 4),

        // Game description
        Center(
          child: Text(
            widget.gameDescription,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              color: KinrelColors.textDim,
              height: 1.4,
            ),
          ),
        ),

        const SizedBox(height: KinrelSpacing.xl),

        // Primary action: Create Game
        DKButton(
          label: 'Create Game',
          variant: DKButtonVariant.gradient,
          icon: Icons.play_arrow_rounded,
          fullWidth: true,
          isLoading: widget.isLoading,
          onPressed: widget.onCreate,
        ),

        // Optional smart-default hint
        if (widget.familyMemberCount != null) ...[
          const SizedBox(height: KinrelSpacing.sm),
          Center(
            child: Text(
              'Suggested for ${widget.familyMemberCount} family members',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11,
                color: KinrelColors.textDim.withValues(alpha: 0.7),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],

        // Advanced settings (collapsible)
        if (widget.advancedSettings.isNotEmpty) ...[
          const SizedBox(height: KinrelSpacing.lg),
          InkWell(
            onTap: () => setState(() => _advancedOpen = !_advancedOpen),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: KinrelSpacing.md, vertical: KinrelSpacing.sm),
              decoration: BoxDecoration(
                color: KinrelColors.darkCard,
                borderRadius: BorderRadius.circular(KinrelRadius.md),
                border: Border.all(color: KinrelColors.border),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.tune,
                    size: 14,
                    color: KinrelColors.textDim,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Advanced Settings',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.textDim,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _advancedOpen
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 18,
                    color: KinrelColors.textDim,
                  ),
                ],
              ),
            ),
          ),
          if (_advancedOpen) ...[
            const SizedBox(height: KinrelSpacing.md),
            Container(
              padding: const EdgeInsets.all(KinrelSpacing.md),
              decoration: BoxDecoration(
                color: KinrelColors.darkCard,
                borderRadius: BorderRadius.circular(KinrelRadius.md),
                border: Border.all(color: KinrelColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int i = 0; i < widget.advancedSettings.length; i++) ...[
                    if (i > 0) const SizedBox(height: KinrelSpacing.lg),
                    widget.advancedSettings[i].build(context),
                  ],
                ],
              ),
            ),
          ],
        ],

        // Rules card moved to advanced settings (or shown collapsed below)
        const SizedBox(height: KinrelSpacing.xl),
      ],
    );
  }
}
