const { Client } = require('pg');
const bcrypt = require('bcryptjs');
const fs = require('fs');

const pg = new Client({ connectionString: 'postgresql://postgres.promxswvsnvilplmrtsj:tvAFZQp89nUulXeE@aws-1-ap-southeast-1.pooler.supabase.com:5432/postgres' });

async function main() {
  await pg.connect();
  
  const testEmail = 'trackc-e2e-' + Date.now() + '@kinrel-test.com';
  const passwordHash = await bcrypt.hash('TestPassword123!', 12);
  const userId = 'usr_' + Date.now();
  const familyId = 'fam_' + Date.now();
  
  console.log('Creating test user:', userId, testEmail);
  
  await pg.query('INSERT INTO "User" (id, email, name, "passwordHash", role, "preferredLanguage", "createdAt", "updatedAt") VALUES ($1, $2, $3, $4, $5, $6, NOW(), NOW())', 
    [userId, testEmail, 'Track C Tester', passwordHash, 'user', 'en']);
  console.log('  User created');
  
  // The after_family_insert trigger auto-creates a FamilyMember with role='owner'
  await pg.query('INSERT INTO "Family" (id, name, "createdBy", "primaryLanguage", "privacyMode", "memberCount", "lastActivityAt", "createdAt", "updatedAt", "familyCode", "isOnboarded") VALUES ($1, $2, $3, $4, $5, 1, NOW(), NOW(), NOW(), $6, true)',
    [familyId, 'Track C Test Family', userId, 'en', 'private', 'code_' + Date.now()]);
  console.log('  Family created (trigger auto-creates FamilyMember)');
  
  // Verify the member was auto-created
  const m = await pg.query('SELECT role FROM "FamilyMember" WHERE "familyId" = $1 AND "userId" = $2', [familyId, userId]);
  console.log('  Auto-created member role:', m.rows[0]?.role || 'NOT FOUND');
  
  // Test login
  const loginRes = await fetch('https://daxelo-kinrel-server.onrender.com/api/auth/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: testEmail, password: 'TestPassword123!' }),
  });
  const loginData = await loginRes.json();
  console.log('Login status:', loginRes.status);
  
  if (loginRes.status === 200 || loginRes.status === 201) {
    const token = loginData.accessToken || loginData.access_token;
    console.log('  Login successful, token length:', token.length);
    fs.writeFileSync('/tmp/trackc-test-creds.json', JSON.stringify({ userId, familyId, token, email: testEmail }, null, 2));
    console.log('  Credentials saved');
  } else {
    console.log('  Login failed:', JSON.stringify(loginData).slice(0, 300));
  }
  
  await pg.end();
}
main().catch(e => console.error(e.message));
