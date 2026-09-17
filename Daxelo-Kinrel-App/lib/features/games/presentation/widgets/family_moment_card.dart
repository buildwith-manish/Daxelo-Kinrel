// lib/features/games/presentation/widgets/family_moment_card.dart
//
// FamilyMomentCard — Zone 3 of the 3-zone Family Arena home screen.
//
// Replaces the plain log-list `GamingActivityTile` with a lightweight
// social feed card. Each moment shows:
//   • Larger avatar + actorName + timestamp (reads as a feed, not a log)
//   • Description (privacy-respecting — see note below)
//   • ❤️ / 👏 reaction buttons with optimistic UI update on tap, revert on
//     failure. Reaction counts appear once > 0.
//
// PRIVACY (unchanged from the prior reframe):
//   • Entries about match RESULTS respect the participant gate. The
//     backend continues to log the event in FamilyActivityLog; this
//     widget receives the actorUserId + metadata.participants (when
//     present) and the requesting user's id, and swaps result-revealing
//     copy for non-participants to "X and Y played together" phrasing.
//     Result-revealing entries for non-participants are NOT rendered at
//     all if no neutral phrasing is available.
//   • Reaction counts and the viewer's own reaction state are returned
//     by fn_get_family_gaming_activity_v2.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../gaming_ecosystem/data/gaming_models.dart';
import '../../games/shared/icons/kinrel_icons.dart';

/// Extended ActivityEntry that includes reaction counts + the viewer's
/// own reactions (from fn_get_family_gaming_activity_v2).
class FamilyMoment {
  const FamilyMoment({
    required this.id,
    required this.action,
    required this.description,
    required this.createdAt,
    this.actorUserId,
    this.actorName,
    this.metadata = const {},
    this.reactionCounts = const {},
    this.myReactions = const [],
  });

  final String id;
  final String action;
  final String description;
  final DateTime? createdAt;
  final String? actorUserId;
  final String? actorName;
  final Map<String, dynamic> metadata;

  /// Per-type counts: { "heart": 2, "clap": 1 }.
  final Map<String, int> reactionCounts;

  /// Reaction types the current viewer has left on this moment.
  final List<String> myReactions;

  /// Whether the moment description references a match result. If true and
  /// the requesting user is NOT in metadata.participants, the card swaps
  /// to a neutral phrasing ("X and Y played together") and hides the
  /// result-revealing copy. If no neutral phrasing is constructible, the
  /// card hides the entry entirely (returns null from shouldRender).
  bool get isResultRevealing {
    switch (action) {
      case 'game_match_completed':
      case 'game_cup_won':
        return true;
      default:
        return false;
    }
  }

