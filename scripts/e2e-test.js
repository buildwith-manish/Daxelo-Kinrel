// E2E test using the server's own /api/auth/register + /api/auth/login flow
const SERVER_URL = 'https://daxelo-kinrel-server.onrender.com';
const SUPABASE_URL = 'https://promxswvsnvilplmrtsj.supabase.co';
const SUPABASE_SERVICE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InByb214c3d2c252aWxwbG1ydHNqIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3OTU5NzE4MCwiZXhwIjoyMDk1MTczMTgwfQ.sgaciYwaTVd3FoGqZEe_cQamSXiAXA9SYdLjf2ICcCE';
const { createClient } = require('@supabase/supabase-js');
const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

let accessToken = null;
let userId = null;
let familyId = null;
let decisionId = null;
let timelineEventId = null;
let insightId = null;
let artifactId = null;
const results = { pass: 0, fail: 0, warnings: [] };

async function apiCall(method, path, body) {
  const headers = { 'Content-Type': 'application/json' };
  if (accessToken) headers['Authorization'] = `Bearer ${accessToken}`;
  const opts = { method, headers };
  if (body !== undefined) opts.body = JSON.stringify(body);
  const res = await fetch(`${SERVER_URL}${path}`, opts);
  let data = null;
  try { data = await res.json(); } catch {}
  return { status: res.status, data };
}

function check(name, condition, detail = '') {
  if (condition) {
    console.log(`  ✅ ${name}`);
    results.pass++;
  } else {
    console.log(`  ❌ ${name} ${detail}`);
    results.fail++;
  }
}

