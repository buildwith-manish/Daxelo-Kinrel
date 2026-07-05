#!/usr/bin/env python3
"""
Wire PendingInvitesSection into all 10 share-code lobby screens.

For each lobby:
1. Add imports for pending_invites_section.dart (and check that the
   shared/models/game_invite.dart import is already there from the
   previous task).
2. Insert PendingInvitesSection(gameId: state.game!.id) right BEFORE
   the Start Game DKButton, gated on hasGame (or hasRound for redlight).

Per-game configuration:
   - file: lobby screen path
   - state_game_id_expr: the expression for the game UUID
     (state.game!.id for most, state.round!.id for redlight)
   - anchor_pattern: regex matching the DKButton line where we insert before
   - hasgame_var: hasGame or hasRound
"""
import re
from pathlib import Path

BASE = Path('/home/z/my-project/Daxelo-Kinrel-App')

LOBBIES = [
    {
        'file': 'lib/features/games/bingo/bingo_lobby_screen.dart',
        'state_game_id_expr': 'state.game!.id',
        'anchor_pattern': r"DKButton\(\s*\n\s*label:\s*isHost",
        'hasgame_var': 'hasGame',
    },
    {
        'file': 'lib/features/games/ludo/ludo_lobby_screen.dart',
        'state_game_id_expr': 'state.game!.id',
        'anchor_pattern': r"DKButton\(\s*\n\s*label:\s*isHost",
        'hasgame_var': 'hasGame',
    },
    {
        'file': 'lib/features/games/sos/sos_lobby_screen.dart',
        'state_game_id_expr': 'state.game!.id',
        'anchor_pattern': r"DKButton\(\s*\n\s*label:\s*isHost",
        'hasgame_var': 'hasGame',
    },
    {
        'file': 'lib/features/games/antakshari/antakshari_lobby_screen.dart',
        'state_game_id_expr': 'state.game!.id',
        'anchor_pattern': r"DKButton\(\s*\n\s*label:\s*isHost",
        'hasgame_var': 'hasGame',
    },
    {
        'file': 'lib/features/games/truthordare/truthordare_lobby_screen.dart',
        'state_game_id_expr': 'state.game!.id',
        'anchor_pattern': r"if \(isHost\) DKButton\(label: canStart \? 'Start Game'",
        'hasgame_var': 'hasGame',
    },
    {
        'file': 'lib/features/games/twotruths/twotruths_lobby_screen.dart',
        'state_game_id_expr': 'state.game!.id',
        'anchor_pattern': r"if \(isHost\) DKButton\(label: canStart \? 'Start Game'",
        'hasgame_var': 'hasGame',
    },
    {
        'file': 'lib/features/games/dotsboxes/dotsboxes_lobby_screen.dart',
        'state_game_id_expr': 'state.game!.id',
        'anchor_pattern': r"if \(isHost\) DKButton\(label: canStart \? 'Start Game'",
        'hasgame_var': 'hasGame',
    },
    {
        'file': 'lib/features/games/nameplace/nameplace_lobby_screen.dart',
        'state_game_id_expr': 'state.game!.id',
        'anchor_pattern': r"DKButton\(label: canStart \? 'Start Game'",
        'hasgame_var': 'hasGame',
    },
    {
        'file': 'lib/features/games/chitmatch/chitmatch_lobby_screen.dart',
        'state_game_id_expr': 'state.game!.id',
        'anchor_pattern': r"DKButton\(\s*\n\s*label:\s*canStart",
        'hasgame_var': 'hasGame',
    },
    {
        'file': 'lib/features/games/redlight/redlight_lobby_screen.dart',
        'state_game_id_expr': 'state.round!.id',
        'anchor_pattern': r"DKButton\(\s*\n\s*label:\s*isHost",
        'hasgame_var': 'hasRound',
    },
]


def apply(cfg):
    fp = BASE / cfg['file']
    src = fp.read_text()
    orig = src

    # 1) Add the pending_invites_section import (if not already present)
    if 'pending_invites_section.dart' not in src:
        # Insert after the existing invite_family_sheet import
        target_import = "import '../shared/widgets/invite_family_sheet.dart';"
        new_import = (
            f"{target_import}\n"
            "import '../shared/widgets/pending_invites_section.dart';"
        )
        if target_import in src:
            src = src.replace(target_import, new_import, 1)
        else:
            print(f"  {cfg['file']}: WARNING — anchor import not found")
            return False

    # 2) Insert PendingInvitesSection BEFORE the Start Game button
    if 'PendingInvitesSection(' in src:
        print(f"  {cfg['file']}: already has PendingInvitesSection, skipping")
        return True

    pattern = re.compile(cfg['anchor_pattern'])
    m = pattern.search(src)
    if not m:
        print(f"  {cfg['file']}: WARNING — anchor pattern not found")
        return False

    insert_pos = m.start()
    section = (
        f"if ({cfg['hasgame_var']})\n"
        f"          PendingInvitesSection(gameId: {cfg['state_game_id_expr']}),\n"
        f"        const SizedBox(height: KinrelSpacing.md),\n"
        f"        "
    )
    src = src[:insert_pos] + section + src[insert_pos:]

    fp.write_text(src)
    print(f"  {cfg['file']}: ✓ updated")
    return True


def main():
    ok = 0
    fail = 0
    for cfg in LOBBIES:
        if apply(cfg):
            ok += 1
        else:
            fail += 1
    print(f"\n{ok} updated, {fail} failed")


if __name__ == '__main__':
    main()