  /// The participant userIds when available in metadata.
  List<String> get participantUserIds {
    final raw = metadata['participants'];
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).toList(growable: false);
  }

  /// Returns true if this moment should be rendered for the given viewer.
  /// Non-participants never see result-revealing moments that have no
  /// neutral phrasing available.
  bool shouldRenderFor(String? viewerUserId) {
    if (!isResultRevealing) return true;
    // Result-revealing: render only if the viewer is a participant OR
    // metadata allows a neutral phrasing (currently we allow neutral
    // phrasing whenever participants list has >= 2 entries — we can name
    // both players without revealing who won).
    if (viewerUserId == null) return false;
    if (participantUserIds.contains(viewerUserId)) return true;
    return participantUserIds.length >= 2;
  }

  /// Returns the description that should be shown to the given viewer.
  /// For non-participants viewing a result-revealing moment, swaps to a
  /// neutral phrasing.
  String descriptionFor(String? viewerUserId) {
    if (!isResultRevealing) return description;
    if (viewerUserId != null && participantUserIds.contains(viewerUserId)) {
      return description;
    }
    // Build neutral phrasing from participants if available.
    if (participantUserIds.length >= 2) {
      final names = metadata['participantNames'];
      if (names is List && names.length >= 2) {
        final a = names[0].toString();
        final b = names[1].toString();
        final more = names.length > 2 ? ' +${names.length - 2}' : '';
        return '$a and $b$more played together';
      }
    }
    // Fallback: hide the result detail, show a generic participation line.
    return 'Family played together';
  }

  factory FamilyMoment.fromJson(Map<String, dynamic> json) {
    final rawCounts = json['reactionCounts'];
    final Map<String, int> counts = {};
    if (rawCounts is Map) {
      rawCounts.forEach((k, v) {
        counts[k.toString()] = v is num ? v.toInt() : 0;
      });
    }
    final rawMine = json['myReactions'];
    final List<String> mine = (rawMine is List)
        ? rawMine.map((e) => e.toString()).toList(growable: false)
        : const [];
    return FamilyMoment(
      id: (json['id'] as String?) ?? '',
      action: (json['action'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.tryParse(json['createdAt'].toString()),
      actorUserId: json['actorUserId'] as String?,
      actorName: json['actorName'] as String?,
      metadata: json['metadata'] is Map
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : const {},
      reactionCounts: counts,
      myReactions: mine,
    );
  }
}

/// Riverpod provider that fetches v2 activity (with reaction counts + the
/// viewer's own reactions) for the Family Moments feed.
final familyMomentsProvider = FutureProvider.autoDispose
    .family<List<FamilyMoment>, String>((ref, familyId) async {
  final client = ref.watch(supabaseProvider);
  if (client == null) return const <FamilyMoment>[];
  try {
    final raw = await client.rpc('fn_get_family_gaming_activity_v2', params: {
      'p_family_id': familyId,
      'p_limit': 30,
      'p_offset': 0,
    });
    if (raw is! List) return const <FamilyMoment>[];
    return raw
        .whereType<Map>()
        .map((e) => FamilyMoment.fromJson(Map<String, dynamic>.from(e)))
        .where((m) => m.id.isNotEmpty)
        .toList();
  } catch (_) {
    return const <FamilyMoment>[];
  }
});

/// The set of reaction types surfaced on each moment card. Kept small per
/// the spec ("start with just these two to keep scope small").
const List<String> kMomentReactionTypes = ['heart', 'clap'];

/// The FamilyMomentCard widget. Renders one moment with reaction buttons.
///
/// Reactions update optimistically: tapping a reaction button immediately
/// flips the local state, then calls fn_toggle_moment_reaction. On
/// failure, the local state is reverted.
class FamilyMomentCard extends ConsumerStatefulWidget {
  const FamilyMomentCard({super.key, required this.moment});
  final FamilyMoment moment;

  @override
  ConsumerState<FamilyMomentCard> createState() => _FamilyMomentCardState();
}

class _FamilyMomentCardState extends ConsumerState<FamilyMomentCard> {
  // Local optimistic state — initialized from the server, then mutated
  // immediately on tap. Reverted if the toggle RPC fails.
  late Map<String, int> _counts;
  late Set<String> _mine;

  @override
  void initState() {
    super.initState();
    _counts = Map<String, int>.from(widget.moment.reactionCounts);
    _mine = Set<String>.from(widget.moment.myReactions);
  }

  @override
  void didUpdateWidget(covariant FamilyMomentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.moment.reactionCounts != widget.moment.reactionCounts ||
        oldWidget.moment.myReactions != widget.moment.myReactions) {
      _counts = Map<String, int>.from(widget.moment.reactionCounts);
      _mine = Set<String>.from(widget.moment.myReactions);
    }
  }

  Future<void> _toggle(String reactionType) async {
    final client = ref.read(supabaseProvider);
    if (client == null) return;
    final wasActive = _mine.contains(reactionType);

    // Optimistic update.
    setState(() {
      if (wasActive) {
        _mine.remove(reactionType);
        final cur = _counts[reactionType] ?? 0;
        if (cur <= 1) {
          _counts.remove(reactionType);
        } else {
          _counts[reactionType] = cur - 1;
        }
      } else {
        _mine.add(reactionType);
        _counts[reactionType] = (_counts[reactionType] ?? 0) + 1;
      }
    });

    try {
      final raw = await client.rpc('fn_toggle_moment_reaction', params: {
        'p_moment_id': widget.moment.id,
        // We don't have the familyId on the moment model — derive from
        // metadata or pass through. The toggle RPC accepts it for the RLS
        // check; we use metadata.familyId when present, else fall back to
        // an empty string (the RPC will reject if the family check fails).
        'p_family_id': (widget.moment.metadata['familyId'] as String?) ?? '',
        'p_reaction_type': reactionType,
      });
      // Confirm with server response — if it failed, revert.
      if (raw is! Map) throw StateError('Invalid RPC response');
      final ok = raw['ok'] as bool? ?? false;
      if (!ok) throw StateError('RPC rejected reaction toggle');
      // Reconcile local state with the authoritative server response.
      final serverCounts = raw['reactionCounts'];
      final serverMine = raw['myReactions'];
      if (mounted) {
        setState(() {
          _counts = <String, int>{};
          if (serverCounts is Map) {
            serverCounts.forEach((k, v) {
              _counts[k.toString()] = v is num ? v.toInt() : 0;
            });
          }
          _mine = (serverMine is List)
              ? serverMine.map((e) => e.toString()).toSet()
              : <String>{};
        });
      }
    } catch (_) {
      // Revert on failure.
      if (mounted) {
        setState(() {
          _counts = Map<String, int>.from(widget.moment.reactionCounts);
          _mine = Set<String>.from(widget.moment.myReactions);
        });
        // Brief shake to signal the revert.
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('Couldn\'t react — try again'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.moment;
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final description = m.descriptionFor(myId);
    if (!m.shouldRenderFor(myId)) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _MomentAvatar(name: m.actorName ?? 'Family'),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      m.actorName ?? 'Family Member',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    Text(
                      _timeAgo(m.createdAt),
                      style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 10,
                        color: KinrelColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
              _MomentActionIcon(action: m.action),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13.5,
              height: 1.35,
              color: KinrelColors.textSilver,
            ),
          ),
          const SizedBox(height: 8),
          _ReactionRow(
            counts: _counts,
            mine: _mine,
            onToggle: _toggle,
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 250.ms)
        .slideY(begin: 0.03, end: 0, duration: 250.ms);
  }

  String _timeAgo(DateTime? t) {
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return '${d.inDays ~/ 7}w ago';
  }
}

class _MomentAvatar extends StatelessWidget {
  const _MomentAvatar({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            KinrelColors.orange.withValues(alpha: 0.45),
            KinrelColors.amber.withValues(alpha: 0.25),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: KinrelColors.textWhite,
          ),
        ),
      ),
    );
  }
}