async function main() {
  console.log('=== END-TO-END API TEST (NestJS Auth) ===\n');

  // ── 1. Register via server's auth ────────────────────────────────────
  console.log('1. Authentication (server /api/auth/register):');
  const testEmail = `trackc-e2e-${Date.now()}@kinrel-test.com`;
  const testPassword = 'TestPassword123!';
  
  const regRes = await apiCall('POST', '/api/auth/register', {
    name: 'Track C Tester',
    email: testEmail,
    password: testPassword,
  });
  console.log(`  Register status: ${regRes.status}`);
  
  if (regRes.status !== 200 && regRes.status !== 201) {
    console.log(`  Register response: ${JSON.stringify(regRes.data).slice(0, 200)}`);
    // Try login if user already exists
  }

  // Login
  const loginRes = await apiCall('POST', '/api/auth/login', {
    email: testEmail,
    password: testPassword,
  });
  console.log(`  Login status: ${loginRes.status}`);
  
  if (loginRes.status === 200 || loginRes.status === 201) {
    accessToken = loginRes.data.accessToken || loginRes.data.access_token || loginRes.data.token;
    userId = loginRes.data.user?.id || loginRes.data.id;
    check('Login + get NestJS JWT', accessToken && accessToken.length > 20, `token: ${accessToken?.slice(0, 20)}...`);
  } else {
    check('Login + get NestJS JWT', false, `status ${loginRes.status}: ${JSON.stringify(loginRes.data).slice(0, 200)}`);
    console.log('\n=== CANNOT CONTINUE WITHOUT AUTH ===');
    printSummary();
    return;
  }
  console.log(`  User ID: ${userId}`);
  console.log(`  Token: ${accessToken.slice(0, 30)}...`);

  // ── 2. Create family via Supabase admin (bypassing RLS) ──────────────
  console.log('\n2. Family setup:');
  familyId = `fam_test_${Date.now()}`;
  const { error: famErr } = await supabaseAdmin.from('Family').insert({ 
    id: familyId, 
    name: 'Track C Test Family', 
    createdBy: userId 
  });
  check('Create family', !famErr, famErr?.message);

  // Add user as family member
  const { error: memErr } = await supabaseAdmin.from('FamilyMember').insert({ 
    id: `mem_${Date.now()}`,
    familyId, 
    userId, 
    role: 'admin' 
  });
  check('Add user as family admin', !memErr, memErr?.message);

  // ── 3. Constitution ──────────────────────────────────────────────────
  console.log('\n3. Constitution:');
  const getConst = await apiCall('GET', `/api/v1/families/${familyId}/constitution`);
  check('GET constitution (auto-creates shell)', getConst.status === 200, `status ${getConst.status}: ${JSON.stringify(getConst.data).slice(0, 100)}`);

  const draftRes = await apiCall('POST', `/api/v1/families/${familyId}/constitution/draft`, {
    title: 'Test Family Constitution',
    preamble: 'We, the test family, establish these rules.',
    articles: [{
      title: 'Annual Gathering',
      intent: 'Ensure annual reunion',
      clauses: [
        { text: 'The family shall gather annually.' },
        { text: 'The gathering shall rotate between branches.' },
      ],
    }],
  });
  check('POST draft constitution', draftRes.status === 200 || draftRes.status === 201, `status ${draftRes.status}: ${JSON.stringify(draftRes.data).slice(0, 200)}`);

  const pubRes = await apiCall('POST', `/api/v1/families/${familyId}/constitution/publish`, { changeSummary: 'Initial' });
  check('POST publish constitution', pubRes.status === 200 || pubRes.status === 201, `status ${pubRes.status}: ${JSON.stringify(pubRes.data).slice(0, 200)}`);

  const verRes = await apiCall('GET', `/api/v1/families/${familyId}/constitution/versions`);
  check('GET versions', verRes.status === 200 && verRes.data?.length > 0, `status ${verRes.status}`);

  // ── 4. Decisions ─────────────────────────────────────────────────────
  console.log('\n4. Decisions:');
  const createDec = await apiCall('POST', `/api/v1/families/${familyId}/decisions`, {
    title: 'Summer Vacation Destination',
    description: 'Choose between Goa, Kerala, and Himachal',
    type: 'simple_vote',
    options: ['Goa', 'Kerala', 'Himachal'],
    quorumPct: 50,
    deadlineAt: new Date(Date.now() + 7 * 86400000).toISOString(),
  });
  check('POST create decision', createDec.status === 200 || createDec.status === 201, `status ${createDec.status}: ${JSON.stringify(createDec.data).slice(0, 200)}`);
  decisionId = createDec.data?.id;

  if (decisionId) {
    const listDec = await apiCall('GET', `/api/v1/families/${familyId}/decisions?status=open`);
    check('GET list decisions', listDec.status === 200 && listDec.data?.items?.length > 0, `status ${listDec.status}`);

    const getDec = await apiCall('GET', `/api/v1/families/${familyId}/decisions/${decisionId}`);
    check('GET decision detail', getDec.status === 200, `status ${getDec.status}`);

    const voteRes = await apiCall('POST', `/api/v1/families/${familyId}/decisions/${decisionId}/vote`, { option: 'Goa' });
    check('POST vote', voteRes.status === 200 || voteRes.status === 201, `status ${voteRes.status}: ${JSON.stringify(voteRes.data).slice(0, 200)}`);

    const voteAgain = await apiCall('POST', `/api/v1/families/${familyId}/decisions/${decisionId}/vote`, { option: 'Kerala' });
    check('POST duplicate vote → 409', voteAgain.status === 409, `expected 409, got ${voteAgain.status}`);

    const resolveRes = await apiCall('POST', `/api/v1/families/${familyId}/decisions/${decisionId}/resolve`, { resolutionNote: 'Resolved' });
    check('POST resolve decision', resolveRes.status === 200, `status ${resolveRes.status}: ${JSON.stringify(resolveRes.data).slice(0, 200)}`);

    const lcRes = await apiCall('PATCH', `/api/v1/families/${familyId}/decisions/${decisionId}/lifecycle`, { to: 'started' });
    check('PATCH lifecycle planned→started', lcRes.status === 200, `status ${lcRes.status}: ${JSON.stringify(lcRes.data).slice(0, 200)}`);
  }

  // ── 5. Timeline ──────────────────────────────────────────────────────
  console.log('\n5. Timeline:');
  const tlRes = await apiCall('GET', `/api/v1/families/${familyId}/timeline`);
  check('GET timeline', tlRes.status === 200 && tlRes.data?.items?.length > 0, `status ${tlRes.status}, items: ${tlRes.data?.items?.length || 0}`);
  if (tlRes.data?.items?.length > 0) {
    timelineEventId = tlRes.data.items[0].id;
    console.log(`    Found ${tlRes.data.items.length} timeline events`);

    const corrRes = await apiCall('POST', `/api/v1/families/${familyId}/timeline/${timelineEventId}/correct`, {
      correctedFields: { title: { from: 'old', to: 'corrected' } },
      note: 'Test correction',
    });
    check('POST correct timeline event', corrRes.status === 200 || corrRes.status === 201, `status ${corrRes.status}: ${JSON.stringify(corrRes.data).slice(0, 200)}`);

    const expRes = await apiCall('GET', `/api/v1/families/${familyId}/timeline/export?format=json`);
    check('GET timeline export (JSON)', expRes.status === 200, `status ${expRes.status}`);
  }

  // ── 6. AI Insights ───────────────────────────────────────────────────
  console.log('\n6. AURA Intelligence (AI Insights):');
  if (decisionId) {
    const insRes = await apiCall('POST', `/api/v1/families/${familyId}/decisions/${decisionId}/insights/request`, {
      kinds: ['decision_analysis', 'pros_cons'],
    });
    check('POST request insights', insRes.status === 200, `status ${insRes.status}: ${JSON.stringify(insRes.data).slice(0, 300)}`);
    if (insRes.status === 200) {
      console.log(`    cached: ${insRes.data.cached?.length || 0}, generated: ${insRes.data.generated?.length || 0}, degraded: ${insRes.data.degradedMode}`);
      insightId = insRes.data.generated?.[0]?.id || insRes.data.cached?.[0]?.id;
    }

    if (insightId) {
      const accRes = await apiCall('POST', `/api/v1/insights/${insightId}/accept`, { familyId });
      check('POST accept insight', accRes.status === 200, `status ${accRes.status}: ${JSON.stringify(accRes.data).slice(0, 200)}`);
    }
  }

  // ── 7. Learning ──────────────────────────────────────────────────────
  console.log('\n7. AURA Learning:');
  const lpRes = await apiCall('GET', `/api/v1/families/${familyId}/learning/profile`);
  check('GET learning profile', lpRes.status === 200, `status ${lpRes.status}: ${JSON.stringify(lpRes.data).slice(0, 200)}`);
  if (lpRes.status === 200) {
    console.log(`    confidence: ${lpRes.data.confidenceScore}, sampleSize: ${lpRes.data.sampleSize}, usingDefaults: ${lpRes.data.usingDefaults}`);
  }

  const sigRes = await apiCall('POST', `/api/v1/families/${familyId}/learning/signals`, {
    signalType: 'insight_accepted',
    targetType: 'AIInsight',
    targetId: insightId || 'test',
    payload: { kind: 'decision_analysis' },
  });
  check('POST learning signal', sigRes.status === 200 || sigRes.status === 201, `status ${sigRes.status}: ${JSON.stringify(sigRes.data).slice(0, 200)}`);

  // ── 8. Search ────────────────────────────────────────────────────────
  console.log('\n8. AURA Search:');
  const reindexRes = await apiCall('POST', `/api/v1/families/${familyId}/search/reindex`);
  check('POST reindex', reindexRes.status === 200, `status ${reindexRes.status}: ${JSON.stringify(reindexRes.data).slice(0, 200)}`);
  if (reindexRes.status === 200) console.log(`    reindexed ${reindexRes.data.reindexed} entities`);

  const searchRes = await apiCall('GET', `/api/v1/families/${familyId}/search?q=vacation`);
  check('GET search (q=vacation)', searchRes.status === 200, `status ${searchRes.status}: ${JSON.stringify(searchRes.data).slice(0, 200)}`);
  if (searchRes.status === 200) console.log(`    found ${searchRes.data.count} results`);

  const sugRes = await apiCall('GET', `/api/v1/families/${familyId}/search/suggest?q=dec`);
  check('GET suggest', sugRes.status === 200, `status ${sugRes.status}`);

  // ── 9. Secretary ─────────────────────────────────────────────────────
  console.log('\n9. AURA Secretary:');
  const artRes = await apiCall('POST', `/api/v1/families/${familyId}/secretary/artifacts`, {
    title: 'Family Meeting — Test',
    heldAt: new Date().toISOString(),
    participants: [userId],
    agenda: ['Discuss vacation'],
    discussionPoints: [{ point: 'Vacation', perspectives: [{ userId, perspective: 'Goa' }] }],
    decisions: [{ text: 'Goa selected', decided: true }],
  });
  check('POST create artifact', artRes.status === 200 || artRes.status === 201, `status ${artRes.status}: ${JSON.stringify(artRes.data).slice(0, 200)}`);
  artifactId = artRes.data?.id;

  const listArt = await apiCall('GET', `/api/v1/families/${familyId}/secretary/artifacts`);
  check('GET list artifacts', listArt.status === 200, `status ${listArt.status}`);

  if (artifactId) {
    const pubArt = await apiCall('POST', `/api/v1/families/${familyId}/secretary/artifacts/${artifactId}/publish`, {});
    check('POST publish artifact', pubArt.status === 200, `status ${pubArt.status}: ${JSON.stringify(pubArt.data).slice(0, 200)}`);
  }

  // ── 10. Analytics ────────────────────────────────────────────────────
  console.log('\n10. AURA Analytics:');
  const trigRes = await apiCall('POST', `/api/v1/families/${familyId}/analytics/trigger?granularity=weekly`);
  check('POST trigger snapshot', trigRes.status === 200, `status ${trigRes.status}: ${JSON.stringify(trigRes.data).slice(0, 200)}`);

  const sumRes = await apiCall('GET', `/api/v1/families/${familyId}/analytics/summary`);
  check('GET analytics summary', sumRes.status === 200, `status ${sumRes.status}: ${JSON.stringify(sumRes.data).slice(0, 200)}`);
  if (sumRes.status === 200 && sumRes.data.current?.metrics) {
    console.log(`    decisionsCreated: ${sumRes.data.current.metrics.decisionsCreated}, anomalies: ${sumRes.data.current.anomalies?.length || 0}`);
  }

  // ── 11. Sync ─────────────────────────────────────────────────────────
  console.log('\n11. Sync:');
  const deltaRes = await fetch(`${SERVER_URL}/api/v1/sync/delta`, {
    headers: { 'Authorization': `Bearer ${accessToken}`, 'X-Device-Id': 'test-device-1' },
  });
  const deltaData = await deltaRes.json();
  check('GET delta (with X-Device-Id)', deltaRes.status === 200, `status ${deltaRes.status}: ${JSON.stringify(deltaData).slice(0, 200)}`);
  if (deltaRes.status === 200) console.log(`    watermark: ${deltaData.watermark}, change keys: ${Object.keys(deltaData.changes || {}).length}`);

  const pushRes = await apiCall('POST', `/api/v1/sync/push`, { operations: [] });
  check('POST push (empty)', pushRes.status === 200, `status ${pushRes.status}`);

  // ── Cleanup ──────────────────────────────────────────────────────────
  console.log('\n12. Cleanup:');
  await supabaseAdmin.from('Family').delete().eq('id', familyId);
  console.log('  ✅ Test family deleted');

  printSummary();
}

function printSummary() {
  console.log('\n=== SUMMARY ===');
  console.log(`Passed: ${results.pass}`);
  console.log(`Failed: ${results.fail}`);
  console.log(`Total: ${results.pass + results.fail}`);
  console.log(`Success rate: ${((results.pass / (results.pass + results.fail)) * 100).toFixed(1)}%`);
}

main().catch(e => { console.error('\nFATAL:', e.message); process.exit(1); });
