#!/usr/bin/env python3
"""Retry the 9 failed icons with max_workers=2 and 3 retries each."""
import subprocess, time
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed

OUT_DIR = Path('/home/z/my-project/download/fresh_icons')

STYLE = (
    "glossy 3D rendered app icon, vibrant solid-color background, "
    "centered composition, full-bleed artwork filling the entire square, "
    "soft studio lighting, smooth rounded shapes, modern mobile game icon style, "
    "highly detailed, professional quality. "
    "ABSOLUTELY NO text, NO captions, NO numbers, NO letters, NO words, "
    "NO labels, NO watermark, NO border, NO frame. Pure artwork only."
)

ALL_GAMES = {
    'ghost-painter.png': "A cute friendly cartoon ghost holding a colorful paintbrush, with a small splash of pink paint, soft pastel pink background",
    'freeze-dash.png': "A cartoon boy character running fast, motion lines, a blue snowflake floating above, vibrant lime-green background",
    'sos.png': "Three stacked wooden tile pieces spelling nothing in particular but with red and white SOS-style tiles, a small life preserver ring beside them, vibrant coral-red background",
    'antakshari.png': "A golden musical note with a microphone, surrounded by small floating musical symbols, vibrant purple background",
    'bingo.png': "A bingo card grid with colorful red dauber marks, white calling balls with numbers, vibrant blue background",
    'checkers.png': "A stack of red and black checker discs with one piece mid-jump, checkerboard pattern in the corner, vibrant teal-blue background",
    'ludo.png': "Four colorful pawns (red, blue, green, yellow) arranged in a circle around a single die showing dots, vibrant red-orange background",
    'carrom.png': "A wooden carrom board from above with white and black coins and a red striker piece, vibrant orange background",
    'chess.png': "A white king chess piece and a black queen chess piece standing face-to-face, vibrant slate-gray background",
    'chitmatch.png': "Three playing cards fanned out with golden stars on them, sparkles around, vibrant teal-green background",
    'nameplace.png': "A stack of colorful alphabet letter tiles (A, B, C) with a yellow pencil resting on top, vibrant leaf-green background",
    'tictactoe.png': "A tic-tac-toe grid with three X marks and two O marks, the third row showing a winning diagonal of X, vibrant sky-blue background",
    'truthordare.png': "An empty green glass bottle lying on its side as if just spun, vibrant crimson-red background",
    'twotruths.png': "A stylized cartoon head silhouette with a question mark above, two small green checkmarks and one red X floating around, vibrant hot-pink background",
    'dotsboxes.png': "A grid of dots connected by lines forming one completed box in the center, blue lines on white dots, vibrant royal-blue background",
    'hot-seat.png': "A single red velvet armchair viewed from the front, spotlit from above, vibrant warm-orange background",
    'relation-riddles.png': "A small family tree diagram with three connected figures (parent and two children) and a question mark above, vibrant purple background",
    'truth-streak.png': "A stylized orange flame with a glowing number seven inside it, sparkles, vibrant orange background",
}


def gen_one_with_retry(fname, max_retries=4):
    out = OUT_DIR / fname
    prompt = f"{ALL_GAMES[fname]}. {STYLE}"
    cmd = ['z-ai', 'image', '-p', prompt, '-o', str(out), '-s', '1024x1024']
    for attempt in range(1, max_retries + 1):
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=240)
            if r.returncode == 0 and out.exists() and out.stat().st_size > 5000:
                return (fname, True, out.stat().st_size, attempt)
            # Rate-limit error: wait longer
            time.sleep(15 * attempt)
        except subprocess.TimeoutExpired:
            time.sleep(10)
        except Exception:
            time.sleep(10)
    return (fname, False, 0, max_retries)


# Find missing icons
missing = [f for f in ALL_GAMES if not (OUT_DIR / f).exists() or (OUT_DIR / f).stat().st_size < 5000]
print(f"Missing icons: {len(missing)}")
print(f"  {missing}\n")

# Generate 2 at a time (lower concurrency to avoid rate limits)
with ThreadPoolExecutor(max_workers=2) as ex:
    futures = {ex.submit(gen_one_with_retry, f): f for f in missing}
    for fut in as_completed(futures):
        fname, ok, info, attempts = fut.result()
        if ok:
            print(f"  ✓ {fname}  ({info//1024}KB, {attempts} attempt(s))")
        else:
            print(f"  ✗ {fname}  -> failed after {attempts} attempts")

# Final state
print("\n=== Final state ===")
present = sorted(f.name for f in OUT_DIR.iterdir() if f.suffix == '.png')
print(f"Icons present: {len(present)}/18")
still_missing = [f for f in ALL_GAMES if f not in present]
if still_missing:
    print(f"Still missing: {still_missing}")
