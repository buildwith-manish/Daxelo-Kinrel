// lib/features/games/shared/widgets/lobby_kit/challenge_lobby_screen.dart
//
// ChallengeLobbyScreen — the unified head-to-head challenge lobby used
// by the 4 board games (Chess, Checkers, Tic-Tac-Toe, Carrom).
//
// One shared screen replaces the four near-identical ~400-line
// copy-pasted challenge lobbies. Each game now supplies only:
//   • identity (icon, title, tagline, piece-color note),
//   • its rules list,
//   • an onCreateGame callback that calls its own provider,
//   • optional extra settings (Tic-Tac-Toe's BEST OF).
//
// Layout contract (identical to the temporary-room lobbies):
//   compact hero → opponent list (primary decision) → game settings →
//   room options (spectators + auto-close) → collapsible How to Play →
//   PINNED "Challenge <name>" CTA that never scrolls away.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/constants/brand_colors.dart';
import '../../../../../core/constants/brand_typography.dart';
import '../../../../../core/network/socket_service.dart';
import '../../../../../core/services/supabase_service.dart';
import '../../../../../shared/widgets/dk_components.dart';
import '../../../game_motion_tokens.dart';
import '../../models/game_invite.dart';
import '../../multiplayer/multiplayer.dart';
import '../../../../presence/last_seen_provider.dart';
import '../../providers/family_invite_members_provider.dart';
import '../../../../../core/constants/brand_spacing.dart';
import 'how_to_play_card.dart';
import 'lobby_hero.dart';
import 'lobby_sections.dart';
import 'lobby_setup_screen.dart';

/// Arguments handed to the game's create callback.
class ChallengeArgs {
  const ChallengeArgs({
    required this.opponentId,
    required this.opponentName,
    required this.spectatorsEnabled,
    required this.autoCloseMinutes,
    this.extra = const {},
  });

  final String opponentId;
  final String opponentName;
  final bool spectatorsEnabled;
  final int autoCloseMinutes;

  /// Game-specific extras (e.g. {'bestOf': 3} for Tic-Tac-Toe).
  final Map<String, dynamic> extra;
}

/// Creates the game via the game's own provider. Returns the new game id
/// (or null on failure — the shared screen then just re-enables the CTA).
typedef ChallengeCreateGame = Future<String?> Function(
  WidgetRef ref,
  String familyId,
  ChallengeArgs args,
);

/// Optional game-specific settings block (BEST OF selector…).
class ChallengeExtraSettings {
  const ChallengeExtraSettings({
    required this.defaults,
    required this.builder,
  });

  /// Initial values handed to the builder and back via args.extra.
  final Map<String, dynamic> defaults;

  /// Renders the settings; mutate values via onChanged.
  final Widget Function(
    Map<String, dynamic> values,
    void Function(Map<String, dynamic> values) onChanged,
  ) builder;
}

/// Everything the shared challenge screen needs to know about one game.
class ChallengeLobbySpec {
  const ChallengeLobbySpec({
    required this.gameId,
    required this.title,
    required this.tagline,
    required this.versusNote,
    required this.gameType,
    required this.routeSegment,
    required this.roomConfig,
    required this.rules,
    required this.onCreateGame,
    this.facts,
    this.extraSettings,
  });

  /// 'chess' — icon asset + accent color.
  final String gameId;

  /// 'Chess' — hero title + app bar title.
  final String title;

  /// Hero tagline ('Head-to-head · first to checkmate').
  final String tagline;

  /// Explains the player's side ('You play White and move first.').
  final String versusNote;

  final GameType gameType;

  /// Route segment for the board (`chess` → `/family/x/chess/board/<id>`).
  final String routeSegment;

  /// RoomConfig for the shared room-lifecycle controller.
  final RoomConfig roomConfig;

  final List<LobbyRule> rules;
  final List<LobbyFact>? facts;
  final ChallengeCreateGame onCreateGame;
  final ChallengeExtraSettings? extraSettings;
}

class ChallengeLobbyScreen extends ConsumerStatefulWidget {
  const ChallengeLobbyScreen({
    super.key,
    required this.familyId,
    required this.spec,
  });

  final String familyId;
  final ChallengeLobbySpec spec;

  @override
  ConsumerState<ChallengeLobbyScreen> createState() =>
      _ChallengeLobbyScreenState();
}

class _ChallengeLobbyScreenState extends ConsumerState<ChallengeLobbyScreen> {
  String? _selectedOpponentId;
  String _selectedOpponentName = '';
  bool _creating = false;
  bool _spectatorsEnabled = true;
  int _autoCloseMinutes = 5;
  late Map<String, dynamic> _extraValues =
      Map<String, dynamic>.from(widget.spec.extraSettings?.defaults ?? const {});

  RoomControllerKey get _roomKey =>
      RoomControllerKey(widget.spec.roomConfig, widget.familyId);

