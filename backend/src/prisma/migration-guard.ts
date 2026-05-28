#!/usr/bin/env ts-node
/**
 * DAXELO KINREL — Migration Guard (P3-B4)
 *
 * Pre-migration safety check that blocks dangerous SQL operations.
 * Run before every deployment to catch potentially destructive migrations.
 *
 * Usage: npx ts-node src/prisma/migration-guard.ts <path/to/migration.sql>
 *
 * Blocked patterns:
 *   - DROP COLUMN (without deprecation comment)
 *   - DROP TABLE (without deprecation comment)
 *   - ALTER ... NOT NULL (without default value)
 *
 * To allow a dangerous operation, add a comment:
 *   -- DEPRECATED: <reason> (allowed by migration-guard)
 */

import * as fs from 'fs';

interface CheckResult {
  passed: boolean;
  errors: string[];
  warnings: string[];
}

const dangerousPatterns: Array<{ pattern: RegExp; description: string }> = [
  {
    pattern: /DROP\s+COLUMN/i,
    description: 'DROP COLUMN (removes data permanently)',
  },
  {
    pattern: /DROP\s+TABLE/i,
    description: 'DROP TABLE (deletes all data)',
  },
  {
    pattern: /ALTER\s+.*\s+SET\s+NOT\s+NULL(?!\s*DEFAULT)/i,
    description: 'ALTER ... SET NOT NULL without DEFAULT (can fail on existing rows)',
  },
];

/** Check if a dangerous pattern is explicitly allowed via deprecation comment */
function isAllowed(sql: string, matchIndex: number): boolean {
  // Look backwards from the match for a deprecation comment
  const beforeMatch = sql.substring(Math.max(0, matchIndex - 200), matchIndex);
  return /--\s*DEPRECATED:/i.test(beforeMatch) || /allowed\s+by\s+migration-guard/i.test(beforeMatch);
}

function checkMigration(sqlPath: string): CheckResult {
  const result: CheckResult = { passed: true, errors: [], warnings: [] };

  if (!fs.existsSync(sqlPath)) {
    result.passed = false;
    result.errors.push(`File not found: ${sqlPath}`);
    return result;
  }

  const sql = fs.readFileSync(sqlPath, 'utf-8');
  const lines = sql.split('\n');

  for (const { pattern, description } of dangerousPatterns) {
    let match: RegExpExecArray | null;
    const regex = new RegExp(pattern.source, pattern.flags);

    while ((match = regex.exec(sql)) !== null) {
      if (isAllowed(sql, match.index)) {
        // Find the line number
        const lineNumber = sql.substring(0, match.index).split('\n').length;
        result.warnings.push(
          `Line ${lineNumber}: ${description} — ALLOWED (deprecation comment found)`,
        );
      } else {
        const lineNumber = sql.substring(0, match.index).split('\n').length;
        result.errors.push(
          `Line ${lineNumber}: ${description}\n` +
            `  → Add "-- DEPRECATED: <reason> (allowed by migration-guard)" to proceed`,
        );
        result.passed = false;
      }
    }
  }

  // Check for missing rollback documentation
  if (!sql.includes('-- Rollback:') && !sql.includes('-- Rollback ')) {
    result.warnings.push(
      'No rollback documentation found. Add "-- Rollback:" comment with steps.',
    );
  }

  return result;
}

// ── Main ──────────────────────────────────────────────────────────
const migrationFile = process.argv[2];

if (!migrationFile) {
  console.error('Usage: npx ts-node src/prisma/migration-guard.ts <path/to/migration.sql>');
  console.error('');
  console.error('Checks a Prisma migration SQL file for dangerous operations.');
  process.exit(1);
}

console.log('🛡️  Migration Guard — Checking: ' + migrationFile);
console.log('');

const result = checkMigration(migrationFile);

if (result.warnings.length > 0) {
  console.log('⚠️  Warnings:');
  for (const warning of result.warnings) {
    console.log('   ' + warning);
  }
  console.log('');
}

if (result.errors.length > 0) {
  console.error('❌ BLOCKED — Dangerous operations detected:');
  for (const error of result.errors) {
    console.error('   ' + error);
  }
  console.error('');
  console.error('Add deprecation comments to proceed, or fix the migration.');
  process.exit(1);
}

console.log('✅ Migration check passed — no dangerous operations detected.');
process.exit(0);
