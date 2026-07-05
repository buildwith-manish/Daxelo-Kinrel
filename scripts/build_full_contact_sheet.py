"""Build a full contact sheet showing all 18 fresh icons in 6x3 grid."""
from PIL import Image, ImageDraw, ImageFont
from pathlib import Path

SRC = Path('/home/z/my-project/download/fresh_icons')
OUT = Path('/home/z/my-project/download/verification/all_18_fresh.png')

ICONS = [
    'ghost-painter.png', 'freeze-dash.png', 'sos.png', 'antakshari.png', 'bingo.png', 'checkers.png',
    'ludo.png', 'carrom.png', 'chess.png', 'chitmatch.png', 'nameplace.png', 'tictactoe.png',
    'truthordare.png', 'twotruths.png', 'dotsboxes.png', 'hot-seat.png', 'relation-riddles.png', 'truth-streak.png',
]

THUMB = 280
COLS = 6
ROWS = 3
PAD = 10
LABEL_H = 20
W = PAD * 2 + COLS * THUMB + (COLS - 1) * PAD
H = PAD * 2 + ROWS * (THUMB + LABEL_H + PAD) + (ROWS - 1) * PAD

sheet = Image.new('RGB', (W, H), (250, 250, 250))
draw = ImageDraw.Draw(sheet)
try:
    font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 14)
except Exception:
    font = ImageFont.load_default()

for i, name in enumerate(ICONS):
    r, c = divmod(i, COLS)
    im = Image.open(SRC / name).convert('RGB').resize((THUMB, THUMB), Image.LANCZOS)
    x = PAD + c * (THUMB + PAD)
    y = PAD + r * (THUMB + LABEL_H + PAD + PAD)
    sheet.paste(im, (x, y))
    # draw a 1px gray border
    draw.rectangle([x, y, x + THUMB - 1, y + THUMB - 1], outline=(180, 180, 180))
    draw.text((x + 4, y + THUMB + 3), name.replace('.png', ''), fill=(40, 40, 40), font=font)

sheet.save(OUT, 'PNG')
print(f"Saved: {OUT} ({W}x{H})")
