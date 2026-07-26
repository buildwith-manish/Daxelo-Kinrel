/**
 * v5.0 Part 1 — Production verification screenshot script.
 *
 * Captures 4 screenshots required by docs/PRODUCTION_VERIFICATION_v5.0.md:
 *   1. Production happy path — tiles + markers visible
 *   2. Staging PMTiles probe failure — bad PMTiles URL → OpenFreeMap fallback
 *   3. Staging OpenFreeMap blocked → offline floor style
 *   4. Staging markers decoupled — markers visible even when tiles fail
 *
 * Usage:
 *   node screenshots.js <production_url> <staging_url> <output_dir>
 *
 * Outputs:
 *   <output_dir>/01-production-happy-path.png
 *   <output_dir>/02-staging-pmtiles-probe-fallback.png
 *   <output_dir>/03-staging-offline-floor.png
 *   <output_dir>/04-staging-markers-decoupled.png
 *   <output_dir>/05-console-logs.txt  (aggregated browser console logs per stage)
 *   <output_dir>/verification-result.json  (pass/fail per screenshot)
 */
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const PRODUCTION_URL = process.argv[2];
const STAGING_URL = process.argv[3];
const OUTPUT_DIR = process.argv[4];

if (!PRODUCTION_URL || !STAGING_URL || !OUTPUT_DIR) {
  console.error('Usage: node screenshots.js <production_url> <staging_url> <output_dir>');
  process.exit(1);
}

fs.mkdirSync(OUTPUT_DIR, { recursive: true });

const results = {
  timestamp: new Date().toISOString(),
  production_url: PRODUCTION_URL,
  staging_url: STAGING_URL,
  screenshots: [],
};

function log(msg) {
  console.log(`[screenshots] ${msg}`);
}

async function captureConsole(page, label) {
  const logs = [];
  page.on('console', (msg) => {
    logs.push(`[${msg.type()}] ${msg.text()}`);
  });
  page.on('pageerror', (err) => {
    logs.push(`[pageerror] ${err.message}`);
  });
  return logs;
}

async function waitForMapReady(page, opts = {}) {
  const { timeout = 30000, expectTiles = true } = opts;
  log(`  waiting for map ready (timeout=${timeout}ms, expectTiles=${expectTiles})...`);

  // Wait for the map widget container to appear
  await page.waitForSelector('.maplibregl-map, [class*="maplibre"]', { timeout });

  // Wait a bit for tiles to load (or fail and fall back)
  await page.waitForTimeout(8000);

  // Check if "Loading family map…" is still visible (skeleton)
  const skeletonVisible = await page.evaluate(() => {
    const body = document.body.innerText || '';
    return body.includes('Loading family map');
  });

  return { skeletonVisible };
}

async function countAvatarMarkers(page) {
  // AvatarMarkerOverlay renders Flutter widgets — they're inside the Flutter
  // view, not DOM elements. We can't directly count them via DOM. Instead,
  // check if "0 members located" text is NOT present (which means markers
  // loaded) and "X members located" IS present.
  const bodyText = await page.evaluate(() => document.body.innerText || '');
  const hasZeroMembers = /0\s+members?\s+located/i.test(bodyText);
  const hasMembersLocated = /\d+\s+members?\s+located/i.test(bodyText);
  return { hasZeroMembers, hasMembersLocated, bodyText: bodyText.slice(0, 500) };
}

