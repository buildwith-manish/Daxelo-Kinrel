"""
Split the sprite sheet (1536x1024) into 18 game icons (6 cols x 3 rows)
and replace the existing game icons in Daxelo-Kinrel-App/assets/icons/games/.

- Each cell is 256 wide x 341.33 tall.
- Icons are square (~256x256) centered vertically within each cell.
- We auto-detect the tight content bounding box per cell, then upscale to
  1024x1024 with LANCZOS so the output matches the existing icon dimensions.
"""

from PIL import Image, ImageChops
import numpy as np
from pathlib import Path

SRC = '/home/z/my-project/upload/file_0000000032a4720ba04c5f6d587498bd.png'
DEST_DIR = Path('/home/z/my-project/Daxelo-Kinrel-App/assets/icons/games')
OUT_DIR = Path('/home/z/my-project/download/split_icons')
OUT_DIR.mkdir(parents=True, exist_ok=True)

# Mapping: (row, col) 1-indexed -> existing filename in assets/icons/games/
# Layout per VLM analysis (top-left to bottom-right reading order):
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
print(f"Source: {W}x{H}")

# Final output icon size (matches existing files)
OUT_SIZE = 1024


def tight_bbox(cell_im: Image.Image, bg_color):
    """Find tight content bbox by detecting pixels that differ from bg."""
    arr = np.array(cell_im)
    bg = np.array(bg_color)
    # Distance from bg
    diff = np.abs(arr.astype(int) - bg.astype(int)).sum(axis=2)
    mask = diff > 24  # tolerance threshold
    if not mask.any():
        return None
    ys, xs = np.where(mask)
    return (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)


results = []
for (r, c), fname in MAPPING.items():
    # Cell bounds (floats -> ints)
    x0 = int(round((c - 1) * CELL_W))
    x1 = int(round(c * CELL_W))
    y0 = int(round((r - 1) * ROW_H))
    y1 = int(round(r * ROW_H))
    cell = src_im.crop((x0, y0, x1, y1))

    # Sample background color from corners of the cell
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

    # Add small padding so icons don't touch edges
    pad = 6
    bx0 = max(0, bbox[0] - pad)
    by0 = max(0, bbox[1] - pad)
    bx1 = min(cell.width, bbox[2] + pad)
    by1 = min(cell.height, bbox[3] + pad)

    tight = cell.crop((bx0, by0, bx1, by1))
    # Make square by padding with bg_color if not square
    w, h = tight.size
    side = max(w, h)
    square = Image.new('RGB', (side, side), bg_color)
    square.paste(tight, ((side - w) // 2, (side - h) // 2))

    # Upscale to OUT_SIZE with high-quality LANCZOS
    final = square.resize((OUT_SIZE, OUT_SIZE), Image.LANCZOS)

    # Save to both download dir (preview) and assets dir (replacement)
    preview_path = OUT_DIR / fname
    final.save(preview_path, 'PNG', optimize=True)

    asset_path = DEST_DIR / fname
    final.save(asset_path, 'PNG', optimize=True)

    results.append((fname, w, h, side))
    print(f"  {fname:30s} cell=({cell.width}x{cell.height}) tight=({w}x{h}) -> {OUT_SIZE}x{OUT_SIZE}")

print(f"\nDone. {len(results)} icons saved to:")
print(f"  Preview: {OUT_DIR}")
print(f"  Assets:  {DEST_DIR}")
