import os
#!/usr/bin/env python3
"""Lightweight Vercel deployment monitor — polls every 20s, exits on terminal state."""
import json, urllib.request, time, sys

TOKEN = os.environ.get("VERCEL_TOKEN", "")
TEAM = "team_wHW013lfpn4IkolJAvbPzux7"
PROJECT = "prj_N8xJJpSuL073ulQYN4HLi7CwXA3Q"
TARGET_SHA = "9b0d38e"

def get(path):
    url = f"https://api.vercel.com{path}"
    sep = "&" if "?" in url else "?"
    url += f"{sep}teamId={TEAM}"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {TOKEN}"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode())

# Find target deployment
def find_target():
    resp = get(f"/v6/deployments?projectId={PROJECT}&limit=10")
    for d in resp.get("deployments", []):
        if d.get("meta", {}).get("githubCommitSha", "").startswith(TARGET_SHA):
            return d["uid"]
    return None

uid = find_target()
if not uid:
    print(f"No deployment yet for {TARGET_SHA}, waiting up to 5 min...")
    for _ in range(15):
        time.sleep(20)
        uid = find_target()
        if uid:
            break
if not uid:
    print("TIMEOUT: no deployment appeared")
    sys.exit(1)

print(f"Tracking deployment: {uid}")
last_state = None
start = time.time()
while time.time() - start < 1500:  # 25 min cap
    try:
        d = get(f"/v13/deployments/{uid}")
    except Exception as e:
        print(f"  API error: {e}")
        time.sleep(20)
        continue
    state = d.get("readyState") or d.get("status")
    if state != last_state:
        elapsed = int(time.time() - start)
        print(f"[+{elapsed:4d}s] state={state}")
        last_state = state
    if state in ("READY", "ERROR", "CANCELED"):
        break
    time.sleep(20)

print(f"\nFinal state: {state}")
print(f"URL: https://{d.get('url')}")
print(f"Inspect: https://vercel.com/daxelo-kinrel/{uid}")
if state == "ERROR":
    print(f"Error: {d.get('errorMessage')}")

# Save result
result = {
    "commit": TARGET_SHA,
    "deployment_uid": uid,
    "final_state": state,
    "url": f"https://{d.get('url')}" if d.get('url') else None,
    "error": d.get("errorMessage"),
}
with open("/home/z/my-project/download/vercel_deploy_result.json", "w") as f:
    json.dump(result, f, indent=2)

# If READY, fetch the events log to confirm completion
if state == "READY":
    print("\n=== Last 10 deployment events ===")
    events = get(f"/v3/deployments/{uid}/events")
    if isinstance(events, list):
        for e in events[-10:]:
            msg = e.get("text", "").rstrip()
            if msg:
                print(f"  {msg[:200]}")
