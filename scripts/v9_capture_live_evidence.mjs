// scripts/v9_capture_live_evidence.mjs
//
// v9.0 — Live evidence capture (NO login required)
//
// The user reports Family Map is "blank on web and Android" despite the
// v7.0 TileJSON fix. This script captures EVERYTHING we can observe on
// the public production URL (unauthenticated landing page) so we can
// diagnose whether:
//   (a) The deployed bundle is stale (Vercel not rebuilding)
//   (b) JS errors break Flutter bootstrap before Family Map can render
//   (c) Service worker is serving cached v6.0 (broken) bundle
//   (d) maplibre-gl.js or pmtiles.js CDN scripts fail to load
//   (e) OpenFreeMap TileJSON endpoint is unreachable from the browser
//   (f) main.dart.js itself references the old direct-tile-template URL
//
// This does NOT log in — it captures the landing page and then probes
// the production assets directly to verify what the deployed bundle
// actually contains.

import puppeteer from 'puppeteer';
import fs from 'node:fs';
import path from 'node:path';

const OUT_DIR = '/home/z/my-project/download/v9-blank-investigation';
fs.mkdirSync(OUT_DIR, { recursive: true });

const LIVE_URL = 'https://daxelo-kinrel.vercel.app/';

function ts() {
  return new Date().toISOString().replace(/[:.]/g, '-');
}

