"""
Inspect current icons: split each 1024x1024 icon into a top-half and bottom-half
strip, save the bottom strips side-by-side as a single image so we can see
exactly where the text band is.
"""
from PIL import Image
from pathlib import Path

ICONS_DIR = Path('/home/z/my-project/Daxelo-Kinrel-App/assets/icons/games')
OUT = Path('/home/z/my-project/download/icon_inspection')
OUT.mkdir(parents=True, exist_ok=True)

ICONS = [
    'ghost-painter.png', 'freeze-dash.png', 'sos.png', 'antakshari.png',
    'bingo.png', 'checkers.png', 'ludo.png', 'carrom.png', 'chess.png',
    'chitmatch.png', 'nameplace.png', 'tictactoe.png', 'truthordare.png',
    'twotruths.png', 'dotsboxes.png', 'hot-seat.png', 'relation-riddles.png',
    'truth-streak.png',
]

# Build a contact sheet where each row = one icon's bottom 25% strip
STRIP_H = 256  # bottom 25% of 1024
COLS = 3
ROWS = (len(ICONS) + COLS - 1) // COLS
CELL_W = 512  # 2x scale for visibility
CELL_H = STRIP_H // 2  # display at half height
PAD = 8
LABEL_H = 24

W = PAD * 2 + COLS * CELL_W + (COLS - 1) * PAD
H = PAD * 2 + ROWS * (CELL_H + LABEL_H + PAD) + (ROWS - 1) * PAD

sheet = Image.new('RGB', (W, H), (255, 255, 255))
from PIL import ImageDraw, ImageFont
draw = ImageDraw.Draw(sheet)
try:
    font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 16)
except Exception:
    font = ImageFont.load_default()

for i, name in enumerate(ICONS):
    r, c = divmod(i, COLS)
    im = Image.open(ICONS_DIR / name).convert('RGB')
    # Take bottom 25% (last 256px)
    bottom = im.crop((0, 1024 - STRIP_H, 1024, 1024))
    bottom = bottom.resize((CELL_W, CELL_H), Image.LANCZOS)
    x = PAD + c * (CELL_W + PAD)
    y = PAD + r * (CELL_H + LABEL_H + PAD + PAD)
    sheet.paste(bottom, (x, y))
    draw.text((x + 4, y + CELL_H + 4), name, fill=(0, 0, 0), font=font)

sheet.save(OUT / 'bottom_strips.png', 'PNG')
print(f"Saved: {OUT / 'bottom_strips.png'}  ({W}x{H})")

# Also save a single contact sheet of the FULL icons for reference
FULL = 256
FW = PAD * 2 + COLS * FULL + (COLS - 1) * PAD
FH = PAD * 2 + ROWS * (FULL + LABEL_H + PAD) + (ROWS - 1) * PAD
full_sheet = Image.new('RGB', (FW, FH), (255, 255, 255))
draw2 = ImageDraw.Draw(full_sheet)
for i, name in enumerate(ICONS):
    r, c = divmod(i, COLS)
    im = Image.open(ICONS_DIR / name).convert('RGB').resize((FULL, FULL), Image.LANCZOS)
    x = PAD + c * (FULL + PAD)
    y = PAD + r * (FULL + LABEL_H + PAD + PAD)
    full_sheet.paste(im, (x, y))
    draw2.text((x + 4, y + FULL + 4), name, fill=(0, 0, 0), font=font)
full_sheet.save(OUT / 'full_icons.png', 'PNG')
print(f"Saved: {OUT / 'full_icons.png'}  ({FW}x{FH})")
