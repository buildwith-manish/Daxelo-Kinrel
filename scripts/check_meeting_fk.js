const { Client } = require('pg');
const client = new Client({
  connectionString: 'postgresql://postgres.promxswvsnvilplmrtsj:tvAFZQp89nUulXeE@aws-1-ap-southeast-1.pooler.supabase.com:5432/postgres',
});
async function main() {
  await client.connect();
  const r = await client.query(`
    SELECT conname, pg_get_constraintdef(oid) as def
    FROM pg_constraint
    WHERE conrelid = '"MeetingArtifact"'::regclass AND contype = 'f'
  `);
  for (const row of r.rows) {
    console.log(row.conname, ':', row.def);
  }
  await client.end();
}
main().catch(e => { console.error(e.message); process.exit(1); });
