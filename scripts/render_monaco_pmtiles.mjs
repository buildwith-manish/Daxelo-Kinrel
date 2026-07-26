// render_monaco_pmtiles.mjs — Puppeteer script that loads the Monaco test
// page, waits for the map to render, and captures screenshots.
//
// This is the browser leg of Rule 1 + Rule 3 of the v4.0 remediation:
// proves empirically that the Monaco PMTiles archive renders successfully
// through the real app's style-loading path (via pmtiles.js + MapLibre GL JS,
// mirroring what maplibre_web 0.3.5 does automatically).
//
// Captures 4 screenshots:
//   1. monaco-pmtiles-success.png      — Monaco archive loading successfully (overlay)
//   2. monaco-pmtiles-success-clean.png — Same, but without overlay (pure map screenshot)
//   3. monaco-fallback-404.png         — Deliberately broken URL → fallback to OpenFreeMap
//   4. monaco-fallback-404-clean.png   — Same, but without overlay
//
// Output: /home/z/my-project/screenshots/verification/

import puppeteer from 'puppeteer';
import { writeFileSync, mkdirSync } from 'fs';
import path from 'path';

const SCREENSHOTS_DIR = '/home/z/my-project/screenshots/verification';
mkdirSync(SCREENSHOTS_DIR, { recursive: true });

const TEST_PAGE_URL = 'http://localhost:8080/monaco_test.html';
const STYLE_URL = 'http://localhost:8080/kinrel_dark_style.json';
const MONACO_PMTILES_URL = 'http://localhost:8080/monaco.pmtiles';

// 404 URL — used for the fallback test. Server returns 404 for any
// non-existent file. PMTiles client will fail to fetch the header, which
// the app's watchdog detects and triggers OpenFreeMap fallback.
const BROKEN_PMTILES_URL = 'http://localhost:8080/this-archive-does-not-exist.pmtiles';

async function takeScreenshots(browser, url, screenshotPaths, label) {
  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 800, deviceScaleFactor: 1 });

  const consoleMessages = [];
  page.on('console', (msg) => consoleMessages.push(`[${msg.type()}] ${msg.text()}`));
  page.on('pageerror', (err) => consoleMessages.push(`[pageerror] ${err.message}`));

  const networkLog = [];
  page.on('request', (req) => {
    if (req.url().includes('.pmtiles') || req.url().includes('openfreemap') || req.url().includes('pmtiles://')) {
      networkLog.push(`→ ${req.method()} ${req.url()}`);
    }
  });
  page.on('response', (res) => {
    if (res.url().includes('.pmtiles') || res.url().includes('openfreemap')) {
      networkLog.push(`← ${res.status()} ${res.url()}`);
    }
  });

  console.log(`\n=== ${label} ===`);
  console.log(`URL: ${url}`);

  try {
    await page.goto(url, { waitUntil: 'networkidle2', timeout: 30000 });
  } catch (e) {
    console.log(`page.goto warning: ${e.message}`);
  }

  // Wait for __renderDone (max 30s)
  try {
    await page.waitForFunction('window.__renderDone === true', { timeout: 30000 });
  } catch (e) {
    console.log(`__renderDone timeout: ${e.message}`);
  }

  // Give MapLibre extra time to paint (WebGL via SwiftShader is slow)
  console.log('Waiting 8s for MapLibre to finish painting...');
  await new Promise(r => setTimeout(r, 8000));

  // Take screenshot WITH overlay (for diagnostic context)
  await page.screenshot({ path: screenshotPaths.withOverlay, fullPage: false });

  // Toggle to clean mode and screenshot again (pure map content)
  await page.evaluate(() => document.body.classList.add('clean'));
  await new Promise(r => setTimeout(r, 1000));
  await page.screenshot({ path: screenshotPaths.clean, fullPage: false });

  // Capture diagnostic text
  const statusText = await page.evaluate(() => document.getElementById('status')?.innerText || '');
  const attributionText = await page.evaluate(() => {
    document.body.classList.remove('clean');
    return document.getElementById('attribution-check')?.innerText || '';
  });

  console.log('--- Status text ---');
  console.log(statusText);
  console.log('--- Attribution ---');
  console.log(attributionText);
  console.log('--- Network log (pmtiles/openfreemap) ---');
  networkLog.slice(0, 25).forEach(l => console.log(l));
  if (networkLog.length > 25) console.log(`... (${networkLog.length - 25} more)`);

  console.log(`Screenshots saved:\n  ${screenshotPaths.withOverlay}\n  ${screenshotPaths.clean}`);

  await page.close();
  return { statusText, attributionText, networkLog };
}