async function hasVisibleTiles(page) {
  // Check if the map has actually rendered tiles (canvas with non-black pixels)
  return await page.evaluate(() => {
    const canvases = document.querySelectorAll('canvas');
    if (canvases.length === 0) return { hasCanvas: false, hasTiles: false };
    const c = canvases[0];
    if (c.width === 0 || c.height === 0) return { hasCanvas: true, hasTiles: false };
    const ctx = c.getContext('2d');
    if (!ctx) return { hasCanvas: true, hasTiles: false };
    // Sample a 10x10 grid of pixels — if they're all the same color, it's
    // a blank background (no tiles). If they vary, tiles are rendering.
    try {
      const samples = [];
      for (let i = 1; i < 10; i++) {
        for (let j = 1; j < 10; j++) {
          const x = Math.floor((c.width * i) / 10);
          const y = Math.floor((c.height * j) / 10);
          const p = ctx.getImageData(x, y, 1, 1).data;
          samples.push(`${p[0]},${p[1]},${p[2]}`);
        }
      }
      const unique = new Set(samples).size;
      return { hasCanvas: true, hasTiles: unique > 3, uniqueColors: unique };
    } catch (e) {
      return { hasCanvas: true, hasTiles: false, error: e.message };
    }
  });
}

// ─────────────────────────────────────────────────────────────────
// Screenshot 1: Production happy path
// ─────────────────────────────────────────────────────────────────
async function screenshot1ProductionHappyPath(browser) {
  log('=== Screenshot 1: Production happy path ===');
  const context = await browser.newContext({
    viewport: { width: 1280, height: 800 },
    deviceScaleFactor: 2,
  });
  const page = await context.newPage();
  const consoleLogs = [];
  page.on('console', (m) => consoleLogs.push(`[${m.type()}] ${m.text()}`));
  page.on('pageerror', (e) => consoleLogs.push(`[pageerror] ${e.message}`));

  try {
    log(`  navigating to ${PRODUCTION_URL}`);
    await page.goto(PRODUCTION_URL, { waitUntil: 'networkidle', timeout: 60000 });

    // Dismiss any onboarding / sign-in wall — if there's a "Skip" or
    // "Get Started" button, click it. The family map may require auth
    // in production; we'll try to navigate directly to the map route.
    log('  looking for navigation to family map...');

    // Wait for app to load
    await page.waitForTimeout(5000);

    // Try to find and click a map nav button (varies by app state)
    const mapNavSelectors = [
      'text=Family Map',
      'text=Map',
      '[aria-label*="map" i]',
      '[data-testid*="map" i]',
      'button:has-text("Map")',
    ];
    for (const sel of mapNavSelectors) {
      try {
        const el = await page.$(sel);
        if (el) {
          log(`  clicking nav: ${sel}`);
          await el.click({ timeout: 5000 });
          await page.waitForTimeout(3000);
          break;
        }
      } catch (_) {}
    }

    // Wait for the map widget
    const { skeletonVisible } = await waitForMapReady(page, { timeout: 30000 });
    log(`  skeleton still visible: ${skeletonVisible}`);

    const tiles = await hasVisibleTiles(page);
    log(`  tiles rendering: ${tiles.hasTiles} (${tiles.uniqueColors || 0} unique colors sampled)`);

    const markers = await countAvatarMarkers(page);
    log(`  markers text: zero=${markers.hasZeroMembers}, any=${markers.hasMembersLocated}`);

    const outPath = path.join(OUTPUT_DIR, '01-production-happy-path.png');
    await page.screenshot({ path: outPath, fullPage: false });
    log(`  saved: ${outPath}`);

    results.screenshots.push({
      name: '01-production-happy-path',
      path: outPath,
      passed: tiles.hasTiles && !skeletonVisible,
      details: {
        skeletonVisible,
        tilesRendering: tiles.hasTiles,
        uniqueColorsSampled: tiles.uniqueColors,
        markers,
      },
    });

    // Save console logs
    fs.writeFileSync(
      path.join(OUTPUT_DIR, '05-console-logs-stage1.txt'),
      consoleLogs.join('\n'),
    );
  } finally {
    await context.close();
  }
}

