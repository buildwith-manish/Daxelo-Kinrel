"""Stitch the best v3 screenshots into one final verification image."""
from PIL import Image
from pathlib import Path

SRC = Path('/home/z/my-project/download/verification')
OUT = SRC / 'v3_final_live_games.png'

# Pick the 3 best non-overlapping screenshots that cover 15 games
parts = ['v3B_01_top.png', 'v3B_02.png', 'v3B_03.png']
imgs = [Image.open(SRC / p).convert('RGB') for p in parts]
W = imgs[0].width
H = sum(i.height for i in imgs)
stitched = Image.new('RGB', (W, H), (10, 10, 14))
y = 0
for im in imgs:
    stitched.paste(im, (0, y))
    y += im.height
stitched.save(OUT, 'PNG')
print(f"Saved: {OUT} ({W}x{H})")
