// lib/features/gaming_ecosystem/presentation/match_ecosystem_summary.dart
//
// MatchEcosystemSummary — the post-match rewards + sportsmanship surface
// shown on every game's results view.
//
// Flow:
//   1. The game's results screen embeds this widget with (gameTable, gameId,
//      familyId, participants).
//   2. It calls fn_get_match_ecosystem — the FIRST render processes +
//      archives the match (badges evaluated, challenges advanced, milestones
//      checked, activity logged, Cup points awarded) and returns rewards.
//   3. The banner celebrates: new badges (gold glow), completed challenges
//      (purple), family milestones (amber), with staggered entrance
//      animations (emotionally rewarding feedback, zero clutter).
//   4. A sportsmanship row lets players cheer opponents (gg / great move /
//      well played / fun game) — one tap, persisted, and the receiver's
//      sportsmanship score grows.
//
// The widget renders nothing when the match produced no rewards (e.g. a
// cancelled room) — results screens stay clean.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/supabase_service.dart';
import '../data/gaming_models.dart';
import '../data/gaming_providers.dart';
import '../../games/shared/icons/kinrel_icons.dart';
import 'widgets/gaming_kit.dart';
import 'package:flutter_animate/flutter_animate.dart';

class MatchEcosystemSummary extends ConsumerWidget {
  const MatchEcosystemSummary({
    super.key,
    required this.gameTable,
    required this.gameId,
    required this.familyId,
    this.padding = const EdgeInsets.only(top: 14),
  });

  final String gameTable;
  final String gameId;
  final String familyId;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ecoAsync = ref.watch(
        matchEcosystemProvider(MatchEcosystemKey(gameTable: gameTable, gameId: gameId)));

    return Padding(
      padding: padding,
      child: ecoAsync.maybeWhen(
        data: (eco) => eco == null
            ? const SizedBox.shrink()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Variable Reward (Skinner): ~20% of completed matches
                  // surface a surprise coin bonus. Unpredictable rewards
                  // sustain engagement far longer than fixed ones.
                  VariableRewardBanner(
                    key: ValueKey('vr_$gameId'),
                    gameId: gameId,
                    familyId: familyId,
                  ),
                  if (eco.hasRewards) _RewardsBanner(eco: eco),
                  if (eco.hasScores) _SuperlativesSection(eco: eco),
                  _SportsmanshipSection(
                    eco: eco,
                    gameTable: gameTable,
                    gameId: gameId,
                    familyId: familyId,
                  ),
                ],
              ),
        orElse: () => const SizedBox.shrink(),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Variable Reward banner (operant conditioning, variable-ratio)
//
// After a match ends, ~20% of the time the viewer receives a surprise
// bonus of 1–5 coins. The roll is DETERMINISTIC per (gameId, viewer) via
// a stable FNV-1a hash — so rebuilds/return visits never re-roll a
// different outcome, and the award itself is idempotent server-side
// (fn_award_coins with p_idempotency_key = gameId). Only shown for
// real completed matches (eco != null) — never for cancelled rooms.
// ═══════════════════════════════════════════════════════════════════

class VariableRewardBanner extends ConsumerStatefulWidget {
  const VariableRewardBanner({
    super.key,
    required this.gameId,
    required this.familyId,
  });

  final String gameId;
  final String familyId;

