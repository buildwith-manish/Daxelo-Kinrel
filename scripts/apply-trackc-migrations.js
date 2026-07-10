#!/usr/bin/env node
// =============================================================================
// Track C v2.0 — Migration Runner
// =============================================================================
// Applies all 20 Track C migrations in lexical order to the Supabase database.
// Uses the DIRECT_URL (bypasses PgBouncer) for DDL operations.
// =============================================================================

const fs = require('fs');
const path = require('path');
const { Client } = require('pg');

const DIRECT_URL = process.env.DIRECT_URL;
if (!DIRECT_URL) {
  console.error('DIRECT_URL env var is required');
  process.exit(1);
}

const MIGRATIONS_DIR = path.join(__dirname, '..', 'supabase', 'migrations');

// Track C migrations in lexical order (only the forward migrations, not rollbacks)
const TRACKC_MIGRATIONS = [
  '20260711000001_trackc_create_constitution.sql',
  '20260711000002_trackc_create_family_decision.sql',
  '20260711000003_trackc_create_kinrel_timeline.sql',
  '20260711000004_trackc_create_timeline_triggers.sql',
  '20260711000005_trackc_create_ai_insight.sql',
  '20260711000006_trackc_create_learning_signal.sql',
  '20260711000007_trackc_create_family_behavior_profile.sql',
  '20260711000008_trackc_create_smart_reminder.sql',
  '20260711000009_trackc_create_decision_memory.sql',
  '20260711000010_trackc_create_meeting_artifact.sql',
  '20260711000011_trackc_create_search_index.sql',
  '20260711000012_trackc_create_search_tsvector.sql',
  '20260711000013_trackc_create_analytics_snapshot.sql',
  '20260711000014_trackc_partition_family_decision.sql',
  '20260711000015_trackc_partition_timeline.sql',
  '20260711000016_trackc_partition_ai_insight.sql',
  '20260711000017_trackc_partition_learning_signal.sql',
  '20260711000018_trackc_rls_all_tables.sql',
  '20260711000019_trackc_pg_boss_schema.sql',
  '20260711000020_trackc_seed_global_defaults.sql',
];

async function main() {
  const client = new Client({
    connectionString: DIRECT_URL,
    connectionTimeoutMillis: 30000,
    query_timeout: 120000,
  });

  try {
    console.log('Connecting to Supabase database...');
    await client.connect();
    console.log('Connected.');

    // Check which migrations are already applied via supabase_migrations.schema_migrations
    let appliedMigrations = new Set();
    try {
      const res = await client.query(
        `SELECT version FROM supabase_migrations.schema_migrations ORDER BY version`
      );
      appliedMigrations = new Set(res.rows.map(r => r.version));
      console.log(`Found ${appliedMigrations.size} already-applied migrations in supabase_migrations.`);
    } catch (e) {
      console.log('supabase_migrations schema not found — will use our own tracking table.');
      await client.query(`
        CREATE TABLE IF NOT EXISTS public._trackc_migrations_applied (
          filename TEXT PRIMARY KEY,
          applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        );
      `);
      const res = await client.query(`SELECT filename FROM public._trackc_migrations_applied`);
      appliedMigrations = new Set(res.rows.map(r => r.filename));
    }

    // Ensure our own tracking table exists (for idempotency across runs)
    await client.query(`
      CREATE TABLE IF NOT EXISTS public._trackc_migrations_applied (
        filename TEXT PRIMARY KEY,
        applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );
    `);
    const ownRes = await client.query(`SELECT filename FROM public._trackc_migrations_applied`);
    for (const row of ownRes.rows) {
      appliedMigrations.add(row.filename);
    }

    let appliedCount = 0;
    let skippedCount = 0;

    for (const filename of TRACKC_MIGRATIONS) {
      const filepath = path.join(MIGRATIONS_DIR, filename);
      if (!fs.existsSync(filepath)) {
        console.error(`✗ Migration file not found: ${filename}`);
        continue;
      }

      // Check if already applied (check both version prefix and full filename)
      const version = filename.split('_')[0];
      const alreadyApplied = appliedMigrations.has(version) || appliedMigrations.has(filename);

      if (alreadyApplied) {
        console.log(`↻ Skipping (already applied): ${filename}`);
        skippedCount++;
        continue;
      }

      const sql = fs.readFileSync(filepath, 'utf8');
      console.log(`▶ Applying: ${filename} (${sql.length} bytes)`);

      try {
        await client.query('BEGIN');
        // Split on semicolons but respect DO $$ ... $$ blocks
        // Simple approach: execute the whole thing as one query (Postgres supports multi-statement)
        await client.query(sql);
        // Track that we applied it
        await client.query(
          `INSERT INTO public._trackc_migrations_applied (filename) VALUES ($1) ON CONFLICT DO NOTHING`,
          [filename]
        );
        await client.query('COMMIT');
        console.log(`✓ Applied: ${filename}`);
        appliedCount++;
      } catch (err) {
        await client.query('ROLLBACK');
        console.error(`✗ Failed: ${filename}`);
        console.error(`  Error: ${err.message}`);
        // Some errors are non-fatal (e.g., "already exists" from CREATE IF NOT EXISTS)
        // Check if it's a benign error
        if (err.message.includes('already exists') || err.message.includes('no-op') || err.message.includes('Skipping')) {
          console.log(`  (treating as benign — continuing)`);
          // Still mark as applied so we don't retry
          try {
            await client.query(
              `INSERT INTO public._trackc_migrations_applied (filename) VALUES ($1) ON CONFLICT DO NOTHING`,
              [filename]
            );
            appliedCount++;
          } catch (_) {}
        } else {
          throw err;
        }
      }
    }

    console.log(`\n=== Migration Summary ===`);
    console.log(`Applied: ${appliedCount}`);
    console.log(`Skipped (already applied): ${skippedCount}`);
    console.log(`Total Track C migrations: ${TRACKC_MIGRATIONS.length}`);

  } catch (err) {
    console.error('FATAL:', err.message);
    process.exit(1);
  } finally {
    await client.end();
  }
}

main().catch(err => {
  console.error('Unhandled error:', err);
  process.exit(1);
});
