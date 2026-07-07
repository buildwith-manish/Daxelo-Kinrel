"""
Scan ALL 18 fresh icons for text/letter content using VLM.
This catches any icon where text leaked through despite the prompt forbidding it.
"""
import subprocess, json, sys
from pathlib import Path

SRC = Path('/home/z/my-project/download/fresh_icons')

ICONS = sorted(p.name for p in SRC.iterdir() if p.suffix == '.png')
print(f"Scanning {len(ICONS)} icons for text content...\n")

results = {}
for name in ICONS:
    p = SRC / name
    # Run z-ai vision CLI on each
    cmd = ['z-ai', 'vision', '-p',
           'Examine this 1024x1024 game icon carefully. Look at EVERY part of the image (top, middle, bottom). '
           'Report: 1) Are there ANY letters, numbers, words, or text visible ANYWHERE in the image? '
           '2) If yes, what does the text say and where is it? '
           '3) Note: X and O marks in tic-tac-toe are game symbols, NOT text — those are OK. '
           'Letters A, B, C on alphabet blocks ARE text and should be flagged. '
           'Digits inside a flame ARE numbers and should be flagged. '
           'Answer in this format only: "TEXT: <description>" or "NO TEXT"',
           '-i', str(p)]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        # Extract content from JSON output
        out = r.stdout
        # Find the "content" field
        try:
            # The CLI prints JSON; find the JSON block
            j_start = out.find('{')
            if j_start >= 0:
                j = json.loads(out[j_start:])
                content = j.get('choices', [{}])[0].get('message', {}).get('content', '').strip()
            else:
                content = out[:500]
        except Exception:
            content = out[:500]
        results[name] = content
        flag = '⚠️' if 'NO TEXT' not in content.upper() else '✓'
        print(f"  {flag} {name:30s} -> {content[:120]}")
    except subprocess.TimeoutExpired:
        print(f"  ⚠ {name:30s} -> TIMEOUT")
        results[name] = "TIMEOUT"

# Save results
import json
with open('/home/z/my-project/download/verification/vlm_text_scan.json', 'w') as f:
    json.dump(results, f, indent=2)
print(f"\nResults saved to /home/z/my-project/download/verification/vlm_text_scan.json")
