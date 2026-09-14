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
import '../../../../family/presentation/add_member_source.dart';
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
  List<Map<String, dynamic>> _members = [];
  bool _loading = true;
  String? _error;
  String? _selectedOpponentId;
  String _selectedOpponentName = '';
  bool _creating = false;
  bool _spectatorsEnabled = true;
  int _autoCloseMinutes = 5;
  late Map<String, dynamic> _extraValues =
      Map<String, dynamic>.from(widget.spec.extraSettings?.defaults ?? const {});

  RoomControllerKey get _roomKey =>
      RoomControllerKey(widget.spec.roomConfig, widget.familyId);

  @override
  void initState() {
    super.initState();
    _loadFamilyMembers();
  }

  Future<void> _loadFamilyMembers() async {
    final client = ref.read(supabaseProvider);
    final myId = client?.auth.currentUser?.id;
    if (client == null || myId == null) {
      setState(() {
        _loading = false;
        _error = 'Not signed in';
      });
      return;
    }
    try {
      // Only real linked Kinrel accounts are listed (matches the
      // Family-Space invite flow).
      final resp = await client.rpc(
        'fn_get_linked_family_members',
        params: {'p_family_id': widget.familyId},
      ).timeout(const Duration(seconds: 15));

      final rows = (resp as List).cast<Map<String, dynamic>>();
      final members = rows.map((r) {
        final user = KinrelUser.fromJson(r);
        return {
          'userId': user.id,
          'name': user.name,
          'username': user.username,
          'avatarUrl': user.avatarUrl,
          'photoThumb': user.photoThumb,
        };
      }).toList();
      setState(() {
        _members = members;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
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
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: KinrelColors.orange),
            )
          : _error != null
              ? DKErrorState(message: _error!, onRetry: _loadFamilyMembers)
              : _members.isEmpty
                  ? DKEmptyState(
                      icon: Icons.group_outlined,
                      title: 'No family members to challenge',
                      subtitle:
                          'Invite family members to your family first, then come back to play ${spec.title}.',
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
                label: 'Select Opponent',
                child: Column(
                  children: [
                    for (int i = 0; i < _members.length; i++) ...[
                      if (i > 0) const SizedBox(height: 8),
                      _OpponentTile(
                        name: _members[i]['name'] as String,
                        isSelected:
                            _selectedOpponentId == _members[i]['userId'],
                        onTap: () {
                          GameMotionTokens.tap();
                          setState(() {
                            _selectedOpponentId = _members[i]['userId'] as String;
                            _selectedOpponentName = _members[i]['name'] as String;
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
    required this.name,
    required this.isSelected,
    required this.onTap,
  });

  final String name;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
              DKAvatar(
                initials: name.isNotEmpty ? name[0].toUpperCase() : '?',
                borderColor: isSelected ? KinrelColors.orange : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? KinrelColors.textWhite
                        : KinrelColors.textDim,
                  ),
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
