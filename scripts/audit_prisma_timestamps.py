#!/usr/bin/env python3
# scripts/audit_prisma_timestamps.py
#
# Step 7 — Prisma schema DateTime field audit.
#
# Walks server/prisma/schema.prisma and classifies every DateTime field
# into one of three buckets:
#
#   1. @db.Timestamptz        — timezone-aware. CORRECT.
#   2. @db.Timestamp           — plain timestamp (without tz). FLAG.
#   3. Plain DateTime (no @db) — defaults to timestamp(3) in PostgreSQL
#                                 (without tz). FLAG.
#
# Writes a markdown report to docs/audit/prisma-timestamp-audit.md.
# Does NOT modify schema.prisma — auto-migration is deferred per the
# user's instruction "don't auto-migrate without approval".

import re
import sys
from pathlib import Path
from collections import Counter, defaultdict

SCHEMA_PATH = Path('server/prisma/schema.prisma')
OUT_PATH = Path('docs/audit/prisma-timestamp-audit.md')


def parse_schema(text: str):
    lines = text.split('\n')
    current_model = None
    current_model_line = 0
    fields_tstz = []     # @db.Timestamptz
    fields_ts = []       # @db.Timestamp (plain)
    fields_plain = []    # DateTime without @db annotation
    for i, line in enumerate(lines, 1):
        stripped = line.strip()
        m = re.match(r'^model\s+(\w+)\s+\{', stripped)
        if m:
            current_model = m.group(1)
            current_model_line = i
            continue
        if stripped == '}' and current_model:
            current_model = None
            continue
        if current_model is None:
            continue
        m = re.match(r'^\s*(\w+)\s+DateTime\b(.*)', line)
        if m:
            field_name = m.group(1)
            rest = m.group(2)
            # Strip comments from the rest for classification.
            rest_no_comment = re.sub(r'//.*$', '', rest).strip()
            # Check what's after DateTime (excluding the comment).
            if '@db.Timestamptz' in rest_no_comment:
                fields_tstz.append({
                    'model': current_model,
                    'field': field_name,
                    'line': i,
                    'rest': rest.strip(),
                })
            elif '@db.Timestamp' in rest_no_comment:
                fields_ts.append({
                    'model': current_model,
                    'field': field_name,
                    'line': i,
                    'rest': rest.strip(),
                })
            else:
                fields_plain.append({
                    'model': current_model,
                    'field': field_name,
                    'line': i,
                    'rest': rest.strip(),
                })
    return fields_tstz, fields_ts, fields_plain


