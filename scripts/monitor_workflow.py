#!/usr/bin/env python3
"""
Monitor a GitHub Actions workflow run until completion.
Prints job-by-job status updates as they happen.
"""
import json
import os
import sys
import time
import urllib.request

GH_PAT = os.environ["GH_PAT"]
REPO = "buildwith-manish/Daxelo-Kinrel"
RUN_ID = sys.argv[1] if len(sys.argv) > 1 else None

if not RUN_ID:
    print("Usage: monitor_workflow.py <run_id>", file=sys.stderr)
    sys.exit(1)


def api(path):
    req = urllib.request.Request(
        f"https://api.github.com/repos/{REPO}/{path}",
        headers={
            "Authorization": f"token {GH_PAT}",
            "Accept": "application/vnd.github+json",
        },
    )
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())


def fmt_job(job):
    name = job["name"]
    status = job["status"]
    concl = job.get("conclusion") or "—"
    return f"  {name:40s} status={status:12s} conclusion={concl}"


last_jobs_signature = None
last_run_status = None
last_run_concl = None

print(f"Monitoring run {RUN_ID}...")
print(f"URL: https://github.com/{REPO}/actions/runs/{RUN_ID}")
print()

start = time.time()
while True:
    try:
        run = api(f"actions/runs/{RUN_ID}")
        jobs = api(f"actions/runs/{RUN_ID}/jobs")["jobs"]
    except Exception as e:
        print(f"  (API error: {e})")
        time.sleep(15)
        continue

    elapsed = int(time.time() - start)
    run_status = run["status"]
    run_concl = run.get("conclusion") or "—"

    # Build a signature of all job statuses — only print if changed
    sig = tuple((j["name"], j["status"], j.get("conclusion")) for j in jobs)
    if sig != last_jobs_signature or run_status != last_run_status or run_concl != last_run_concl:
        print(f"\n[{elapsed:4d}s] run status={run_status} conclusion={run_concl}")
        for j in sorted(jobs, key=lambda x: x.get("started_at") or ""):
            print(fmt_job(j))
        last_jobs_signature = sig
        last_run_status = run_status
        last_run_concl = run_concl

    if run_status == "completed":
        print(f"\n=== RUN COMPLETED — conclusion={run_concl} ===")
        print(f"Total elapsed: {elapsed}s")
        # Print job conclusion summary
        for j in sorted(jobs, key=lambda x: x.get("started_at") or ""):
            concl = j.get("conclusion") or "—"
            icon = "✅" if concl == "success" else "❌" if concl in ("failure", "cancelled") else "⚠️"
            print(f"  {icon} {j['name']}: {concl}")
            # If failed, print the most recent failed step
            if concl in ("failure", "cancelled"):
                for step in j.get("steps", []):
                    if step.get("conclusion") in ("failure", "cancelled"):
                        print(f"     failed step: {step['name']}")
                        break
        sys.exit(0 if run_concl == "success" else 1)

    time.sleep(20)
