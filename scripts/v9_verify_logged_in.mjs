// scripts/v9_verify_logged_in.mjs
//
// v9.0 — Authenticated Family Map verification.
//
// Logs into https://daxelo-kinrel.vercel.app/sign-in using test credentials
// (read from env vars TEST_EMAIL + TEST_PASS — NEVER committed), navigates
// to the Family Map screen, and captures:
//
//   - 3 screenshots at city-wide / street-level / building-level zoom
//   - the "N members located" counter
//   - Console + Network + Service Worker evidence from the authenticated session
//
// Usage:
//   TEST_EMAIL='...' TEST_PASS='...' node scripts/v9_verify_logged_in.mjs
//
// Required: puppeteer (already in /home/z/my-project/node_modules)

import puppeteer from 'puppeteer';
import { mkdirSync, writeFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const OUT_DIR = join(__dirname, '..', 'download', 'v9-verification');
mkdirSync(OUT_DIR, { recursive: true });

const LIVE_URL = 'https://daxelo-kinrel.vercel.app';
const SIGN_IN_URL = `${LIVE_URL}/sign-in`;

const TEST_EMAIL = process.env.TEST_EMAIL;
const TEST_PASS = process.env.TEST_PASS;

if (!TEST_EMAIL || !TEST_PASS) {
  console.error('ERROR: TEST_EMAIL and TEST_PASS environment variables must be set.');
  console.error('Do NOT pass credentials on the command line (they would appear in shell history).');
  console.error('Use: TEST_EMAIL=... TEST_PASS=... node scripts/v9_verify_logged_in.mjs');
  process.exit(2);
}

const sleep = (ms) => new Promise(r => setTimeout(r, ms));

// Sanitize logs to strip any credential traces
function sanitize(text) {
  if (typeof text !== 'string') return text;
  return text
    .replace(new RegExp(TEST_EMAIL.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'g'), '<redacted-email>')
    .replace(new RegExp(TEST_PASS.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'g'), '<redacted-pass>');
}

async function login(page) {
  console.log(`\n=== Step 1: Sign in to ${SIGN_IN_URL} ===`);
  await page.goto(SIGN_IN_URL, { waitUntil: 'networkidle2', timeout: 60000 });
  await sleep(2000);  // Let the form settle

  // Flutter web renders TextFormField as <input type="text"> and <input type="password">
  // We target by the placeholder/decoration — but Flutter web doesn't expose hintText as
  // a native placeholder attribute. Instead, the input fields appear in DOM order:
  //   1st <input> = identifier (email/username)
  //   2nd <input> = password
  // We use :visible filter and fall back to the multi-input selector.
  const inputs = await page.$$('input:visible');
  console.log(`  Found ${inputs.length} visible input(s) on sign-in page`);
  if (inputs.length < 2) {
    throw new Error(`Expected at least 2 inputs on sign-in page, got ${inputs.length}`);
  }

  // Type into identifier field
  await inputs[0].click({ clickCount: 3 });  // select all
  await inputs[0].type(TEST_EMAIL, { delay: 25 });
  await sleep(300);

  // Type into password field
  await inputs[1].click({ clickCount: 3 });
  await inputs[1].type(TEST_PASS, { delay: 25 });
  await sleep(300);

  // Find the submit button — Flutter web renders elevated buttons as <flt-glass-pane>
  // wrapping <semantics-button>. Easiest: press Enter on the password field, OR
  // dispatch a click on the role=button element with text "Sign in".
  const submitHandled = await page.evaluate(() => {
    // Try Enter key first (Flutter TextFormField.onFieldSubmitted fires _signIn)
    return true;  // We'll trigger via keyboard below
  });
  await page.keyboard.press('Enter');
  console.log('  Submitted sign-in form (Enter key)');

  // Wait for redirect away from /sign-in (Flutter router redirect to /home or /2fa-verify)
  try {
    await page.waitForFunction(
      (signInUrl) => !window.location.href.startsWith(signInUrl),
      { timeout: 30000 },
      SIGN_IN_URL
    );
  } catch (e) {
    // Maybe 2FA — check the URL
    const url = page.url();
    if (url.includes('/2fa-verify')) {
      throw new Error('Login requires 2FA — this script does not handle 2FA verification. Use a non-2FA test account.');
    }
    throw new Error(`Login did not redirect from /sign-in within 30s. Current URL: ${url}`);
  }
  console.log(`  Post-login URL: ${page.url()}`);
  await sleep(3000);  // Let post-login redirect + initial data load settle
}

async function findAndNavigateToMap(page) {
  console.log('\n=== Step 2: Navigate to Family Map screen ===');

  // Strategy 1: Look at the home screen for a "Map" / "Family Map" button.
  // Strategy 2: If we know the familyId, navigate directly to /family/:id/map.
  //
  // We don't know the familyId a priori, so we'll first capture the home screen
  // state, then look for any link/button whose text matches /map/i.
  //
  // If that fails, we'll fall back to scraping the familyId from any
  // /family/<id>/... link present on the home screen.

  await page.waitForFunction(
    () => document.body && document.body.innerText.length > 100,
    { timeout: 15000 }
  ).catch(() => {});

  const homeText = await page.evaluate(() => document.body.innerText.substring(0, 1500));
  console.log(`  Home screen text preview (first 300 chars):\n    ${homeText.substring(0, 300).replace(/\n/g, '\n    ')}`);

  // Find any /family/<id>/ link in the DOM
  const familyLinks = await page.evaluate(() => {
    const links = [];
    // Flutter web renders semantics links as <a> tags inside <flt-semantics>
    document.querySelectorAll('a[href*="/family/"]').forEach(a => {
      links.push({ href: a.href, text: a.innerText.trim() });
    });
    return links;
  });
  console.log(`  Found ${familyLinks.length} family links on home screen`);
  familyLinks.slice(0, 5).forEach(l => console.log(`    ${l.href} — "${l.text}"`));

  // Try to find a family ID — look in any /family/<id>/ URL
  let familyId = null;
  for (const link of familyLinks) {
    const m = link.href.match(/\/family\/([^/?#]+)/);
    if (m && m[1] !== 'join-family' && m[1] !== 'qr') {
      familyId = m[1];
      break;
    }
  }

  if (!familyId) {
    // Fallback: probe a few well-known places — call the Supabase families endpoint
    // via the page's existing auth context (cookies/tokens already loaded)
    familyId = await page.evaluate(async () => {
      try {
        // Flutter web stores auth tokens in IndexedDB under supabase.auth.token
        // We can't easily get them from raw JS, but we can ask the running
        // Flutter app's global provider container.
        // Easier: try fetching the Supabase REST endpoint directly using the
        // page's fetch() (same-origin cookies apply).
        return null;  // Give up gracefully — fall through to UI navigation
      } catch (e) {
        return null;
      }
    });
  }

  if (familyId) {
    const mapUrl = `${LIVE_URL}/family/${familyId}/map`;
    console.log(`  Navigating directly to: ${mapUrl}`);
    await page.goto(mapUrl, { waitUntil: 'networkidle2', timeout: 60000 });
  } else {
    console.log('  No family ID found in home screen links. Attempting UI navigation...');
    // Look for any element with text matching "map" or "family map"
    const clicked = await page.evaluate(() => {
      const candidates = [];
      document.querySelectorAll('flt-semantics, [role="button"], button, a').forEach(el => {
        const t = (el.innerText || el.textContent || '').trim().toLowerCase();
        if (t === 'map' || t === 'family map' || t.includes('view map') || t.includes('open map')) {
          candidates.push({ tag: el.tagName, text: t });
          el.click();
        }
      });
      return candidates;
    });
    console.log(`  Clicked ${clicked.length} map-related element(s)`);
    await sleep(3000);
  }

  // Wait for the map canvas to appear — Flutter web renders MapLibre inside a <canvas>
  console.log('  Waiting for map canvas to appear...');
  let canvasFound = false;
  for (let i = 0; i < 30; i++) {  // up to 30s
    const canvases = await page.$$('canvas');
    if (canvases.length > 0) {
      canvasFound = true;
      break;
    }
    await sleep(1000);
  }
  console.log(`  Canvas found: ${canvasFound}`);
  await sleep(8000);  // Allow style + tiles to load
}

async function captureZoomLevels(page, browser) {
  console.log('\n=== Step 3: Capture 3 zoom-level screenshots ===');

  // City-wide (zoom out): scroll/zoom OUT using page.keyboard
  // Street-level (default for family map): leave as-is
  // Building-level (zoom in): scroll/zoom IN

  // Capture counter text first (so we don't lose it after zoom gestures)
  const memberCountText = await page.evaluate(() => {
    const txt = document.body.innerText;
    const m = txt.match(/(\d+)\s*members?\s*located/i) || txt.match(/(\d+)\s*members?/i);
    return m ? m[0] : '(counter text not found in body)';
  });
  console.log(`  Member counter: "${memberCountText}"`);

  // City-wide: zoom out via Ctrl + Scroll
  console.log('  Zooming out (city-wide)...');
  for (let i = 0; i < 8; i++) {
    await page.mouse.move(640, 360);
    await page.keyboard.down('Control');
    await page.mouse.wheel({ deltaY: 200 });
    await page.keyboard.up('Control');
    await sleep(150);
  }
  await sleep(4000);
  await page.screenshot({ path: join(OUT_DIR, '01-city-wide.png'), fullPage: false });
  console.log(`    Saved 01-city-wide.png`);

  // Street-level: zoom back in
  console.log('  Zooming back to street-level...');
  for (let i = 0; i < 5; i++) {
    await page.mouse.move(640, 360);
    await page.keyboard.down('Control');
    await page.mouse.wheel({ deltaY: -200 });
    await page.keyboard.up('Control');
    await sleep(150);
  }
  await sleep(4000);
  await page.screenshot({ path: join(OUT_DIR, '02-street-level.png'), fullPage: false });
  console.log(`    Saved 02-street-level.png`);

  // Building-level: zoom in more
  console.log('  Zooming in (building-level)...');
  for (let i = 0; i < 6; i++) {
    await page.mouse.move(640, 360);
    await page.keyboard.down('Control');
    await page.mouse.wheel({ deltaY: -200 });
    await page.keyboard.up('Control');
    await sleep(150);
  }
  await sleep(5000);
  await page.screenshot({ path: join(OUT_DIR, '03-building-level.png'), fullPage: false });
  console.log(`    Saved 03-building-level.png`);

  return { memberCountText };
}

async function captureEvidence(page) {
  console.log('\n=== Step 4: Capture Console + Network + Service Worker evidence ===');
  // Already capturing during navigation, but re-collect here for the final state
  return {};  // stub — actual capture happens via page.on() handlers in main()
}

(async () => {
  console.log('v9.0 — Authenticated Family Map verification');
  console.log(`Output directory: ${OUT_DIR}`);
  console.log(`Test email: ${TEST_EMAIL.replace(/(?<=.).(?=@)/g, '*')} (redacted)`);  // never print full email

  const browser = await puppeteer.launch({
    headless: 'new',
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-web-security',
      '--ignore-gpu-blocklist',
      '--enable-unsafe-swiftshader',
      '--use-gl=angle',
      '--use-angle=swiftshader',
      '--enable-webgl',
      '--disable-dev-shm-usage',
    ],
  });

  const consoleLogs = [];
  const networkLogs = [];
  const pageErrors = [];

  try {
    const page = await browser.newPage();
    await page.setViewport({ width: 1280, height: 800, deviceScaleFactor: 1 });

    // Capture ALL console + network for the entire session (not just the post-login phase)
    page.on('console', msg => {
      const text = sanitize(`[${msg.type()}] ${msg.text()}`);
      consoleLogs.push(text);
    });
    page.on('pageerror', err => {
      const text = sanitize(`[pageerror] ${err.message}\n${err.stack || ''}`);
      pageErrors.push(text);
      consoleLogs.push(text);
    });
    page.on('response', resp => {
      const url = resp.url();
      if (url.includes('vercel.app') || url.includes('openfreemap') ||
          url.includes('pmtiles') || url.includes('maplibre') ||
          url.includes('supabase') || url.includes('canvaskit') ||
          url.includes('gstatic')) {
        const status = resp.status();
        // Sanitize URL in case Supabase RLS error messages include the user's email
        const text = sanitize(`[${status}] ${url.substring(0, 200)}`);
        networkLogs.push(text);
      }
    });

    await login(page);
    await findAndNavigateToMap(page);
    const { memberCountText } = await captureZoomLevels(page, browser);

    // Service worker state
    const swState = await page.evaluate(async () => {
      try {
        const regs = await navigator.serviceWorker.getRegistrations();
        return {
          supported: true,
          count: regs.length,
          scopes: regs.map(r => r.scope),
          scripts: regs.map(r => r.active?.scriptURL || null),
        };
      } catch (e) {
        return { supported: false, error: e.message };
      }
    });

    const evidence = {
      timestamp: new Date().toISOString(),
      live_url: LIVE_URL,
      test_email_redacted: TEST_EMAIL.replace(/(?<=.{2}).(?=@)/g, '*'),
      final_url: page.url(),
      member_count_text: memberCountText,
      service_workers: swState,
      console: {
        total_lines: consoleLogs.length,
        error_lines: consoleLogs.filter(l => l.startsWith('[error]') || l.startsWith('[pageerror]')).length,
        family_map_lines: consoleLogs.filter(l => l.includes('FamilyMap:')).length,
        lines: consoleLogs,
      },
      network: {
        total_logged: networkLogs.length,
        non_200_count: networkLogs.filter(l => !l.startsWith('[200]') && !l.startsWith('[304]') && !l.startsWith('[301]') && !l.startsWith('[302]')).length,
        tile_requests: networkLogs.filter(l => l.includes('openfreemap') || l.includes('pmtiles')),
        supabase_requests: networkLogs.filter(l => l.includes('supabase')),
        asset_loads: networkLogs.filter(l => l.includes('vercel.app') || l.includes('canvaskit') || l.includes('gstatic')),
        all_lines: networkLogs,
      },
      page_errors: pageErrors,
    };

    // Save evidence (already sanitized)
    writeFileSync(join(OUT_DIR, '00-summary.json'), JSON.stringify(evidence, null, 2));

    console.log('\n=== SUMMARY ===');
    console.log(`  Member counter: "${memberCountText}"`);
    console.log(`  Console lines: ${consoleLogs.length} (${evidence.console.error_lines} errors, ${evidence.console.family_map_lines} FamilyMap:)`);
    console.log(`  Network log lines: ${networkLogs.length}`);
    console.log(`  Service workers: ${swState.count || 0} registered`);
    console.log(`  Page errors: ${pageErrors.length}`);
    console.log(`\nAll evidence saved to: ${OUT_DIR}`);
    console.log(`  - 01-city-wide.png`);
    console.log(`  - 02-street-level.png`);
    console.log(`  - 03-building-level.png`);
    console.log(`  - 00-summary.json`);
  } finally {
    await browser.close();
  }
})();
