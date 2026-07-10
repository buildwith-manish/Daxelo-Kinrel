const SERVER_URL = 'https://daxelo-kinrel-server.onrender.com';
const { Client } = require('pg');
const bcrypt = require('bcryptjs');
const pg = new Client({ connectionString: 'postgresql://postgres.promxswvsnvilplmrtsj:tvAFZQp89nUulXeE@aws-1-ap-southeast-1.pooler.supabase.com:5432/postgres' });

async function main() {
  await pg.connect();
  const testEmail = 'trackc-full-' + Date.now() + '@kinrel-test.com';
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
  const headers = { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token };
  
  // Constitution draft — full error
  const dc = await fetch(SERVER_URL + '/api/v1/families/' + familyId + '/constitution/draft', {
    method: 'POST', headers,
    body: JSON.stringify({
      title: 'Test', preamble: 'Test',
      articles: [{ title: 'A1', intent: 'I1', clauses: [{ text: 'C1' }] }],
    }),
  });
  const dcData = await dc.json();
  console.log('=== CONSTITUTION DRAFT FULL ERROR ===');
  console.log(dcData.message);
  
  // Decision create — full error
  const dd = await fetch(SERVER_URL + '/api/v1/families/' + familyId + '/decisions', {
    method: 'POST', headers,
    body: JSON.stringify({
      title: 'Test', type: 'simple_vote', options: ['A','B'],
      quorumPct: 50, deadlineAt: new Date(Date.now()+86400000).toISOString(),
    }),
  });
  const ddData = await dd.json();
  console.log('\n=== DECISION CREATE FULL ERROR ===');
  console.log(ddData.message);
  
  // Search — full error
  const se = await fetch(SERVER_URL + '/api/v1/families/' + familyId + '/search?q=test', { headers });
  const seData = await se.json();
  console.log('\n=== SEARCH FULL ERROR ===');
  console.log(seData.message);
  
  // Secretary create — full error
  const ar = await fetch(SERVER_URL + '/api/v1/families/' + familyId + '/secretary/artifacts', {
    method: 'POST', headers,
    body: JSON.stringify({
      title: 'Test', heldAt: new Date().toISOString(), participants: [userId],
      agenda: ['A1'], discussionPoints: [], decisions: [],
    }),
  });
  const arData = await ar.json();
  console.log('\n=== SECRETARY CREATE FULL ERROR ===');
  console.log(arData.message);
  
  // RLS test — can user2 read family1's constitution?
  const user2Id = 'usr2_' + Date.now();
  const email2 = 'trackc-full2-' + Date.now() + '@kinrel-test.com';
  await pg.query('INSERT INTO "User" (id, email, name, "passwordHash", role, "preferredLanguage", "createdAt", "updatedAt") VALUES ($1,$2,$3,$4,$5,$6, NOW(), NOW())',
    [user2Id, email2, 'User2', passwordHash, 'user', 'en']);
  await pg.query('INSERT INTO "Family" (id, name, "createdBy", "primaryLanguage", "privacyMode", "memberCount", "lastActivityAt", "familyCode", "isOnboarded") VALUES ($1,$2,$3,$4,$5,1,NOW(),$6,true)',
    [`fam2_${Date.now()}`, 'Fam2', user2Id, 'en', 'private', 'code2_' + Date.now()]);
  const login2 = await fetch(SERVER_URL + '/api/auth/login', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: email2, password: 'TestPassword123!' }),
  });
  const login2Data = await login2.json();
  const token2 = login2Data.data?.accessToken;
  
  const crossRes = await fetch(SERVER_URL + '/api/v1/families/' + familyId + '/constitution', {
    headers: { 'Authorization': 'Bearer ' + token2 },
  });
  console.log('\n=== RLS CROSS-FAMILY TEST ===');
  console.log('User2 accessing Family1 constitution — status:', crossRes.status);
  if (crossRes.status === 200) {
    const crossData = await crossRes.json();
    console.log('DATA LEAKED:', JSON.stringify(crossData).slice(0, 200));
  }
  
  await pg.query('DELETE FROM "Family" WHERE "createdBy" IN ($1, $2)', [userId, user2Id]);
  await pg.query('DELETE FROM "User" WHERE id IN ($1, $2)', [userId, user2Id]);
  await pg.end();
}
main();
