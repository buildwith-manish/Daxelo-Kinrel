"""Stitch the 4 v2 scroll screenshots vertically into one long image."""
from PIL import Image
from pathlib import Path

SRC = Path('/home/z/my-project/download/verification')
OUT = SRC / 'v2_live_games_screen_full.png'

parts = ['v2_games_top.png', 'v2_games_mid1.png', 'v2_games_mid2.png', 'v2_games_bottom.png']
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
