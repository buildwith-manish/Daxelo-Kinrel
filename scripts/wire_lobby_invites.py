#!/usr/bin/env python3
"""
Wire up the Invite button into each "share code" style game lobby screen.

For each lobby file, this script:
1. Adds two imports after the existing 'game_motion_tokens.dart' import:
   - '../shared/models/game_invite.dart'
   - '../shared/widgets/invite_family_sheet.dart'
2. Inserts an Invite IconButton BEFORE the existing Share Code IconButton
   in the AppBar actions, gated on `hasGame && isHost`.

Per-game configuration:
   - game_id_expr: the expression for the game/room UUID
   - room_code_expr: the expression for the 6-char display code
   - max_players_expr: the expression for max players
   - players_expr: the expression for the players list (e.g. state.players, state.allCards)
   - player_id_field: which field on each player gives the userId
   - game_type_enum: GameType.xxx
   - state_var: usually 'state' but checkers uses different patterns

The lobbies covered (10):
   - ludo, sos, antakshari, truthordare, twotruths, dotsboxes,
     nameplace, chitmatch, redlight
"""
import re
from pathlib import Path

LOBBIES = [
    # (file, game_id_expr, room_code_expr, max_players_expr, players_expr,
    #  player_id_field, game_type_enum, state_var, has_state_object)
    {
        'file': 'lib/features/games/ludo/ludo_lobby_screen.dart',
        'game_id_expr': "state.game?.id ?? ''",
        'room_code_expr': "state.game?.id != null ? state.game!.id.replaceAll('-', '').substring(0, 6).toUpperCase() : '------'",
        'max_players_expr': 'state.game?.playerCount ?? 4',
        'players_expr': 'state.players',
        'player_id_field': 'userId',
        'game_type_enum': 'GameType.ludo',
        'state_var': 'state',
    },
    {
        'file': 'lib/features/games/sos/sos_lobby_screen.dart',
        'game_id_expr': "state.game?.id ?? ''",
        'room_code_expr': "state.game?.id != null ? state.game!.id.replaceAll('-', '').substring(0, 6).toUpperCase() : '------'",
        'max_players_expr': 'mode.maxPlayers',
        'players_expr': 'state.players',
        'player_id_field': 'userId',
        'game_type_enum': 'GameType.sos',
        'state_var': 'state',
    },
    {
        'file': 'lib/features/games/antakshari/antakshari_lobby_screen.dart',
        'game_id_expr': "state.game?.id ?? ''",
        'room_code_expr': "state.game?.id != null ? state.game!.id.replaceAll('-', '').substring(0, 6).toUpperCase() : '------'",
        'max_players_expr': 'state.game?.maxPlayers ?? 12',
        'players_expr': 'state.players',
        'player_id_field': 'userId',
        'game_type_enum': 'GameType.antakshari',
        'state_var': 'state',
    },
    {
        'file': 'lib/features/games/truthordare/truthordare_lobby_screen.dart',
        'game_id_expr': "game.id",
        'room_code_expr': "game.id.replaceAll('-', '').substring(0, 6).toUpperCase()",
        'max_players_expr': '12',
        'players_expr': 'state.players',
        'player_id_field': 'userId',
        'game_type_enum': 'GameType.truthordare',
        'state_var': 'state',
    },
    {
        'file': 'lib/features/games/twotruths/twotruths_lobby_screen.dart',
        'game_id_expr': "game.id",
        'room_code_expr': "game.id.replaceAll('-', '').substring(0, 6).toUpperCase()",
        'max_players_expr': '12',
        'players_expr': 'state.players',
        'player_id_field': 'userId',
        'game_type_enum': 'GameType.twotruths',
        'state_var': 'state',
    },
    {
        'file': 'lib/features/games/dotsboxes/dotsboxes_lobby_screen.dart',
        'game_id_expr': "game.id",
        'room_code_expr': "game.id.replaceAll('-', '').substring(0, 6).toUpperCase()",
        'max_players_expr': '4',
        'players_expr': 'state.players',
        'player_id_field': 'userId',
        'game_type_enum': 'GameType.dotsboxes',
        'state_var': 'state',
    },
    {
        'file': 'lib/features/games/nameplace/nameplace_lobby_screen.dart',
        'game_id_expr': "game.id",
        'room_code_expr': "game.id.replaceAll('-', '').substring(0, 6).toUpperCase()",
        'max_players_expr': '20',
        'players_expr': 'state.players',
        'player_id_field': 'userId',
        'game_type_enum': 'GameType.nameplace',
        'state_var': 'state',
    },
    {
        'file': 'lib/features/games/chitmatch/chitmatch_lobby_screen.dart',
        'game_id_expr': "game.id",
        'room_code_expr': "game.id.replaceAll('-', '').substring(0, 6).toUpperCase()",
        'max_players_expr': 'game.playerCount',
        'players_expr': 'state.players',
        'player_id_field': 'userId',
        'game_type_enum': 'GameType.chitmatch',
        'state_var': 'state',
    },
    {
        'file': 'lib/features/games/redlight/redlight_lobby_screen.dart',
        'game_id_expr': "state.round?.id ?? ''",
        'room_code_expr': "state.round?.id != null ? state.round!.id.replaceAll('-', '').substring(0, 6).toUpperCase() : '------'",
        'max_players_expr': '20',
        'players_expr': 'state.players',
        'player_id_field': 'userId',
        'game_type_enum': 'GameType.redlight',
        'state_var': 'state',
    },
]

