// Full E2E test using the known token format
const SERVER_URL = 'https://daxelo-kinrel-server.onrender.com';
const { createClient } = require('@supabase/supabase-js');
const { Client } = require('pg');
const bcrypt = require('bcryptjs');
const supabaseAdmin = createClient('https://promxswvsnvilplmrtsj.supabase.co', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InByb214c3d2c252aWxwbG1ydHNqIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3OTU5NzE4MCwiZXhwIjoyMDk1MTczMTgwfQ.sgaciYwaTVd3FoGqZEe_cQamSXiAXA9SYdLjf2ICcCE');
const pg = new Client({ connectionString: 'postgresql://postgres.promxswvsnvilplmrtsj:tvAFZQp89nUulXeE@aws-1-ap-southeast-1.pooler.supabase.com:5432/postgres' });

let accessToken, userId, familyId;
let decisionId, timelineEventId, insightId, artifactId;
const results = { pass: 0, fail: 0, bugs: [] };

async function api(method, path, body) {
  const headers = { 'Content-Type': 'application/json', 'Authorization': `Bearer ${accessToken}` };
  const opts = { method, headers };
  if (body !== undefined) opts.body = JSON.stringify(body);
  const res = await fetch(`${SERVER_URL}${path}`, opts);
  let data = null;
  try { data = await res.json(); } catch {}
  return { status: res.status, data };
}

function check(name, condition, detail = '') {
  if (condition) { console.log(`  ✅ ${name}`); results.pass++; }
  else { console.log(`  ❌ ${name} ${detail}`); results.fail++; results.bugs.push(name); }
}

async function main() {
  console.log('=== TRACK C v2.0 END-TO-END VERIFICATION ===\n');

  // ── Setup: create user + family + get token ──────────────────────────
  console.log('0. Setup:');
  await pg.connect();
  const testEmail = `trackc-verify-${Date.now()}@kinrel-test.com`;
  const passwordHash = await bcrypt.hash('TestPassword123!', 12);
  userId = `usr_${Date.now()}`;
  familyId = `fam_${Date.now()}`;
  
  await pg.query('INSERT INTO "User" (id, email, name, "passwordHash", role, "preferredLanguage", "createdAt", "updatedAt") VALUES ($1,$2,$3,$4,$5,$6, NOW(), NOW())',
    [userId, testEmail, 'Verifier', passwordHash, 'user', 'en']);
  await pg.query('INSERT INTO "Family" (id, name, "createdBy", "primaryLanguage", "privacyMode", "memberCount", "lastActivityAt", "familyCode", "isOnboarded") VALUES ($1,$2,$3,$4,$5,1,NOW(),$6,true)',
    [familyId, 'Verify Family', userId, 'en', 'private', `code_${Date.now()}`]);
  
  const loginRes = await fetch(`${SERVER_URL}/api/auth/login`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: testEmail, password: 'TestPassword123!' }),
  });
  const loginData = await loginRes.json();
  accessToken = loginData.data?.accessToken;
  check('Auth: register + login + get NestJS JWT', !!accessToken, `token: ${accessToken?.slice(0, 20)}...`);
  console.log(`  User: ${userId}, Family: ${familyId}`);

  // ── 1. Constitution ──────────────────────────────────────────────────
  console.log('\n1. Constitution:');
  const gc = await api('GET', `/api/v1/families/${familyId}/constitution`);
  check('GET constitution (auto-creates shell)', gc.status === 200, `status ${gc.status}: ${JSON.stringify(gc.data).slice(0,150)}`);

  const dc = await api('POST', `/api/v1/families/${familyId}/constitution/draft`, {
    title: 'Test Constitution', preamble: 'Test preamble',
    articles: [{ title: 'Article 1', intent: 'Test', clauses: [{ text: 'Clause 1' }] }],
  });
  check('POST draft constitution', dc.status === 200 || dc.status === 201, `status ${dc.status}: ${JSON.stringify(dc.data).slice(0,150)}`);

  const pc = await api('POST', `/api/v1/families/${familyId}/constitution/publish`, { changeSummary: 'v1' });
  check('POST publish constitution', pc.status === 200 || pc.status === 201, `status ${pc.status}: ${JSON.stringify(pc.data).slice(0,150)}`);

  const vc = await api('GET', `/api/v1/families/${familyId}/constitution/versions`);
  check('GET versions', vc.status === 200 && vc.data?.length > 0, `status ${vc.status}`);

  // ── 2. Decisions ─────────────────────────────────────────────────────
  console.log('\n2. Decisions:');
  const cd = await api('POST', `/api/v1/families/${familyId}/decisions`, {
    title: 'Test Decision', description: 'Test', type: 'simple_vote',
    options: ['A','B'], quorumPct: 50,
    deadlineAt: new Date(Date.now() + 86400000).toISOString(),
  });
  check('POST create decision', cd.status === 200 || cd.status === 201, `status ${cd.status}: ${JSON.stringify(cd.data).slice(0,200)}`);
  decisionId = cd.data?.id;

  if (decisionId) {
    const ld = await api('GET', `/api/v1/families/${familyId}/decisions?status=open`);
    check('GET list decisions', ld.status === 200 && ld.data?.items?.length > 0, `status ${ld.status}`);

    const gd = await api('GET', `/api/v1/families/${familyId}/decisions/${decisionId}`);
    check('GET decision detail', gd.status === 200, `status ${gd.status}`);

    const vd = await api('POST', `/api/v1/families/${familyId}/decisions/${decisionId}/vote`, { option: 'A' });
    check('POST vote', vd.status === 200 || vd.status === 201, `status ${vd.status}: ${JSON.stringify(vd.data).slice(0,200)}`);

    const vd2 = await api('POST', `/api/v1/families/${familyId}/decisions/${decisionId}/vote`, { option: 'B' });
    check('POST duplicate vote → 409', vd2.status === 409, `expected 409, got ${vd2.status}`);

    const rd = await api('POST', `/api/v1/families/${familyId}/decisions/${decisionId}/resolve`, {});
    check('POST resolve decision', rd.status === 200, `status ${rd.status}: ${JSON.stringify(rd.data).slice(0,200)}`);

    const lc = await api('PATCH', `/api/v1/families/${familyId}/decisions/${decisionId}/lifecycle`, { to: 'started' });
    check('PATCH lifecycle planned→started', lc.status === 200, `status ${lc.status}: ${JSON.stringify(lc.data).slice(0,200)}`);
  }

  // ── 3. Timeline ──────────────────────────────────────────────────────
  console.log('\n3. Timeline:');
  const tl = await api('GET', `/api/v1/families/${familyId}/timeline`);
  check('GET timeline', tl.status === 200 && tl.data?.items?.length > 0, `status ${tl.status}, items: ${tl.data?.items?.length||0}`);
  if (tl.data?.items?.length > 0) {
    timelineEventId = tl.data.items[0].id;
    console.log(`    ${tl.data.items.length} events found`);
    
    const co = await api('POST', `/api/v1/families/${familyId}/timeline/${timelineEventId}/correct`, {
      correctedFields: { title: { from: 'old', to: 'new' } }, note: 'test',
    });
    check('POST correct timeline event', co.status === 200 || co.status === 201, `status ${co.status}`);

    const ex = await api('GET', `/api/v1/families/${familyId}/timeline/export?format=json`);
    check('GET timeline export (JSON)', ex.status === 200, `status ${ex.status}`);
  }

  // ── 4. AI Insights ───────────────────────────────────────────────────
  console.log('\n4. AURA Intelligence (AI):');
  if (decisionId) {
    const ir = await api('POST', `/api/v1/families/${familyId}/decisions/${decisionId}/insights/request`, {
      kinds: ['decision_analysis', 'pros_cons'],
    });
    check('POST request insights', ir.status === 200, `status ${ir.status}: ${JSON.stringify(ir.data).slice(0,300)}`);
    if (ir.status === 200) {
      console.log(`    cached: ${ir.data.cached?.length||0}, generated: ${ir.data.generated?.length||0}, degraded: ${ir.data.degradedMode}`);
      insightId = ir.data.generated?.[0]?.id || ir.data.cached?.[0]?.id;
    }
    if (insightId) {
      const ac = await api('POST', `/api/v1/insights/${insightId}/accept`, { familyId });
      check('POST accept insight', ac.status === 200, `status ${ac.status}`);
    }
  }

  // ── 5. Learning ──────────────────────────────────────────────────────
  console.log('\n5. AURA Learning:');
  const lp = await api('GET', `/api/v1/families/${familyId}/learning/profile`);
  check('GET learning profile', lp.status === 200, `status ${lp.status}: ${JSON.stringify(lp.data).slice(0,200)}`);

  const sg = await api('POST', `/api/v1/families/${familyId}/learning/signals`, {
    signalType: 'insight_accepted', targetType: 'AIInsight', targetId: insightId || 'x', payload: { kind: 'test' },
  });
  check('POST learning signal', sg.status === 200 || sg.status === 201, `status ${sg.status}`);

  // ── 6. Search ────────────────────────────────────────────────────────
  console.log('\n6. AURA Search:');
  const ri = await api('POST', `/api/v1/families/${familyId}/search/reindex`);
  check('POST reindex', ri.status === 200, `status ${ri.status}: ${JSON.stringify(ri.data).slice(0,200)}`);

  const se = await api('GET', `/api/v1/families/${familyId}/search?q=test`);
  check('GET search', se.status === 200, `status ${se.status}: ${JSON.stringify(se.data).slice(0,200)}`);

  const su = await api('GET', `/api/v1/families/${familyId}/search/suggest?q=te`);
  check('GET suggest', su.status === 200, `status ${su.status}`);

  // ── 7. Secretary ─────────────────────────────────────────────────────
  console.log('\n7. AURA Secretary:');
  const ar = await api('POST', `/api/v1/families/${familyId}/secretary/artifacts`, {
    title: 'Test Meeting', heldAt: new Date().toISOString(), participants: [userId],
    agenda: ['Item 1'], discussionPoints: [{ point: 'P1', perspectives: [{userId, perspective:'ok'}] }],
    decisions: [{ text: 'D1', decided: true }],
  });
  check('POST create artifact', ar.status === 200 || ar.status === 201, `status ${ar.status}: ${JSON.stringify(ar.data).slice(0,200)}`);
  artifactId = ar.data?.id;

  const la = await api('GET', `/api/v1/families/${familyId}/secretary/artifacts`);
  check('GET list artifacts', la.status === 200, `status ${la.status}`);

  if (artifactId) {
    const pa = await api('POST', `/api/v1/families/${familyId}/secretary/artifacts/${artifactId}/publish`, {});
    check('POST publish artifact', pa.status === 200, `status ${pa.status}`);
  }

  // ── 8. Analytics ─────────────────────────────────────────────────────
  console.log('\n8. AURA Analytics:');
  const tr = await api('POST', `/api/v1/families/${familyId}/analytics/trigger?granularity=weekly`);
  check('POST trigger snapshot', tr.status === 200, `status ${tr.status}: ${JSON.stringify(tr.data).slice(0,200)}`);

  const sm = await api('GET', `/api/v1/families/${familyId}/analytics/summary`);
  check('GET analytics summary', sm.status === 200, `status ${sm.status}: ${JSON.stringify(sm.data).slice(0,200)}`);

  // ── 9. Sync ──────────────────────────────────────────────────────────
  console.log('\n9. Sync:');
  const dl = await fetch(`${SERVER_URL}/api/v1/sync/delta`, {
    headers: { 'Authorization': `Bearer ${accessToken}`, 'X-Device-Id': 'verify-dev-1' },
  });
  const dlData = await dl.json();
  check('GET delta (with X-Device-Id)', dl.status === 200, `status ${dl.status}: ${JSON.stringify(dlData).slice(0,200)}`);

  const pu = await api('POST', `/api/v1/sync/push`, { operations: [] });
  check('POST push (empty)', pu.status === 200, `status ${pu.status}`);

  // ── 10. RLS verification (cross-family isolation) ────────────────────
  console.log('\n10. RLS cross-family isolation:');
  // Create a second family + user, try to access first family's data
  const user2Id = `usr2_${Date.now()}`;
  const family2Id = `fam2_${Date.now()}`;
  const email2 = `trackc-verify2-${Date.now()}@kinrel-test.com`;
  await pg.query('INSERT INTO "User" (id, email, name, "passwordHash", role, "preferredLanguage", "createdAt", "updatedAt") VALUES ($1,$2,$3,$4,$5,$6, NOW(), NOW())',
    [user2Id, email2, 'User2', passwordHash, 'user', 'en']);
  await pg.query('INSERT INTO "Family" (id, name, "createdBy", "primaryLanguage", "privacyMode", "memberCount", "lastActivityAt", "familyCode", "isOnboarded") VALUES ($1,$2,$3,$4,$5,1,NOW(),$6,true)',
    [family2Id, 'Family2', user2Id, 'en', 'private', `code2_${Date.now()}`]);
  
  const login2Res = await fetch(`${SERVER_URL}/api/auth/login`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: email2, password: 'TestPassword123!' }),
  });
  const login2Data = await login2Res.json();
  const token2 = login2Data.data?.accessToken;
  
  if (token2) {
    // User2 tries to access Family1's constitution — should get 404 (not found, because RLS hides it)
    const crossRes = await fetch(`${SERVER_URL}/api/v1/families/${familyId}/constitution`, {
      headers: { 'Authorization': `Bearer ${token2}` },
    });
    check('RLS: user2 cannot access family1 constitution', crossRes.status === 404, `expected 404, got ${crossRes.status}`);
  } else {
    check('RLS: login user2', false, 'could not get token2');
  }

  // ── 11. Timeline append-only enforcement ─────────────────────────────
  console.log('\n11. Timeline append-only enforcement:');
  if (timelineEventId) {
    // Try to UPDATE a timeline event directly via DB — should fail
    try {
      await pg.query(`UPDATE "AURATimelineEvent" SET title = 'HACKED' WHERE id = $1`, [timelineEventId]);
      check('Timeline UPDATE blocked by trigger', false, 'UPDATE succeeded — trigger not working!');
    } catch (e) {
      check('Timeline UPDATE blocked by trigger', e.message.includes('append-only'), `error: ${e.message.slice(0,80)}`);
    }
    // Try to DELETE
    try {
      await pg.query(`DELETE FROM "AURATimelineEvent" WHERE id = $1`, [timelineEventId]);
      check('Timeline DELETE blocked by trigger', false, 'DELETE succeeded — trigger not working!');
    } catch (e) {
      check('Timeline DELETE blocked by trigger', e.message.includes('append-only'), `error: ${e.message.slice(0,80)}`);
    }
  }

  // ── Cleanup ──────────────────────────────────────────────────────────
  console.log('\nCleanup:');
  await pg.query('DELETE FROM "Family" WHERE id IN ($1, $2)', [familyId, family2Id]);
  await pg.query('DELETE FROM "User" WHERE id IN ($1, $2)', [userId, user2Id]);
  console.log('  ✅ Test data cleaned up');
  await pg.end();

  console.log('\n=== VERIFICATION SUMMARY ===');
  console.log(`Passed: ${results.pass}`);
  console.log(`Failed: ${results.fail}`);
  console.log(`Total: ${results.pass + results.fail}`);
  console.log(`Success rate: ${((results.pass / (results.pass + results.fail)) * 100).toFixed(1)}%`);
  if (results.bugs.length > 0) {
    console.log('\nBugs found:');
    results.bugs.forEach(b => console.log(`  - ${b}`));
  }
}

main().catch(e => { console.error('FATAL:', e.message); process.exit(1); });