  @override
  ConsumerState<VariableRewardBanner> createState() =>
      _VariableRewardBannerState();
}

class _VariableRewardBannerState extends ConsumerState<VariableRewardBanner> {
  int? _amount;
  bool _attempted = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _maybeAward());
  }

  /// FNV-1a — small, fast, and stable across sessions/platforms
  /// (unlike String.hashCode, which is only stable per isolate).
  static int _stableHash(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0x7fffffff;
    }
    return h;
  }

  Future<void> _maybeAward() async {
    if (_attempted) return;
    _attempted = true;

    final client = ref.read(supabaseProvider);
    final myId = client?.auth.currentUser?.id;
    if (client == null || myId == null) return;

    // Deterministic 20% roll per (game, viewer).
    final roll = _stableHash('${widget.gameId}|$myId');
    if (roll % 100 >= 20) return;

    // Deterministic 1–5 coin amount.
    final amount = (_stableHash('${widget.gameId}|$myId|amt') % 5) + 1;

    try {
      final resp = await client.rpc('fn_award_coins', params: {
        'p_user_id': myId,
        'p_family_id': widget.familyId,
        'p_amount': amount,
        'p_reason': 'match_bonus_variable',
        'p_idempotency_key': widget.gameId,
        'p_metadata': {'source': 'variable_reward_banner'},
      }).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (resp is Map && resp['ok'] == true) {
        setState(() => _amount = amount);
      }
    } catch (_) {
      // Award failed — show nothing rather than a false promise.
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount = _amount;
    if (amount == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2A1E06), Color(0xFF191218)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: KinrelColors.amber.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: KinrelColors.amber.withValues(alpha: 0.16),
            blurRadius: 20,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          const Text('🎉', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bonus! You earned $amount coin${amount == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: KinrelColors.amber,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'A surprise thank-you for playing — added to your balance',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 11,
                    color: KinrelColors.textSilver,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 450.ms, delay: 250.ms)
        .scale(
          begin: const Offset(0.92, 0.92),
          end: const Offset(1, 1),
          duration: 450.ms,
          delay: 250.ms,
          curve: Curves.easeOutBack,
        );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Rewards banner
// ═══════════════════════════════════════════════════════════════════════

class _RewardsBanner extends ConsumerWidget {
  const _RewardsBanner({required this.eco});
  final MatchEcosystemResult eco;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = <Widget>[];

    // New badges — highest emotional value, shown first.
    for (final pb in eco.newBadges) {
      for (final b in pb.badges) {
        rows.add(_RewardRow(
          leading: GamingBadgeChip(
            icon: b.icon,
            name: b.name,
            tier: b.tier,
            earned: true,
            size: 46,
            showName: false,
          ),
          accent: KinrelColors.brightGold,
          title: '${pb.userName == '' ? 'You' : pb.userName} earned ${b.name}!',
          subtitle: b.description,
        ));
      }
    }

    // Personal bests — competence & growth mindset: celebrate
    // improvement, not just victory. Shown right after badges.
    for (final pb in eco.personalBests) {
      rows.add(_RewardRow(
        leading: _personalBestIcon(pb.metric),
        accent: KinrelColors.orange,
        title: _personalBestTitle(pb),
        subtitle: _personalBestSubtitle(pb),
      ));
    }

    // Completed challenges.
    for (final pc in eco.completedChallenges) {
      for (final c in pc.challenges) {
        rows.add(_RewardRow(
          leading: KinrelIcon(kinrelIconFromEmoji(c.icon) ?? KinrelIconData.flag,
              size: 24, color: const Color(0xFF8B5CF6)),
          accent: const Color(0xFF8B5CF6),
          title: 'Challenge complete: ${c.title}',
          subtitle: '+${c.rewardPoints} bonus points',
        ));
      }
    }

    // Family milestones.
    for (final m in eco.milestones) {
      rows.add(_RewardRow(
        leading: const KinrelIcon(KinrelIconData.trophy,
            size: 24, color: KinrelColors.brightGold),
        accent: KinrelColors.gold,
        title: 'Family milestone unlocked!',
        subtitle: m.description,
      ));
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF221509), Color(0xFF161218)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: KinrelColors.gold.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: KinrelColors.gold.withValues(alpha: 0.14),
            blurRadius: 22,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const KinrelIcon(KinrelIconData.sparkle,
                  size: 18, color: KinrelColors.brightGold),
              const SizedBox(width: 8),
              Text(
                'FAMILY MOMENTS FROM THIS MATCH',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  color: KinrelColors.brightGold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...rows
              .map((r) => r
                  .animate()
                  .fadeIn(duration: 350.ms)
                  .slideX(begin: 0.05, end: 0, duration: 350.ms))
              .expand((r) => [r, const SizedBox(height: 10)])
              .toList()
            ..removeLast(),
        ],
      ),
    );
  }

  // ── Personal-best presentation (growth-mindset framing) ──────────

  Widget _personalBestIcon(String metric) {
    switch (metric) {
      case 'fastest_win':
        return const KinrelIcon(KinrelIconData.zap,
            size: 24, color: KinrelColors.amber);
      case 'accuracy_pct':
        return const KinrelIcon(KinrelIconData.target,
            size: 24, color: KinrelColors.tealAccent);
      default:
        return const KinrelIcon(KinrelIconData.chart,
            size: 24, color: KinrelColors.orange);
    }
  }

  String _personalBestTitle(PersonalBestReward pb) {
    final name = pb.userName.isEmpty ? 'You' : pb.userName;
    switch (pb.metric) {
      case 'fastest_win':
        return pb.firstEver
            ? '$name\'s first win is on the board!'
            : '$name set a fastest win!';
      case 'accuracy_pct':
        return pb.firstEver
            ? '$name\'s sharpest game yet: ${_fmtNum(pb.value)}%'
            : 'New accuracy best for $name: ${_fmtNum(pb.value)}%';
      default:
        final unit = _scoreUnit(eco.gameTable);
        return pb.firstEver
            ? '$name\'s first recorded best: ${_fmtNum(pb.value)} $unit'
            : 'New personal best for $name!';
    }
  }

  String _personalBestSubtitle(PersonalBestReward pb) {
    if (pb.metric == 'fastest_win') {
      return pb.firstEver
          ? 'Won ${_formatClock(pb.value)} in ${eco.gameName} — the clock starts now'
          : '${_formatClock(pb.value)} — ${_improvementLine(pb)}';
    }
    if (pb.metric == 'accuracy_pct') {
      return pb.firstEver
          ? 'Every flip, shot and guess counted — beautifully played'
          : '${_improvementLine(pb)} — keep growing!';
    }
    final unit = _scoreUnit(eco.gameTable);
    return pb.firstEver
        ? 'Beat it next match and watch the record climb'
        : '${_fmtNum(pb.value)} $unit — ${_improvementLine(pb)}';
  }

  String _improvementLine(PersonalBestReward pb) {
    final prev = pb.previousValue;
    if (prev == null) return 'a brand-new record';
    if (pb.metric == 'fastest_win') {
      final delta = (prev - pb.value).toDouble();
      if (delta <= 0) return 'matching your best';
      return '${_formatClock(delta)} faster than before';
    }
    final delta = (pb.value - prev).toDouble();
    if (delta <= 0) return 'matching your best';
    final unit = pb.metric == 'accuracy_pct'
        ? '%'
        : _scoreUnit(eco.gameTable);
    return '${_fmtNum(delta)} $unit better than before';
  }
}

