# Turso Kinship Matrix Upload

This guide explains how to upload the 28,761,769-row kinship chain matrix to Turso (libSQL) using GitHub Actions.

## Overview

The upload is split into two GitHub Actions workflows:

| Workflow | File | Purpose |
|----------|------|---------|
| **Generate Kinship Matrix CSV** | `.github/workflows/generate_matrix.yml` | Generates `kinship_matrix.csv` (2.79 GB) from `indian_kinship.json` and uploads it as a workflow artifact (gzip-compressed). |
| **Upload Kinship Matrix to Turso** | `.github/workflows/turso_upload.yml` | Downloads the CSV artifact and uploads it to Turso in chunks, with automatic checkpoint/resume across runs. |

The upload workflow uses GitHub Actions' 6-hour job timeout window. Each run uploads as many rows as possible, commits the checkpoint back to the repo, and exits. Re-run the workflow to continue from the checkpoint.

---

## Setup (one-time)

### 1. Add GitHub Secrets

Go to **Settings → Secrets and variables → Actions → New repository secret** and add:

| Secret name | Value |
|-------------|-------|
| `TURSO_URL` | `libsql://your-db-name-your-org.turso.io` |
| `TURSO_AUTH_TOKEN` | Your Turso database auth token |

**How to get these values:**
1. Go to https://turso.io/app → your database → Settings
2. Copy the **URL** (looks like `libsql://xyz.turso.io`)
3. Click **Create auth token** → copy the token (starts with `eyJ...`)

> ⚠️ **Never commit the token to the repo.** The `.env` file is in `.gitignore`. The workflow reads it from GitHub Secrets only.

### 2. Create the Turso table (first time only)

Run the setup script locally once to create the table and indexes:

```bash
export TURSO_URL=libsql://your-db.turso.io
export TURSO_AUTH_TOKEN=your-token-here
python scripts/setup_turso_table.py
```

This creates:
- Table `kinship_matrix (from_key, via_key, result_key, result_female_key)` with `PRIMARY KEY (from_key, via_key)`
- Index `idx_from_key` on `from_key`
- Index `idx_via_key` on `via_key`
- Index `idx_from_via` on `(from_key, via_key)`

To verify the table later (without recreating it), use:
```bash
python scripts/setup_turso_table.py --verify-only
```

---

## Running the Upload

### Step 1: Generate the CSV artifact

Go to **Actions tab → "Generate Kinship Matrix CSV" → Run workflow**.

This takes ~2 minutes and produces a workflow artifact named `kinship-matrix` containing the gzip-compressed CSV (≈800 MB compressed, 2.79 GB uncompressed).

### Step 2: Run the upload workflow

Go to **Actions tab → "Upload Kinship Matrix to Turso" → Run workflow**.

