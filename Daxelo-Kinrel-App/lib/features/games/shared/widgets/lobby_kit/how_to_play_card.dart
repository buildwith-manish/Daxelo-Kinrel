// lib/features/games/shared/widgets/lobby_kit/how_to_play_card.dart
//
// HowToPlayCard — the collapsible rules section shared by all 14 game
// lobby setup screens.
//
// Progressive disclosure: rules are real content players need only on
// demand, so the card is COLLAPSED by default — a single tap expands it.
// The header always shows the step count so players know the rules are
// one tap away without the list occupying setup space or pushing the
// primary Create Game action below the fold.

import 'package:flutter/material.dart';

import '../../../../../core/constants/brand_colors.dart';
import '../../../../../core/constants/brand_spacing.dart';
import '../../../../../core/constants/brand_typography.dart';
import '../../../game_motion_tokens.dart';
import '../../icons/game_icon_tokens.dart';

/// One step / bullet inside [HowToPlayCard].
class LobbyRule {
  const LobbyRule(
    this.text, {
    this.marker,
    this.highlight = false,
  });

  final String text;

  /// Explicit marker ('★' for mode-specific notes). Numbered steps get
  /// an automatic '1.', '2.', … marker.
  final String? marker;

  /// Highlighted rules render white + orange marker (variant notes).
  final bool highlight;
}

class HowToPlayCard extends StatefulWidget {
  const HowToPlayCard({
    super.key,
    required this.rules,
    this.footnote,
    this.initiallyExpanded = false,
    this.gameId,
  });

  final List<LobbyRule> rules;

  /// Mode-specific closing note, rendered as a highlighted ★ line.
  final String? footnote;

  final bool initiallyExpanded;

  /// Optional game id — tints the header icon with the game's accent.
  final String? gameId;

  @override
  State<HowToPlayCard> createState() => _HowToPlayCardState();
}

class _HowToPlayCardState extends State<HowToPlayCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
    value: widget.initiallyExpanded ? 1.0 : 0.0,
  );
  late final Animation<double> _chevron =
      CurvedAnimation(parent: _controller, curve: Curves.easeOut);

  bool get _expanded => _controller.value > 0.5;

  void _toggle() {
    GameMotionTokens.tap();
    setState(() {
      _expanded ? _controller.reverse() : _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent =
        widget.gameId != null ? GameIconTokens.colorFor(widget.gameId!) : null;

    return Container(
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Column(
        children: [
          // ── Always-visible header (tap target spans the full width) ──
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _toggle,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(KinrelRadius.lg),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: KinrelSpacing.md,
                  vertical: KinrelSpacing.md,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: (accent ?? KinrelColors.orange)
                            .withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(KinrelRadius.sm),
                      ),
                      child: Icon(
                        Icons.menu_book_rounded,
                        size: 17,
                        color: accent ?? KinrelColors.orange,
                      ),
                    ),
                    const SizedBox(width: KinrelSpacing.md),
                    Expanded(
                      child: Text(
                        'How to Play',
                        style: TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: KinrelColors.textWhite,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: KinrelColors.darkElevated,
                        borderRadius: BorderRadius.circular(KinrelRadius.full),
                      ),
                      child: Text(
                        '${widget.rules.length} steps',
                        style: TextStyle(
                          fontFamily: KinrelTypography.monoFont,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: KinrelColors.textDim,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: KinrelSpacing.sm),
                    RotationTransition(
                      turns: _chevron,
                      child: Icon(
                        Icons.expand_more,
                        size: 20,
                        color: KinrelColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // ── Collapsible body ────────────────────────────────────────
          SizeTransition(
            sizeFactor: _chevron,
            axisAlignment: -1,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                KinrelSpacing.md, 0, KinrelSpacing.md, KinrelSpacing.md,
              ),
              child: _RuleList(rules: widget.rules, footnote: widget.footnote),
            ),
          ),
        ],
      ),
    );
  }
}

class _RuleList extends StatelessWidget {
  const _RuleList({required this.rules, this.footnote});

  final List<LobbyRule> rules;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < rules.length; i++) ...[
          if (i > 0) const SizedBox(height: 7),
          _RuleLine(
            marker: rules[i].marker ?? '${i + 1}.',
            rule: rules[i],
          ),
        ],
        if (footnote != null) ...[
          const SizedBox(height: 7),
          _RuleLine(marker: '★', rule: LobbyRule(footnote!, highlight: true)),
        ],
      ],
    );
  }
}

class _RuleLine extends StatelessWidget {
  const _RuleLine({required this.marker, required this.rule});

  final String marker;
  final LobbyRule rule;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          child: Text(
            marker,
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: rule.highlight
                  ? KinrelColors.orange
                  : KinrelColors.textDim,
            ),
          ),
        ),
        Expanded(
          child: Text(
            rule.text,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              color:
                  rule.highlight ? KinrelColors.textWhite : KinrelColors.textDim,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}
