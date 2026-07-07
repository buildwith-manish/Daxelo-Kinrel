// lib/features/games/tictactoe/tictactoe_lobby_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/network/socket_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../game_motion_tokens.dart';
import '../shared/models/game_invite.dart';
import '../../family/presentation/add_member_source.dart';
import 'tictactoe_provider.dart';

class TttLobbyScreen extends ConsumerStatefulWidget {
  const TttLobbyScreen({super.key, required this.familyId});
  final String familyId;
  @override
  ConsumerState<TttLobbyScreen> createState() => _TttLobbyScreenState();
}

class _TttLobbyScreenState extends ConsumerState<TttLobbyScreen> {
  List<Map<String, dynamic>> _members = []; bool _loading = true; String? _error;
  String? _opponentId; String _opponentName = ''; int _bestOf = 1; bool _creating = false;

  @override
  void initState() { super.initState(); _loadMembers(); }

  Future<void> _loadMembers() async {
    final client = ref.read(supabaseProvider); final myId = client?.auth.currentUser?.id;
    if (client == null || myId == null) { setState(() { _loading = false; _error = 'Not signed in'; }); return; }
    try {
      // Use the Find-on-Kinrel-linked members RPC so only real linked
      // Kinrel accounts are listed (matches the Family-Space invite flow).
      final resp = await client.rpc('fn_get_linked_family_members', params: {'p_family_id': widget.familyId}).timeout(const Duration(seconds: 15));
      final rows = (resp as List).cast<Map<String, dynamic>>();
      setState(() { _members = rows.map((r) { final u = KinrelUser.fromJson(r); return <String, dynamic>{'userId': u.id, 'name': u.name, 'username': u.username, 'avatarUrl': u.avatarUrl, 'photoThumb': u.photoThumb}; }).toList(); _loading = false; });
    } catch (e) { setState(() { _loading = false; _error = '$e'; }); }
  }

  Future<void> _createGame() async {
    if (_opponentId == null) return;
    setState(() => _creating = true);
    final gameId = await ref.read(tttProvider(widget.familyId).notifier).createGame(opponentId: _opponentId!, opponentName: _opponentName, bestOf: _bestOf);
    if (mounted) {
      // Send a real-time invite so the opponent sees a "Tic-Tac-Toe" challenge
      // dialog and can jump straight into the board.
      if (gameId != null) {
        final client = ref.read(supabaseProvider);
        final myId = client?.auth.currentUser?.id ?? '';
        final myName = (client?.auth.currentUser?.userMetadata?['name'] as String?) ?? 'A family member';
        final code = gameId.replaceAll('-', '').substring(0, 6).toUpperCase();
        final invite = GameInvite(
          inviteId: 'inv_${DateTime.now().millisecondsSinceEpoch}_${_opponentId!.substring(0, 8)}',
          gameType: GameType.tictactoe, gameId: gameId, roomCode: code,
          familyId: widget.familyId, fromUserId: myId, fromName: myName,
          maxPlayers: 2, currentPlayers: 1,
          message: '$myName challenged you to Tic-Tac-Toe',
          timestamp: DateTime.now().toUtc(),
        );
        try {
          await ref.read(socketServiceProvider).sendGameInvite(toUserId: _opponentId!, invite: invite);
        } catch (_) {}
        context.pushReplacement('/family/${widget.familyId}/tictactoe/board/$gameId');
      }
      setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop()),
        title: Text('Tic-Tac-Toe', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
        backgroundColor: KinrelColors.darkCard, foregroundColor: KinrelColors.textWhite, elevation: 0,
      ),
      body: _loading ? const Center(child: CircularProgressIndicator(color: KinrelColors.orange))
        : _error != null ? DKErrorState(message: _error!, onRetry: _loadMembers)
        : _members.isEmpty ? DKEmptyState(icon: Icons.group_outlined, title: 'No family members to challenge', subtitle: 'Invite family members first.')
        : ListView(padding: const EdgeInsets.all(KinrelSpacing.base), children: [
          Text('Challenge a Family Member', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 18, fontWeight: FontWeight.w700, color: KinrelColors.textWhite)),
          const SizedBox(height: 4),
          Text('You\'ll play as X (moves first). Opponent plays as O.', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim)),
          const SizedBox(height: KinrelSpacing.lg),
          // Best of selector
          Text('BEST OF', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 11, fontWeight: FontWeight.w700, color: KinrelColors.textDim, letterSpacing: 1.5)),
          const SizedBox(height: KinrelSpacing.sm),
          Wrap(spacing: 8, children: [1, 3, 5].map((n) {
            final sel = n == _bestOf;
            return GestureDetector(onTap: () { GameMotionTokens.tap(); setState(() => _bestOf = n); },
              child: Container(width: 60, padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: sel ? KinrelColors.orange : KinrelColors.border, width: sel ? 2 : 1)),
                child: Center(child: Text('$n', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 16, fontWeight: FontWeight.w700, color: sel ? KinrelColors.orange : KinrelColors.textDim)))));
          }).toList()),
          const SizedBox(height: KinrelSpacing.lg),
          Text('SELECT OPPONENT', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 11, fontWeight: FontWeight.w700, color: KinrelColors.textDim, letterSpacing: 1.5)),
          const SizedBox(height: KinrelSpacing.sm),
          ..._members.map((m) {
            final sel = _opponentId == m['userId'];
            return GestureDetector(onTap: () { GameMotionTokens.tap(); setState(() { _opponentId = m['userId']; _opponentName = m['name']; }); },
              child: Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: sel ? KinrelColors.orange : KinrelColors.border, width: sel ? 2 : 1)),
                child: Row(children: [
                  DKAvatar(initials: m['name'][0].toUpperCase(), borderColor: sel ? KinrelColors.orange : null),
                  const SizedBox(width: 10),
                  Expanded(child: Text(m['name'], style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, fontWeight: FontWeight.w600, color: sel ? KinrelColors.textWhite : KinrelColors.textDim))),
                  if (sel) Icon(Icons.check_circle, color: KinrelColors.orange, size: 20),
                ])));
          }),
          const SizedBox(height: KinrelSpacing.xl),
          DKButton(label: _opponentId == null ? 'Select an opponent' : 'Challenge $_opponentName',
            variant: DKButtonVariant.gradient, fullWidth: true, isLoading: _creating, onPressed: _opponentId == null ? null : _createGame),
        ]),
    );
  }
}
