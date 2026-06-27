#!/usr/bin/env python3
"""
upload_to_neon.py

Uploads kinship_matrix.csv to Neon PostgreSQL using psycopg2.

Features:
  - Reads CSV in chunks of 5,000 rows
  - Batch INSERT using executemany() with ON CONFLICT DO NOTHING (idempotent)
  - Progress every 100,000 rows with rate + ETA
  - Retry failed batches 3 times with exponential backoff
  - Checkpoint/resume: scripts/neon_checkpoint.json (and local ./neon_checkpoint.json)
  - --verify-only flag to run verification queries without uploading
  - SSL mode required (enforced by connection string)
  - Connection pooling via psycopg2 connection reuse

Usage:
    export NEON_CONNECTION_STRING=postgresql://user:pass@host/db?sslmode=require
    python scripts/upload_to_neon.py [path/to/kinship_matrix.csv]
    python scripts/upload_to_neon.py --verify-only
"""

import os
import sys
import csv
import json
import time
import traceback
from datetime import datetime

try:
    import psycopg2
    from psycopg2 import OperationalError, DatabaseError
    from psycopg2.extras import execute_values
except ImportError:
    print("ERROR: psycopg2-binary not installed.")
    print("Install with: pip install psycopg2-binary")
    sys.exit(1)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

CSV_PATH = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else "kinship_matrix.csv"
CHECKPOINT_FILE = "neon_checkpoint.json"
ERROR_LOG = "neon_upload_errors.log"
REPO_CHECKPOINT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "neon_checkpoint.json")

CHUNK_SIZE       = 5_000          # rows read from CSV per batch
PROGRESS_EVERY   = 100_000        # print progress every N rows
CHECKPOINT_EVERY = 100_000        # save checkpoint every N rows
MAX_RETRIES      = 3              # retry attempts per batch
RETRY_BACKOFF    = [1, 5, 15]     # seconds to wait between retries
TOTAL_EXPECTED   = 28_761_769     # 5363 x 5363

NEON_CONNECTION_STRING = os.environ.get("NEON_CONNECTION_STRING", "")

if not NEON_CONNECTION_STRING and "--verify-only" not in sys.argv:
    print("ERROR: NEON_CONNECTION_STRING environment variable must be set.")
    print()
    print("Example:")
    print("  export NEON_CONNECTION_STRING='postgresql://user:pass@host/db?sslmode=require'")
    sys.exit(1)

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

def get_connection():
    """Get a new psycopg2 connection. SSL is enforced by the connection string."""
    # Ensure sslmode=require is present
    conn_str = NEON_CONNECTION_STRING
    if "sslmode" not in conn_str:
        sep = "&" if "?" in conn_str else "?"
        conn_str = f"{conn_str}{sep}sslmode=require"
    # Strip channel_binding=require (psycopg2 < 2.9.5 doesn't support it)
    # Actually psycopg2 2.9+ supports it; keep it if present
    return psycopg2.connect(conn_str)

# ---------------------------------------------------------------------------
# Checkpoint
# ---------------------------------------------------------------------------

def load_checkpoint():
    """Load checkpoint from local file, falling back to repo checkpoint."""
    if os.path.exists(CHECKPOINT_FILE):
        try:
            with open(CHECKPOINT_FILE, "r", encoding="utf-8") as f:
                cp = json.load(f)
            print(f"Resuming from local checkpoint: rows_uploaded={cp['rows_uploaded']:,}, byte_offset={cp['byte_offset']:,}")
            return cp
        except Exception as e:
            log_error(f"local checkpoint load failed: {e}; trying repo checkpoint")

    if os.path.exists(REPO_CHECKPOINT):
        try:
            with open(REPO_CHECKPOINT, "r", encoding="utf-8") as f:
                cp = json.load(f)
            print(f"Resuming from repo checkpoint ({REPO_CHECKPOINT}):")
            print(f"  rows_uploaded={cp['rows_uploaded']:,}, byte_offset={cp['byte_offset']:,}")
            with open(CHECKPOINT_FILE, "w", encoding="utf-8") as f:
                json.dump(cp, f, indent=2)
            return cp
        except Exception as e:
            log_error(f"repo checkpoint load failed: {e}; starting fresh")
    return None

def save_checkpoint(rows_uploaded, byte_offset):
    """Save checkpoint to BOTH local and repo file."""
    payload = {
        "rows_uploaded": rows_uploaded,
        "byte_offset": byte_offset,
        "timestamp": datetime.utcnow().isoformat() + "Z",
    }
    tmp = CHECKPOINT_FILE + ".tmp"
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(payload, f, indent=2)
        os.replace(tmp, CHECKPOINT_FILE)
    except Exception as e:
        log_error(f"local checkpoint save failed: {e}")

    try:
        with open(REPO_CHECKPOINT, "w", encoding="utf-8") as f:
            json.dump(payload, f, indent=2)
    except Exception:
        pass  # Repo file may not be writable in some environments

