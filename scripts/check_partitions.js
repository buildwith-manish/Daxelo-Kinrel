const { Client } = require('pg');
const client = new Client({
  connectionString: 'postgresql://postgres.promxswvsnvilplmrtsj:tvAFZQp89nUulXeE@aws-1-ap-southeast-1.pooler.supabase.com:5432/postgres',
});
async function main() {
  await client.connect();
  // List all FamilyDecision partitions
  const r = await client.query(`
    SELECT c.relname FROM pg_inherits
    JOIN pg_class c ON c.oid = pg_inherits.inhrelid
    JOIN pg_class p ON p.oid = pg_inherits.inhparent
    WHERE p.relname = 'FamilyDecision'
    ORDER BY c.relname
  `);
  console.log('FamilyDecision partitions:', r.rows.map(x => x.relname));
  // Same for KinrelTimelineEvent
  const r2 = await client.query(`
    SELECT c.relname FROM pg_inherits
    JOIN pg_class c ON c.oid = pg_inherits.inhrelid
    JOIN pg_class p ON p.oid = pg_inherits.inhparent
    WHERE p.relname = 'KinrelTimelineEvent'
    ORDER BY c.relname
  `);
  console.log('KinrelTimelineEvent partitions:', r2.rows.map(x => x.relname));
  await client.end();
}
main().catch(e => { console.error(e.message); process.exit(1); });
