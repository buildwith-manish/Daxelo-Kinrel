#!/usr/bin/env python3
"""
Re-split the sprite sheet using the ACTUAL content boundaries (detected via
background-color separator bands), not the naive 6x3 equal-cell grid.

Previous bug: assuming 256x341 cells caused icons in row 2 to include the
bottom 43px of row 1's icons, and row 3 to include the top 42px of row 2's
icons — leading to "half cutted" icons.

Detected actual grid (from background band analysis):
  Row separators (bg bands): y=0-24, y=268-347, y=590-671, y=920-944
  Col separators (bg bands): x=0-20, x=262-272, x=512-523, x=761-771,
                              x=1008-1019, x=1256-1267, x=1508-1536

So actual icon content regions are between these bands:
  Row 1: y = 24..268
  Row 2: y = 347..590
  Row 3: y = 671..920
  Col 1: x = 20..262
  Col 2: x = 272..512
  Col 3: x = 523..761
  Col 4: x = 771..1008
  Col 5: x = 1019..1256
  Col 6: x = 1267..1508

Each icon is ~240x244 px. We pad to square with the dark bg color,
then upscale to 1024x1024 with LANCZOS. NOTHING is cut.
"""
from PIL import Image
import numpy as np
from pathlib import Path

SRC = '/home/z/my-project/upload/Picsart_26-07-05_14-12-56-657.png'
DEST_DIR = Path('/home/z/my-project/Daxelo-Kinrel-App/assets/icons/games')
OUT_DIR = Path('/home/z/my-project/download/split_icons_v3')
OUT_DIR.mkdir(parents=True, exist_ok=True)

# Exact content boundaries detected from background-band analysis
ROWS = [(24, 268), (347, 590), (671, 920)]
COLS = [(20, 262), (272, 512), (523, 761), (771, 1008), (1019, 1256), (1267, 1508)]

# Mapping (row_idx, col_idx) 0-indexed -> filename
MAPPING = {
    (0, 0): 'ghost-painter.png',
    (0, 1): 'freeze-dash.png',
    (0, 2): 'sos.png',
    (0, 3): 'antakshari.png',
    (0, 4): 'bingo.png',
    (0, 5): 'checkers.png',
    (1, 0): 'ludo.png',
    (1, 1): 'carrom.png',
    (1, 2): 'chess.png',
    (1, 3): 'chitmatch.png',
    (1, 4): 'nameplace.png',
    (1, 5): 'tictactoe.png',
    (2, 0): 'truthordare.png',
    (2, 1): 'twotruths.png',
    (2, 2): 'dotsboxes.png',
    (2, 3): 'hot-seat.png',
    (2, 4): 'relation-riddles.png',
    (2, 5): 'truth-streak.png',
}

src_im = Image.open(SRC).convert('RGB')
OUT_SIZE = 1024
# Use the dark background color from the sprite sheet
BG_COLOR = (0, 7, 23)

results = []
for (r, c), fname in MAPPING.items():
    y0, y1 = ROWS[r]
    x0, x1 = COLS[c]
    cell = src_im.crop((x0, y0, x1, y1))
    w, h = cell.size

    # Pad to square with bg color (preserves ENTIRE content, nothing cut)
    side = max(w, h)
    square = Image.new('RGB', (side, side), BG_COLOR)
    square.paste(cell, ((side - w) // 2, (side - h) // 2))

    # Upscale to 1024x1024 with LANCZOS
    final = square.resize((OUT_SIZE, OUT_SIZE), Image.LANCZOS)

    # Save to both preview and assets
    final.save(OUT_DIR / fname, 'PNG', optimize=True)
    final.save(DEST_DIR / fname, 'PNG', optimize=True)

    results.append((fname, w, h, side))
    print(f"  {fname:30s} cell=({w}x{h}) -> pad to {side}x{side} -> {OUT_SIZE}x{OUT_SIZE}")

print(f"\nDone. {len(results)} icons saved (FULL content, nothing cut).")
print(f"  Preview: {OUT_DIR}")
print(f"  Assets:  {DEST_DIR}")
