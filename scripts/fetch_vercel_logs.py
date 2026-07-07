import os
#!/usr/bin/env python3
"""Fetch detailed build logs for failed deployment."""
import json, urllib.request, urllib.error

TOKEN = os.environ.get("VERCEL_TOKEN", "")
TEAM = "team_wHW013lfpn4IkolJAvbPzux7"
DPL = "dpl_AV3QRcoEDpwjr35DC6coRHxUr3kv"

def get(path, raw=False):
    url = f"https://api.vercel.com{path}"
    sep = "&" if "?" in url else "?"
    url += f"{sep}teamId={TEAM}"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {TOKEN}"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            data = r.read().decode()
            return data if raw else json.loads(data)
    except urllib.error.HTTPError as e:
        return {"error": e.code, "body": e.read().decode()[:600]}

# Try multiple log endpoints
endpoints = [
    f"/v2/deployments/{DPL}/events",
    f"/v3/deployments/{DPL}/events",
    f"/v6/deployments/{DPL}/events",
    f"/v1/deployments/{DPL}/logs",
]

for ep in endpoints:
    print("=" * 60)
    print(f"ENDPOINT: {ep}")
    print("=" * 60)
    r = get(ep)
    if isinstance(r, dict) and "error" in r:
        print(f"  HTTP {r['error']}: {r['body'][:200]}")
        continue
    # Could be list or dict
    events = r if isinstance(r, list) else r.get("events", r.get("logs", []))
    print(f"  Got {len(events)} entries")
    for e in events[-50:]:
        if isinstance(e, dict):
            ts = e.get("created", "")
            msg = e.get("text", e.get("message", "")).rstrip()
        else:
            ts = ""
            msg = str(e).rstrip()
        if msg:
            print(f"  [{ts}] {msg}")

# Also try the deployment itself with full info
print()
print("=" * 60)
print("FULL DEPLOYMENT OBJECT")
print("=" * 60)
d = get(f"/v13/deployments/{DPL}")
# Print relevant error fields
for k in ["status", "readyState", "errorMessage", "errorLink", "aliasError", "aliasAssigned", "readyStateAt", "buildingAt", "createdAt"]:
    print(f"  {k}: {d.get(k)}")
print()
# Save full json
with open("/home/z/my-project/download/vercel_deploy_full.json", "w") as f:
    json.dump(d, f, indent=2)
print("Full deployment JSON saved to /home/z/my-project/download/vercel_deploy_full.json")
