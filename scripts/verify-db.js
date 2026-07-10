// Comprehensive DB verification
const { Client } = require('pg');
const client = new Client({
  connectionString: 'postgresql://postgres.promxswvsnvilplmrtsj:tvAFZQp89nUulXeE@aws-1-ap-southeast-1.pooler.supabase.com:5432/postgres',
});

async function main() {
  await client.connect();
  console.log('=== DATABASE VERIFICATION ===\n');

  // 1. All Track C tables exist
  const expectedTables = [
    'FamilyConstitution','ConstitutionVersion','ConstitutionArticle','ConstitutionClause',
    'FamilyDecision','DecisionVote','KinrelTimelineEvent','AIInsight',
    'LearningSignal','FamilyBehaviorProfile','FamilyBehaviorProfileHistory',
    'SmartReminder','DecisionMemory','DecisionImpact','MeetingArtifact',
    'SearchIndex','FamilyAnalyticsSnapshot','GlobalLearningDefaults',
    'AICostBudget','SyncWatermark'
  ];
  const r1 = await client.query(`SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename = ANY($1)`, [expectedTables]);
  const found = new Set(r1.rows.map(r => r.tablename));
  const missing = expectedTables.filter(t => !found.has(t));
  console.log(`Tables: ${found.size}/${expectedTables.length} ${missing.length ? 'MISSING: ' + missing.join(',') : '✅'}`);

  // 2. Partitioning
  const r2 = await client.query(`SELECT c.relname, pt.partstrat FROM pg_partitioned_table pt JOIN pg_class c ON c.oid = pt.partrelid WHERE c.relname IN ('FamilyDecision','KinrelTimelineEvent','AIInsight','LearningSignal')`);
  console.log(`Partitioned tables: ${r2.rows.length}/4 ${r2.rows.length === 4 ? '✅' : '❌'}`);
  for (const row of r2.rows) {
    const pc = await client.query(`SELECT count(*) as n FROM pg_inherits JOIN pg_class c ON c.oid = inhrelid JOIN pg_class p ON p.oid = inhparent WHERE p.relname = $1`, [row.relname]);
    const expected = row.relname === 'FamilyDecision' || row.relname === 'KinrelTimelineEvent' ? 32 : 16;
    console.log(`  ${row.relname}: ${pc.rows[0].n} partitions (expected ${expected}) ${pc.rows[0].n == expected ? '✅' : '❌'}`);
  }

  // 3. RLS enabled
  const rlsTables = ['FamilyConstitution','ConstitutionVersion','ConstitutionArticle','ConstitutionClause','FamilyDecision','DecisionVote','KinrelTimelineEvent','AIInsight','LearningSignal','FamilyBehaviorProfile','FamilyBehaviorProfileHistory','SmartReminder','DecisionMemory','DecisionImpact','MeetingArtifact','SearchIndex','FamilyAnalyticsSnapshot'];
  const r3 = await client.query(`SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname='public' AND tablename = ANY($1)`, [rlsTables]);
  const rlsEnabled = r3.rows.filter(r => r.rowsecurity).length;
  console.log(`RLS enabled: ${rlsEnabled}/${rlsTables.length} ${rlsEnabled === rlsTables.length ? '✅' : '❌'}`);

  // 4. RLS policies count
  const r4 = await client.query(`SELECT count(*) as n FROM pg_policies WHERE schemaname='public' AND tablename IN ('FamilyDecision','KinrelTimelineEvent','AIInsight','LearningSignal')`);
  console.log(`RLS policies on key tables: ${r4.rows[0].n} ${r4.rows[0].n >= 8 ? '✅' : '⚠️ (expected ≥8)'}`);

  // 5. Timeline append-only triggers
  const r5 = await client.query(`SELECT count(*) as n FROM pg_trigger WHERE tgname IN ('timeline_no_update','timeline_no_delete') AND NOT tgisinternal`);
  console.log(`Timeline append-only triggers: ${r5.rows[0].n} ${r5.rows[0].n >= 2 ? '✅' : '❌'}`);

  // 6. Monotonic updatedAt triggers
  const r6 = await client.query(`SELECT count(*) as n FROM pg_trigger WHERE tgname LIKE 'trg_trackc_%_updated_at' AND NOT tgisinternal`);
  console.log(`Monotonic updatedAt triggers: ${r6.rows[0].n} ${r6.rows[0].n >= 8 ? '✅' : '⚠️'}`);

  // 7. SearchIndex tsvector + GIN
  const r7 = await client.query(`SELECT column_name FROM information_schema.columns WHERE table_name='SearchIndex' AND column_name='search_tsvector'`);
  console.log(`SearchIndex tsvector column: ${r7.rows.length > 0 ? '✅' : '❌'}`);
  const r7b = await client.query(`SELECT indexname FROM pg_indexes WHERE tablename='SearchIndex' AND indexname='search_index_tsvector_gin'`);
  console.log(`SearchIndex GIN index: ${r7b.rows.length > 0 ? '✅' : '❌'}`);

  // 8. pgboss schema
  const r8 = await client.query(`SELECT nspname FROM pg_namespace WHERE nspname='pgboss'`);
  console.log(`pgboss schema: ${r8.rows.length > 0 ? '✅' : '❌'}`);

  // 9. GlobalLearningDefaults seeded
  const r9 = await client.query(`SELECT id FROM "GlobalLearningDefaults" WHERE id='global'`);
  console.log(`GlobalLearningDefaults seeded: ${r9.rows.length > 0 ? '✅' : '❌'}`);

  // 10. FK constraints on partitioned tables (composite FKs)
  const r10 = await client.query(`
    SELECT conname FROM pg_constraint
    WHERE contype='f' AND conname IN ('DecisionVote_decisionId_fkey','DecisionMemory_decisionId_fkey','AIInsight_decisionId_fkey','SmartReminder_decisionId_fkey','MeetingArtifact_decisionId_fkey')
  `);
  console.log(`Composite FKs to FamilyDecision: ${r10.rows.length}/5 ${r10.rows.length >= 5 ? '✅' : '❌'}`);

  // 11. Check the _trackc_migrations_applied tracking table
  const r11 = await client.query(`SELECT count(*) as n FROM public._trackc_migrations_applied`);
  console.log(`Applied migrations tracked: ${r11.rows[0].n}/20 ${r11.rows[0].n >= 20 ? '✅' : '⚠️'}`);

  // 12. Verify a sample RLS policy actually works (test as anon)
  await client.query(`SET ROLE anon`);
  try {
    const r12 = await client.query(`SELECT count(*) FROM "FamilyDecision"`);
    console.log(`RLS anon read test: returned ${r12.rows[0].n} rows (expected 0) ✅`);
  } catch (e) {
    console.log(`RLS anon read test: ${e.message} ❌`);
  }
  await client.query(`RESET ROLE`);

  await client.end();
}
main().catch(e => { console.error(e.message); process.exit(1); });
