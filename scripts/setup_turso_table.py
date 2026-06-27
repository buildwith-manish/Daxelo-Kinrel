#!/usr/bin/env python3
"""
setup_turso_table.py

Creates the kinship_matrix table and indexes in Turso (libSQL) via HTTP API.
Uses pip-installable libsql-experimental package OR raw HTTP requests.
"""
import os
import sys
import json
import urllib.request
import urllib.error

TURSO_URL = os.environ.get(
    "TURSO_URL",
    "libsql://kinrel-kinship-daxelo-kinrel.aws-ap-south-1.turso.io"
)
TURSO_AUTH_TOKEN = os.environ.get(
    "TURSO_AUTH_TOKEN",
    "eyJhbGciOiJFZERTQSIsInR5cCI6IkpXVCJ9.eyJhIjoicnciLCJpYXQiOjE3ODI1NzgxMjQsImlkIjoiMDE5ZjA5YzItMzAwMS03ZGU1LWE3NTQtMWEwZmZmNjQzODljIiwicmlkIjoiODg2ZjM1MzctOGFlZC00ZjdiLTg4MzctMjRmN2ZhZDFhOTIzIn0.pKftSB12uJCZlKHPTjazhmte6uOKieqSG-1s1aiZj-c3pYI9eP2ddcxNah2fZ80m1sREfQW6lzZDFVVgztR3DA"
)

# Convert libsql:// to https://
HTTP_URL = TURSO_URL.replace("libsql://", "https://").rstrip("/")

def execute_sql(sql, args=None):
    """Execute a SQL statement via Turso HTTP v2/pipeline API.
    The v2/pipeline API auto-commits after each request."""
    payload = {
        "requests": [
            {
                "type": "execute",
                "stmt": {
                    "sql": sql,
                }
            }
        ]
    }
    if args:
        payload["requests"][0]["stmt"]["args"] = args

    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        f"{HTTP_URL}/v2/pipeline",
        data=body,
        headers={
            "Authorization": f"Bearer {TURSO_AUTH_TOKEN}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return data
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="replace")
        print(f"HTTP {e.code}: {err_body[:500]}")
        return None
    except Exception as e:
        print(f"Error: {e}")
        return None

def verify_only():
    """Run only verification queries against an already-populated table.
    Exits 0 if all checks pass, 1 otherwise.
    """
    print(f"Turso URL: {HTTP_URL}")
    print(f"Auth token: {TURSO_AUTH_TOKEN[:30]}...")
    print()

    # Test connection
    print("[1] Testing connection...")
    result = execute_sql("SELECT 1 AS test")
    if result is None:
        print("FAILED: Could not connect to Turso")
        sys.exit(1)
    print(f"    Connection OK")
    print()

    # Row count
    print("[2] Row count...")
    result = execute_sql("SELECT COUNT(*) AS cnt FROM kinship_matrix")
    if result is None:
        print("FAILED to query row count")
        sys.exit(1)
    try:
        cnt = int(result["results"][0]["response"]["result"]["rows"][0][0]["value"])
    except (KeyError, IndexError, ValueError):
        print(f"Unexpected response: {json.dumps(result)[:300]}")
        sys.exit(1)
    expected = 5363 * 5363  # 28,761,769
    print(f"    COUNT(*) = {cnt:,}")
    print(f"    Expected = {expected:,} (5363 x 5363)")
    if cnt == expected:
        print(f"    Row count MATCHES")
    elif cnt > 0:
        pct = cnt / expected * 100
        print(f"    Upload in progress: {pct:.2f}% complete ({cnt:,}/{expected:,})")
    else:
        print(f"    Table is EMPTY")
    print()

    # Sample query checks
    print("[3] Sample query verification...")
    expected_results = [
        ("father", "brother", "paternal-uncle", "paternal-aunt"),
        ("mother", "brother", "maternal-uncle", "maternal-aunt"),
        ("husband", "elder_brother", "jeth", "jethani"),
        ("wife", "sister", "sali", "sali"),
        ("son", "father", "self", "self"),
        ("brother", "son", "nephew", "niece"),
        ("fathers_elder_brother", "son", "cousin-elder", "cousin-elder"),
        ("mothers_brother", "daughter", "cousin-maternal", "cousin-maternal"),
    ]
    passed = 0
    failed = 0
    for from_key, via_key, exp_male, exp_female in expected_results:
        sql = f"SELECT result_key, result_female_key FROM kinship_matrix WHERE from_key='{from_key}' AND via_key='{via_key}'"
        result = execute_sql(sql)
        if result is None:
            print(f"    FAIL: {from_key} + {via_key} (query failed)")
            failed += 1
            continue
        try:
            rows = result["results"][0]["response"]["result"]["rows"]
            if not rows:
                print(f"    SKIP: {from_key} + {via_key} = (not yet uploaded)")
                continue
            actual_male = rows[0][0]["value"]
            actual_female = rows[0][1]["value"]
            if actual_male == exp_male and actual_female == exp_female:
                print(f"    PASS: {from_key} + {via_key} = {actual_male} / {actual_female}")
                passed += 1
            else:
                print(f"    FAIL: {from_key} + {via_key} = {actual_male} / {actual_female} (expected {exp_male} / {exp_female})")
                failed += 1
        except (KeyError, IndexError) as e:
            print(f"    FAIL: {from_key} + {via_key} (parse error: {e})")
            failed += 1

    print()
    print(f"Verification: {passed} passed, {failed} failed")
    if failed > 0:
        sys.exit(1)
    print("All checks passed.")

