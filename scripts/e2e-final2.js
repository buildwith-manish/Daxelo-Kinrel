// Final comprehensive E2E test with correct response envelope handling
const SERVER_URL = 'https://daxelo-kinrel-server.onrender.com';
const { Client } = require('pg');
const bcrypt = require('bcryptjs');
const pg = new Client({ connectionString: 'postgresql://postgres.promxswvsnvilplmrtsj:tvAFZQp89nUulXeE@aws-1-ap-southeast-1.pooler.supabase.com:5432/postgres' });

let accessToken, userId, familyId;
let decisionId, timelineEventId, insightId, artifactId;
const results = { pass: 0, fail: 0, bugs: [] };

// Unwrap the {success, data} envelope
function unwrap(r) { return r.data?.data !== undefined ? r.data.data : r.data; }

async function api(method, path, body) {
  const headers = { 'Content-Type': 'application/json', 'Authorization': `Bearer ${accessToken}` };
  const opts = { method, headers };
  if (body !== undefined) opts.body = JSON.stringify(body);
  const res = await fetch(`${SERVER_URL}${path}`, opts);
  let data = null;
  try { data = await res.json(); } catch {}
  return { status: res.status, data: unwrap({ data }) };
}

function check(name, condition, detail = '') {
  if (condition) { console.log(`  ✅ ${name}`); results.pass++; }
  else { console.log(`  ❌ ${name} ${detail}`); results.fail++; results.bugs.push(name); }
}
const ok = (s) => s === 200 || s === 201;

