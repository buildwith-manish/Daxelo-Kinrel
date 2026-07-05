"""Build a contact sheet from the split icons to visually verify."""
from PIL import Image
from pathlib import Path

ICON_DIR = Path('/home/z/my-project/download/split_icons')
OUT = '/home/z/my-project/download/split_icons/_contact_sheet.png'

# Same grid order as the source sprite
ORDER = [
    ['ghost-painter.png', 'freeze-dash.png', 'sos.png', 'antakshari.png', 'bingo.png', 'checkers.png'],
    ['ludo.png', 'carrom.png', 'chess.png', 'chitmatch.png', 'nameplace.png', 'tictactoe.png'],
    ['truthordare.png', 'twotruths.png', 'dotsboxes.png', 'hot-seat.png', 'relation-riddles.png', 'truth-streak.png'],
]

THUMB = 256
GAP = 8
PAD = 12
COLS = 6
ROWS = 3
W = PAD * 2 + COLS * THUMB + (COLS - 1) * GAP
H = PAD * 2 + ROWS * THUMB + (ROWS - 1) * GAP

sheet = Image.new('RGB', (W, H), (240, 240, 240))
for r, row in enumerate(ORDER):
    for c, fname in enumerate(row):
        p = ICON_DIR / fname
        if not p.exists():
            print(f"missing: {p}")
            continue
        im = Image.open(p).resize((THUMB, THUMB), Image.LANCZOS)
        x = PAD + c * (THUMB + GAP)
        y = PAD + r * (THUMB + GAP)
        sheet.paste(im, (x, y))

sheet.save(OUT, 'PNG')
print(f"Contact sheet saved: {OUT} ({W}x{H})")