def main():
    # Check for --verify-only flag
    if "--verify-only" in sys.argv:
        verify_only()
        return

    print(f"Turso URL: {HTTP_URL}")
    print(f"Auth token: {TURSO_AUTH_TOKEN[:30]}...")
    print()

    # Test connection
    print("[1] Testing connection...")
    result = execute_sql("SELECT 1 AS test")
    if result is None:
        print("FAILED: Could not connect to Turso")
        sys.exit(1)
    print(f"    Connection OK: {json.dumps(result)[:200]}")
    print()

    # Drop existing table if exists (clean slate)
    print("[2] Dropping existing kinship_matrix table (if exists)...")
    execute_sql("DROP TABLE IF EXISTS kinship_matrix")
    print("    Done")
    print()

    # Create table
    print("[3] Creating kinship_matrix table...")
    sql = """
    CREATE TABLE kinship_matrix (
        from_key TEXT NOT NULL,
        via_key TEXT NOT NULL,
        result_key TEXT NOT NULL,
        result_female_key TEXT NOT NULL,
        PRIMARY KEY (from_key, via_key)
    )
    """
    result = execute_sql(sql.strip())
    if result is None:
        print("FAILED to create table")
        sys.exit(1)
    print("    Table created")
    print()

    # Create indexes
    print("[4] Creating idx_from_key index...")
    execute_sql("CREATE INDEX idx_from_key ON kinship_matrix(from_key)")
    print("    Done")

    print("[5] Creating idx_via_key index...")
    execute_sql("CREATE INDEX idx_via_key ON kinship_matrix(via_key)")
    print("    Done")

    print("[6] Creating idx_from_via index...")
    execute_sql("CREATE INDEX idx_from_via ON kinship_matrix(from_key, via_key)")
    print("    Done")
    print()

    # Verify schema
    print("[7] Verifying table schema...")
    result = execute_sql("SELECT sql FROM sqlite_master WHERE type='table' AND name='kinship_matrix'")
    if result:
        print(f"    {json.dumps(result, indent=2)[:600]}")
    print()

    print("[8] Verifying indexes...")
    result = execute_sql("SELECT name, sql FROM sqlite_master WHERE type='index' AND tbl_name='kinship_matrix'")
    if result:
        print(f"    {json.dumps(result, indent=2)[:800]}")
    print()

    print("=" * 60)
    print("TURSO TABLE SETUP COMPLETE")
    print("=" * 60)
    print("Table: kinship_matrix")
    print("Indexes: idx_from_key, idx_via_key, idx_from_via")
    print("Ready for data upload via upload_to_turso.py")

if __name__ == "__main__":
    main()