// ─────────────────────────────────────────────────────────────────
// Screenshot 2: Staging PMTiles probe failure → OpenFreeMap fallback
// ─────────────────────────────────────────────────────────────────
async function screenshot2PmtilesProbeFallback(browser) {
  log('=== Screenshot 2: Staging PMTiles probe failure → OpenFreeMap fallback ===');
  const context = await browser.newContext({
    viewport: { width: 1280, height: 800 },
    deviceScaleFactor: 2,
  });
  const page = await context.newPage();
  const consoleLogs = [];
  page.on('console', (m) => consoleLogs.push(`[${m.type()}] ${m.text()}`));
  page.on('pageerror', (e) => consoleLogs.push(`[pageerror] ${e.message}`));

  try {
    log(`  navigating to ${STAGING_URL}`);
    await page.goto(STAGING_URL, { waitUntil: 'networkidle', timeout: 60000 });
    await page.waitForTimeout(5000);

    // Try to nav to map (same as screenshot 1)
    for (const sel of ['text=Family Map', 'text=Map', 'button:has-text("Map")']) {
      try {
        const el = await page.$(sel);
        if (el) {
          await el.click({ timeout: 5000 });
          await page.waitForTimeout(3000);
          break;
        }
      } catch (_) {}
    }

    // Wait for map + PMTiles probe + fallback
    log('  waiting for PMTiles probe + fallback...');
    await waitForMapReady(page, { timeout: 30000 });

    const tiles = await hasVisibleTiles(page);
    log(`  tiles rendering: ${tiles.hasTiles} (fallback should have succeeded)`);

    // Verify the probe fallback actually fired
    const probeLogFound = consoleLogs.some((l) =>
      l.includes('PMTiles source probe failed') || l.includes('falling back to OpenFreeMap')
    );
    log(`  probe fallback log found: ${probeLogFound}`);

    const outPath = path.join(OUTPUT_DIR, '02-staging-pmtiles-probe-fallback.png');
    await page.screenshot({ path: outPath, fullPage: false });
    log(`  saved: ${outPath}`);

    results.screenshots.push({
      name: '02-staging-pmtiles-probe-fallback',
      path: outPath,
      passed: tiles.hasTiles && probeLogFound,
      details: {
        probeLogFound,
        tilesRendering: tiles.hasTiles,
        uniqueColorsSampled: tiles.uniqueColors,
      },
    });

    fs.writeFileSync(
      path.join(OUTPUT_DIR, '05-console-logs-stage2.txt'),
      consoleLogs.join('\n'),
    );
  } finally {
    await context.close();
  }
}

