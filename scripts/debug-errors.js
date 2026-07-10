const SERVER_URL = 'https://daxelo-kinrel-server.onrender.com';
const { Client } = require('pg');
const bcrypt = require('bcryptjs');
const pg = new Client({ connectionString: 'postgresql://postgres.promxswvsnvilplmrtsj:tvAFZQp89nUulXeE@aws-1-ap-southeast-1.pooler.supabase.com:5432/postgres' });

async function main() {
  await pg.connect();
  const testEmail = 'trackc-debug-' + Date.now() + '@kinrel-test.com';
  const passwordHash = await bcrypt.hash('TestPassword123!', 12);
  const userId = 'usr_' + Date.now();
  const familyId = 'fam_' + Date.now();
  await pg.query('INSERT INTO "User" (id, email, name, "passwordHash", role, "preferredLanguage", "createdAt", "updatedAt") VALUES ($1,$2,$3,$4,$5,$6, NOW(), NOW())',
    [userId, testEmail, 'Debug', passwordHash, 'user', 'en']);
  await pg.query('INSERT INTO "Family" (id, name, "createdBy", "primaryLanguage", "privacyMode", "memberCount", "lastActivityAt", "familyCode", "isOnboarded") VALUES ($1,$2,$3,$4,$5,1,NOW(),$6,true)',
    [familyId, 'Debug Family', userId, 'en', 'private', 'code_' + Date.now()]);
  
  const loginRes = await fetch(SERVER_URL + '/api/auth/login', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: testEmail, password: 'TestPassword123!' }),
  });
  const loginData = await loginRes.json();
  const token = loginData.data?.accessToken;
  
  // Constitution draft
  const dc = await fetch(SERVER_URL + '/api/v1/families/' + familyId + '/constitution/draft', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token },
    body: JSON.stringify({
      title: 'Test', preamble: 'Test',
      articles: [{ title: 'A1', intent: 'I1', clauses: [{ text: 'C1' }] }],
    }),
  });
  const dcData = await dc.json();
  console.log('=== CONSTITUTION DRAFT ERROR ===');
  console.log(dcData.message);
  
  // Decision create
  const dd = await fetch(SERVER_URL + '/api/v1/families/' + familyId + '/decisions', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token },
    body: JSON.stringify({
      title: 'Test', type: 'simple_vote', options: ['A','B'],
      quorumPct: 50, deadlineAt: new Date(Date.now()+86400000).toISOString(),
    }),
  });
  const ddData = await dd.json();
  console.log('\n=== DECISION CREATE ERROR ===');
  console.log(ddData.message);
  
  // Search reindex
  const sr = await fetch(SERVER_URL + '/api/v1/families/' + familyId + '/search/reindex', {
    method: 'POST',
    headers: { 'Authorization': 'Bearer ' + token },
  });
  const srData = await sr.json();
  console.log('\n=== SEARCH REINDEX ERROR ===');
  console.log(srData.message);
  
  await pg.query('DELETE FROM "Family" WHERE id = $1', [familyId]);
  await pg.query('DELETE FROM "User" WHERE id = $1', [userId]);
  await pg.end();
}
main();
