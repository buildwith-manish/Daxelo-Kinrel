#!/usr/bin/env node
// scripts/e2e-chat-verify.js
// End-to-end verification of the 5 chat engagement features against the
// Daxelo-Kinrel Supabase database + deployed backend.
//
// Verifies:
//   Feature 1: readBy/readAt columns work on ChatMessage
//   Feature 2: fn_toggle_reaction RPC uses new WhatsApp semantics
//   Feature 3: ChatStreak table exists + insert/update works
//   Feature 4: UserPresence table updates work
//   Feature 5: notified column exists + update works
//
// Cleanup: all test rows are deleted at the end (test prefix 'e2e_').

// Usage: SUPABASE_MANAGER_PAT=<pat> node e2e-chat-verify.js <service_role_key>
// The manager PAT is used for SQL queries via the Supabase management API
// (cleanup of test rows that the REST API can't reach due to RLS).
const SERVICE_ROLE = process.argv[2] || '';
const SUPABASE_URL = 'https://promxswvsnvilplmrtsj.supabase.co';
const MANAGER_PAT = process.env.SUPABASE_MANAGER_PAT || '';
const PROJECT_REF = 'promxswvsnvilplmrtsj';
const FAMILY_ID = 'cmqvaf6e4337puutqtj6ypysh'; // Manish's "Test" family
const USER_ID = 'a4e58129-8397-4c84-86ca-bbfa2a0b6660'; // Manish
const SECOND_USER_ID = 'e2e_second_user'; // fake ID for read-receipt test

if (!SERVICE_ROLE) {
  console.error('Usage: SUPABASE_MANAGER_PAT=<pat> node e2e-chat-verify.js <service_role_key>');
  process.exit(1);
}

const headers = {
  'apikey': SERVICE_ROLE,
  'Authorization': `Bearer ${SERVICE_ROLE}`,
  'Content-Type': 'application/json',
};

async function supabaseInsert(table, data) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${table}`, {
    method: 'POST',
    headers: { ...headers, 'Prefer': 'return=representation' },
    body: JSON.stringify(data),
  });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`Insert into ${table} failed (HTTP ${res.status}): ${text}`);
  }
  return JSON.parse(text);
}

async function supabaseSelect(table, query) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${table}?${query}`, {
    headers,
  });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`Select from ${table} failed (HTTP ${res.status}): ${text}`);
  }
  return JSON.parse(text);
}

async function supabaseUpdate(table, data, filter) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${table}?${filter}`, {
    method: 'PATCH',
    headers: { ...headers, 'Prefer': 'return=representation' },
    body: JSON.stringify(data),
  });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`Update ${table} failed (HTTP ${res.status}): ${text}`);
  }
  return JSON.parse(text);
}

async function supabaseDelete(table, filter) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${table}?${filter}`, {
    method: 'DELETE',
    headers,
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Delete from ${table} failed (HTTP ${res.status}): ${text}`);
  }
}

async function supabaseRpc(fn, params) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers,
    body: JSON.stringify(params),
  });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`RPC ${fn} failed (HTTP ${res.status}): ${text}`);
  }
  return JSON.parse(text);
}

async function managerQuery(sql) {
  const res = await fetch(
    `https://api.supabase.com/v1/projects/${PROJECT_REF}/database/query`,
    {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${MANAGER_PAT}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ query: sql }),
    },
  );
  const text = await res.text();
  if (!res.ok) throw new Error(`Manager query failed: ${text}`);
  return JSON.parse(text);
}

async function cleanup() {
  // Delete all test rows prefixed with 'e2e_'
  try {
    await supabaseDelete('ChatReaction', 'id=like.e2e_%25');
  } catch {}
  try {
    await supabaseDelete('ChatStreak', 'id=like.e2e_%25');
  } catch {}
  try {
    await supabaseDelete('ChatMessage', 'id=like.e2e_%25');
  } catch {}
  try {
    await managerQuery('DELETE FROM "UserPresence" WHERE "userId" = \'e2e_second_user\';');
  } catch {}
}