// ─────────────────────────────────────────────────────────────────
// Screenshots 3 + 4: Staging OpenFreeMap blocked → offline floor
// ─────────────────────────────────────────────────────────────────
async function screenshots3And4OfflineFloor(browser) {
  log('=== Screenshots 3 + 4: Staging OpenFreeMap blocked → offline floor ===');
  const context = await browser.newContext({
    viewport: { width: 1280, height: 800 },
    deviceScaleFactor: 2,
  });
  const page = await context.newPage();
  const consoleLogs = [];
  page.on('console', (m) => consoleLogs.push(`[${m.type()}] ${m.text()}`));
  page.on('pageerror', (e) => consoleLogs.push(`[pageerror] ${e.message}`));

  // Block OpenFreeMap requests — simulates total CDN outage
  // The app's watchdog should kick in: PMTiles probe fails (~3s) → OpenFreeMap
  // blocked → watchdog 6s → offline floor style (no external sources).
  await page.route('**/*openfreemap.org**', (route) => {
    log(`  [blocked] ${route.request().url()}`);
    route.abort('failed');
  });
  // Also block the PMTiles URL (example.com/nonexistent.pmtiles from --dart-define)
  await page.route('**/*example.com/**', (route) => {
    log(`  [blocked] ${route.request().url()}`);
    route.abort('failed');
  });
  // Also block natural_earth (the raster background) — to truly test the
  // offline floor, no external tiles should load
  await page.route('**/*natural_earth**', (route) => {
    log(`  [blocked] ${route.request().url()}`);
    route.abort('failed');
  });

  try {
    log(`  navigating to ${STAGING_URL} (all map sources blocked)`);
    await page.goto(STAGING_URL, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.waitForTimeout(5000);

    // Try to nav to map
    for (const sel of ['text=Family Map', 'text=Map', 'button:has-text("Map")']) {
      try {
        const el = await page.$(sel);
        if (el) {
          await el.click({ timeout: 5000 });
          await page.waitForTimeout(3000);
          break;
        }
      } catch (_) {}
    }

    // Wait for the watchdog to chain through all fallback tiers
    // PMTiles probe: ~3s, OpenFreeMap watchdog: 6s, offline floor: 6s
    // Total: up to 15s + buffer
    log('  waiting 20s for full fallback chain to complete...');
    await page.waitForTimeout(20000);

    // Screenshot 3: offline floor visible
    const tiles3 = await hasVisibleTiles(page);
    log(`  tiles rendering: ${tiles3.hasTiles} (should be false — offline floor has no tiles)`);

    const outPath3 = path.join(OUTPUT_DIR, '03-staging-offline-floor.png');
    await page.screenshot({ path: outPath3, fullPage: false });
    log(`  saved: ${outPath3}`);

    // Screenshot 4: markers visible (decoupled from basemap)
    const markers4 = await countAvatarMarkers(page);
    log(`  markers text: zero=${markers4.hasZeroMembers}, any=${markers4.hasMembersLocated}`);

    const outPath4 = path.join(OUTPUT_DIR, '04-staging-markers-decoupled.png');
    await page.screenshot({ path: outPath4, fullPage: false });
    log(`  saved: ${outPath4}`);

    // The offline floor + error UI should be visible
    const offlineFloorLogFound = consoleLogs.some((l) =>
      l.includes('offline floor') || l.includes('All map sources failed')
    );
    const errorUiVisible = await page.evaluate(() => {
      const body = document.body.innerText || '';
      return (
        body.includes('Use Offline Mode') ||
        body.includes('Could not load the family map') ||
        body.includes('offline')
      );
    });

    results.screenshots.push({
      name: '03-staging-offline-floor',
      path: outPath3,
      passed: !tiles3.hasTiles && (offlineFloorLogFound || errorUiVisible),
      details: {
        tilesRendering: tiles3.hasTiles,
        offlineFloorLogFound,
        errorUiVisible,
      },
    });

    results.screenshots.push({
      name: '04-staging-markers-decoupled',
      path: outPath4,
      passed: !markers4.hasZeroMembers,
      details: {
        markers,
        offlineFloorLogFound,
        errorUiVisible,
      },
    });

    fs.writeFileSync(
      path.join(OUTPUT_DIR, '05-console-logs-stage3-4.txt'),
      consoleLogs.join('\n'),
    );
  } finally {
    await context.close();
  }
}

(async () => {
  log(`Production URL: ${PRODUCTION_URL}`);
  log(`Staging URL: ${STAGING_URL}`);
  log(`Output dir: ${OUTPUT_DIR}`);

  const browser = await chromium.launch({ headless: true });

  try {
    await screenshot1ProductionHappyPath(browser);
    await screenshot2PmtilesProbeFallback(browser);
    await screenshots3And4OfflineFloor(browser);
  } catch (e) {
    log(`FATAL: ${e.message}`);
    log(e.stack);
    results.fatalError = e.message;
  } finally {
    await browser.close();
  }

  // Write results JSON
  const resultsPath = path.join(OUTPUT_DIR, 'verification-result.json');
  fs.writeFileSync(resultsPath, JSON.stringify(results, null, 2));
  log(`Results written to ${resultsPath}`);

  // Print summary
  log('\n=== Verification Summary ===');
  for (const s of results.screenshots) {
    log(`  ${s.name}: ${s.passed ? 'PASS' : 'FAIL'}`);
  }

  // Exit non-zero if any screenshot failed
  const anyFailed = results.screenshots.some((s) => !s.passed);
  process.exit(anyFailed ? 1 : 0);
})();
