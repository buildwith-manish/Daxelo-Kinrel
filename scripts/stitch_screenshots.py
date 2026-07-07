"""Stitch the 4 scroll screenshots vertically into one long image."""
from PIL import Image
from pathlib import Path

SRC = Path('/home/z/my-project/download/verification')
OUT = SRC / 'live_games_screen_full.png'

parts = ['scroll_1_top.png', 'scroll_2_mid.png', 'scroll_3_lower.png', 'scroll_4_bottom.png']
imgs = [Image.open(SRC / p).convert('RGB') for p in parts]
W = imgs[0].width
# Use 80% overlap reduction — keep last 20% of each image as continuation
# Actually, just stack with no overlap for clarity
H = sum(i.height for i in imgs)
stitched = Image.new('RGB', (W, H), (10, 10, 14))  # dark bg
y = 0
for im in imgs:
    stitched.paste(im, (0, y))
    y += im.height
stitched.save(OUT, 'PNG')
print(f"Saved: {OUT} ({W}x{H})")
