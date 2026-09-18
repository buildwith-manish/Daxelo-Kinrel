// lib/features/games/shared/widgets/lobby_kit/lobby_setup_screen.dart
//
// LobbySetupScreen — the unified premium setup body shared by all 10
// temporary-room multiplayer game lobbies (SOS, Antakshari, Bingo, Ludo,
// Chitmatch, Dots&Boxes, NamePlace, TruthOrDare, TwoTruths, FreezeDash).
//
// Layout contract (identical across every game):
//
//   ┌────────────────────────────────────┐
//   │  [icon] SOS                        │  ← compact hero (identity)
//   │         Team letter duel           │
//   │  (2–4 players) (~10 min)           │
//   ├────────────────────────────────────┤
//   │  GAME MODE                         │  ← game settings (visible)
//   │  [ 2 Players ] [ 4P Teams ]        │
//   │  …                                 │
//   │  [👁 Allow spectators        ⬤]    │  ← visible, compact
//   │  ▸ How to Play               (5)   │  ← collapsed, on demand
//   ├────────────────────────────────────┤
//   │ ╔════════════════════════════════╗ │  ← PINNED primary CTA —
//   │ ║  ▶  CREATE GAME                ║ │     always above the fold,
//   │ ╚════════════════════════════════╝ │     never scrolls away
//   │  Family gets an invite to join     │
//   └────────────────────────────────────┘
//
// The pinned CTA is the single loudest element on the screen (Fitts's
// Law: 56px full-width thumb target). The hero is deliberately compact
// so mode + spectator settings stay visible without scrolling (Hick's
// Law: few, grouped choices). Rules collapse into How to Play.

import 'package:flutter/material.dart';

import '../../../../../core/constants/brand_colors.dart';
import '../../../../../core/constants/brand_spacing.dart';
import '../../../../../core/constants/brand_typography.dart';
import '../../../game_motion_tokens.dart';
import 'how_to_play_card.dart';
import 'lobby_hero.dart';
import 'lobby_sections.dart';

class LobbySetupScreen extends StatelessWidget {
  const LobbySetupScreen({
    super.key,
    required this.gameId,
    required this.title,
    required this.tagline,
    this.facts,
    this.banner,
    this.settings,
    required this.rules,
    this.rulesFootnote,
    this.rulesInitiallyExpanded = false,
    this.showSpectatorToggle = true,
    required this.spectatorsEnabled,
    this.onSpectatorsChanged,
    this.footer,
    required this.ctaLabel,
    this.ctaHint,
    this.ctaLoading = false,
    this.ctaEnabled = true,
    required this.onCtaPressed,
  });

  /// Game id for icon + accent color ('sos', 'bingo', …).
  final String gameId;
  final String title;
  final String tagline;
  final List<LobbyFact>? facts;

  /// Optional status strip rendered between hero and settings (e.g. the
  /// closed-room notice or a reconnecting banner).
  final Widget? banner;

  /// Game settings column (LobbySection groups).
  final Widget? settings;

  /// How to Play steps.
  final List<LobbyRule> rules;
  final String? rulesFootnote;
  final bool rulesInitiallyExpanded;

  final bool showSpectatorToggle;
  final bool spectatorsEnabled;
  final ValueChanged<bool>? onSpectatorsChanged;

  /// Extra content below How to Play.
  final Widget? footer;

  final String ctaLabel;
  final String? ctaHint;
  final bool ctaLoading;
  final bool ctaEnabled;
  final Future<void> Function() onCtaPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Scrollable setup content ─────────────────────────────────
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              KinrelSpacing.base, KinrelSpacing.md, KinrelSpacing.base,
              KinrelSpacing.base,
            ),
            children: [
              LobbyHero(
                gameId: gameId,
                title: title,
                tagline: tagline,
                facts: facts,
              ),
              if (banner != null) ...[
                const SizedBox(height: KinrelSpacing.md),
                banner!,
              ],
              if (settings != null) ...[
                const SizedBox(height: KinrelSpacing.lg),
                settings!,
              ],
              if (showSpectatorToggle) ...[
                const SizedBox(height: KinrelSpacing.md),
                LobbySwitchRow(
                  icon: Icons.visibility_outlined,
                  label: 'Allow spectators',
                  caption: spectatorsEnabled
                      ? 'Family can watch read-only'
                      : 'Only players can see the game',
                  value: spectatorsEnabled,
                  onChanged: onSpectatorsChanged,
                ),
              ],
              const SizedBox(height: KinrelSpacing.md),
              HowToPlayCard(
                gameId: gameId,
                rules: rules,
                footnote: rulesFootnote,
                initiallyExpanded: rulesInitiallyExpanded,
              ),
              if (footer != null) ...[
                const SizedBox(height: KinrelSpacing.md),
                footer!,
              ],
              const SizedBox(height: KinrelSpacing.md),
            ],
          ),
        ),

        // ── Pinned primary action — always above the fold ────────────
        LobbyPinnedCtaBar(
          label: ctaLabel,
          hint: ctaHint,
          loading: ctaLoading,
          enabled: ctaEnabled,
          onPressed: onCtaPressed,
        ),
      ],
    );
  }
}

/// Full-width pinned primary-action bar. Always visible; the gradient
/// button is 56px tall with an ignite glow — the unmistakable "next
/// step" on every game lobby.
class LobbyPinnedCtaBar extends StatelessWidget {
  const LobbyPinnedCtaBar({
    super.key,
    required this.label,
    required this.onPressed,
    this.hint,
    this.loading = false,
    this.enabled = true,
  });

  final String label;
  final String? hint;
  final bool loading;
  final bool enabled;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(
          KinrelSpacing.base, KinrelSpacing.md, KinrelSpacing.base,
          KinrelSpacing.md,
        ),
        decoration: BoxDecoration(
          color: KinrelColors.darkSurface,
          border: Border(
            top: BorderSide(
              color: KinrelColors.border.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PrimaryButton(
              label: label,
              loading: loading,
              enabled: enabled,
              onPressed: onPressed,
            ),
            if (hint != null && hint!.isNotEmpty) ...[
              const SizedBox(height: 7),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 11,
                  color: KinrelColors.textDim.withValues(alpha: 0.8),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatefulWidget {
  const _PrimaryButton({
    required this.label,
    required this.loading,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool loading;
  final bool enabled;
  final Future<void> Function() onPressed;

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
  bool _localBusy = false;

  Future<void> _run() async {
    if (_localBusy || widget.loading || !widget.enabled) return;
    GameMotionTokens.tap();
    setState(() => _localBusy = true);
    try {
      await widget.onPressed();
    } finally {
      if (mounted) setState(() => _localBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _localBusy || widget.loading;
    final enabled = widget.enabled && !busy;

    return Material(
      borderRadius: BorderRadius.circular(KinrelRadius.lg),
      child: InkWell(
        onTap: enabled ? _run : null,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        child: Ink(
          height: 56,
          decoration: BoxDecoration(
            gradient: enabled
                ? const LinearGradient(
                    colors: [KinrelColors.orange, KinrelColors.amber],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  )
                : null,
            color: enabled ? null : KinrelColors.darkElevated,
            borderRadius: BorderRadius.circular(KinrelRadius.lg),
            border: enabled
                ? null
                : Border.all(color: KinrelColors.border),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: KinrelColors.orangeGlow,
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.label,
                        style: TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                          color: enabled
                              ? Colors.white
                              : KinrelColors.textDim,
                        ),
                      ),
                      if (enabled) ...[
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