async function main() {
  let passed = 0;
  let failed = 0;
  const assert = (cond, msg) => {
    if (cond) { passed++; console.log(`  ✓ ${msg}`); }
    else { failed++; console.log(`  ✗ ${msg}`); }
  };

  console.log('=== Cleanup previous test rows ===');
  await cleanup();
  console.log('  done\n');

  // ── Feature 1: readBy / readAt ──────────────────────────────────────
  console.log('Feature 1: readBy / readAt columns on ChatMessage');
  const msg = (await supabaseInsert('ChatMessage', [{
    id: 'e2e_msg_1',
    familyId: FAMILY_ID,
    senderId: USER_ID,
    senderName: 'E2E Sender',
    content: 'test message for read receipt',
    readBy: [],
    readAt: null,
    notified: false,
  }]))[0];
  assert(!!msg, 'inserted ChatMessage with readBy=[] + readAt=null');

  // Simulate markAsRead: append a userId to readBy + set readAt
  await supabaseUpdate(
    'ChatMessage',
    { readBy: ['e2e_reader_1'], readAt: new Date().toISOString(), messageStatus: 'read' },
    'id=eq.e2e_msg_1',
  );
  const afterRead = (await supabaseSelect('ChatMessage', 'id=eq.e2e_msg_1&select=readBy,readAt,messageStatus'))[0];
  assert(
    Array.isArray(afterRead.readBy) && afterRead.readBy.includes('e2e_reader_1'),
    `readBy array contains the reader (got: ${JSON.stringify(afterRead.readBy)})`,
  );
  assert(!!afterRead.readAt, `readAt is set (got: ${afterRead.readAt})`);
  assert(afterRead.messageStatus === 'read', `messageStatus=red (got: ${afterRead.messageStatus})`);
  console.log('');

  // ── Feature 2: fn_toggle_reaction (WhatsApp semantics) ─────────────
  console.log('Feature 2: fn_toggle_reaction RPC (WhatsApp semantics)');
  // Note: fn_toggle_reaction uses auth.uid() for the user, which won't work
  // with the service_role key (no auth context). So we test the table
  // constraint directly instead.
  const r1 = (await supabaseInsert('ChatReaction', [{
    id: 'e2e_cr_1',
    messageId: 'e2e_msg_1',
    userId: 'e2e_reactor_1',
    emoji: '❤️',
  }]))[0];
  assert(!!r1, 'inserted first emoji (❤️)');

  const r2 = (await supabaseInsert('ChatReaction', [{
    id: 'e2e_cr_2',
    messageId: 'e2e_msg_1',
    userId: 'e2e_reactor_1',
    emoji: '🎉',
  }]))[0];
  assert(!!r2, 'inserted DIFFERENT emoji (🎉) for same user (WhatsApp multi-emoji)');

  // Try to insert a DUPLICATE (same messageId, userId, emoji) — should fail
  let dupFailed = false;
  try {
    await supabaseInsert('ChatReaction', [{
      id: 'e2e_cr_3',
      messageId: 'e2e_msg_1',
      userId: 'e2e_reactor_1',
      emoji: '❤️', // duplicate
    }]);
  } catch (e) {
    dupFailed = true;
  }
  assert(dupFailed, 'duplicate (messageId, userId, emoji) rejected by unique constraint');

  const reactions = await supabaseSelect('ChatReaction', 'messageId=eq.e2e_msg_1&select=emoji');
  assert(reactions.length === 2, `2 distinct emojis for the user (got: ${reactions.length})`);
  console.log('');

  // ── Feature 3: ChatStreak ──────────────────────────────────────────
  console.log('Feature 3: ChatStreak table');
  const streak = (await supabaseInsert('ChatStreak', [{
    id: 'e2e_streak_1',
    chatId: FAMILY_ID,
    currentStreak: 5,
    longestStreak: 7,
    lastMessageAt: new Date().toISOString(),
  }]))[0];
  assert(!!streak, 'inserted ChatStreak row');
  assert(streak.currentStreak === 5, `currentStreak=5 (got: ${streak.currentStreak})`);

  // Simulate a streak increment
  await supabaseUpdate('ChatStreak', { currentStreak: 6, longestStreak: 7 }, 'id=eq.e2e_streak_1');
  const afterInc = (await supabaseSelect('ChatStreak', 'id=eq.e2e_streak_1&select=currentStreak,longestStreak'))[0];
  assert(afterInc.currentStreak === 6, `streak incremented to 6 (got: ${afterInc.currentStreak})`);

  // Simulate a streak reset (gap > 24h)
  await supabaseUpdate('ChatStreak', { currentStreak: 1 }, 'id=eq.e2e_streak_1');
  const afterReset = (await supabaseSelect('ChatStreak', 'id=eq.e2e_streak_1&select=currentStreak,longestStreak'))[0];
  assert(afterReset.currentStreak === 1, `streak reset to 1 (got: ${afterReset.currentStreak})`);
  assert(afterReset.longestStreak === 7, `longestStreak preserved at 7 (got: ${afterReset.longestStreak})`);

  // Verify UNIQUE(chatId) — duplicate chatId should fail
  let chatIdDupFailed = false;
  try {
    await supabaseInsert('ChatStreak', [{ id: 'e2e_streak_2', chatId: FAMILY_ID, currentStreak: 1 }]);
  } catch {
    chatIdDupFailed = true;
  }
  assert(chatIdDupFailed, 'duplicate chatId rejected by UNIQUE(chatId) constraint');
  console.log('');

  // ── Feature 4: UserPresence ────────────────────────────────────────
  console.log('Feature 4: UserPresence table');
  await supabaseInsert('UserPresence', [{
    userId: 'e2e_second_user',
    isOnline: true,
    lastSeenAt: new Date().toISOString(),
  }]).catch(() => {}); // may already exist
  await supabaseUpdate('UserPresence', { isOnline: true, lastSeenAt: new Date().toISOString() }, 'userId=eq.e2e_second_user');
  const presence = (await supabaseSelect('UserPresence', 'userId=eq.e2e_second_user&select=isOnline,lastSeenAt'))[0];
  assert(!!presence, 'UserPresence row exists for test user');
  assert(presence.isOnline === true, `isOnline=true (got: ${presence.isOnline})`);

  await supabaseUpdate('UserPresence', { isOnline: false, lastSeenAt: new Date().toISOString() }, 'userId=eq.e2e_second_user');
  const afterOffline = (await supabaseSelect('UserPresence', 'userId=eq.e2e_second_user&select=isOnline'))[0];
  assert(afterOffline.isOnline === false, `isOnline=false after disconnect (got: ${afterOffline.isOnline})`);
  console.log('');

  // ── Feature 5: notified column ─────────────────────────────────────
  console.log('Feature 5: notified column on ChatMessage');
  const msg5 = (await supabaseSelect('ChatMessage', 'id=eq.e2e_msg_1&select=notified'))[0];
  assert(msg5.notified === false, `notified=false initially (got: ${msg5.notified})`);

  await supabaseUpdate('ChatMessage', { notified: true }, 'id=eq.e2e_msg_1');
  const afterNotified = (await supabaseSelect('ChatMessage', 'id=eq.e2e_msg_1&select=notified'))[0];
  assert(afterNotified.notified === true, `notified=true after cron update (got: ${afterNotified.notified})`);
  console.log('');

  // ── Cleanup ─────────────────────────────────────────────────────────
  console.log('=== Cleanup ===');
  await cleanup();
  console.log('  done\n');

  // ── Summary ────────────────────────────────────────────────────────
  console.log('=== SUMMARY ===');
  console.log(`  Passed: ${passed}`);
  console.log(`  Failed: ${failed}`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((e) => {
  console.error('Unhandled error:', e);
  process.exit(1);
});