Each run:
1. Downloads the CSV artifact from the previous `generate_matrix.yml` run
2. Reads the checkpoint from `scripts/upload_checkpoint.json`
3. Uploads rows in batches of 500 per INSERT statement (using SQL literals to bypass SQLite's 999-parameter limit)
4. Saves the checkpoint every 100,000 rows
5. Commits the updated checkpoint back to the repo
6. Verifies the upload with sample queries
7. If upload completes (28,761,769 rows), creates a GitHub issue to notify you

### Step 3: Re-run until complete

Each run uploads for ~5.5 hours (350-minute timeout). At ~2,000 rows/sec on GitHub Actions (US-based servers, lower latency to Turso), one run uploads ~40M rows — but the actual rate depends on Turso's region.

**To check progress:**
- Look at the workflow run logs for `Progress: N / 28,761,769 (X%)`
- Or run `python scripts/setup_turso_table.py --verify-only` locally

**To resume:** Just run the workflow again. It will automatically pick up from the committed checkpoint.

---

## How the upload script works

### Resolution engine (already done)

`scripts/generate_kinship_matrix.py` generates the CSV using a 6-priority resolution engine:
1. Self-reference detection (inverse path cancellation) → `("self", "self")`
2. `CORE_OVERRIDES` — 130+ well-known Indian kinship domain terms (tau, chacha, mama, mausi, jeth, devar, nanad, sala, sali, etc.)
3. `PATH_OVERRIDES` — 4,638 overrides derived from JSON `relationshipPath` (2-step paths)
4. Generation + lineage + gender + elderYounger math (with `BY_GEN_LINEAGE_GENDER` lookup)
5. Fuzzy match on (gen, lineage) with bilateral substitution
6. `distant-relative` fallback

Pre-generation verification passes 31/31 = 100%.

### Upload script

`scripts/upload_to_turso.py`:
- Reads CSV in 50,000-row chunks
- Builds INSERT statements with 500 rows each using SQL literal values (not positional parameters) to bypass SQLite's 999-parameter limit
- Uses `INSERT OR IGNORE` to safely skip duplicates on resume
- Sends each chunk as a single HTTP request to Turso's `/v2/pipeline` endpoint
- Retries failed batches 3 times with exponential backoff (1s, 5s, 15s)
- Saves checkpoint every 100,000 rows
- Prints progress every 50,000 rows

### Checkpoint format

`scripts/upload_checkpoint.json`:
```json
{
  "rows_uploaded": 1900000,
  "byte_offset": 171599230,
  "timestamp": "2026-06-27T17:35:34.411055Z"
}
```

The `byte_offset` lets the script `seek()` directly to the resume position in the 2.79 GB CSV without re-reading earlier rows.

---

## Verification queries

After upload is complete, test with:

```sql
-- Total rows (should be 28,761,769)
SELECT COUNT(*) FROM kinship_matrix;

-- father + brother = paternal-uncle / paternal-aunt
SELECT * FROM kinship_matrix WHERE from_key='father' AND via_key='brother';

-- husband + elder_brother = jeth / jethani
SELECT * FROM kinship_matrix WHERE from_key='husband' AND via_key='elder_brother';

-- wife + sister = sali / sali
SELECT * FROM kinship_matrix WHERE from_key='wife' AND via_key='sister';

-- son + father = self / self
SELECT * FROM kinship_matrix WHERE from_key='son' AND via_key='father';

-- mother + brother = maternal-uncle / maternal-aunt
SELECT * FROM kinship_matrix WHERE from_key='mother' AND via_key='brother';
```

---

## Troubleshooting

### "ERROR: TURSO_URL and TURSO_AUTH_TOKEN secrets must be set"

Add the GitHub Secrets (see Setup step 1 above).

### "HTTP 401: invalid JWT token"

Your Turso token is invalid or expired. Generate a new one at https://turso.io/app → your database → Settings → Create auth token, then update the `TURSO_AUTH_TOKEN` GitHub Secret.

### Upload is slow

The Turso database region affects latency. AWS ap-south-1 (Mumbai) gives ~350 rows/sec from outside India. GitHub Actions servers (US) get ~2,000 rows/sec to most Turso regions.

### Upload keeps timing out

Each run uploads for ~5.5 hours. At 2,000 rows/sec, one run uploads ~40M rows. The CSV has ~29M rows, so one run from scratch should complete it. If your Turso is in a high-latency region, you may need 2-3 runs.

### Want to start over

Run the workflow with the `reset` input set to `true`. This deletes the checkpoint file. Existing Turso rows are NOT deleted — `INSERT OR IGNORE` will skip them on re-upload.

To completely clear Turso data:
```sql
DELETE FROM kinship_matrix;
```
Then run the workflow normally.

---

## Files

| File | Purpose |
|------|---------|
| `scripts/generate_kinship_matrix.py` | Generates `kinship_matrix.csv` from `indian_kinship.json` (5363² = 28.7M rows) |
| `scripts/setup_turso_table.py` | Creates Turso table + 3 indexes. Use `--verify-only` to run verification queries only. |
| `scripts/upload_to_turso.py` | Chunked CSV uploader with checkpoint/resume. Reads from `scripts/upload_checkpoint.json` if local checkpoint is missing. |
| `scripts/upload_checkpoint.json` | Resume checkpoint (committed to repo after each workflow run) |
| `.github/workflows/generate_matrix.yml` | GitHub Actions workflow: generates CSV artifact |
| `.github/workflows/turso_upload.yml` | GitHub Actions workflow: uploads CSV to Turso with checkpoint/resume |
| `.env.example` | Documents required environment variables |