async function capture() {
  const browser = await puppeteer.launch({
    headless: 'new',
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage',
      '--disable-gpu',
      '--enable-logging',
      '--v=1',
      '--use-gl=angle',
      '--use-angle=swiftshader',
      '--enable-unsafe-swiftshader',
    ],
  });

  const page = await browser.newPage();
  await page.setViewport({ width: 1440, height: 900, deviceScaleFactor: 1 });

  const consoleLog = [];
  const networkLog = [];
  const pageErrors = [];
  const requestFailed = [];
  const responses4xx5xx = [];

  page.on('console', (msg) => {
    consoleLog.push({
      t: Date.now(),
      type: msg.type(),
      text: msg.text(),
      location: msg.location()?.url ?? null,
    });
  });
  page.on('pageerror', (err) => {
    pageErrors.push({ t: Date.now(), name: err.name, message: err.message, stack: err.stack });
  });
  page.on('requestfailed', (req) => {
    requestFailed.push({
      t: Date.now(),
      url: req.url(),
      method: req.method(),
      failure: req.failure()?.errorText ?? null,
    });
  });
  page.on('response', (resp) => {
    const status = resp.status();
    if (status >= 400 || status === 0) {
      responses4xx5xx.push({
        t: Date.now(),
        url: resp.url(),
        status,
        statusText: resp.statusText(),
      });
    }
    networkLog.push({
      t: Date.now(),
      url: resp.url(),
      status,
      method: resp.request().method(),
      contentType: resp.headers()['content-type'] ?? null,
      contentLength: resp.headers()['content-length'] ?? null,
    });
  });

  console.log('[v9] Navigating to', LIVE_URL);
  try {
    await page.goto(LIVE_URL, { waitUntil: 'networkidle2', timeout: 45000 });
  } catch (e) {
    console.log('[v9] goto error (continuing):', e.message);
  }

  // Wait past Flutter bootstrap (typically <5s, but give a wide berth).
  console.log('[v9] Waiting 20s for Flutter bootstrap…');
  await new Promise((r) => setTimeout(r, 20000));

  // Screenshot the landing page
  await page.screenshot({ path: path.join(OUT_DIR, '01_landing_page.png'), fullPage: false });
  console.log('[v9] Screenshot saved: 01_landing_page.png');

  // Dump the rendered DOM so we can see if Flutter inserted its canvas
  const html = await page.content();
  fs.writeFileSync(path.join(OUT_DIR, '02_landing_dom.html'), html);
  console.log('[v9] DOM dump saved:', html.length, 'chars');

  // Probe the Flutter bootstrap script + main.dart.js to see if it's v7.0
  console.log('[v9] Probing flutter_bootstrap.js + main.dart.js for v7.0 markers…');
  const probeResults = {};
  for (const assetPath of [
    'flutter_bootstrap.js',
    'main.dart.js',
    'assets/assets/map_styles/kinrel_dark_style.json',
    'index.html',
    'flutter_service_worker.js',
  ]) {
    const url = LIVE_URL + assetPath;
    try {
      const r = await fetch(url, { redirect: 'follow' });
      const text = await r.text();
      probeResults[assetPath] = {
        url,
        status: r.status,
        contentType: r.headers.get('content-type'),
        size: text.length,
        // Search for v7.0 vs v6.0 markers
        containsTileJsonUrl: text.includes('https://tiles.openfreemap.org/planet"')
          || text.includes('https://tiles.openfreemap.org/planet\'')
          || text.includes('"url":"https://tiles.openfreemap.org/planet"')
          || text.includes('%22url%22%3A%22https%3A%2F%2Ftiles.openfreemap.org%2Fplanet'),
        containsDirectTileTemplate: text.includes('https://tiles.openfreemap.org/planet/{z}/{x}/{y}.pbf')
          || text.includes('https%3A%2F%2Ftiles.openfreemap.org%2Fplanet%2F%7Bz%7D%2F%7Bx%7D%2F%7By%7D.pbf'),
        containsPmtilesPlaceholder: text.includes('{{PMTILES_URL}}') || text.includes('%7B%7BPMTILES_URL%7D%7D'),
        containsV6Comment: text.includes('v6.0') || text.includes('v5.0 Part 1'),
        containsV7Comment: text.includes('v7.0'),
      };
    } catch (e) {
      probeResults[assetPath] = { url, error: e.message };
    }
  }
  fs.writeFileSync(path.join(OUT_DIR, '03_asset_probe.json'), JSON.stringify(probeResults, null, 2));
  console.log('[v9] Asset probe saved: 03_asset_probe.json');
  for (const [k, v] of Object.entries(probeResults)) {
    console.log(`[v9]   ${k}: status=${v.status} size=${v.size} TileJsonUrl=${v.containsTileJsonUrl} DirectTemplate=${v.containsDirectTileTemplate}`);
  }

  // Check what service workers are registered
  const swInfo = await page.evaluate(async () => {
    if (!('serviceWorker' in navigator)) return { supported: false };
    const regs = await navigator.serviceWorker.getRegistrations();
    return {
      supported: true,
      count: regs.length,
      scopes: regs.map((r) => r.scope),
      scripts: regs.map((r) => r.active?.scriptURL ?? r.installing?.scriptURL ?? r.waiting?.scriptURL),
    };
  });
  fs.writeFileSync(path.join(OUT_DIR, '04_service_workers.json'), JSON.stringify(swInfo, null, 2));
  console.log('[v9] Service workers:', JSON.stringify(swInfo));

  // Check what global JS objects are loaded (maplibregl, pmtiles)
  const globalsInfo = await page.evaluate(() => ({
    hasMaplibregl: typeof maplibregl !== 'undefined',
    maplibreglVersion: typeof maplibregl !== 'undefined' ? (maplibregl.version || 'unknown') : null,
    hasPmtiles: typeof pmtiles !== 'undefined',
    flutterReady: typeof window._flutter != 'undefined',
    flutterAppRunner: typeof window._flutter?.appRunner != 'undefined',
    location: window.location.href,
    documentTitle: document.title,
    bodyChildren: document.body?.children?.length ?? 0,
    bodyInnerHTMLLength: document.body?.innerHTML?.length ?? 0,
    fltGlassPaneCount: document.querySelectorAll('flt-glass-pane').length,
    fltSceneHostCount: document.querySelectorAll('flt-scene-host').length,
    fltPlatformViewCount: document.querySelectorAll('flt-platform-view').length,
  }));
  fs.writeFileSync(path.join(OUT_DIR, '05_globals.json'), JSON.stringify(globalsInfo, null, 2));
  console.log('[v9] Globals:', JSON.stringify(globalsInfo, null, 2));

  // Save console + pageerror logs
  fs.writeFileSync(path.join(OUT_DIR, '06_console_log.json'), JSON.stringify(consoleLog, null, 2));
  fs.writeFileSync(path.join(OUT_DIR, '07_page_errors.json'), JSON.stringify(pageErrors, null, 2));
  fs.writeFileSync(path.join(OUT_DIR, '08_request_failures.json'), JSON.stringify(requestFailed, null, 2));
  fs.writeFileSync(path.join(OUT_DIR, '09_responses_4xx_5xx.json'), JSON.stringify(responses4xx5xx, null, 2));
  fs.writeFileSync(path.join(OUT_DIR, '10_network_log.json'), JSON.stringify(networkLog, null, 2));

  console.log('[v9] Console messages:', consoleLog.length);
  console.log('[v9] Page errors:', pageErrors.length);
  console.log('[v9] Request failures:', requestFailed.length);
  console.log('[v9] 4xx/5xx responses:', responses4xx5xx.length);
  console.log('[v9] Network log entries:', networkLog.length);

  if (pageErrors.length > 0) {
    console.log('\n[v9] !! PAGE ERRORS DETECTED:');
    for (const e of pageErrors) {
      console.log('  -', e.name, ':', e.message);
    }
  }
  if (requestFailed.length > 0) {
    console.log('\n[v9] !! REQUEST FAILURES:');
    for (const f of requestFailed.slice(0, 20)) {
      console.log('  -', f.url, '→', f.failure);
    }
  }
  if (responses4xx5xx.length > 0) {
    console.log('\n[v9] !! 4XX/5XX RESPONSES:');
    for (const r of responses4xx5xx.slice(0, 20)) {
      console.log('  -', r.status, r.url);
    }
  }

  // Filter console errors and warnings
  const errorsAndWarnings = consoleLog.filter((l) => l.type === 'error' || l.type === 'warning');
  if (errorsAndWarnings.length > 0) {
    console.log('\n[v9] !! Console errors/warnings (first 30):');
    for (const e of errorsAndWarnings.slice(0, 30)) {
      console.log('  -', '[' + e.type + ']', e.text);
    }
  }

  await browser.close();
  console.log('\n[v9] Done. Evidence saved to', OUT_DIR);
}

capture().catch((e) => {
  console.error('[v9] FATAL:', e);
  process.exit(1);
});