class _MomentActionIcon extends StatelessWidget {
  const _MomentActionIcon({required this.action});
  final String action;

  @override
  Widget build(BuildContext context) {
    final iconData = _iconFor(action);
    final color = _colorFor(action);
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Center(
        child: KinrelIcon(iconData, size: 14, color: color),
      ),
    );
  }

  KinrelIconData _iconFor(String action) {
    switch (action) {
      case 'game_match_completed':
        return KinrelIconData.controller;
      case 'game_badge_earned':
      case 'game_cup_won':
        return KinrelIconData.medal;
      case 'game_challenge_completed':
        return KinrelIconData.flag;
      case 'game_milestone_reached':
        return KinrelIconData.trophy;
      case 'game_sportsmanship':
        return KinrelIconData.heart;
      default:
        return KinrelIconData.sparkle;
    }
  }

  Color _colorFor(String action) {
    switch (action) {
      case 'game_badge_earned':
      case 'game_cup_won':
        return KinrelColors.brightGold;
      case 'game_challenge_completed':
        return const Color(0xFF8B5CF6);
      case 'game_milestone_reached':
        return KinrelColors.gold;
      case 'game_sportsmanship':
        return KinrelColors.success;
      default:
        return KinrelColors.orange;
    }
  }
}

class _ReactionRow extends StatelessWidget {
  const _ReactionRow({
    required this.counts,
    required this.mine,
    required this.onToggle,
  });

  final Map<String, int> counts;
  final Set<String> mine;
  final void Function(String) onToggle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final type in kMomentReactionTypes)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: _ReactionButton(
              type: type,
              count: counts[type] ?? 0,
              active: mine.contains(type),
              onTap: () => onToggle(type),
            ),
          ),
      ],
    );
  }
}

class _ReactionButton extends StatelessWidget {
  const _ReactionButton({
    required this.type,
    required this.count,
    required this.active,
    required this.onTap,
  });

  final String type;
  final int count;
  final bool active;
  final VoidCallback onTap;

  String get _glyph {
    switch (type) {
      case 'heart':
        return '❤';
      case 'clap':
        return '👏';
      default:
        return '?';
    }
  }

  Color get _activeColor {
    switch (type) {
      case 'heart':
        return KinrelColors.error;
      case 'clap':
        return KinrelColors.amber;
      default:
        return KinrelColors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = active ? _activeColor : KinrelColors.textDim;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active
              ? _activeColor.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active
                ? _activeColor.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _glyph,
              style: TextStyle(
                fontSize: 12,
                color: color,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(
                '$count',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
