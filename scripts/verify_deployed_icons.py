#!/usr/bin/env python3
"""
Verify the deployed Vercel site serves the 18 new (1024x1024) game icons.
Compares content-md5 of each deployed icon vs. the local file in the repo.
"""
import hashlib, urllib.request, urllib.error, sys
from pathlib import Path

BASE = "https://daxelo-kinrel.vercel.app"
LOCAL_DIR = Path("/home/z/my-project/Daxelo-Kinrel-App/assets/icons/games")

# The 18 game icons (filenames match the local repo)
ICONS = [
    "ghost-painter.png", "freeze-dash.png", "sos.png", "antakshari.png",
    "bingo.png", "checkers.png", "ludo.png", "carrom.png", "chess.png",
    "chitmatch.png", "nameplace.png", "tictactoe.png", "truthordare.png",
    "twotruths.png", "dotsboxes.png", "hot-seat.png", "relation-riddles.png",
    "truth-streak.png",
]

# Flutter web asset paths look like:
#   /assets/assets/icons/games/<name>.png?<hash>
# We just fetch without query string.
def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "VercelIconVerifier/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.read(), r.status, dict(r.headers)
    except urllib.error.HTTPError as e:
        return None, e.code, dict(e.headers)

print(f"Verifying {len(ICONS)} game icons at {BASE}\n")
print(f"{'Icon':<24} {'Status':<8} {'Local KB':>10} {'Remote KB':>10} {'md5 match':<10} {'Cache-Control':<40}")
print("-" * 110)

all_match = True
results = []
for name in ICONS:
    # Try both with /assets/assets/... (Flutter web asset path) and /assets/icons/...
    candidates = [
        f"{BASE}/assets/assets/icons/games/{name}",
        f"{BASE}/assets/icons/games/{name}",
    ]
    body = None
    status = None
    hdrs = {}
    used_url = None
    for url in candidates:
        body, status, hdrs = fetch(url)
        if status == 200 and body:
            used_url = url
            break

    local_path = LOCAL_DIR / name
    local_bytes = local_path.read_bytes() if local_path.exists() else b""
    local_md5 = hashlib.md5(local_bytes).hexdigest()
    remote_md5 = hashlib.md5(body).hexdigest() if body else "none"
    match = "YES" if local_md5 == remote_md5 else "NO"
    if match == "NO":
        all_match = False

    cc = hdrs.get("Cache-Control", hdrs.get("cache-control", ""))[:40]
    print(f"{name:<24} {str(status):<8} {len(local_bytes)//1024:>8}KB {len(body or b'')//1024:>8}KB {match:<10} {cc:<40}")
    results.append({"name": name, "status": status, "local_kb": len(local_bytes)//1024, "remote_kb": len(body or b'')//1024, "md5_match": match, "url": used_url})

print()
if all_match:
    print(f"✅ ALL {len(ICONS)} icons match local files exactly. Deploy is serving the new icons.")
else:
    print(f"❌ Some icons don't match. Check above.")
    sys.exit(1)

# Save results
import json
with open("/home/z/my-project/download/icon_verification.json", "w") as f:
    json.dump(results, f, indent=2)
print(f"\nDetailed results saved to /home/z/my-project/download/icon_verification.json")
