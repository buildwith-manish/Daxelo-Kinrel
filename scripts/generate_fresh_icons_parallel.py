#!/usr/bin/env python3
"""
Parallel batch generator for the remaining 15 game icons.
Runs 4 z-ai image calls concurrently to minimize wall-clock time.
"""
import subprocess, time, os
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed

OUT_DIR = Path('/home/z/my-project/download/fresh_icons')
OUT_DIR.mkdir(parents=True, exist_ok=True)

STYLE = (
    "glossy 3D rendered app icon, vibrant solid-color background, "
    "centered composition, full-bleed artwork filling the entire square, "
    "soft studio lighting, smooth rounded shapes, modern mobile game icon style, "
    "highly detailed, professional quality. "
    "ABSOLUTELY NO text, NO captions, NO numbers, NO letters, NO words, "
    "NO labels, NO watermark, NO border, NO frame. Pure artwork only."
)

# Only generate icons that don't already exist
ALL_GAMES = [
    ('ghost-painter.png', "A cute friendly cartoon ghost holding a colorful paintbrush, with a small splash of pink paint, soft pastel pink background"),
    ('freeze-dash.png', "A cartoon boy character running fast, motion lines, a blue snowflake floating above, vibrant lime-green background"),
    ('sos.png', "Three stacked wooden tile pieces spelling nothing in particular but with red and white SOS-style tiles, a small life preserver ring beside them, vibrant coral-red background"),
    ('antakshari.png', "A golden musical note with a microphone, surrounded by small floating musical symbols, vibrant purple background"),
    ('bingo.png', "A bingo card grid with colorful red dauber marks, white calling balls with numbers, vibrant blue background"),
    ('checkers.png', "A stack of red and black checker discs with one piece mid-jump, checkerboard pattern in the corner, vibrant teal-blue background"),
    ('ludo.png', "Four colorful pawns (red, blue, green, yellow) arranged in a circle around a single die showing dots, vibrant red-orange background"),
    ('carrom.png', "A wooden carrom board from above with white and black coins and a red striker piece, vibrant orange background"),
    ('chess.png', "A white king chess piece and a black queen chess piece standing face-to-face, vibrant slate-gray background"),
    ('chitmatch.png', "Three playing cards fanned out with golden stars on them, sparkles around, vibrant teal-green background"),
    ('nameplace.png', "A stack of colorful alphabet letter tiles (A, B, C) with a yellow pencil resting on top, vibrant leaf-green background"),
    ('tictactoe.png', "A tic-tac-toe grid with three X marks and two O marks, the third row showing a winning diagonal of X, vibrant sky-blue background"),
    ('truthordare.png', "An empty green glass bottle lying on its side as if just spun, vibrant crimson-red background"),
    ('twotruths.png', "A stylized cartoon head silhouette with a question mark above, two small green checkmarks and one red X floating around, vibrant hot-pink background"),
    ('dotsboxes.png', "A grid of dots connected by lines forming one completed box in the center, blue lines on white dots, vibrant royal-blue background"),
    ('hot-seat.png', "A single red velvet armchair viewed from the front, spotlit from above, vibrant warm-orange background"),
    ('relation-riddles.png', "A small family tree diagram with three connected figures (parent and two children) and a question mark above, vibrant purple background"),
    ('truth-streak.png', "A stylized orange flame with a glowing number seven inside it, sparkles, vibrant orange background"),
]

# Only generate what's missing
TODO = [(f, s) for f, s in ALL_GAMES if not (OUT_DIR / f).exists() or (OUT_DIR / f).stat().st_size < 5000]
print(f"Need to generate: {len(TODO)} icons")
print(f"Already have: {len(ALL_GAMES) - len(TODO)} icons")


def gen_one(item):
    fname, subject = item
    out = OUT_DIR / fname
    prompt = f"{subject}. {STYLE}"
    cmd = ['z-ai', 'image', '-p', prompt, '-o', str(out), '-s', '1024x1024']
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=240)
        if r.returncode == 0 and out.exists() and out.stat().st_size > 5000:
            return (fname, True, out.stat().st_size)
        return (fname, False, f"rc={r.returncode} stderr={r.stderr[:200]}")
    except subprocess.TimeoutExpired:
        return (fname, False, "timeout")
    except Exception as e:
        return (fname, False, str(e))


# Run 4 at a time
with ThreadPoolExecutor(max_workers=4) as ex:
    futures = {ex.submit(gen_one, item): item[0] for item in TODO}
    for fut in as_completed(futures):
        fname, ok, info = fut.result()
        if ok:
            print(f"  ✓ {fname}  ({info//1024}KB)")
        else:
            print(f"  ✗ {fname}  -> {info}")

# Final check
print("\n=== Final state ===")
present = sorted(f.name for f in OUT_DIR.iterdir() if f.suffix == '.png')
print(f"Icons in {OUT_DIR}: {len(present)}")
for n in present:
    sz = (OUT_DIR / n).stat().st_size
    print(f"  {n}  ({sz//1024}KB)")