  // Members come from the shared familyInviteMembersProvider — the
  // membership-source RPC (FamilyMember JOIN User + linked Persons)
  // with realtime sync: the opponent list refreshes automatically when
  // members are added / removed / linked. Live online status comes
  // from lastSeenProvider (UserPresence realtime).
  FamilyInviteMembersState get _memberState =>
      ref.watch(familyInviteMembersProvider(widget.familyId));

  /// Opponents sorted online-first (a live opponent accepts fastest).
  List<FamilyInviteMember> get _opponents {
    final presenceMap = ref.watch(lastSeenProvider);
    final members = _memberState.members
        .map((m) {
      final live = presenceMap[m.user.id];
      if (live == null) return m;
      return m.copyWith(isOnline: live.isOnline, lastSeenAt: live.lastSeenAt);
    })
        .toList()
      ..sort((a, b) {
        final aOnline = (a.isOnline ?? false) ? 1 : 0;
        final bOnline = (b.isOnline ?? false) ? 1 : 0;
        if (aOnline != bOnline) return bOnline - aOnline;
        return (a.user.name).compareTo(b.user.name);
      });
    return members;
  }

  Future<void> _createGame() async {
    if (_selectedOpponentId == null) return;
    setState(() => _creating = true);
    try {
      final gameId = await widget.spec.onCreateGame(
        ref,
        widget.familyId,
        ChallengeArgs(
          opponentId: _selectedOpponentId!,
          opponentName: _selectedOpponentName,
          spectatorsEnabled: _spectatorsEnabled,
          autoCloseMinutes: _autoCloseMinutes,
          extra: Map<String, dynamic>.from(_extraValues),
        ),
      );
      if (gameId != null) {
        await _sendInvite(gameId);
        // Attach the shared multiplayer room-lifecycle framework
        // (auto-close deadline, spectator flag, host-ready, host join).
        // Must happen BEFORE pushReplacement so the board screen sees
        // the room columns set on the game row.
        await ref.read(roomControllerProvider(_roomKey).notifier)
            .attachToExistingGame(
          gameId,
          spectatorsEnabled: _spectatorsEnabled,
          autoCloseMinutes: _autoCloseMinutes,
        );
        if (!mounted) return;
        context.pushReplacement(
          '/family/${widget.familyId}/${widget.spec.routeSegment}/board/$gameId',
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _sendInvite(String gameId) async {
    final client = ref.read(supabaseProvider);
    final myId = client?.auth.currentUser?.id ?? '';
    final myName =
        (client?.auth.currentUser?.userMetadata?['name'] as String?) ??
            'A family member';
    final code = gameId.replaceAll('-', '').substring(0, 6).toUpperCase();
    final invite = GameInvite(
      inviteId:
          'inv_${DateTime.now().millisecondsSinceEpoch}_${_selectedOpponentId!.substring(0, 8)}',
      gameType: widget.spec.gameType,
      gameId: gameId,
      roomCode: code,
      familyId: widget.familyId,
      fromUserId: myId,
      fromName: myName,
      maxPlayers: 2,
      currentPlayers: 1,
      message: '$myName challenged you to ${widget.spec.title}',
      timestamp: DateTime.now().toUtc(),
    );
    try {
      await ref
          .read(socketServiceProvider)
          .sendGameInvite(toUserId: _selectedOpponentId!, invite: invite);
    } catch (_) {
      // best-effort — game was created, opponent will see it via Realtime
    }
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/family/${widget.familyId}');
            }
          },
        ),
        title: Text(
          spec.title,
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontWeight: FontWeight.w600,
            color: KinrelColors.textWhite,
          ),
        ),
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
      ),
      body: _memberState.loading
          ? const Center(
              child: CircularProgressIndicator(color: KinrelColors.orange),
            )
          : _memberState.error != null
              ? DKErrorState(
                  message: _memberState.error!,
                  onRetry: () => ref
                      .read(familyInviteMembersProvider(widget.familyId)
                          .notifier)
                      .load(),
                )
              : _memberState.members.isEmpty
                  ? DKEmptyState(
                      icon: Icons.group_outlined,
                      title: _memberState.stats.membershipCount > 1
                          ? 'No linked Kinrel accounts yet'
                          : 'No family members to challenge',
                      subtitle: _memberState.stats.membershipCount > 1
                          ? 'Members in this family haven\'t linked Kinrel '
                              'accounts yet — invite them to join Kinrel, then '
                              'come back to play ${spec.title}.'
                          : 'Invite family members to your family first, then '
                              'come back to play ${spec.title}.',
                    )
                  : _body(),
    );
  }

  Widget _body() {
    final spec = widget.spec;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              LobbyHero(
                gameId: spec.gameId,
                title: spec.title,
                tagline: spec.tagline,
                facts: spec.facts,
              ),
              const SizedBox(height: 12),
              LobbyInfoNote(
                icon: Icons.swap_horiz_rounded,
                text: spec.versusNote,
              ),

              // ── Primary decision: who to challenge ─────────────────
              const SizedBox(height: 16),
              LobbySection(
                label:
                    'Select Opponent  ·  ${_opponents.length} member${_opponents.length == 1 ? '' : 's'}  ·  ${_memberState.onlineCount} online',
                child: Column(
                  children: [
                    for (int i = 0; i < _opponents.length; i++) ...[
                      if (i > 0) const SizedBox(height: 8),
                      _OpponentTile(
                        member: _opponents[i],
                        isSelected:
                            _selectedOpponentId == _opponents[i].user.id,
                        onTap: () {
                          GameMotionTokens.tap();
                          setState(() {
                            _selectedOpponentId = _opponents[i].user.id;
                            _selectedOpponentName = _opponents[i].user.name;
                          });
                        },
                      ),
                    ],
                  ],
                ),
              ),

              // ── Game-specific extras (BEST OF…) ─────────────────────
              if (spec.extraSettings != null) ...[
                const SizedBox(height: 16),
                spec.extraSettings!.builder(
                  _extraValues,
                  (v) => setState(() => _extraValues = v),
                ),
              ],

              // ── Room options: spectators + auto-close ───────────────
              const SizedBox(height: 16),
              LobbySection(
                label: 'Room',
                child: Column(
                  children: [
                    LobbySwitchRow(
                      icon: Icons.visibility_outlined,
                      label: 'Allow spectators',
                      caption: _spectatorsEnabled
                          ? 'Family can watch read-only'
                          : 'Only players can see the game',
                      value: _spectatorsEnabled,
                      onChanged: (v) =>
                          setState(() => _spectatorsEnabled = v),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'AUTO-CLOSE ROOM AFTER',
                      style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: KinrelColors.textDim,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    LobbyNumberRow(
                      numbers: const [3, 5, 10, 15],
                      selected: _autoCloseMinutes,
                      onSelect: (n) =>
                          setState(() => _autoCloseMinutes = n),
                      suffix: ' min',
                    ),
                  ],
                ),
              ),

              // ── Collapsible rules ───────────────────────────────────
              const SizedBox(height: 16),
              HowToPlayCard(gameId: spec.gameId, rules: spec.rules),
              const SizedBox(height: 12),
            ],
          ),
        ),

        // ── Pinned primary action ────────────────────────────────────
        LobbyPinnedCtaBar(
          label: _selectedOpponentId == null
              ? 'Select an opponent'
              : 'Challenge $_selectedOpponentName',
          hint: _selectedOpponentId == null
              ? 'Pick a family member above to send them a challenge'
              : '$_selectedOpponentName gets a live challenge notification',
          loading: _creating,
          enabled: _selectedOpponentId != null,
          onPressed: _createGame,
        ),
      ],
    );
  }
}

