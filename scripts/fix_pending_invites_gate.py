#!/usr/bin/env python3
"""
Fix the previous PendingInvitesSection insertion: remove the undefined
'if (hasGame)' / 'if (hasRound)' gate (those getters aren't in scope inside
_lobbyView). The section already auto-hides when there are no invites, so
the gate is unnecessary.

Pattern to replace:
  if (hasGame)
            PendingInvitesSection(gameId: state.game!.id),
          const SizedBox(height: KinrelSpacing.md),
          
With:
  PendingInvitesSection(gameId: state.game!.id),
          const SizedBox(height: KinrelSpacing.md),
"""
import re
from pathlib import Path

BASE = Path('/home/z/my-project/Daxelo-Kinrel-App')

LOBBIES = [
    'lib/features/games/bingo/bingo_lobby_screen.dart',
    'lib/features/games/ludo/ludo_lobby_screen.dart',
    'lib/features/games/sos/sos_lobby_screen.dart',
    'lib/features/games/antakshari/antakshari_lobby_screen.dart',
    'lib/features/games/truthordare/truthordare_lobby_screen.dart',
    'lib/features/games/twotruths/twotruths_lobby_screen.dart',
    'lib/features/games/dotsboxes/dotsboxes_lobby_screen.dart',
    'lib/features/games/nameplace/nameplace_lobby_screen.dart',
    'lib/features/games/chitmatch/chitmatch_lobby_screen.dart',
    'lib/features/games/redlight/redlight_lobby_screen.dart',
]

# Two patterns to remove:
# 1. "if (hasGame)\n          PendingInvitesSection"
# 2. "if (hasRound)\n          PendingInvitesSection"
PATTERN = re.compile(r'if \(has(?:Game|Round)\)\s*\n(\s+)PendingInvitesSection', re.MULTILINE)

for rel in LOBBIES:
    fp = BASE / rel
    src = fp.read_text()
    new = PATTERN.sub(r'\1PendingInvitesSection', src)
    if new == src:
        print(f"  {rel}: no change needed")
    else:
        fp.write_text(new)
        print(f"  {rel}: ✓ removed gate")
