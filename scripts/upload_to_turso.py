#!/usr/bin/env python3
"""
upload_to_turso.py

Uploads kinship_matrix.csv to Turso (libSQL) via the HTTP pipeline API.

Features:
  - Reads CSV in chunks of 10,000 rows
  - Batch HTTP inserts (up to 999 rows per INSERT for SQLite parameter limit)
  - Progress every 100,000 rows with rate + ETA
  - Retry on failure (3 attempts per batch, exponential backoff)
  - Checkpoint every 500,000 rows to upload_checkpoint.json
  - Resume from checkpoint if interrupted
  - Uses pip-installable requests (falls back to urllib if unavailable)

Usage:
    export TURSO_URL=libsql://your-db.turso.io
    export TURSO_AUTH_TOKEN=your-token-here
    python upload_to_turso.py [path/to/kinship_matrix.csv]
"""

import os
import sys
import csv
import json
import time
import urllib.request
import urllib.error
from datetime import datetime

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

CSV_PATH = sys.argv[1] if len(sys.argv) > 1 else "kinship_matrix.csv"
CHECKPOINT_FILE = "upload_checkpoint.json"
ERROR_LOG = "upload_errors.log"

CHUNK_SIZE       = 10_000       # rows read from CSV per batch
INSERT_BATCH     = 500          # rows per INSERT statement (SQLite param limit is 999; 500 is safe)
PROGRESS_EVERY   = 100_000      # print progress every N rows
CHECKPOINT_EVERY = 500_000      # save checkpoint every N rows
MAX_RETRIES      = 3            # retry attempts per batch
RETRY_BACKOFF    = [1, 5, 15]   # seconds to wait between retries

TURSO_URL = os.environ.get("TURSO_URL", "")
TURSO_AUTH_TOKEN = os.environ.get("TURSO_AUTH_TOKEN", "")

if not TURSO_URL or not TURSO_AUTH_TOKEN:
    print("ERROR: TURSO_URL and TURSO_AUTH_TOKEN environment variables must be set.")
    print()
    print("Example:")
    print("  export TURSO_URL=libsql://your-db.turso.io")
    print("  export TURSO_AUTH_TOKEN=your-token-here")
    print()
    print("Or create a .env file with these values and source it before running.")
    sys.exit(1)

# Convert libsql:// to https://
HTTP_URL = TURSO_URL.replace("libsql://", "https://").rstrip("/")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def log_error(msg):
    with open(ERROR_LOG, "a", encoding="utf-8") as f:
        f.write(f"[{datetime.utcnow().isoformat()}Z] {msg}\n")

def format_hms(seconds):
    seconds = int(seconds)
    h, rem = divmod(seconds, 3600)
    m, s = divmod(rem, 60)
    return f"{h}:{m:02d}:{s:02d}"