String _fmtNum(num v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(1);
}

String _formatClock(num seconds) {
  final s = seconds.toInt();
  if (s < 60) return '${s}s';
  final m = s ~/ 60;
  final rest = s % 60;
  return rest == 0 ? '${m}m' : '${m}m ${rest}s';
}

/// Human unit for the score metric of each game table.
String _scoreUnit(String gameTable) {
  switch (gameTable) {
    case 'memorymatch_games':
      return 'pairs';
    case 'tugofwar_games':
      return 'pulls';
    case 'dotsboxes_games':
      return 'boxes';
    case 'ludo_games':
      return 'tokens home';
    case 'redlight_rounds':
      return 'm of progress';
    case 'twotruths_games':
    case 'ghost_painter_rounds':
      return 'correct guesses';
    default:
      return 'points';
  }
}

class _RewardRow extends StatelessWidget {
  const _RewardRow({
    required this.leading,
    required this.accent,
    required this.title,
    required this.subtitle,
  });

  final Widget leading;
  final Color accent;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 46, height: 46, child: Center(child: leading)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 11.5,
                  height: 1.3,
                  color: KinrelColors.textSilver,
                ),
              ),
            ],
          ),
        ),
        Icon(Icons.celebration_rounded, size: 18, color: accent),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Superlatives — benign social comparison: every player leaves with a
// stat to be proud of, not just the winner.
// ═══════════════════════════════════════════════════════════════════════

class _SuperlativesSection extends ConsumerWidget {
  const _SuperlativesSection({required this.eco});
  final MatchEcosystemResult eco;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.read(supabaseProvider);
    final myId = client?.auth.currentUser?.id;

    final scored = eco.players
        .where((p) => p.score != null || p.accuracyPct != null)
        .toList();
    if (scored.length < 2) return const SizedBox.shrink();

    // Top score (ties shared — superlatives never exclude).
    final maxScore = scored
        .map((p) => p.score ?? 0)
        .reduce((a, b) => a > b ? a : b);
    final topScorers = scored.where((p) => (p.score ?? 0) == maxScore);

    // Sharpest accuracy among players who have one.
    final accs = scored.where((p) => p.accuracyPct != null);
    final maxAcc = accs.isEmpty
        ? null
        : accs.map((p) => p.accuracyPct!).reduce((a, b) => a > b ? a : b);
    final sharpest = maxAcc == null
        ? const <MatchPlayerResult>[]
        : accs.where((p) => p.accuracyPct == maxAcc);