async function main() {
  console.log('=== TRACK C v2.0 FINAL VERIFICATION ===\n');

  // Setup
  await pg.connect();
  const testEmail = `trackc-final2-${Date.now()}@t.com`;
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
  console.log(`0. Setup: ${accessToken ? '✅' : '❌'} auth\n`);

  // 1. Constitution
  console.log('1. Constitution:');
  const gc = await api('GET', `/api/v1/families/${familyId}/constitution`);
  check('GET constitution', ok(gc.status));
  const dc = await api('POST', `/api/v1/families/${familyId}/constitution/draft`, {
    title: 'Test', articles: [{ title: 'A1', clauses: [{ text: 'C1' }] }],
  });
  check('POST draft', ok(dc.status), JSON.stringify(dc.data).slice(0,150));
  const pc = await api('POST', `/api/v1/families/${familyId}/constitution/publish`, {});
  check('POST publish', ok(pc.status));
  const vc = await api('GET', `/api/v1/families/${familyId}/constitution/versions`);
  check('GET versions', ok(vc.status) && Array.isArray(vc.data) && vc.data.length > 0, `count: ${vc.data?.length}`);

  // 2. Decisions
  console.log('\n2. Decisions:');
  const cd = await api('POST', `/api/v1/families/${familyId}/decisions`, {
    title: 'Test', type: 'simple_vote', options: ['A','B'],
    quorumPct: 50, deadlineAt: new Date(Date.now()+86400000).toISOString(),
  });
  check('POST create', ok(cd.status));
  decisionId = cd.data?.id;
  if (decisionId) {
    const ld = await api('GET', `/api/v1/families/${familyId}/decisions?status=open`);
    check('GET list', ok(ld.status) && ld.data?.items?.length > 0);
    const vd = await api('POST', `/api/v1/families/${familyId}/decisions/${decisionId}/vote`, { option: 'A' });
    check('POST vote', ok(vd.status));
    const vd2 = await api('POST', `/api/v1/families/${familyId}/decisions/${decisionId}/vote`, { option: 'B' });
    check('Duplicate vote → 409', vd2.status === 409);
    const rd = await api('POST', `/api/v1/families/${familyId}/decisions/${decisionId}/resolve`, {});
    check('POST resolve', ok(rd.status));
    const lc = await api('PATCH', `/api/v1/families/${familyId}/decisions/${decisionId}/lifecycle`, { to: 'started' });
    check('PATCH lifecycle', ok(lc.status));
  }

  // 3. Timeline
  console.log('\n3. Timeline:');
  const tl = await api('GET', `/api/v1/families/${familyId}/timeline`);
  check('GET timeline (has events)', ok(tl.status) && tl.data?.items?.length > 0, `items: ${tl.data?.items?.length||0}`);
  if (tl.data?.items?.length > 0) {
    timelineEventId = tl.data.items[0].id;
    const co = await api('POST', `/api/v1/families/${familyId}/timeline/${timelineEventId}/correct`, {
      correctedFields: { title: { from: 'old', to: 'new' } }, note: 'test',
    });
    check('POST correct', ok(co.status));
  }

  // 4. AI Insights
  console.log('\n4. Kinrel Intelligence:');
  if (decisionId) {
    const ir = await api('POST', `/api/v1/families/${familyId}/decisions/${decisionId}/insights/request`, {
      kinds: ['decision_analysis', 'pros_cons'],
    });
    check('POST request insights', ok(ir.status), `status ${ir.status}`);
    if (ok(ir.status)) {
      console.log(`    cached: ${ir.data?.cached?.length||0}, generated: ${ir.data?.generated?.length||0}, degraded: ${ir.data?.degradedMode}`);
      insightId = ir.data?.generated?.[0]?.id || ir.data?.cached?.[0]?.id;
    }
    if (insightId) {
      const ac = await api('POST', `/api/v1/insights/${insightId}/accept`, { familyId });
      check('POST accept', ok(ac.status));
    }
  }

  // 5-9: Learning, Search, Secretary, Analytics, Sync
  console.log('\n5. Learning:');
  const lp = await api('GET', `/api/v1/families/${familyId}/learning/profile`);
  check('GET profile', ok(lp.status));
  const sg = await api('POST', `/api/v1/families/${familyId}/learning/signals`, {
    signalType: 'insight_accepted', targetType: 'AIInsight', targetId: insightId || 'x', payload: { kind: 'test' },
  });
  check('POST signal', ok(sg.status));

  console.log('\n6. Search:');
  const ri = await api('POST', `/api/v1/families/${familyId}/search/reindex`);
  check('POST reindex', ok(ri.status));
  const se = await api('GET', `/api/v1/families/${familyId}/search?q=test`);
  check('GET search', ok(se.status));
  const su = await api('GET', `/api/v1/families/${familyId}/search/suggest?q=te`);
  check('GET suggest', ok(su.status));

  console.log('\n7. Secretary:');
  const ar = await api('POST', `/api/v1/families/${familyId}/secretary/artifacts`, {
    title: 'Test', heldAt: new Date().toISOString(), participants: [userId],
    agenda: ['A1'], discussionPoints: [], decisions: [],
  });
  check('POST create artifact', ok(ar.status));
  artifactId = ar.data?.id;
  const la = await api('GET', `/api/v1/families/${familyId}/secretary/artifacts`);
  check('GET list artifacts', ok(la.status));
  if (artifactId) {
    const pa = await api('POST', `/api/v1/families/${familyId}/secretary/artifacts/${artifactId}/publish`, {});
    check('POST publish', ok(pa.status));
  }

  console.log('\n8. Analytics:');
  const tr = await api('POST', `/api/v1/families/${familyId}/analytics/trigger?granularity=weekly`);
  check('POST trigger', ok(tr.status));
  const sm = await api('GET', `/api/v1/families/${familyId}/analytics/summary`);
  check('GET summary', ok(sm.status));

  console.log('\n9. Sync:');
  const dl = await fetch(`${SERVER_URL}/api/v1/sync/delta`, {
    headers: { 'Authorization': `Bearer ${accessToken}`, 'X-Device-Id': 'dev1' },
  });
  check('GET delta', dl.status === 200);
  const pu = await api('POST', `/api/v1/sync/push`, { operations: [] });
  check('POST push', ok(pu.status));

  // 10. RLS
  console.log('\n10. RLS:');
  const user2Id = `usr2_${Date.now()}`;
  const email2 = `trackc-final2b-${Date.now()}@t.com`;
  await pg.query('INSERT INTO "User" (id, email, name, "passwordHash", role, "preferredLanguage", "createdAt", "updatedAt") VALUES ($1,$2,$3,$4,$5,$6, NOW(), NOW())',
    [user2Id, email2, 'U2', passwordHash, 'user', 'en']);
  await pg.query('INSERT INTO "Family" (id, name, "createdBy", "primaryLanguage", "privacyMode", "memberCount", "lastActivityAt", "familyCode", "isOnboarded") VALUES ($1,$2,$3,$4,$5,1,NOW(),$6,true)',
    [`fam2_${Date.now()}`, 'F2', user2Id, 'en', 'private', `c2_${Date.now()}`]);
  const l2 = await fetch(`${SERVER_URL}/api/auth/login`, {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:email2,password:'TestPassword123!'})});
  const l2d = await l2.json();
  const t2 = l2d.data?.accessToken;
  if (t2) {
    const cr = await fetch(`${SERVER_URL}/api/v1/families/${familyId}/constitution`, {headers:{'Authorization':'Bearer '+t2}});
    check('Cross-family blocked (404)', cr.status === 404, `got ${cr.status}`);
  }

  // 11. Append-only
  console.log('\n11. Timeline append-only:');
  if (timelineEventId) {
    try {
      await pg.query(`UPDATE "KinrelTimelineEvent" SET title = 'HACKED' WHERE id = $1`, [timelineEventId]);
      check('UPDATE blocked', false);
    } catch (e) { check('UPDATE blocked', true); }
  }

  // Cleanup
  await pg.query('DELETE FROM "Family" WHERE "createdBy" IN ($1, $2)', [userId, user2Id]);
  await pg.query('DELETE FROM "User" WHERE id IN ($1, $2)', [userId, user2Id]);
  await pg.end();

  console.log('\n=== FINAL RESULTS ===');
  console.log(`Passed: ${results.pass}/${results.pass + results.fail}`);
  console.log(`Success rate: ${((results.pass / (results.pass + results.fail)) * 100).toFixed(1)}%`);
  if (results.bugs.length) { console.log('Bugs:'); results.bugs.forEach(b => console.log(`  - ${b}`)); }
}
main().catch(e => console.error('FATAL:', e.message));
