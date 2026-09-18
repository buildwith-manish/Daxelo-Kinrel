// lib/features/games/shared/widgets/lobby_join_handler.dart
//
// Cold-boot-safe ?join= deep-link handling for every game lobby.
//
// PROBLEM: opening (or RELOADING) a lobby URL that carries ?join=<gameId>
// can build the lobby screen BEFORE the Supabase auth session is restored
// from localStorage. Every game provider's joinGame() bails with a silent
// 'Not signed in' in that window — the join is dropped and the invited
// family member is stranded on the setup screen even though the room is
// live (same class of bug as Ghost Painter's cold-start f28fb88 and
// TugOfWar's loadGame retries).
//
// FIX: [joinRoomWhenReady] retries the join with backoff until the
// session is wired (bounded, ~7 s worst case), then hands the room id to
// the game's own join path exactly once.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/services/supabase_service.dart';

/// The ?join= room id from the current route, or null when absent.
String? currentJoinId(BuildContext context) {
  final joinId = GoRouterState.of(context).uri.queryParameters['join'];
  return (joinId == null || joinId.isEmpty) ? null : joinId;
}

/// Join a room from the route's ?join= param once the session is ready.
///
/// Call from a post-frame callback in the lobby's initState:
///
///     WidgetsBinding.instance.addPostFrameCallback((_) {
///       joinRoomWhenReady(
///         context: context,
///         ref: ref,
///         onJoin: (id) =>
///             ref.read(myProvider(widget.familyId).notifier).joinGame(id),
///       );
///     });
///
/// No-ops when there is no ?join= param. Retries up to [maxRetries]
/// times ([delayMs] apart) while the Supabase session is still null, so
/// cold-boot deep links land in the room instead of the setup screen.
void joinRoomWhenReady({
  required BuildContext context,
  required WidgetRef ref,
  required void Function(String gameId) onJoin,
  int maxRetries = 8,
  int delayMs = 900,
}) {
  final joinId = currentJoinId(context);
  if (joinId == null) return;
  _attempt(context, ref, joinId, onJoin, 0, maxRetries, delayMs);
}

void _attempt(
  BuildContext context,
  WidgetRef ref,
  String joinId,
  void Function(String gameId) onJoin,
  int attempt,
  int maxRetries,
  int delayMs,
) {
  void step() {
    if (!context.mounted) return;
    final signedIn =
        ref.read(supabaseProvider)?.auth.currentUser?.id != null;
    if (signedIn || attempt >= maxRetries) {
      if (!signedIn) {
        debugPrint('[LobbyJoin] session never appeared after $attempt '
            'retries — attempting join anyway (provider will surface the '
            'auth error)');
      }
      onJoin(joinId);
      return;
    }
    debugPrint('[LobbyJoin] session not ready — retrying join '
        '(${attempt + 1}/$maxRetries)');
    _attempt(context, ref, joinId, onJoin, attempt + 1, maxRetries, delayMs);
  }

  if (attempt == 0) {
    step();
  } else {
    Future.delayed(Duration(milliseconds: delayMs), step);
  }
}