def classify_field(field: str, rest: str) -> str:
    """Return a category label for the field based on its name + comment."""
    rest_low = rest.lower()
    field_low = field.lower()
    if field_low in ('createdat', 'updatedat'):
        return 'audit-trail (createdAt / updatedAt)'
    if 'dateofbirth' in field_low or field_low == 'dateofbirth':
        return 'date-of-birth (date-only — tz mostly irrelevant)'
    if 'anniversary' in field_low:
        return 'anniversary (date-only — tz mostly irrelevant)'
    if 'deletedat' in field_low:
        return 'soft-delete timestamp (real instant — needs timestamptz)'
    if 'lastactivityat' in field_low or 'lastengagedat' in field_low:
        return 'last-activity timestamp (real instant — needs timestamptz)'
    if 'lastanswereddate' in field_low:
        return 'streak-date (date-only by name but stored as DateTime — IST-anchored)'
    if 'assigneddate' in field_low:
        return 'assignment-date (date-only by name but stored as DateTime — IST-anchored)'
    if 'weekstart' in field_low or 'weekend' in field_low:
        return 'week boundary (IST-anchored per code comment — definitely needs timestamptz)'
    if 'deadline' in field_low:
        return 'deadline (real instant — needs timestamptz)'
    if 'joinedat' in field_low or 'resolvedat' in field_low or 'closedat' in field_low:
        return 'lifecycle timestamp (real instant — needs timestamptz)'
    if 'expiresat' in field_low:
        return 'expiry timestamp (real instant — needs timestamptz)'
    if 'lastreadat' in field_low or 'readat' in field_low or 'viewedat' in field_low or 'deliveredat' in field_low:
        return 'read/delivered/viewed timestamp (real instant — needs timestamptz)'
    if 'oncalluntil' in field_low or 'nextshift' in field_low:
        return 'on-call schedule (real instant — needs timestamptz)'
    if 'linkedat' in field_low or 'backfilledat' in field_low:
        return 'linkage timestamp (real instant — needs timestamptz)'
    if 'lastseenat' in field_low:
        return 'last-seen presence (real instant — needs timestamptz)'
    if 'firstresponseat' in field_low or 'firstresponsedeadline' in field_low or 'resolutiondeadline' in field_low:
        return 'SLA timestamp (real instant — needs timestamptz)'
    if 'downtimestart' in field_low or 'downtimeend' in field_low:
        return 'downtime window (real instant — needs timestamptz)'
    if 'startedat' in field_low or 'identifiedat' in field_low or 'monitoringat' in field_low:
        return 'incident lifecycle (real instant — needs timestamptz)'
    if 'completedat' in field_low:
        return 'completion timestamp (real instant — needs timestamptz)'
    if 'publishedat' in field_low:
        return 'publish timestamp (real instant — needs timestamptz)'
    if 'capturedat' in field_low or 'computedat' in field_low or 'generatedat' in field_low:
        return 'analytics snapshot timestamp (real instant — needs timestamptz)'
    if 'subscription' in field_low or field_low == 'startdate' or field_low == 'enddate':
        return 'subscription period boundary (real instant — needs timestamptz)'
    if 'sentat' in field_low or 'respondedat' in field_low:
        return 'message/invite sent/responded timestamp (real instant — needs timestamptz)'
    if 'lastcallat' in field_low:
        return 'last-call timestamp (real instant — needs timestamptz)'
    return 'other (review individually)'


