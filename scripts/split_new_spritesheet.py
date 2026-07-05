#!/usr/bin/env python3
"""
Split the new clean sprite sheet (Picsart_26-07-05_14-12-56-657.png, 1536x1024)
into 18 individual game icons and overwrite the existing files.

User instructions:
  - "replace all 18 game icons with the 18 icons in the first image"
  - "split the 18 images to replace them perfectly without changing the image"
  - "If you are confused about the names, use the second image"

So: we extract each cell of the 6x3 grid cleanly, preserving the artwork
exactly as-is (NO regeneration, NO modification). We upscale to 1024x1024
with LANCZOS for consistency with the existing icon dimensions.

Grid layout matches the labeled reference image (file_0000000032a4720ba04c5f6d587498bd.png):
  Row 1: ghost-painter, freeze-dash, sos, antakshari, bingo, checkers
  Row 2: ludo, carrom, chess, chitmatch, nameplace, tictactoe
  Row 3: truthordare, twotruths, dotsboxes, hot-seat, relation-riddles, truth-streak
"""
from PIL import Image
import numpy as np
from pathlib import Path

SRC = '/home/z/my-project/upload/Picsart_26-07-05_14-12-56-657.png'
DEST_DIR = Path('/home/z/my-project/Daxelo-Kinrel-App/assets/icons/games')
OUT_DIR = Path('/home/z/my-project/download/split_icons_v2')
OUT_DIR.mkdir(parents=True, exist_ok=True)

# Mapping (row, col) 1-indexed -> filename
# Same as the labeled sprite sheet layout
MAPPING = {
    (1, 1): 'ghost-painter.png',
    (1, 2): 'freeze-dash.png',
    (1, 3): 'sos.png',
    (1, 4): 'antakshari.png',
    (1, 5): 'bingo.png',
    (1, 6): 'checkers.png',
    (2, 1): 'ludo.png',
    (2, 2): 'carrom.png',
    (2, 3): 'chess.png',
    (2, 4): 'chitmatch.png',
    (2, 5): 'nameplace.png',
    (2, 6): 'tictactoe.png',
    (3, 1): 'truthordare.png',
    (3, 2): 'twotruths.png',
    (3, 3): 'dotsboxes.png',
    (3, 4): 'hot-seat.png',
    (3, 5): 'relation-riddles.png',
    (3, 6): 'truth-streak.png',
}

CELL_W = 1536 // 6  # 256
ROW_H = 1024 / 3    # 341.33

src_im = Image.open(SRC).convert('RGB')
W, H = src_im.size
print(f"Source: {W}x{H}  (mode after RGB convert)")

OUT_SIZE = 1024


def tight_bbox(cell_im: Image.Image, bg_color):
    """Find tight content bbox by detecting pixels that differ from bg."""
    arr = np.array(cell_im)
    bg = np.array(bg_color)
    diff = np.abs(arr.astype(int) - bg.astype(int)).sum(axis=2)
    mask = diff > 18  # tolerance
    if not mask.any():
        return None
    ys, xs = np.where(mask)
    return (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)


results = []
for (r, c), fname in MAPPING.items():
    x0 = int(round((c - 1) * CELL_W))
    x1 = int(round(c * CELL_W))
    y0 = int(round((r - 1) * ROW_H))
    y1 = int(round(r * ROW_H))
    cell = src_im.crop((x0, y0, x1, y1))

    # Sample background color from the 4 corners of the cell
    corner_pixels = [
        cell.getpixel((2, 2)),
        cell.getpixel((cell.width - 3, 2)),
        cell.getpixel((2, cell.height - 3)),
        cell.getpixel((cell.width - 3, cell.height - 3)),
    ]
    bg_color = tuple(int(sum(p[i] for p in corner_pixels) / 4) for i in range(3))

    bbox = tight_bbox(cell, bg_color)
    if bbox is None:
        print(f"  WARNING: no content found for {fname}")
        continue

    # Add a small symmetric padding so the artwork doesn't touch the edges.
    # Use a small pad (4px) to preserve the artwork faithfully — the user
    # said "without changing the image" so we keep the tight crop + tiny pad.
    pad = 4
    bx0 = max(0, bbox[0] - pad)
    by0 = max(0, bbox[1] - pad)
    bx1 = min(cell.width, bbox[2] + pad)
    by1 = min(cell.height, bbox[3] + pad)

    tight = cell.crop((bx0, by0, bx1, by1))

    # Make square by padding with bg_color so aspect ratio is preserved
    w, h = tight.size
    side = max(w, h)
    square = Image.new('RGB', (side, side), bg_color)
    square.paste(tight, ((side - w) // 2, (side - h) // 2))

    # Upscale to 1024x1024 with LANCZOS
    final = square.resize((OUT_SIZE, OUT_SIZE), Image.LANCZOS)

    # Save to both preview and assets dir
    preview_path = OUT_DIR / fname
    final.save(preview_path, 'PNG', optimize=True)
    asset_path = DEST_DIR / fname
    final.save(asset_path, 'PNG', optimize=True)

    results.append((fname, w, h, side, bg_color))
    print(f"  {fname:30s} cell=({cell.width}x{cell.height}) tight=({w}x{h}) bg={bg_color} -> {OUT_SIZE}x{OUT_SIZE}")

print(f"\nDone. {len(results)} icons saved to:")
print(f"  Preview: {OUT_DIR}")
print(f"  Assets:  {DEST_DIR}")