# ---------------------------------------------------------------------------
# Batch insert
# ---------------------------------------------------------------------------

def execute_batch(conn, rows):
    """
    Execute a batch INSERT using execute_values for high throughput.
    Uses ON CONFLICT DO NOTHING to skip duplicates safely (idempotent).
    Returns (success: bool, error: str or None).
    """
    if not rows:
        return True, None

    sql = """
        INSERT INTO kinship_matrix (from_key, via_key, result_key, result_female_key)
        VALUES %s
        ON CONFLICT (from_key, via_key) DO NOTHING
    """

    last_error = None
    for attempt in range(MAX_RETRIES):
        try:
            with conn.cursor() as cur:
                execute_values(cur, sql, rows, template="(%s, %s, %s, %s)")
            conn.commit()
            return True, None
        except (OperationalError, DatabaseError) as e:
            last_error = f"DB error: {e}"
            log_error(f"Batch failed (attempt {attempt+1}/{MAX_RETRIES}): {last_error}")
            try:
                conn.rollback()
            except Exception:
                pass
            # Reconnect for OperationalError (connection lost)
            if isinstance(e, OperationalError):
                try:
                    conn.close()
                except Exception:
                    pass
                # Return signal to caller to get new connection
                return False, ("RECONNECT", str(e))
        except Exception as e:
            last_error = f"Exception: {e}"
            log_error(f"Batch failed (attempt {attempt+1}/{MAX_RETRIES}): {last_error}")
            try:
                conn.rollback()
            except Exception:
                pass

        if attempt < MAX_RETRIES - 1:
            wait = RETRY_BACKOFF[min(attempt, len(RETRY_BACKOFF) - 1)]
            time.sleep(wait)

    return False, last_error

# ---------------------------------------------------------------------------
# Verification
# ---------------------------------------------------------------------------