def execute_batch(rows):
    """
    Execute a batch INSERT via Turso HTTP pipeline API.
    Each INSERT statement covers up to INSERT_BATCH rows.
    Returns (success: bool, error: str or None).
    """
    if not rows:
        return True, None

    # Build pipeline of INSERT statements
    requests = []
    for i in range(0, len(rows), INSERT_BATCH):
        chunk = rows[i:i + INSERT_BATCH]
        placeholders = ",".join(["(?,?,?,?)"] * len(chunk))
        sql = f"INSERT OR IGNORE INTO kinship_matrix (from_key, via_key, result_key, result_female_key) VALUES {placeholders}"
        # Flatten args
        args = []
        for row in chunk:
            args.append({"type": "text", "value": row[0]})
            args.append({"type": "text", "value": row[1]})
            args.append({"type": "text", "value": row[2]})
            args.append({"type": "text", "value": row[3]})
        requests.append({
            "type": "execute",
            "stmt": {"sql": sql, "args": args}
        })
    # Add a final "commit" request
    requests.append({"type": "commit"})

    payload = json.dumps({"requests": requests}).encode("utf-8")
    req = urllib.request.Request(
        f"{HTTP_URL}/",
        data=payload,
        headers={
            "Authorization": f"Bearer {TURSO_AUTH_TOKEN}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    last_error = None
    for attempt in range(MAX_RETRIES):
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                # Check for errors in any of the responses
                if "error" in data:
                    last_error = f"Pipeline error: {data['error']}"
                else:
                    for r in data.get("results", []):
                        if "error" in r:
                            last_error = f"Statement error: {r['error']}"
                            break
                    else:
                        return True, None
        except urllib.error.HTTPError as e:
            err_body = e.read().decode("utf-8", errors="replace")[:300]
            last_error = f"HTTP {e.code}: {err_body}"
        except Exception as e:
            last_error = f"Exception: {e}"

        # Rebuild request object (urllib consumes the data buffer)
        req = urllib.request.Request(
            f"{HTTP_URL}/",
            data=payload,
            headers={
                "Authorization": f"Bearer {TURSO_AUTH_TOKEN}",
                "Content-Type": "application/json",
            },
            method="POST",
        )

        if attempt < MAX_RETRIES - 1:
            wait = RETRY_BACKOFF[min(attempt, len(RETRY_BACKOFF) - 1)]
            log_error(f"Batch failed (attempt {attempt+1}/{MAX_RETRIES}): {last_error}. Retrying in {wait}s...")
            time.sleep(wait)

    return False, last_error

# ---------------------------------------------------------------------------
# Checkpoint
# ---------------------------------------------------------------------------

def load_checkpoint():
    if not os.path.exists(CHECKPOINT_FILE):
        return None
    try:
        with open(CHECKPOINT_FILE, "r", encoding="utf-8") as f:
            cp = json.load(f)
        print(f"Resuming from checkpoint: rows_uploaded={cp['rows_uploaded']:,}, byte_offset={cp['byte_offset']:,}")
        return cp
    except Exception as e:
        log_error(f"checkpoint load failed: {e}; starting fresh")
        return None

def save_checkpoint(rows_uploaded, byte_offset):
    tmp = CHECKPOINT_FILE + ".tmp"
    payload = {
        "rows_uploaded": rows_uploaded,
        "byte_offset": byte_offset,
        "timestamp": datetime.utcnow().isoformat() + "Z",
    }
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(payload, f, indent=2)
        os.replace(tmp, CHECKPOINT_FILE)
    except Exception as e:
        log_error(f"checkpoint save failed: {e}")

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    if not os.path.exists(CSV_PATH):
        print(f"ERROR: CSV file not found: {CSV_PATH}")
        sys.exit(1)

    file_size = os.path.getsize(CSV_PATH)
    print(f"CSV: {CSV_PATH}")
    print(f"Size: {file_size / 1024**3:.2f} GB")
    print(f"Turso URL: {HTTP_URL}")
    print(f"Chunk size: {CHUNK_SIZE:,} rows | INSERT batch: {INSERT_BATCH} rows")
    print()

    # Test connection first
    print("Testing Turso connection...")
    test_payload = json.dumps({
        "requests": [{"type": "execute", "stmt": {"sql": "SELECT COUNT(*) FROM kinship_matrix"}}]
    }).encode("utf-8")
    test_req = urllib.request.Request(
        f"{HTTP_URL}/",
        data=test_payload,
        headers={
            "Authorization": f"Bearer {TURSO_AUTH_TOKEN}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(test_req, timeout=30) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            print(f"  Connection OK: {json.dumps(data)[:200]}")
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="replace")[:300]
        print(f"  FAILED: HTTP {e.code}: {err_body}")
        print()
        print("Check that TURSO_URL and TURSO_AUTH_TOKEN are valid.")
        sys.exit(1)
    except Exception as e:
        print(f"  FAILED: {e}")
        sys.exit(1)
    print()

    # Load checkpoint
    cp = load_checkpoint()
    if cp:
        start_byte = cp["byte_offset"]
        rows_uploaded = cp["rows_uploaded"]
    else:
        start_byte = 0
        rows_uploaded = 0

    # Clear error log if starting fresh
    if rows_uploaded == 0 and os.path.exists(ERROR_LOG):
        os.remove(ERROR_LOG)

    # Open CSV at the right byte offset
    f = open(CSV_PATH, "r", encoding="utf-8", buffering=1024*1024*16)
    if start_byte > 0:
        f.seek(start_byte)
    else:
        # Skip header
        f.readline()

    reader = csv.reader(f)
    chunk = []
    last_progress_rows = 0
    start_time = time.time()
    consecutive_failures = 0

    print(f"Starting upload from row {rows_uploaded:,}...")
    print()

    try:
        while True:
            try:
                row = next(reader)
            except StopIteration:
                break

            chunk.append(row)
            rows_uploaded += 1

            if len(chunk) >= CHUNK_SIZE:
                success, err = execute_batch(chunk)
                if success:
                    chunk.clear()
                    consecutive_failures = 0
                else:
                    consecutive_failures += 1
                    log_error(f"Batch failed at row {rows_uploaded:,}: {err}")
                    if consecutive_failures >= 5:
                        print(f"FATAL: 5 consecutive batch failures. Aborting.")
                        print(f"Last error: {err}")
                        save_checkpoint(rows_uploaded - len(chunk), f.tell())
                        sys.exit(1)
                    # Keep chunk for retry on next iteration
                    time.sleep(5)

                if rows_uploaded - last_progress_rows >= PROGRESS_EVERY:
                    elapsed = time.time() - start_time
                    rate = rows_uploaded / elapsed if elapsed > 0 else 0
                    remaining = 28_761_769 - rows_uploaded  # 5363^2
                    eta = remaining / rate if rate > 0 else 0
                    pct = rows_uploaded / 28_761_769 * 100
                    print(f"Progress: {rows_uploaded:,} / 28,761,769 "
                          f"({pct:.1f}%) | Rate: {rate:,.0f} rows/s | "
                          f"ETA: {format_hms(eta)} | Elapsed: {format_hms(elapsed)}")
                    last_progress_rows = rows_uploaded

                if rows_uploaded % CHECKPOINT_EVERY == 0:
                    save_checkpoint(rows_uploaded, f.tell())

        # Final flush
        if chunk:
            success, err = execute_batch(chunk)
            if not success:
                log_error(f"Final batch failed: {err}")
            chunk.clear()

    except KeyboardInterrupt:
        print("\nInterrupted by user. Saving checkpoint...")
        save_checkpoint(rows_uploaded - len(chunk), f.tell())
        f.close()
        sys.exit(130)
    except Exception as e:
        log_error(f"Fatal error: {e}")
        save_checkpoint(rows_uploaded - len(chunk), f.tell())
        f.close()
        raise

    f.close()
    elapsed = time.time() - start_time

    if os.path.exists(CHECKPOINT_FILE):
        os.remove(CHECKPOINT_FILE)

    print()
    print("=" * 60)
    print("UPLOAD COMPLETE")
    print("=" * 60)
    print(f"Rows uploaded: {rows_uploaded:,}")
    print(f"Time: {format_hms(elapsed)}")
    print(f"Rate: {rows_uploaded / elapsed:,.0f} rows/sec")

    # Verify
    print()
    print("Verifying row count...")
    verify_payload = json.dumps({
        "requests": [{"type": "execute", "stmt": {"sql": "SELECT COUNT(*) AS cnt FROM kinship_matrix"}}]
    }).encode("utf-8")
    verify_req = urllib.request.Request(
        f"{HTTP_URL}/",
        data=verify_payload,
        headers={
            "Authorization": f"Bearer {TURSO_AUTH_TOKEN}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(verify_req, timeout=30) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            print(f"  COUNT(*) in Turso: {json.dumps(data)[:300]}")
    except Exception as e:
        print(f"  Verification query failed: {e}")

if __name__ == "__main__":
    main()
