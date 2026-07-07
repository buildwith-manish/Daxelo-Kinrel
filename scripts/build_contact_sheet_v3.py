"""Build contact sheet from v3 split icons."""
from PIL import Image, ImageDraw, ImageFont
from pathlib import Path

ICON_DIR = Path('/home/z/my-project/download/split_icons_v3')
OUT = ICON_DIR / '_contact_sheet.png'

ORDER = [
    ['ghost-painter.png', 'freeze-dash.png', 'sos.png', 'antakshari.png', 'bingo.png', 'checkers.png'],
    ['ludo.png', 'carrom.png', 'chess.png', 'chitmatch.png', 'nameplace.png', 'tictactoe.png'],
    ['truthordare.png', 'twotruths.png', 'dotsboxes.png', 'hot-seat.png', 'relation-riddles.png', 'truth-streak.png'],
]

THUMB = 280
GAP = 10
PAD = 14
COLS = 6
ROWS = 3
W = PAD * 2 + COLS * THUMB + (COLS - 1) * GAP
H = PAD * 2 + ROWS * THUMB + (ROWS - 1) * GAP

sheet = Image.new('RGB', (W, H), (240, 240, 240))
draw = ImageDraw.Draw(sheet)
try:
    font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 14)
except Exception:
    font = ImageFont.load_default()

for r, row in enumerate(ORDER):
    for c, fname in enumerate(row):
        p = ICON_DIR / fname
        if not p.exists():
            continue
        im = Image.open(p).resize((THUMB, THUMB), Image.LANCZOS)
        x = PAD + c * (THUMB + GAP)
        y = PAD + r * (THUMB + GAP)
        draw.rectangle([x-1, y-1, x+THUMB, y+THUMB], outline=(100,100,100))
        sheet.paste(im, (x, y))

sheet.save(OUT, 'PNG')
print(f"Contact sheet saved: {OUT} ({W}x{H})")