def verify_only():
    """Run verification queries without uploading."""
    print(f"Neon connection: {NEON_CONNECTION_STRING[:60]}...")
    print()

    try:
        conn = get_connection()
    except Exception as e:
        print(f"FAILED to connect: {e}")
        sys.exit(1)

    try:
        with conn.cursor() as cur:
            print("[1] Testing connection...")
            cur.execute("SELECT 1")
            print(f"    OK")
            print()

            print("[2] Row count...")
            cur.execute("SELECT COUNT(*) FROM kinship_matrix")
            cnt = cur.fetchone()[0]
            print(f"    COUNT(*) = {cnt:,}")
            print(f"    Expected = {TOTAL_EXPECTED:,} (5363 x 5363)")
            if cnt == TOTAL_EXPECTED:
                print(f"    Row count MATCHES")
            elif cnt > 0:
                pct = cnt / TOTAL_EXPECTED * 100
                print(f"    Upload in progress: {pct:.2f}% ({cnt:,}/{TOTAL_EXPECTED:,})")
            else:
                print(f"    Table is EMPTY")
            print()

            print("[3] Sample query verification...")
            expected_results = [
                ("father", "brother", "paternal-uncle", "paternal-aunt"),
                ("husband", "elder_brother", "jeth", "jethani"),
                ("wife", "sister", "sali", "sali"),
                ("son", "father", "self", "self"),
                ("mother", "brother", "maternal-uncle", "maternal-aunt"),
            ]
            passed = 0
            failed = 0
            for from_key, via_key, exp_male, exp_female in expected_results:
                cur.execute(
                    "SELECT result_key, result_female_key FROM kinship_matrix WHERE from_key=%s AND via_key=%s",
                    (from_key, via_key)
                )
                row = cur.fetchone()
                if row is None:
                    print(f"    SKIP: {from_key} + {via_key} (not yet uploaded)")
                    continue
                actual_male, actual_female = row
                if actual_male == exp_male and actual_female == exp_female:
                    print(f"    PASS: {from_key} + {via_key} = {actual_male} / {actual_female}")
                    passed += 1
                else:
                    print(f"    FAIL: {from_key} + {via_key} = {actual_male} / {actual_female} (expected {exp_male} / {exp_female})")
                    failed += 1

            print()
            print(f"Verification: {passed} passed, {failed} failed")
            if failed > 0:
                sys.exit(1)
            print("All checks passed.")
    finally:
        conn.close()

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    if "--verify-only" in sys.argv:
        if not NEON_CONNECTION_STRING:
            print("ERROR: NEON_CONNECTION_STRING must be set for --verify-only")
            sys.exit(1)
        verify_only()
        return

    if not os.path.exists(CSV_PATH):
        print(f"ERROR: CSV file not found: {CSV_PATH}")
        sys.exit(1)

    file_size = os.path.getsize(CSV_PATH)
    print(f"CSV: {CSV_PATH}")
    print(f"Size: {file_size / 1024**3:.2f} GB")
    print(f"Chunk size: {CHUNK_SIZE:,} rows | Progress every: {PROGRESS_EVERY:,} rows")
    print()

    # Test connection
    print("Testing Neon connection...")
    try:
        conn = get_connection()
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM kinship_matrix")
            existing = cur.fetchone()[0]
        print(f"  Connection OK. Existing rows: {existing:,}")
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

    if rows_uploaded == 0 and os.path.exists(ERROR_LOG):
        os.remove(ERROR_LOG)

    # Open CSV — track byte offset manually (csv.reader disables file.tell())
    f = open(CSV_PATH, "r", encoding="utf-8", buffering=1024*1024*16, newline="")
    if start_byte > 0:
        f.seek(start_byte)
    else:
        f.readline()  # skip header

    class TrackedReader:
        def __init__(self, fileobj):
            self.fileobj = fileobj
            self.bytes_read = fileobj.tell()

        def __iter__(self):
            return self

        def __next__(self):
            line = self.fileobj.readline()
            if not line:
                raise StopIteration
            self.bytes_read += len(line.encode("utf-8"))
            return next(csv.reader([line]))

        def byte_offset(self):
            return self.bytes_read

    reader = TrackedReader(f)
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
                success, err = execute_batch(conn, chunk)
                if success:
                    chunk.clear()
                    consecutive_failures = 0
                else:
                    consecutive_failures += 1
                    if isinstance(err, tuple) and err and err[0] == "RECONNECT":
                        log_error(f"Connection lost, reconnecting: {err[1]}")
                        try:
                            conn.close()
                        except Exception:
                            pass
                        try:
                            conn = get_connection()
                            log_error("Reconnected successfully")
                            # Retry this batch with new connection
                            success, err = execute_batch(conn, chunk)
                            if success:
                                chunk.clear()
                                consecutive_failures = 0
                            else:
                                log_error(f"Retry failed after reconnect: {err}")
                        except Exception as e:
                            log_error(f"Reconnect failed: {e}")

                    if consecutive_failures >= 5:
                        print(f"FATAL: 5 consecutive batch failures. Aborting.")
                        print(f"Last error: {err}")
                        save_checkpoint(rows_uploaded - len(chunk), reader.byte_offset())
                        sys.exit(1)
                    time.sleep(5)

                if rows_uploaded - last_progress_rows >= PROGRESS_EVERY:
                    elapsed = time.time() - start_time
                    rate = rows_uploaded / elapsed if elapsed > 0 else 0
                    remaining = TOTAL_EXPECTED - rows_uploaded
                    eta = remaining / rate if rate > 0 else 0
                    pct = rows_uploaded / TOTAL_EXPECTED * 100
                    print(f"Progress: {rows_uploaded:,} / {TOTAL_EXPECTED:,} "
                          f"({pct:.2f}%) | Rate: {rate:,.0f} rows/s | "
                          f"ETA: {format_hms(eta)} | Elapsed: {format_hms(elapsed)}")
                    last_progress_rows = rows_uploaded

                if rows_uploaded % CHECKPOINT_EVERY == 0:
                    save_checkpoint(rows_uploaded, reader.byte_offset())

        # Final flush
        if chunk:
            success, err = execute_batch(conn, chunk)
            if not success:
                log_error(f"Final batch failed: {err}")
            chunk.clear()

    except KeyboardInterrupt:
        print("\nInterrupted by user. Saving checkpoint...")
        save_checkpoint(rows_uploaded - len(chunk), reader.byte_offset())
        f.close()
        conn.close()
        sys.exit(130)
    except Exception as e:
        log_error(f"Fatal error: {e}\n{traceback.format_exc()}")
        save_checkpoint(rows_uploaded - len(chunk), reader.byte_offset())
        f.close()
        conn.close()
        raise

    f.close()
    conn.close()
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
    print("Running verification...")
    try:
        conn = get_connection()
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM kinship_matrix")
            cnt = cur.fetchone()[0]
            print(f"  COUNT(*) in Neon: {cnt:,}")
        conn.close()
    except Exception as e:
        print(f"  Verification query failed: {e}")

if __name__ == "__main__":
    main()
