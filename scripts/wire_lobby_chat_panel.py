#!/usr/bin/env python3
"""
Wire LobbyChatPanel into all 14 lobby screens.

For each lobby, after the existing PendingInvitesSection insertion,
add a LobbyChatPanel that joins the lobby's chat room. Gated on
hasGame (or hasRound for redlight) since chat only makes sense once
the room exists.

Pattern (per lobby):
  PendingInvitesSection(gameId: state.game!.id),
  const SizedBox(height: KinrelSpacing.md),
  LobbyChatPanel(
    gameTable: '{game}_games',  # or 'redlight_rounds'
    gameId: state.game!.id,     # or state.round!.id for redlight
    familyId: widget.familyId,
  ),

Also adds the necessary imports.
"""
import re
from pathlib import Path

BASE = Path('/home/z/my-project/Daxelo-Kinrel-App')

LOBBIES = [
    ('lib/features/games/bingo/bingo_lobby_screen.dart',       'bingo_games',       'state.game!.id'),
    ('lib/features/games/ludo/ludo_lobby_screen.dart',         'ludo_games',        'state.game!.id'),
    ('lib/features/games/sos/sos_lobby_screen.dart',           'sos_games',         'state.game!.id'),
    ('lib/features/games/antakshari/antakshari_lobby_screen.dart', 'antakshari_games', 'state.game!.id'),
    ('lib/features/games/truthordare/truthordare_lobby_screen.dart', 'truthordare_games', 'state.game!.id'),
    ('lib/features/games/twotruths/twotruths_lobby_screen.dart',     'twotruths_games', 'state.game!.id'),
    ('lib/features/games/dotsboxes/dotsboxes_lobby_screen.dart',     'dotsboxes_games', 'state.game!.id'),
    ('lib/features/games/nameplace/nameplace_lobby_screen.dart',     'nameplace_games', 'state.game!.id'),
    ('lib/features/games/chitmatch/chitmatch_lobby_screen.dart',     'chitmatch_games', 'state.game!.id'),
    ('lib/features/games/redlight/redlight_lobby_screen.dart',  'redlight_rounds',   'state.round!.id'),
]

for rel, game_table, game_id_expr in LOBBIES:
    fp = BASE / rel
    src = fp.read_text()

    # 1) Add the import (after the existing pending_invites_section import)
    if 'lobby_chat_panel.dart' not in src:
        target_import = "import '../shared/widgets/pending_invites_section.dart';"
        new_import = (
            f"{target_import}\n"
            "import '../shared/widgets/lobby_chat_panel.dart';"
        )
        if target_import in src:
            src = src.replace(target_import, new_import, 1)
        else:
            print(f"  {rel}: WARNING — anchor import not found")
            continue

    # 2) Insert LobbyChatPanel right BEFORE PendingInvitesSection
    if 'LobbyChatPanel(' in src:
        print(f"  {rel}: already has LobbyChatPanel, skipping")
        continue

    # The PendingInvitesSection insertion is on its own line.
    # Insert LobbyChatPanel BEFORE the SizedBox that follows PendingInvitesSection,
    # so the chat panel appears after the Start Game button (cleaner UX).
    # Actually, insert AFTER the Start Game DKButton so chat is at the bottom.
    # Simpler: insert right before the closing `],` of the lobby ListView.

    # Find the PendingInvitesSection line and insert LobbyChatPanel AFTER
    # the SizedBox that follows it.
    pattern = re.compile(
        r"(PendingInvitesSection\(gameId: " + re.escape(game_id_expr) + r"\),\s*\n"
        r"\s*const SizedBox\(height: KinrelSpacing\.md\),)"
    )
    chat_block = (
        "\n            LobbyChatPanel(\n"
        f"              gameTable: '{game_table}',\n"
        f"              gameId: {game_id_expr},\n"
        "              familyId: widget.familyId,\n"
        "            ),"
    )

    new_src, n = pattern.subn(lambda m: m.group(1) + chat_block, src, count=1)
    if n == 0:
        print(f"  {rel}: WARNING — PendingInvitesSection pattern not found")
        continue

    fp.write_text(new_src)
    print(f"  {rel}: ✓ updated")
