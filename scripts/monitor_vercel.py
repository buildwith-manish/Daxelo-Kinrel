#!/usr/bin/env python3
"""
Monitor Vercel deployment for project prj_N8xJJpSuL073ulQYN4HLi7CwXA3Q.
Polls /v6/deployments every 15s until the latest deployment is READY.
"""
import os, sys, time, json, urllib.request, urllib.error

TOKEN = os.environ.get("VERCEL_TOKEN", "")
TEAM = "team_wHW013lfpn4IkolJAvbPzux7"
PROJECT = "prj_N8xJJpSuL073ulQYN4HLi7CwXA3Q"

def api(path, method="GET", body=None, with_limit=True):
    url = f"https://api.vercel.com{path}"
    sep = "&" if "?" in url else "?"
    url += f"{sep}teamId={TEAM}"
    if with_limit:
        url += "&limit=10"
    headers = {
        "Authorization": f"Bearer {TOKEN}",
        "Content-Type": "application/json",
    }
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        return {"error": e.code, "body": e.read().decode()[:400]}

print(f"Fetching latest deployments for project {PROJECT}...")
resp = api(f"/v6/deployments?projectId={PROJECT}&limit=5&target=production", with_limit=False)
if "error" in resp:
    print(f"ERROR: {resp}")
    sys.exit(1)

deps = resp.get("deployments", [])
print(f"Found {len(deps)} recent deployments:")
for d in deps[:5]:
    meta = d.get("meta", {})
    print(f"  - uid={d.get('uid','?')[:12]} state={d.get('status','?'):12} created={time.strftime('%H:%M:%S', time.localtime(d.get('createdAt',0)/1000))} ref={meta.get('githubCommitRef','?')} sha={meta.get('githubCommitSha','?')[:7]}")

# Find deployment matching our commit (9b0d38e)
TARGET_SHA = "9b0d38e"
target = None
for d in deps:
    sha = d.get("meta", {}).get("githubCommitSha", "")
    if sha.startswith(TARGET_SHA):
        target = d
        break

if not target:
    print(f"\nNo deployment yet for commit {TARGET_SHA}. Watching for new deployment...")
    # Poll for up to 2 minutes for the deployment to appear
    for _ in range(8):
        time.sleep(15)
        resp = api(f"/v6/deployments?projectId={PROJECT}&limit=3", with_limit=False)
        for d in resp.get("deployments", []):
            sha = d.get("meta", {}).get("githubCommitSha", "")
            if sha.startswith(TARGET_SHA):
                target = d
                break
        if target:
            break
        print("  ... still waiting")

if not target:
    print(f"\nTIMEOUT: No deployment appeared for commit {TARGET_SHA}")
    print("Listing all recent deployments again for diagnosis:")
    resp = api(f"/v6/deployments?projectId={PROJECT}&limit=10", with_limit=False)
    for d in resp.get("deployments", [])[:10]:
        meta = d.get("meta", {})
        print(f"  - uid={d.get('uid','?')[:12]} state={d.get('status','?'):12} sha={meta.get('githubCommitSha','?')[:7]} ref={meta.get('githubCommitRef','?')}")
    sys.exit(2)

uid = target["uid"]
print(f"\nTracking deployment uid={uid} for commit {TARGET_SHA}")
print(f"Initial state: {target.get('status')}")

# Poll until terminal state
last_state = None
for attempt in range(80):  # up to 20 minutes
    state_resp = api(f"/v13/deployments/{uid}")
    state = state_resp.get("status") or state_resp.get("readyState")
    if state != last_state:
        ts = time.strftime('%H:%M:%S')
        print(f"[{ts}] state={state}")
        last_state = state
    if state in ("READY", "ERROR", "CANCELED"):
        break
    time.sleep(15)

print(f"\nFinal state: {state}")
if state == "READY":
    url = f"https://{state_resp.get('url')}"
    print(f"Deployment URL: {url}")
    # Also fetch inspect URL
    inspector = f"https://vercel.com/{state_resp.get('team',{}).get('slug','daxelo-kinrel')}/{state_resp.get('name','daxelo-kinrel')}/{uid}"
    print(f"Inspect URL:    {inspector}")
elif state == "ERROR":
    print("Build failed. Fetching build logs...")
    logs_resp = api(f"/v2/deployments/{uid}/builds")
    print(json.dumps(logs_resp, indent=2)[:2000])

# Save final result
result = {
    "commit": TARGET_SHA,
    "deployment_uid": uid,
    "final_state": state,
    "url": state_resp.get("url"),
    "inspector_url": inspector if state == "READY" else None,
}
with open("/home/z/my-project/download/vercel_deploy_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("\nResult saved to /home/z/my-project/download/vercel_deploy_result.json")