BASE = Path('/home/z/my-project/Daxelo-Kinrel-App')


def apply_lobby_edit(cfg):
    fp = BASE / cfg['file']
    src = fp.read_text()
    orig = src

    # 1) Add imports after 'game_motion_tokens.dart'
    motion_import = "import '../game_motion_tokens.dart';"
    extra_imports = (
        f"{motion_import}\n"
        "import '../shared/models/game_invite.dart';\n"
        "import '../shared/widgets/invite_family_sheet.dart';"
    )
    if motion_import in src and '../shared/widgets/invite_family_sheet.dart' not in src:
        src = src.replace(motion_import, extra_imports, 1)
    elif '../shared/widgets/invite_family_sheet.dart' in src:
        print(f"  {cfg['file']}: imports already present, skipping import step")
    else:
        print(f"  {cfg['file']}: WARNING — motion_import not found, skipping")
        return False

    # 2) Build the Invite IconButton block — match the exact pattern of the
    #    existing Share Code IconButton: `if (hasGame) IconButton(...)`
    #    Insert BEFORE the Share Code button.
    invite_block = (
        "if (hasGame && isHost)\n"
        "            IconButton(\n"
        "              tooltip: 'Invite family member',\n"
        "              icon: const Icon(Icons.person_add_outlined),\n"
        "              onPressed: () {{\n"
        "                final code = {room_code_expr};\n"
        "                final maxP = {max_players_expr};\n"
        "                GameMotionTokens.tap();\n"
        "                InviteFamilySheet.show(\n"
        "                  context,\n"
        "                  familyId: widget.familyId,\n"
        "                  gameType: {game_type_enum},\n"
        "                  gameId: {game_id_expr},\n"
        "                  roomCode: code,\n"
        "                  currentPlayerIds: {players_expr}\n"
        "                      .map((p) => p.{player_id_field})\n"
        "                      .whereType<String>()\n"
        "                      .toSet(),\n"
        "                  maxPlayers: maxP,\n"
        "                  currentPlayers: {players_expr}.length,\n"
        "                );\n"
        "              }},\n"
        "            ),\n"
        "          if (hasGame)\n"
    ).format(**cfg)

    # The pattern to find: "actions: [\n          if (hasGame)\n            IconButton(\n              icon: const Icon(Icons.share_outlined),"
    pattern = re.compile(
        r"(actions:\s*\[\s*\n\s*)if \(hasGame\)\s*\n\s*IconButton\(\s*\n\s*icon: const Icon\(Icons\.share_outlined\)",
        re.MULTILINE,
    )

    match = pattern.search(src)
    if match:
        # Insert the invite block BEFORE the existing `if (hasGame)` so the
        # share code button stays as the LAST action (matches Bingo).
        # We replace the matched `if (hasGame)` (only the first occurrence in
        # the actions list) with `invite_block` followed by `if (hasGame)`.
        prefix = match.group(1)  # "actions: [\n          "
        src = src[:match.start()] + prefix + invite_block + src[match.end() - len('IconButton(\n              icon: const Icon(Icons.share_outlined)'):]
        # Wait — the above slicing is wrong. Let me redo it.
        src = orig  # reset
        # Re-apply imports first
        src = src.replace(motion_import, extra_imports, 1) if motion_import in src and '../shared/widgets/invite_family_sheet.dart' not in src else src
        # Find the actions block start
        m = pattern.search(src)
        if not m:
            print(f"  {cfg['file']}: WARNING — actions pattern not found")
            return False
        # Insert invite_block right before `if (hasGame)`
        # match.end() points to right after `Icons.share_outlined)`
        # We want to insert before `if (hasGame)` (which is at match.start() + len(prefix))
        insert_pos = m.start() + len(m.group(1))
        # Replace the `if (hasGame)` (12 chars) with the invite block + `if (hasGame)`
        # The match consumed `if (hasGame)` plus the IconButton header. We need to put it back.
        # Easier: just do a string replace on the first occurrence of "if (hasGame)\n            IconButton(\n              icon: const Icon(Icons.share_outlined),"
        target = "if (hasGame)\n            IconButton(\n              icon: const Icon(Icons.share_outlined),"
        if target not in src:
            print(f"  {cfg['file']}: WARNING — exact target string not found")
            return False
        src = src.replace(target, invite_block + "          " + "IconButton(\n              icon: const Icon(Icons.share_outlined),", 1)
    else:
        print(f"  {cfg['file']}: WARNING — actions pattern not found")
        return False

    fp.write_text(src)
    print(f"  {cfg['file']}: ✓ updated")
    return True


def main():
    successes = 0
    failures = 0
    for cfg in LOBBIES:
        ok = apply_lobby_edit(cfg)
        if ok:
            successes += 1
        else:
            failures += 1
    print(f"\nDone. {successes} updated, {failures} failed.")


if __name__ == '__main__':
    main()
