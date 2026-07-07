#!/usr/bin/env python3
"""
Generate 18 fresh, clean game icons using the z-ai image generation CLI.

Each icon:
- 1024x1024 PNG
- NO text, NO captions, NO numbers, NO labels
- Glossy 3D render style, vibrant solid-color background
- Centered subject, full-bleed artwork
- Saved to /home/z/my-project/download/fresh_icons/{filename}

We use a consistent style suffix appended to every prompt to enforce visual
coherence across the set, and we explicitly forbid text/captions.
"""
import subprocess, sys, time, os, shutil
from pathlib import Path

OUT_DIR = Path('/home/z/my-project/download/fresh_icons')
OUT_DIR.mkdir(parents=True, exist_ok=True)

# Common style suffix appended to EVERY prompt for visual coherence
STYLE = (
    "glossy 3D rendered app icon, vibrant solid-color background, "
    "centered composition, full-bleed artwork filling the entire square, "
    "soft studio lighting, smooth rounded shapes, modern mobile game icon style, "
    "highly detailed, professional quality. "
    "ABSOLUTELY NO text, NO captions, NO numbers, NO letters, NO words, "
    "NO labels, NO watermark, NO border, NO frame. Pure artwork only."
)

# 18 games with concise, vivid artwork descriptions
# Each subject described so the model has a clear focal point.
GAMES = [
    ('ghost-painter.png',
     "A cute friendly cartoon ghost holding a colorful paintbrush, "
     "with a small splash of pink paint, soft pastel pink background"),
    ('freeze-dash.png',
     "A cartoon boy character running fast, motion lines, a blue snowflake floating above, "
     "vibrant lime-green background"),
    ('sos.png',
     "Three stacked wooden tile pieces spelling nothing in particular but with red and white SOS-style tiles, "
     "a small life preserver ring beside them, vibrant coral-red background"),
    ('antakshari.png',
     "A golden musical note with a microphone, surrounded by small floating musical symbols, "
     "vibrant purple background"),
    ('bingo.png',
     "A bingo card grid with colorful red dauber marks, white calling balls with numbers, "
     "vibrant blue background"),
    ('checkers.png',
     "A stack of red and black checker discs with one piece mid-jump, "
     "checkerboard pattern in the corner, vibrant teal-blue background"),
    ('ludo.png',
     "Four colorful pawns (red, blue, green, yellow) arranged in a circle around a single die showing dots, "
     "vibrant red-orange background"),
    ('carrom.png',
     "A wooden carrom board from above with white and black coins and a red striker piece, "
     "vibrant orange background"),
    ('chess.png',
     "A white king chess piece and a black queen chess piece standing face-to-face, "
     "vibrant slate-gray background"),
    ('chitmatch.png',
     "Three playing cards fanned out with golden stars on them, sparkles around, "
     "vibrant teal-green background"),
    ('nameplace.png',
     "A stack of colorful alphabet letter tiles (A, B, C) with a yellow pencil resting on top, "
     "vibrant leaf-green background"),
    ('tictactoe.png',
     "A tic-tac-toe grid with three X marks and two O marks, the third row showing a winning diagonal of X, "
     "vibrant sky-blue background"),
    ('truthordare.png',
     "An empty green glass bottle lying on its side as if just spun, "
     "vibrant crimson-red background"),
    ('twotruths.png',
     "A stylized cartoon head silhouette with a question mark above, two small green checkmarks and one red X floating around, "
     "vibrant hot-pink background"),
    ('dotsboxes.png',
     "A grid of dots connected by lines forming one completed box in the center, blue lines on white dots, "
     "vibrant royal-blue background"),
    ('hot-seat.png',
     "A single red velvet armchair viewed from the front, spotlit from above, "
     "vibrant warm-orange background"),
    ('relation-riddles.png',
     "A small family tree diagram with three connected figures (parent and two children) and a question mark above, "
     "vibrant purple background"),
    ('truth-streak.png',
     "A stylized orange flame with a glowing number seven inside it, sparkles, "
     "vibrant orange background"),
]


def generate_one(prompt: str, out_path: Path, timeout: int = 180) -> bool:
    """Invoke z-ai image CLI to generate one icon."""
    cmd = ['z-ai', 'image', '-p', prompt, '-o', str(out_path), '-s', '1024x1024']
    print(f"  CMD: z-ai image -p '<{len(prompt)} chars>' -o {out_path.name} -s 1024x1024")
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        if r.returncode == 0 and out_path.exists() and out_path.stat().st_size > 5000:
            print(f"  ✓ OK ({out_path.stat().st_size//1024}KB)")
            return True
        else:
            print(f"  ✗ FAIL rc={r.returncode}")
            print(f"    stderr: {r.stderr[:400]}")
            print(f"    stdout: {r.stdout[:400]}")
            return False
    except subprocess.TimeoutExpired:
        print(f"  ✗ TIMEOUT ({timeout}s)")
        return False


def main():
    print(f"Generating {len(GAMES)} fresh icons to {OUT_DIR}")
    print(f"Style suffix ({len(STYLE)} chars) appended to every prompt\n")
    successes = []
    failures = []
    for fname, subject in GAMES:
        out = OUT_DIR / fname
        prompt = f"{subject}. {STYLE}"
        print(f"\n[{fname}]")
        ok = generate_one(prompt, out)
        if ok:
            successes.append(fname)
        else:
            failures.append(fname)
        # small delay to avoid rate limits
        time.sleep(2)
    print(f"\n=== Summary ===")
    print(f"Success: {len(successes)}/{len(GAMES)}")
    if failures:
        print(f"Failed: {failures}")
    return 0 if not failures else 1


if __name__ == '__main__':
    sys.exit(main())
