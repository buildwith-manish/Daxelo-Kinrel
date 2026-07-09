const { Client } = require('pg');
const client = new Client({
  connectionString: 'postgresql://postgres.promxswvsnvilplmrtsj:tvAFZQp89nUulXeE@aws-1-ap-southeast-1.pooler.supabase.com:5432/postgres',
});
async function main() {
  await client.connect();
  // Check if AIInsight is partitioned
  const r1 = await client.query(`SELECT c.relname, pt.partstrat FROM pg_partitioned_table pt JOIN pg_class c ON c.oid = pt.partrelid WHERE c.relname = 'AIInsight'`);
  console.log('AIInsight partitioned:', r1.rows.length > 0);
  // Check if AIInsight table exists at all
  const r2 = await client.query(`SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename='AIInsight'`);
  console.log('AIInsight exists:', r2.rows.length > 0);
  // Check SmartReminder FKs
  const r3 = await client.query(`
    SELECT conname, conrelid::regclass AS table_from, confrelid::regclass AS table_to
    FROM pg_constraint
    WHERE conrelid = '"SmartReminder"'::regclass AND contype = 'f'
  `);
  console.log('SmartReminder FKs:', r3.rows);
  await client.end();
}
main().catch(e => { console.error(e.message); process.exit(1); });