    final unit = _scoreUnit(eco.gameTable);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: KinrelColors.orange.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const KinrelIcon(KinrelIconData.medal,
                  size: 16, color: KinrelColors.orange),
              const SizedBox(width: 8),
              Text(
                'MATCH SUPERLATIVES',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  color: KinrelColors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in topScorers)
                _SuperlativeChip(
                  icon: KinrelIconData.target,
                  label:
                      '${p.userName.isEmpty ? 'You' : p.userName} · top score (${_fmtNum(p.score ?? 0)} $unit)',
                  mine: p.userId == myId,
                ),
              for (final p in sharpest)
                if (maxAcc! > 0)
                  _SuperlativeChip(
                    icon: KinrelIconData.brain,
                    label:
                        '${p.userName.isEmpty ? 'You' : p.userName} · sharpest (${p.accuracyPct}%)',
                    mine: p.userId == myId,
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SuperlativeChip extends StatelessWidget {
  const _SuperlativeChip({
    required this.icon,
    required this.label,
    this.mine = false,
  });

  final KinrelIconData icon;
  final String label;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        gradient: mine
            ? LinearGradient(colors: [
                KinrelColors.orange.withValues(alpha: 0.22),
                KinrelColors.orange.withValues(alpha: 0.08),
              ])
            : null,
        color: mine ? null : KinrelColors.darkElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: mine
              ? KinrelColors.orange.withValues(alpha: 0.55)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          KinrelIcon(icon,
              size: 13,
              color: mine ? KinrelColors.orange : KinrelColors.textDim),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: mine ? KinrelColors.textWhite : KinrelColors.textSilver,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Sportsmanship
// ═══════════════════════════════════════════════════════════════════════

class _SportsmanshipSection extends ConsumerStatefulWidget {
  const _SportsmanshipSection({
    required this.eco,
    required this.gameTable,
    required this.gameId,
    required this.familyId,
  });

  final MatchEcosystemResult? eco;
  final String gameTable;
  final String gameId;
  final String familyId;

  @override
  ConsumerState<_SportsmanshipSection> createState() =>
      _SportsmanshipSectionState();
}

class _SportsmanshipSectionState extends ConsumerState<_SportsmanshipSection> {
  final Set<String> _sentTo = {};

  @override
  Widget build(BuildContext context) {
    final client = ref.read(supabaseProvider);
    final myId = client?.auth.currentUser?.id;
    final eco = widget.eco;

    // Cheerable opponents = other players of this match.
    final others = (eco?.players ?? const <MatchPlayerResult>[])
        .where((p) => p.userId.isNotEmpty && p.userId != myId)
        .take(3)
        .toList();
    if (others.isEmpty || myId == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: KinrelColors.success.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const KinrelIcon(KinrelIconData.heart,
                  size: 16, color: KinrelColors.success),
              const SizedBox(width: 8),
              Text(
                'SAY WELL PLAYED',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  color: KinrelColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final p in others) _CheerRow(player: p),
        ],
      ),
    );
  }

  Widget _CheerRow({required MatchPlayerResult player}) {
    final sent = _sentTo.contains(player.userId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              player.userName.isEmpty ? 'Family member' : player.userName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textWhite,
              ),
            ),
          ),
          _CheerChip(
            icon: KinrelIconData.handshake,
            label: 'GG',
            sent: sent,
            onTap: () => _cheer(player, 'gg'),
          ),
          const SizedBox(width: 6),
          _CheerChip(
            icon: KinrelIconData.party,
            label: 'Well played',
            sent: sent,
            onTap: () => _cheer(player, 'well_played'),
          ),
          const SizedBox(width: 6),
          _CheerChip(
            icon: KinrelIconData.sparkle,
            label: 'Fun game',
            sent: sent,
            onTap: () => _cheer(player, 'fun_game'),
          ),
        ],
      ),
    );
  }

  Future<void> _cheer(MatchPlayerResult player, String kind) async {
    if (_sentTo.contains(player.userId)) return;
    setState(() => _sentTo.add(player.userId));
    final newBadges = await sendSportsmanship(
      ref: ref,
      matchId: widget.gameId,
      gameTable: widget.gameTable,
      familyId: widget.familyId,
      toUserId: player.userId,
      toName: player.userName,
      kind: kind,
    );
    if (!mounted) return;
    if (newBadges.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: KinrelColors.darkElevated,
          content: Row(
            children: [
              KinrelIcon(
                  kinrelIconFromEmoji(newBadges.first.icon) ??
                      KinrelIconData.medal,
                  size: 20,
                  color: KinrelColors.brightGold),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Badge earned: ${newBadges.first.name}!',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    color: KinrelColors.textWhite,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    // Refresh dashboard so hub reflects new sportsmanship + badges.
    ref.invalidate(gamingDashboardProvider);
  }
}

class _CheerChip extends StatelessWidget {
  const _CheerChip({
    required this.icon,
    required this.label,
    required this.sent,
    required this.onTap,
  });

  final KinrelIconData icon;
  final String label;
  final bool sent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: sent ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: sent
              ? KinrelColors.success.withValues(alpha: 0.16)
              : KinrelColors.darkElevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: sent
                ? KinrelColors.success
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            KinrelIcon(icon,
                size: 12,
                color: sent ? KinrelColors.success : KinrelColors.textDim),
            const SizedBox(width: 4),
            Text(
              sent ? 'Sent' : label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: sent ? KinrelColors.success : KinrelColors.textSilver,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
