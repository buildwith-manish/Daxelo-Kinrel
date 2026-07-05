#!/usr/bin/env python3
"""
csv_to_sqlite.py

Converts kinship_matrix.csv to a compressed SQLite database
(kinship_matrix.db) optimized for fast lookups on mobile devices.

Schema:
    CREATE TABLE kinship_matrix (
        from_key TEXT NOT NULL,
        via_key TEXT NOT NULL,
        result_key TEXT NOT NULL,
        result_female_key TEXT NOT NULL,
        PRIMARY KEY (from_key, via_key)
    );
    CREATE INDEX idx_from_via ON kinship_matrix(from_key, via_key);

Performance:
    PRAGMA journal_mode=WAL
    PRAGMA synchronous=NORMAL
    PRAGMA cache_size=200000
    Insert in batches of 50,000
    Commit every 1,000,000 rows
    VACUUM at end to compress
    ANALYZE to optimize query planner

Usage:
    python scripts/csv_to_sqlite.py <input.csv> <output.db>
"""

import csv
import sqlite3
import os
import sys
import time

CSV_PATH = sys.argv[1] if len(sys.argv) > 1 else "kinship_matrix.csv"
DB_PATH  = sys.argv[2] if len(sys.argv) > 2 else "kinship_matrix.db"

BATCH_SIZE       = 50_000
PROGRESS_EVERY   = 500_000
COMMIT_EVERY     = 1_000_000

def format_hms(seconds):
    seconds = int(seconds)
    h, rem = divmod(seconds, 3600)
    m, s = divmod(rem, 60)
    return f"{h}:{m:02d}:{s:02d}"

def main():
    if not os.path.exists(CSV_PATH):
        print(f"ERROR: CSV file not found: {CSV_PATH}")
        sys.exit(1)

    csv_size = os.path.getsize(CSV_PATH)
    print(f"Input CSV:  {CSV_PATH} ({csv_size / 1024**3:.2f} GB)")
    print(f"Output DB:  {DB_PATH}")
    print(f"Batch size: {BATCH_SIZE:,} rows | Commit every: {COMMIT_EVERY:,} rows")
    print()

    # Remove existing DB
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
        print(f"Removed existing {DB_PATH}")
    # Clean up any leftover WAL/journal files
    for suffix in ["-wal", "-shm", "-journal"]:
        p = DB_PATH + suffix
        if os.path.exists(p):
            os.remove(p)

    # Create connection
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()

    # Performance pragmas
    print("[1] Setting performance pragmas...")
    cur.execute("PRAGMA journal_mode=WAL")
    cur.execute("PRAGMA synchronous=NORMAL")
    cur.execute("PRAGMA cache_size=200000")
    cur.execute("PRAGMA temp_store=MEMORY")
    cur.execute("PRAGMA locking_mode=EXCLUSIVE")
    print("    Done (journal_mode=WAL, synchronous=NORMAL)")

    # Create table
    print("[2] Creating table...")
    cur.execute("""
        CREATE TABLE kinship_matrix (
            from_key TEXT NOT NULL,
            via_key TEXT NOT NULL,
            result_key TEXT NOT NULL,
            result_female_key TEXT NOT NULL,
            PRIMARY KEY (from_key, via_key)
        )
    """)
    conn.commit()
    print("    Table created")

    # Insert data
    print("[3] Inserting rows...")
    start_time = time.time()
    rows_inserted = 0
    batch = []

    with open(CSV_PATH, "r", encoding="utf-8", buffering=1024*1024*16, newline="") as f:
        reader = csv.reader(f)
        header = next(reader)
        print(f"    Header: {header}")

        for row in reader:
            batch.append((row[0], row[1], row[2], row[3]))
            rows_inserted += 1

            if len(batch) >= BATCH_SIZE:
                cur.executemany(
                    "INSERT INTO kinship_matrix VALUES (?,?,?,?)",
                    batch
                )
                batch.clear()

                if rows_inserted % COMMIT_EVERY == 0:
                    conn.commit()

                if rows_inserted % PROGRESS_EVERY == 0:
                    elapsed = time.time() - start_time
                    rate = rows_inserted / elapsed if elapsed > 0 else 0
                    print(f"    Progress: {rows_inserted:,} rows | "
                          f"Rate: {rate:,.0f} rows/s | "
                          f"Elapsed: {format_hms(elapsed)}")

        # Final flush
        if batch:
            cur.executemany(
                "INSERT INTO kinship_matrix VALUES (?,?,?,?)",
                batch
            )
            batch.clear()

    conn.commit()
    elapsed = time.time() - start_time
    print(f"    Inserted {rows_inserted:,} rows in {format_hms(elapsed)}")
    print(f"    Rate: {rows_inserted / elapsed:,.0f} rows/s")

    # Create index
    print("[4] Creating idx_from_via index...")
    idx_start = time.time()
    cur.execute("CREATE INDEX idx_from_via ON kinship_matrix(from_key, via_key)")
    conn.commit()
    print(f"    Index created in {format_hms(time.time() - idx_start)}")

    # Checkpoint WAL into main DB file
    print("[5] Checkpointing WAL...")
    cur.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    conn.commit()
    print("    WAL checkpointed")

    # VACUUM
    print("[6] Running VACUUM to compress...")
    vac_start = time.time()
    cur.execute("VACUUM")
    print(f"    VACUUM completed in {format_hms(time.time() - vac_start)}")

    # ANALYZE
    print("[7] Running ANALYZE to optimize query planner...")
    cur.execute("ANALYZE")
    conn.commit()
    print("    ANALYZE completed")

    # Verify
    print("[8] Verifying row count...")
    cur.execute("SELECT COUNT(*) FROM kinship_matrix")
    count = cur.fetchone()[0]
    print(f"    COUNT(*) = {count:,}")

    # Sample queries
    print("[9] Sample query verification...")
    samples = [
        ("father", "brother"),
        ("husband", "elder_brother"),
        ("wife", "sister"),
        ("son", "father"),
        ("mother", "brother"),
    ]
    for fk, vk in samples:
        cur.execute(
            "SELECT result_key, result_female_key FROM kinship_matrix WHERE from_key=? AND via_key=?",
            (fk, vk)
        )
        row = cur.fetchone()
        if row:
            print(f"    {fk} + {vk} = {row[0]} / {row[1]}")
        else:
            print(f"    {fk} + {vk} = NOT FOUND")

    # DB size
    db_size = os.path.getsize(DB_PATH)
    print()
    print(f"DB file size: {db_size / 1024 / 1024:.2f} MB ({db_size:,} bytes)")

    cur.close()
    conn.close()

    print()
    print("=" * 60)
    print("CSV TO SQLITE CONVERSION COMPLETE")
    print("=" * 60)
    print(f"  Input:  {CSV_PATH} ({csv_size / 1024**3:.2f} GB)")
    print(f"  Output: {DB_PATH} ({db_size / 1024 / 1024:.2f} MB)")
    print(f"  Rows:   {count:,}")
    print(f"  Time:   {format_hms(time.time() - start_time)}")

if __name__ == "__main__":
    main()
