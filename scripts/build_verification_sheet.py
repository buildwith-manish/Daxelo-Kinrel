"""
Build a verification sheet showing the BOTTOM EDGE of 8 fresh icons,
zoomed in 2x so the user can confirm there's no text bleed.

We deliberately pick icons spread across the full set of 18, NOT just the
ones the user flagged, so they can verify the fix works for all of them.
"""
from PIL import Image, ImageDraw, ImageFont
from pathlib import Path

SRC = Path('/home/z/my-project/download/fresh_icons')
OUT = Path('/home/z/my-project/download/verification')
OUT.mkdir(parents=True, exist_ok=True)

# Pick 8 icons spread across the set (positions 1,3,5,7,9,11,15,18 in our list)
# This covers various games: ghost-painter, sos, bingo, ludo, chess, nameplace,
# dotsboxes, truth-streak — including games the user didn't flag
PICK = [
    'ghost-painter.png',   # 1
    'sos.png',             # 3
    'bingo.png',           # 5
    'ludo.png',            # 7
    'chess.png',           # 9
    'nameplace.png',       # 11
    'dotsboxes.png',       # 15
    'truth-streak.png',    # 18
]

# For each icon, show:
#   - Top row: full icon at 256x256 (context)
#   - Bottom row: bottom 25% (last 256px) of the 1024x1024 icon, scaled up to 1024x256
#                so we can see if there's ANY text bleed
#
# Layout: 4 columns x 2 rows, each cell ~ 280px wide x 600px tall

ICON_FULL = 256       # full icon preview size
BOTTOM_W = 1024       # zoomed bottom strip width (4x scale of source)
BOTTOM_H = 256        # bottom strip source height (bottom 25% of 1024)
BOTTOM_DISP_H = 256   # displayed at native height (already 4x of source visually)

COLS = 4
ROWS = 2
PAD = 12
LABEL_H = 22
ROW_H = ICON_FULL + LABEL_H + PAD + BOTTOM_DISP_H + LABEL_H + PAD
COL_W = max(ICON_FULL, BOTTOM_W) + PAD

W = PAD * 2 + COLS * COL_W + (COLS - 1) * PAD
H = PAD * 2 + ROWS * ROW_H + (ROWS - 1) * PAD

sheet = Image.new('RGB', (W, H), (255, 255, 255))
draw = ImageDraw.Draw(sheet)
try:
    font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 18)
except Exception:
    font = ImageFont.load_default()

for i, name in enumerate(PICK):
    r, c = divmod(i, COLS)
    im = Image.open(SRC / name).convert('RGB')
    
    # Top: full icon preview
    full = im.resize((ICON_FULL, ICON_FULL), Image.LANCZOS)
    
    # Bottom: bottom 25% of original (last 256 rows of 1024)
    bottom_src = im.crop((0, 1024 - BOTTOM_H, 1024, 1024))
    # Scale up to BOTTOM_W x BOTTOM_DISP_H (4x linear scale for visibility)
    bottom = bottom_src.resize((BOTTOM_W, BOTTOM_DISP_H), Image.LANCZOS)
    
    x = PAD + c * COL_W
    y = PAD + r * ROW_H
    
    # Paste full icon centered in column
    full_x = x + (COL_W - PAD - ICON_FULL) // 2
    sheet.paste(full, (full_x, y))
    draw.text((full_x, y + ICON_FULL + 2), f"{name}  (full)", fill=(0, 0, 0), font=font)
    
    # Paste bottom strip below
    bottom_y = y + ICON_FULL + LABEL_H + PAD
    sheet.paste(bottom, (x, bottom_y))
    draw.text((x, bottom_y + BOTTOM_DISP_H + 2), f"{name}  (bottom 25%, 4x zoom)", fill=(200, 0, 0), font=font)

out_path = OUT / 'bottom_edge_verification.png'
sheet.save(out_path, 'PNG')
print(f"Verification sheet saved: {out_path}")
print(f"Size: {W}x{H}")
print(f"\nIcons shown (8 total, covering positions 1,3,5,7,9,11,15,18 of 18):")
for n in PICK:
    print(f"  - {n}")
