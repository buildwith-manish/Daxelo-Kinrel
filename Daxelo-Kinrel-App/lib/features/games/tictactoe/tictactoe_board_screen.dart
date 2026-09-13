// lib/features/games/tictactoe/tictactoe_board_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../game_motion_tokens.dart';
import '../shared/services/temporary_room_service.dart';
import '../shared/widgets/leave_game_dialog.dart';
import 'tictactoe_game_logic.dart';
import 'tictactoe_models.dart';
import 'tictactoe_provider.dart';

class TttBoardScreen extends ConsumerStatefulWidget {
  const TttBoardScreen({super.key, required this.familyId, required this.gameId});
  final String familyId; final String gameId;
  @override
  ConsumerState<TttBoardScreen> createState() => _TttBoardScreenState();
}

class _TttBoardScreenState extends ConsumerState<TttBoardScreen> {
  @override
  void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) { if (ref.read(tttProvider(widget.familyId)).game == null) ref.read(tttProvider(widget.familyId).notifier).loadGame(widget.gameId); }); }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tttProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;

    if (state.isCompleted) return _resultsView(state, myId);

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () async {
            final state = ref.read(tttProvider(widget.familyId));
            final shouldLeave = await LeaveGameDialog.show(
              context,
              isHost: false,
              gameName: 'Tic-Tac-Toe',
            );
            if (shouldLeave != true) return;
            if (!context.mounted) return;
            ref.read(tttProvider(widget.familyId).notifier).leaveGame();
            if (state.game?.id != null) {
              ref.read(temporaryRoomServiceProvider).endGame(
                    gameTable: 'tictactoe_games',
                    gameId: state.game!.id,
                  );
            }
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/family/${widget.familyId}');
            }
          },
        ),
        const SizedBox(height: KinrelSpacing.sm),
        DKButton(label: 'Back to Hub', variant: DKButtonVariant.secondary, fullWidth: true,
          onPressed: () {
            final gameId = ref.read(tttProvider(widget.familyId)).game?.id;
            ref.read(tttProvider(widget.familyId).notifier).leaveGame();
            if (gameId != null) {
              ref.read(temporaryRoomServiceProvider).endGame(gameTable: 'tictactoe_games', gameId: gameId);
            }
            if (context.mounted) context.go('/games?familyId=${widget.familyId}');
          }),
      ]),
    );
  }
}