def write_report(fields_tstz, fields_ts, fields_plain):
    total = len(fields_tstz) + len(fields_ts) + len(fields_plain)
    by_model_plain = defaultdict(list)
    for f in fields_plain:
        by_model_plain[f['model']].append(f)

    # Group plain-DateTime fields by category
    by_category = defaultdict(list)
    for f in fields_plain:
        cat = classify_field(f['field'], f['rest'])
        by_category[cat].append(f)

    out = []
    out.append('# Prisma Schema DateTime Field Audit (Step 7)')
    out.append('')
    out.append('> Generated by `scripts/audit_prisma_timestamps.py` as part of Step 7')
    out.append('> of the date/time accuracy fix. Does NOT modify `schema.prisma` —')
    out.append('> migration requires explicit user approval per the spec.')
    out.append('')
    out.append('## Summary')
    out.append('')
    out.append(f'- **Total DateTime fields**: {total}')
    out.append(f'- **@db.Timestamptz** (correct — timezone-aware): {len(fields_tstz)}')
    out.append(f'- **@db.Timestamp** (plain timestamp — FLAG): {len(fields_ts)}')
    out.append(f'- **Plain DateTime** (no `@db` → defaults to `timestamp(3)` in PostgreSQL — FLAG): {len(fields_plain)}')
    out.append('')
    out.append('## Verdict')
    out.append('')
    out.append(f'**{len(fields_ts) + len(fields_plain)} of {total} DateTime fields ({round((len(fields_ts) + len(fields_plain)) * 100 / total, 1)}%) are stored as plain `timestamp` (without timezone) in PostgreSQL.**')
    out.append('')
    out.append('Plain `timestamp` stores the wall-clock reading verbatim, with no')
    out.append('timezone metadata. When the server timezone differs from the')
    out.append('client timezone (or when Daylight Saving Time shifts), reads and')
    out.append('writes can drift. For the Daxelo-Kinrel family-base app, where')
    out.append('IST (UTC+5:30) is the implicit reference timezone but the')
    out.append('server runs in UTC, this means:')
    out.append('')
    out.append('- A `createdAt` written via Prisma `@default(now())` is stored as')
    out.append('  the server-local (UTC) wall-clock — but reading it back as a')
    out.append('  `Date` object gives the same UTC instant, so this works')
    out.append('  _only_ because the server runs in UTC consistently. If the')
    out.append('  server timezone ever changes (e.g., a deploy in a non-UTC')
    out.append('  region), all historical timestamps would be misinterpreted.')
    out.append('- A user-entered deadline (e.g., Truth Streak `deadline`) written')
    out.append('  via the client is the client-local wall-clock — the server')
    out.append('  stores it verbatim with no timezone info, so a viewer in')
    out.append('  another timezone sees a different wall-clock reading.')
    out.append('')
    out.append('## Recommendation')
    out.append('')
    out.append('Migrate all plain `DateTime` fields to `@db.Timestamptz` in a')
    out.append('single Prisma migration. The migration requires:')
    out.append('')
    out.append('1. Adding `@db.Timestamptz` to each plain `DateTime` field in')
    out.append('   `schema.prisma`.')
    out.append('2. Running `prisma migrate dev --name add_timestamptz_to_*`.')
    out.append('3. The generated SQL migration will `ALTER TABLE ... ALTER COLUMN')
    out.append('   ... TYPE timestamptz USING ... AT TIME ZONE \'UTC\'` (or')
    out.append('   similar) — for columns already storing UTC values, this is')
    out.append('   a no-op semantically but enables correct timezone handling')
    out.append('   going forward.')
    out.append('4. For user-entered deadlines (Truth Streak, decision deadlines,')
    out.append('   etc.), audit each value to determine if it should be')
    out.append('   reinterpreted as IST before the migration.')
    out.append('')
    out.append('This migration is intentionally NOT done in Step 7 — it requires')
    out.append('user approval per the spec.')
    out.append('')
    out.append('## Plain DateTime fields by model')
    out.append('')
    for model, fields in sorted(by_model_plain.items()):
        out.append(f'### `{model}` ({len(fields)} plain DateTime field{"s" if len(fields) != 1 else ""})')
        out.append('')
        out.append('| Field | Line | Rest | Category |')
        out.append('|-------|------|------|----------|')
        for f in fields:
            cat = classify_field(f['field'], f['rest'])
            rest_disp = (f['rest'] or '').replace('|', '\\|').strip()
            out.append(f'| `{f["field"]}` | schema.prisma:{f["line"]} | `{rest_disp}` | {cat} |')
        out.append('')
    out.append('## Plain DateTime fields by category')
    out.append('')
    for cat, fields in sorted(by_category.items()):
        out.append(f'### {cat} ({len(fields)} field{"s" if len(fields) != 1 else ""})')
        out.append('')
        out.append('| Model | Field | Line |')
        out.append('|-------|-------|------|')
        for f in fields:
            out.append(f'| `{f["model"]}` | `{f["field"]}` | schema.prisma:{f["line"]} |')
        out.append('')
    out.append('## Already-correct @db.Timestamptz fields')
    out.append('')
    out.append(f'{len(fields_tstz)} fields already use `@db.Timestamptz` (no change needed).')
    out.append('')
    out.append('These are the model to follow for the migration.')
    out.append('')
    by_model_tstz = defaultdict(list)
    for f in fields_tstz:
        by_model_tstz[f['model']].append(f)
    for model, fields in sorted(by_model_tstz.items()):
        out.append(f'- `{model}`: {", ".join("`" + f["field"] + "`" for f in fields)}')
    out.append('')
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text('\n'.join(out))
    print(f'Report written to {OUT_PATH}')


def main():
    text = SCHEMA_PATH.read_text()
    fields_tstz, fields_ts, fields_plain = parse_schema(text)
    print(f'Total: {len(fields_tstz) + len(fields_ts) + len(fields_plain)}')
    print(f'  @db.Timestamptz: {len(fields_tstz)}')
    print(f'  @db.Timestamp:   {len(fields_ts)}')
    print(f'  Plain DateTime: {len(fields_plain)}')
    write_report(fields_tstz, fields_ts, fields_plain)
    # Also audit the SQL migrations for plain TIMESTAMP (no TZ) usage.
    audit_sql_migrations()


