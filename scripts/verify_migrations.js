const { Client } = require('pg');
const client = new Client({
  connectionString: 'postgresql://postgres.promxswvsnvilplmrtsj:tvAFZQp89nUulXeE@aws-1-ap-southeast-1.pooler.supabase.com:5432/postgres',
});
async function main() {
  await client.connect();

  // 1. Verify all Track C tables exist
  const expectedTables = [
    'FamilyConstitution','ConstitutionVersion','ConstitutionArticle','ConstitutionClause',
    'FamilyDecision','DecisionVote','AURATimelineEvent','AIInsight',
    'LearningSignal','FamilyBehaviorProfile','FamilyBehaviorProfileHistory',
    'SmartReminder','DecisionMemory','DecisionImpact','MeetingArtifact',
    'SearchIndex','FamilyAnalyticsSnapshot','GlobalLearningDefaults',
    'AICostBudget','SyncWatermark'
  ];
  const r1 = await client.query(`
    SELECT tablename FROM pg_tables
    WHERE schemaname = 'public' AND tablename = ANY($1)
  `, [expectedTables]);
  console.log(`Tables found: ${r1.rows.length}/${expectedTables.length}`);
  const found = new Set(r1.rows.map(r => r.tablename));
  const missing = expectedTables.filter(t => !found.has(t));
  if (missing.length) console.log('  MISSING:', missing);

  // 2. Verify partitioned tables
  const r2 = await client.query(`
    SELECT c.relname, pt.partstrat
    FROM pg_partitioned_table pt
    JOIN pg_class c ON c.oid = pt.partrelid
    WHERE c.relname IN ('FamilyDecision','AURATimelineEvent','AIInsight','LearningSignal')
  `);
  console.log(`Partitioned tables: ${r2.rows.length}/4`);
  for (const row of r2.rows) {
    const r = await client.query(`
      SELECT count(*) as n FROM pg_inherits
      JOIN pg_class c ON c.oid = inhrelid
      JOIN pg_class p ON p.oid = inhparent
      WHERE p.relname = $1
    `, [row.relname]);
    console.log(`  ${row.relname}: ${r.rows[0].n} partitions`);
  }

  // 3. Verify RLS enabled
  const r3 = await client.query(`
    SELECT tablename FROM pg_tables
    WHERE schemaname = 'public' AND rowsecurity = true
    AND tablename IN ('FamilyConstitution','FamilyDecision','AURATimelineEvent','AIInsight','LearningSignal','FamilyBehaviorProfile','SmartReminder','DecisionMemory','DecisionImpact','MeetingArtifact','SearchIndex','FamilyAnalyticsSnapshot')
  `);
  console.log(`RLS-enabled tables: ${r3.rows.length}/12`);

  // 4. Verify pg-boss schema
  const r4 = await client.query(`SELECT nspname FROM pg_namespace WHERE nspname = 'pgboss'`);
  console.log(`pgboss schema: ${r4.rows.length > 0 ? 'exists' : 'MISSING'}`);

  // 5. Verify timeline append-only trigger
  const r5 = await client.query(`
    SELECT tgname FROM pg_trigger
    WHERE tgname IN ('timeline_no_update','timeline_no_delete')
  `);
  console.log(`Timeline triggers: ${r5.rows.length}/2`);

  // 6. Verify global defaults seeded
  const r6 = await client.query(`SELECT id FROM "GlobalLearningDefaults" WHERE id = 'global'`);
  console.log(`GlobalLearningDefaults seeded: ${r6.rows.length > 0}`);

  await client.end();
  console.log('\n✓ Verification complete');
}
main().catch(e => { console.error(e.message); process.exit(1); });
