#!/usr/bin/env python3
"""
Set GitHub Actions secrets for the Daxelo-Kinrel repo.
Reads values from environment variables to avoid shell escaping issues.
"""
import base64
import json
import os
import sys
import urllib.request
import urllib.error
import subprocess

# Install pynacl if missing
try:
    from nacl import public, encoding
except ImportError:
    subprocess.check_call([sys.executable, "-m", "pip", "install", "pynacl", "--quiet"])
    from nacl import public, encoding

GH_PAT = os.environ["GH_PAT"]
REPO = "buildwith-manish/Daxelo-Kinrel"
VERCEL_TOKEN = os.environ["VERCEL_TOKEN"]
VERCEL_TEAM_ID = os.environ["VERCEL_TEAM_ID"]

print(f"Setting secrets on {REPO}...")

# 1. Fetch repo public key
req = urllib.request.Request(
    f"https://api.github.com/repos/{REPO}/actions/secrets/public-key",
    headers={
        "Authorization": f"token {GH_PAT}",
        "Accept": "application/vnd.github+json",
    },
)
with urllib.request.urlopen(req) as resp:
    key_resp = json.loads(resp.read())

key_id = key_resp["key_id"]
key_b64 = key_resp["key"]
print(f"  Public key ID: {key_id}, key length: {len(key_b64)} chars")

pub_key = public.PublicKey(key_b64.encode(), encoding.Base64Encoder())
sealed = public.SealedBox(pub_key)


def set_secret(name: str, value: str) -> None:
    encrypted = sealed.encrypt(value.encode())
    body = {
        "encrypted_value": base64.b64encode(encrypted).decode(),
        "key_id": key_id,
    }
    req = urllib.request.Request(
        f"https://api.github.com/repos/{REPO}/actions/secrets/{name}",
        data=json.dumps(body).encode(),
        method="PUT",
        headers={
            "Authorization": f"token {GH_PAT}",
            "Accept": "application/vnd.github+json",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req) as resp:
            print(f"  {name}: HTTP {resp.status}")
    except urllib.error.HTTPError as e:
        print(f"  {name}: HTTP {e.code} - {e.read().decode()}")


set_secret("VERCEL_TOKEN", VERCEL_TOKEN)
set_secret("VERCEL_TEAM_ID", VERCEL_TEAM_ID)

# Verify
req = urllib.request.Request(
    f"https://api.github.com/repos/{REPO}/actions/secrets",
    headers={
        "Authorization": f"token {GH_PAT}",
        "Accept": "application/vnd.github+json",
    },
)
with urllib.request.urlopen(req) as resp:
    data = json.loads(resp.read())
print(f"\nAll secrets now set: {[s['name'] for s in data.get('secrets', [])]}")