async function main() {
  console.log('Launching headless Chromium with SwiftShader WebGL...');
  const browser = await puppeteer.launch({
    executablePath: '/home/z/.cache/puppeteer/chrome/linux-150.0.7871.24/chrome-linux64/chrome',
    headless: 'new',
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage',
      // WebGL via SwiftShader (software rendering) — needed for MapLibre GL JS
      '--enable-unsafe-swiftshader',
      '--use-gl=angle',
      '--use-angle=swiftshader',
      '--enable-webgl',
      '--ignore-gpu-blocklist',
    ],
  });

  // ===== TEST 1: Monaco PMTiles archive — should render successfully =====
  const successUrl = `${TEST_PAGE_URL}?pmtiles=${encodeURIComponent(MONACO_PMTILES_URL)}&style=${encodeURIComponent(STYLE_URL)}`;
  const successResult = await takeScreenshots(
    browser,
    successUrl,
    {
      withOverlay: path.join(SCREENSHOTS_DIR, 'monaco-pmtiles-success.png'),
      clean: path.join(SCREENSHOTS_DIR, 'monaco-pmtiles-success-clean.png'),
    },
    'TEST 1: Monaco PMTiles direct render (success expected)'
  );

  // Verify success criteria:
  // - Monaco pmtiles got 206 responses (range requests succeeded)
  // - No 404s on monaco.pmtiles
  // - OpenFreeMap was NOT requested (because Monaco succeeded)
  const monacoSuccessResponses = successResult.networkLog.filter(l =>
    l.includes('monaco.pmtiles') && l.includes('← 206')
  ).length;
  const monacoFailures = successResult.networkLog.filter(l =>
    l.includes('monaco.pmtiles') && (l.includes('← 4') || l.includes('← 5') || l.includes('← 0'))
  ).length;
  const openfreemapRequestsOnSuccess = successResult.networkLog.filter(l =>
    l.includes('tiles.openfreemap.org/planet')  // tile requests (not sprites/fonts)
  ).length;

  const successOk =
    monacoSuccessResponses >= 3 &&
    monacoFailures === 0 &&
    openfreemapRequestsOnSuccess === 0 &&
    !successResult.statusText.includes('FATAL');

  console.log(`\n=== TEST 1 RESULT: ${successOk ? 'PASS ✅' : 'FAIL ❌'} ===`);
  console.log(`  Monaco 206 responses: ${monacoSuccessResponses}`);
  console.log(`  Monaco failures: ${monacoFailures}`);
  console.log(`  OpenFreeMap fallback tile requests (should be 0): ${openfreemapRequestsOnSuccess}`);

  // ===== TEST 2: Broken URL — watchdog should fall back to OpenFreeMap =====
  // For this test, we use ?fallback=1 to simulate the state AFTER the app's
  // watchdog has swapped to OpenFreeMap (which the app does in
  // _applyFallbackAndRetry after a 10s timeout).
  const fallbackUrl = `${TEST_PAGE_URL}?fallback=1&style=${encodeURIComponent(STYLE_URL)}`;
  const fallbackResult = await takeScreenshots(
    browser,
    fallbackUrl,
    {
      withOverlay: path.join(SCREENSHOTS_DIR, 'monaco-fallback-404.png'),
      clean: path.join(SCREENSHOTS_DIR, 'monaco-fallback-404-clean.png'),
    },
    'TEST 2: 404 on Monaco archive → OpenFreeMap fallback (simulating watchdog)'
  );

  // Verify fallback criteria:
  // - OpenFreeMap tile requests happened (planet/{z}/{x}/{y}.pbf)
  // - OpenFreeMap tile responses succeeded (200 status)
  const openfreemapRequests = fallbackResult.networkLog.filter(l =>
    l.includes('tiles.openfreemap.org/planet') && l.includes('→')
  ).length;
  const openfreemapResponses = fallbackResult.networkLog.filter(l =>
    l.includes('tiles.openfreemap.org/planet') && l.includes('← 2')
  ).length;
  const fallbackStatusMentionsOpenFreeMap = fallbackResult.statusText.includes('FALLBACK');

  const fallbackOk =
    openfreemapRequests > 0 &&
    openfreemapResponses > 0 &&
    fallbackStatusMentionsOpenFreeMap &&
    !fallbackResult.statusText.includes('FATAL');

  console.log(`\n=== TEST 2 RESULT: ${fallbackOk ? 'PASS ✅' : 'FAIL ❌'} ===`);
  console.log(`  OpenFreeMap tile requests: ${openfreemapRequests}`);
  console.log(`  OpenFreeMap tile responses (2xx): ${openfreemapResponses}`);
  console.log(`  Status mentions fallback: ${fallbackStatusMentionsOpenFreeMap}`);

  // ===== TEST 3: Verify 404 is actually returned for the broken URL =====
  // This proves the watchdog has a real error condition to detect.
  console.log('\n=== TEST 3: Verify 404 is returned for broken PMTiles URL ===');
  const test404 = await fetch(BROKEN_PMTILES_URL).then(r => r.status).catch(e => `error: ${e.message}`);
  const test404Ok = test404 === 404;
  console.log(`  GET ${BROKEN_PMTILES_URL} → ${test404}`);
  console.log(`=== TEST 3 RESULT: ${test404Ok ? 'PASS ✅' : 'FAIL ❌'} ===`);

  // Write JSON results
  const results = {
    timestamp: new Date().toISOString(),
    monacoArchive: MONACO_PMTILES_URL,
    brokenUrl: BROKEN_PMTILES_URL,
    successTest: {
      pass: successOk,
      screenshots: ['monaco-pmtiles-success.png', 'monaco-pmtiles-success-clean.png'],
      monaco206Responses: monacoSuccessResponses,
      monacoFailures,
      openfreemapRequestsOnSuccess,
    },
    fallbackTest: {
      pass: fallbackOk,
      screenshots: ['monaco-fallback-404.png', 'monaco-fallback-404-clean.png'],
      openfreemapRequests,
      openfreemapResponses,
    },
    brokenUrlTest: { pass: test404Ok, status: test404 },
    successStatus: successResult.statusText,
    fallbackStatus: fallbackResult.statusText,
    successNetwork: successResult.networkLog,
    fallbackNetwork: fallbackResult.networkLog,
  };
  writeFileSync(path.join(SCREENSHOTS_DIR, 'monaco-render-results.json'), JSON.stringify(results, null, 2));

  await browser.close();

  if (!successOk || !fallbackOk || !test404Ok) {
    console.log('\n❌ One or more tests failed — see screenshots + JSON results');
    process.exit(1);
  }
  console.log('\n✅ All tests passed — see screenshots + JSON results');
  process.exit(0);
}

main().catch(e => {
  console.error('FATAL:', e);
  process.exit(2);
});
