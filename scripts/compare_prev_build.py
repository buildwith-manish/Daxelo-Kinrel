import os
#!/usr/bin/env python3
"""Fetch events for the previous successful deployment to compare."""
import json, urllib.request, urllib.error

TOKEN = os.environ.get("VERCEL_TOKEN", "")
TEAM = "team_wHW013lfpn4IkolJAvbPzux7"

def get(path):
    url = f"https://api.vercel.com{path}"
    sep = "&" if "?" in url else "?"
    url += f"{sep}teamId={TEAM}"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {TOKEN}"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        return {"error": e.code, "body": e.read().decode()[:400]}

# Previous successful deployment: dpl_3poYtddy (commit 4646eaa at 06:50:47)
PREV = "dpl_3poYtddy"
# Get the actual deployment UID by fetching project deployments
resp = get(f"/v6/deployments?projectId=prj_N8xJJpSuL073ulQYN4HLi7CwXA3Q&limit=10")
for d in resp.get("deployments", []):
    sha = d.get("meta", {}).get("githubCommitSha", "")
    state = d.get("status", "?")
    uid = d.get("uid", "?")
    created = d.get("createdAt", 0)
    import time
    print(f"  uid={uid[:18]} state={state:8} sha={sha[:7]} created={time.strftime('%H:%M:%S', time.localtime(created/1000))}")

# Find the most recent READY deployment
ready_uid = None
for d in resp.get("deployments", []):
    if d.get("status") == "READY":
        ready_uid = d["uid"]
        print(f"\nFetching events for last READY deployment: {ready_uid}")
        break

if ready_uid:
    events = get(f"/v3/deployments/{ready_uid}/events")
    if isinstance(events, list):
        for e in events:
            ts = e.get("created", "")
            msg = e.get("text", "").rstrip()
            if msg:
                print(f"  [{ts}] {msg}")
    else:
        print(events)