def audit_sql_migrations():
    """Walk supabase/migrations/*.sql and find any TIMESTAMP (without TZ)
    column definitions or ALTER TABLE ... TYPE TIMESTAMP statements."""
    import glob
    plain_lines = []
    tstz_total = 0
    for path in sorted(glob.glob('supabase/migrations/*.sql')):
        text = Path(path).read_text()
        tstz_total += len(re.findall(r'\bTIMESTAMPTZ\b', text, re.IGNORECASE))
        for i, line in enumerate(text.split('\n'), 1):
            # Skip comment lines.
            stripped = line.lstrip()
            if stripped.startswith('--'):
                continue
            # Detect "plain TIMESTAMP" — i.e., TIMESTAMP not followed by
            # TZ (with optional precision like (3)) AND not "TIMESTAMP WITH
            # TIME ZONE". This catches:
            #   - TIMESTAMP
            #   - TIMESTAMP(3)
            #   - TIMESTAMP WITHOUT TIME ZONE
            #   - timestamp without time zone
            # But NOT:
            #   - TIMESTAMPTZ
            #   - TIMESTAMP WITH TIME ZONE
            #   - timestamp with time zone
            lower = line.lower()
            # If the line mentions "with time zone", it's timestamptz — skip.
            if 'with time zone' in lower:
                continue
            # If the line mentions "timestamptz" anywhere, skip.
            if 'timestamptz' in lower:
                continue
            # Now look for plain TIMESTAMP usage.
            # Patterns: TIMESTAMP, TIMESTAMP(3), TIMESTAMP WITHOUT TIME ZONE.
            for m in re.finditer(r'\bTIMESTAMP(?:\(\d+\))?(?:\s+WITHOUT\s+TIME\s+ZONE)?', line, re.IGNORECASE):
                # Filter: must be a real SQL column definition or ALTER
                # statement, not just a comment in inline SQL.
                # We accept any line that has either of:
                #   - A column-name pattern like `"colName" TIMESTAMP` or
                #     `col_name timestamp`
                #   - An ALTER TABLE ... ADD COLUMN / TYPE clause
                if not re.search(
                    r'(?:^|\s)(["`\w]+\s+)(TIMESTAMP|timestamp)',
                    line,
                ) and not re.search(
                    r'(ADD\s+COLUMN|TYPE\s+TIMESTAMP|ALTER\s+TABLE.*TIMESTAMP)',
                    line,
                    re.IGNORECASE,
                ):
                    continue
                plain_lines.append((path, i, line.rstrip()))
                break
    print()
    print(f'=== SQL migrations audit ===')
    print(f'Total TIMESTAMPTZ occurrences in SQL migrations: {tstz_total}')
    print(f'Lines with plain TIMESTAMP (no TZ) in real SQL: {len(plain_lines)}')
    for path, ln, line in plain_lines[:40]:
        print(f'  {path}:{ln}: {line.strip()[:120]}')
    if len(plain_lines) > 40:
        print(f'  ... ({len(plain_lines)} total)')

    # Append to the report.
    with OUT_PATH.open('a') as f:
        f.write('\n## SQL migrations audit (plain TIMESTAMP without TZ)\n\n')
        f.write(f'Total `TIMESTAMPTZ` occurrences in `supabase/migrations/*.sql`: **{tstz_total}**.\n\n')
        if plain_lines:
            f.write(f'The following **{len(plain_lines)} lines** use plain `TIMESTAMP` (without TZ) in real SQL column definitions / ALTER TABLE statements — these should be migrated to `TIMESTAMPTZ` alongside the Prisma migration.\n\n')
            f.write('| File | Line | SQL |\n|------|------|-----|\n')
            for path, ln, line in plain_lines:
                disp = line.strip().replace('|', '\\|')
                # Truncate very long lines
                if len(disp) > 200:
                    disp = disp[:200] + '...'
                f.write(f'| `{path}` | {ln} | `{disp}` |\n')
        else:
            f.write('No plain `TIMESTAMP` (without TZ) usage found in real SQL column definitions.\n')


if __name__ == '__main__':
    main()