class _OpponentTile extends StatelessWidget {
  const _OpponentTile({
    required this.member,
    required this.isSelected,
    required this.onTap,
  });

  /// The family member being offered as an opponent — carries avatar,
  /// username and live online status.
  final FamilyInviteMember member;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isOnline = member.isOnline ?? false;
    final name = member.user.name;
    return Material(
      color: isSelected
          ? KinrelColors.orange.withValues(alpha: 0.08)
          : KinrelColors.darkCard,
      borderRadius: BorderRadius.circular(KinrelRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KinrelRadius.md),
            border: Border.all(
              color: isSelected ? KinrelColors.orange : KinrelColors.border,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              // Avatar with live online dot.
              SizedBox(
                width: 44,
                height: 44,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _OpponentAvatar(member: member),
                    Positioned(
                      right: -1,
                      bottom: -1,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: isOnline
                              ? const Color(0xFF22C55E)
                              : KinrelColors.darkElevated,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isOnline
                                ? KinrelColors.darkCard
                                : KinrelColors.border,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color:
                            isSelected ? KinrelColors.textWhite : KinrelColors.textDim,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Row(children: [
                      if (member.user.username != null &&
                          member.user.username!.isNotEmpty) ...[
                        Flexible(
                          child: Text(
                            '@${member.user.username}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: KinrelTypography.monoFont,
                              fontSize: 11,
                              color: KinrelColors.orange,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          isOnline ? 'online' : 'offline',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 11,
                            fontWeight:
                                isOnline ? FontWeight.w600 : FontWeight.w400,
                            color: isOnline
                                ? const Color(0xFF22C55E)
                                : KinrelColors.textDim,
                          ),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
              if (isSelected)
                const Icon(
                  Icons.check_circle,
                  color: KinrelColors.orange,
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Avatar for an opponent tile: photo when available, initials otherwise.
class _OpponentAvatar extends StatelessWidget {
  const _OpponentAvatar({required this.member});

  final FamilyInviteMember member;

  @override
  Widget build(BuildContext context) {
    final photo = member.user.photoThumb ?? member.user.avatarUrl;
    if (photo != null && photo.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          photo,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              _initialsAvatar(context, member.user.initials),
        ),
      );
    }
    return _initialsAvatar(context, member.user.initials);
  }

  Widget _initialsAvatar(BuildContext context, String initials) {
    return DKAvatar(
      initials: initials,
      borderColor: Colors.transparent,
    );
  }
}