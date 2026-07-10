// Final E2E verification with corrected assertions
const SERVER_URL = 'https://daxelo-kinrel-server.onrender.com';
const { Client } = require('pg');
const bcrypt = require('bcryptjs');
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

// 200 or 201 both indicate success for reads/creates
const ok = (s) => s === 200 || s === 201;

async function main() {
  console.log('=== TRACK C v2.0 FINAL E2E VERIFICATION ===\n');

  // Setup
  console.log('0. Setup:');
  await pg.connect();
  const testEmail = `trackc-final-${Date.now()}@kinrel-test.com`;
  const passwordHash = await bcrypt.hash('TestPassword123!', 12);
  userId = `usr_${Date.now()}`;
  familyId = `fam_${Date.now()}`;
  await pg.query('INSERT INTO "User" (id, email, name, "passwordHash", role, "preferredLanguage", "createdAt", "updatedAt") VALUES ($1,$2,$3,$4,$5,$6, NOW(), NOW())',
    [userId, testEmail, 'Final', passwordHash, 'user', 'en']);
  await pg.query('INSERT INTO "Family" (id, name, "createdBy", "primaryLanguage", "privacyMode", "memberCount", "lastActivityAt", "familyCode", "isOnboarded") VALUES ($1,$2,$3,$4,$5,1,NOW(),$6,true)',
    [familyId, 'Final Family', userId, 'en', 'private', `code_${Date.now()}`]);
  const loginRes = await fetch(`${SERVER_URL}/api/auth/login`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: testEmail, password: 'TestPassword123!' }),
  });
  const loginData = await loginRes.json();
  accessToken = loginData.data?.accessToken;
  check('Auth: login + get JWT', !!accessToken);

  // 1. Constitution
  console.log('\n1. Constitution:');
  const gc = await api('GET', `/api/v1/families/${familyId}/constitution`);
  check('GET constitution', ok(gc.status), `status ${gc.status}`);

  const dc = await api('POST', `/api/v1/families/${familyId}/constitution/draft`, {
    title: 'Test Constitution', preamble: 'Test',
    articles: [{ title: 'A1', intent: 'I1', clauses: [{ text: 'C1' }] }],
  });
  check('POST draft constitution', ok(dc.status), `status ${dc.status}: ${JSON.stringify(dc.data).slice(0,200)}`);

  const pc = await api('POST', `/api/v1/families/${familyId}/constitution/publish`, { changeSummary: 'v1' });
  check('POST publish constitution', ok(pc.status), `status ${pc.status}: ${JSON.stringify(pc.data).slice(0,200)}`);

  const vc = await api('GET', `/api/v1/families/${familyId}/constitution/versions`);
  check('GET versions', ok(vc.status) && vc.data?.length > 0, `status ${vc.status}, count: ${vc.data?.length}`);

  // 2. Decisions
  console.log('\n2. Decisions:');
  const cd = await api('POST', `/api/v1/families/${familyId}/decisions`, {
    title: 'Test Decision', type: 'simple_vote', options: ['A','B'],
    quorumPct: 50, deadlineAt: new Date(Date.now()+86400000).toISOString(),
  });
  check('POST create decision', ok(cd.status), `status ${cd.status}`);
  decisionId = cd.data?.id;

  if (decisionId) {
    const ld = await api('GET', `/api/v1/families/${familyId}/decisions?status=open`);
    check('GET list decisions', ok(ld.status) && ld.data?.items?.length > 0, `status ${ld.status}`);

    const gd = await api('GET', `/api/v1/families/${familyId}/decisions/${decisionId}`);
    check('GET decision detail', ok(gd.status), `status ${gd.status}`);

    const vd = await api('POST', `/api/v1/families/${familyId}/decisions/${decisionId}/vote`, { option: 'A' });
    check('POST vote', ok(vd.status), `status ${vd.status}: ${JSON.stringify(vd.data).slice(0,200)}`);

    const vd2 = await api('POST', `/api/v1/families/${familyId}/decisions/${decisionId}/vote`, { option: 'B' });
    check('POST duplicate vote → 409', vd2.status === 409, `expected 409, got ${vd2.status}`);

    const rd = await api('POST', `/api/v1/families/${familyId}/decisions/${decisionId}/resolve`, {});
    check('POST resolve decision', ok(rd.status), `status ${rd.status}: ${JSON.stringify(rd.data).slice(0,200)}`);

    const lc = await api('PATCH', `/api/v1/families/${familyId}/decisions/${decisionId}/lifecycle`, { to: 'started' });
    check('PATCH lifecycle planned→started', ok(lc.status), `status ${lc.status}`);
  }

  // 3. Timeline
  console.log('\n3. Timeline:');
  const tl = await api('GET', `/api/v1/families/${familyId}/timeline`);
  check('GET timeline (events present)', ok(tl.status) && tl.data?.items?.length > 0, `status ${tl.status}, items: ${tl.data?.items?.length||0}`);
  if (tl.data?.items?.length > 0) {
    timelineEventId = tl.data.items[0].id;
    console.log(`    ${tl.data.items.length} events found`);
    const co = await api('POST', `/api/v1/families/${familyId}/timeline/${timelineEventId}/correct`, {
      correctedFields: { title: { from: 'old', to: 'new' } }, note: 'test',
    });
    check('POST correct timeline event', ok(co.status), `status ${co.status}`);
  }

  // 4. AI Insights
  console.log('\n4. AURA Intelligence (AI):');
  if (decisionId) {
    const ir = await api('POST', `/api/v1/families/${familyId}/decisions/${decisionId}/insights/request`, {
      kinds: ['decision_analysis', 'pros_cons'],
    });
    check('POST request insights', ok(ir.status), `status ${ir.status}: ${JSON.stringify(ir.data).slice(0,300)}`);
    if (ok(ir.status)) {
      console.log(`    cached: ${ir.data.cached?.length||0}, generated: ${ir.data.generated?.length||0}, degraded: ${ir.data.degradedMode}`);
      insightId = ir.data.generated?.[0]?.id || ir.data.cached?.[0]?.id;
    }
    if (insightId) {
      const ac = await api('POST', `/api/v1/insights/${insightId}/accept`, { familyId });
      check('POST accept insight', ok(ac.status), `status ${ac.status}`);
    }
  }

  // 5. Learning
  console.log('\n5. AURA Learning:');
  const lp = await api('GET', `/api/v1/families/${familyId}/learning/profile`);
  check('GET learning profile', ok(lp.status), `status ${lp.status}`);
  const sg = await api('POST', `/api/v1/families/${familyId}/learning/signals`, {
    signalType: 'insight_accepted', targetType: 'AIInsight', targetId: insightId || 'x', payload: { kind: 'test' },
  });
  check('POST learning signal', ok(sg.status), `status ${sg.status}`);

  // 6. Search
  console.log('\n6. AURA Search:');
  const ri = await api('POST', `/api/v1/families/${familyId}/search/reindex`);
  check('POST reindex', ok(ri.status), `status ${ri.status}`);
  if (ok(ri.status)) console.log(`    reindexed ${ri.data.reindexed || ri.data.data?.reindexed || '?'} entities`);

  const se = await api('GET', `/api/v1/families/${familyId}/search?q=test`);
  check('GET search', ok(se.status), `status ${se.status}`);
  const su = await api('GET', `/api/v1/families/${familyId}/search/suggest?q=te`);
  check('GET suggest', ok(su.status), `status ${su.status}`);

  // 7. Secretary
  console.log('\n7. AURA Secretary:');
  const ar = await api('POST', `/api/v1/families/${familyId}/secretary/artifacts`, {
    title: 'Test Meeting', heldAt: new Date().toISOString(), participants: [userId],
    agenda: ['A1'], discussionPoints: [], decisions: [],
  });
  check('POST create artifact', ok(ar.status), `status ${ar.status}`);
  artifactId = ar.data?.id || ar.data?.data?.id;
  const la = await api('GET', `/api/v1/families/${familyId}/secretary/artifacts`);
  check('GET list artifacts', ok(la.status), `status ${la.status}`);
  if (artifactId) {
    const pa = await api('POST', `/api/v1/families/${familyId}/secretary/artifacts/${artifactId}/publish`, {});
    check('POST publish artifact', ok(pa.status), `status ${pa.status}`);
  }

  // 8. Analytics
  console.log('\n8. AURA Analytics:');
  const tr = await api('POST', `/api/v1/families/${familyId}/analytics/trigger?granularity=weekly`);
  check('POST trigger snapshot', ok(tr.status), `status ${tr.status}`);
  const sm = await api('GET', `/api/v1/families/${familyId}/analytics/summary`);
  check('GET analytics summary', ok(sm.status), `status ${sm.status}`);

  // 9. Sync
  console.log('\n9. Sync:');
  const dl = await fetch(`${SERVER_URL}/api/v1/sync/delta`, {
    headers: { 'Authorization': `Bearer ${accessToken}`, 'X-Device-Id': 'verify-dev-1' },
  });
  check('GET delta', dl.status === 200, `status ${dl.status}`);
  const pu = await api('POST', `/api/v1/sync/push`, { operations: [] });
  check('POST push (empty)', ok(pu.status), `status ${pu.status}`);

  // 10. RLS
  console.log('\n10. RLS cross-family isolation:');
  const user2Id = `usr2_${Date.now()}`;
  const email2 = `trackc-final2-${Date.now()}@kinrel-test.com`;
  await pg.query('INSERT INTO "User" (id, email, name, "passwordHash", role, "preferredLanguage", "createdAt", "updatedAt") VALUES ($1,$2,$3,$4,$5,$6, NOW(), NOW())',
    [user2Id, email2, 'User2', passwordHash, 'user', 'en']);
  await pg.query('INSERT INTO "Family" (id, name, "createdBy", "primaryLanguage", "privacyMode", "memberCount", "lastActivityAt", "familyCode", "isOnboarded") VALUES ($1,$2,$3,$4,$5,1,NOW(),$6,true)',
    [`fam2_${Date.now()}`, 'Fam2', user2Id, 'en', 'private', `code2_${Date.now()}`]);
  const login2 = await fetch(`${SERVER_URL}/api/auth/login`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: email2, password: 'TestPassword123!' }),
  });
  const login2Data = await login2.json();
  const token2 = login2Data.data?.accessToken;
  if (token2) {
    const crossRes = await fetch(`${SERVER_URL}/api/v1/families/${familyId}/constitution`, {
      headers: { 'Authorization': `Bearer ${token2}` },
    });
    check('RLS: user2 blocked from family1', crossRes.status === 404, `expected 404, got ${crossRes.status}`);
  }

  // 11. Timeline append-only
  console.log('\n11. Timeline append-only:');
  if (timelineEventId) {
    try {
      await pg.query(`UPDATE "AURATimelineEvent" SET title = 'HACKED' WHERE id = $1`, [timelineEventId]);
      check('Timeline UPDATE blocked', false, 'UPDATE succeeded!');
    } catch (e) {
      check('Timeline UPDATE blocked', true);
    }
  } else {
    console.log('  ⚠️ Skipped (no timeline event to test)');
  }

  // Cleanup
  console.log('\nCleanup:');
  await pg.query('DELETE FROM "Family" WHERE "createdBy" IN ($1, $2)', [userId, user2Id]);
  await pg.query('DELETE FROM "User" WHERE id IN ($1, $2)', [userId, user2Id]);
  console.log('  ✅ Cleaned up');
  await pg.end();

  console.log('\n=== FINAL SUMMARY ===');
  console.log(`Passed: ${results.pass}`);
  console.log(`Failed: ${results.fail}`);
  console.log(`Total: ${results.pass + results.fail}`);
  console.log(`Success rate: ${((results.pass / (results.pass + results.fail)) * 100).toFixed(1)}%`);
  if (results.bugs.length > 0) {
    console.log('\nRemaining bugs:');
    results.bugs.forEach(b => console.log(`  - ${b}`));
  }
}

main().catch(e => { console.error('FATAL:', e.message); process.exit(1); });
