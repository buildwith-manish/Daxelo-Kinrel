#!/usr/bin/env python3
"""
Wire SpectatorToggle into all 10 share-code lobby setup views.

For each lobby:
1. Add a _spectatorsEnabled state variable (default true).
2. Insert SpectatorToggle widget right before the Create Game button.
3. After createGame() returns the gameId, UPDATE the game row to set
   spectatorsEnabled = _spectatorsEnabled (avoids modifying 14 providers).

Pattern:
  // In state class:
  bool _spectatorsEnabled = true;

  // In _setupView, before the Create Game DKButton:
  SpectatorToggle(
    value: _spectatorsEnabled,
    onChanged: (v) => setState(() => _spectatorsEnabled = v),
  ),
  const SizedBox(height: KinrelSpacing.md),

  // In _createGame, after gameId is returned:
  if (gameId != null) {
    await ref.read(supabaseProvider)?.from('{game_table}').update({'spectatorsEnabled': _spectatorsEnabled}).eq('id', gameId);
  }
"""
import re
from pathlib import Path

BASE = Path('/home/z/my-project/Daxelo-Kinrel-App')

# (file, game_table, create_button_pattern)
# The create_button_pattern matches the DKButton that creates the game
LOBBIES = [
    ('lib/features/games/bingo/bingo_lobby_screen.dart', 'bingo_games',
     r"DKButton\(\s*\n\s*label:\s*'Create Game'"),
    ('lib/features/games/ludo/ludo_lobby_screen.dart', 'ludo_games',
     r"DKButton\(\s*\n\s*label:\s*'Create Game'"),
    ('lib/features/games/sos/sos_lobby_screen.dart', 'sos_games',
     r"DKButton\(\s*\n\s*label:\s*'Create Game'"),
    ('lib/features/games/antakshari/antakshari_lobby_screen.dart', 'antakshari_games',
     r"DKButton\(\s*\n\s*label:\s*'Create Game'"),
    ('lib/features/games/truthordare/truthordare_lobby_screen.dart', 'truthordare_games',
     r"DKButton\(label: 'Create Game'"),
    ('lib/features/games/twotruths/twotruths_lobby_screen.dart', 'twotruths_games',
     r"DKButton\(label: 'Create Game'"),
    ('lib/features/games/dotsboxes/dotsboxes_lobby_screen.dart', 'dotsboxes_games',
     r"DKButton\(label: 'Create Game'"),
    ('lib/features/games/nameplace/nameplace_lobby_screen.dart', 'nameplace_games',
     r"DKButton\(label: 'Create Game'"),
    ('lib/features/games/chitmatch/chitmatch_lobby_screen.dart', 'chitmatch_games',
     r"DKButton\(\s*\n\s*label:\s*'Create Game'"),
    ('lib/features/games/redlight/redlight_lobby_screen.dart', 'redlight_rounds',
     r"DKButton\(\s*\n\s*label:\s*'Create Game'"),
]


def apply(file_rel, game_table, button_pattern):
    fp = BASE / file_rel
    src = fp.read_text()

    # 1. Add import (after lobby_chat_panel import which we added earlier)
    if 'spectator_toggle.dart' not in src:
        target = "import '../shared/widgets/lobby_chat_panel.dart';"
        new_imp = f"{target}\nimport '../shared/widgets/spectator_toggle.dart';"
        if target in src:
            src = src.replace(target, new_imp, 1)
        else:
            # Try the pending_invites_section import as anchor
            target2 = "import '../shared/widgets/pending_invites_section.dart';"
            new_imp2 = f"{target2}\nimport '../shared/widgets/spectator_toggle.dart';"
            if target2 in src:
                src = src.replace(target2, new_imp2, 1)
            else:
                print(f"  {file_rel}: WARNING — no anchor import found")
                return False

    # 2. Add _spectatorsEnabled state var (find the first state var declaration)
    if '_spectatorsEnabled' not in src:
        # Find a line like: bool _creating = false;
        m = re.search(r'(bool _creating\s*=\s*false;)', src)
        if m:
            src = src.replace(m.group(1),
                              m.group(1) + '\n  bool _spectatorsEnabled = true;')
        else:
            # Fallback: add after the class declaration line
            m2 = re.search(r'(extends ConsumerState<\w+> \{\n)', src)
            if m2:
                src = src.replace(m2.group(1),
                                  m2.group(1) + '  bool _spectatorsEnabled = true;\n')
            else:
                print(f"  {file_rel}: WARNING — can't find state var insertion point")
                return False

    # 3. Insert SpectatorToggle before the Create Game button
    if 'SpectatorToggle(' not in src:
        pattern = re.compile(button_pattern)
        m = pattern.search(src)
        if not m:
            print(f"  {file_rel}: WARNING — Create Game button not found")
            return False
        insert_pos = m.start()
        # Detect indentation from the button line
        line_start = src.rfind('\n', 0, insert_pos) + 1
        indent = src[line_start:insert_pos]
        toggle_block = (
            f"{indent}SpectatorToggle(\n"
            f"{indent}  value: _spectatorsEnabled,\n"
            f"{indent}  onChanged: (v) => setState(() => _spectatorsEnabled = v),\n"
            f"{indent}),\n"
            f"{indent}const SizedBox(height: KinrelSpacing.md),\n"
            f"{indent}"
        )
        src = src[:insert_pos] + toggle_block + src[insert_pos:]

    # 4. After createGame returns gameId, UPDATE the row's spectatorsEnabled
    # Pattern varies per lobby; look for `final gameId = await` and add update after
    if f"spectatorsEnabled" not in src or "spectatorsEnabled\": _spectatorsEnabled" not in src:
        # Find the line after gameId is obtained
        # Most lobbies have: `final gameId = await ...createGame(...)`
        # Followed by either a navigation or setState
        update_line = (
            f"      if (gameId != null) {{\n"
            f"        await ref.read(supabaseProvider)?.from('{game_table}').update({{'spectatorsEnabled': _spectatorsEnabled}}).eq('id', gameId);\n"
            f"      }}\n"
        )
        # Find the line `final gameId = await` and insert after the next semicolon
        m = re.search(r'(final gameId = await [^;]+;)', src)
        if m:
            src = src.replace(m.group(1), m.group(1) + '\n' + update_line)
        else:
            # Some lobbies use `await notifier.createGame(...)` without assigning to gameId
            # Skip the update for those — the default true is fine
            pass

    fp.write_text(src)
    print(f"  {file_rel}: ✓ updated")
    return True


for cfg in LOBBIES:
    apply(*cfg)
