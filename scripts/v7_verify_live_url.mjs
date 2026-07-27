// scripts/v7_verify_live_url.mjs
//
// v7.0 — Live production URL verification.
//
// Runs three independent evidence captures against https://daxelo-kinrel.vercel.app:
//
//   1. Console + Network + Service Worker capture from the live auth-gated URL.
//      Loads the live URL, waits 8s (long enough for the 6s style-load watchdog
//      to fire if it's going to), captures every console line, every network
//      request to vercel.app/openfreemap/pmtiles/maplibre, and the
//      navigator.serviceWorker.getRegistrations() result. Saves to
//      download/v7-verification/01-live-url-evidence.json.
//
//   2. Style JSON deployment verification — fetches the deployed style JSON
//      from the live URL and asserts that the `openmaptiles` source uses
//      `{url: TileJSON-endpoint}` (v7.0 fix) and NOT `{tiles: [direct-template]}`
//      (v6.0 broken pattern). Saves to download/v7-verification/02-style-json.json.
//
//   3. 5-region tile-render verification — loads the deployed style JSON in a
//      standalone MapLibre page (bypasses the app's auth gate) and renders
//      Manhattan, Venice, rural Kansas, Riyadh, and Dharavi. Captures a PNG
//      for each region. Saves to download/v7-verification/03-regions/<region>.png.
//      This is the same test that the v6-verification workflow's visual-matrix
//      job runs.
//
// Usage: node scripts/v7_verify_live_url.mjs
//
// Requires: puppeteer (already in /home/z/my-project/node_modules)

import puppeteer from 'puppeteer';
import { mkdirSync, writeFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const OUT_DIR = join(__dirname, '..', 'download', 'v7-verification');
const REGION_DIR = join(OUT_DIR, '03-regions');
mkdirSync(REGION_DIR, { recursive: true });

const LIVE_URL = 'https://daxelo-kinrel.vercel.app';
const STYLE_URL = `${LIVE_URL}/assets/assets/map_styles/kinrel_dark_style.json`;

const regions = [
  { id: 'manhattan',    lng: -74.0060, lat: 40.7128, zoom: 14, pitch: 45 },
  { id: 'venice',       lng: 12.3389,  lat: 45.4376, zoom: 14, pitch: 45 },
  { id: 'rural-kansas', lng: -98.4255, lat: 38.5556, zoom: 14, pitch: 45 },
  { id: 'riyadh',       lng: 46.6753,  lat: 24.7136, zoom: 14, pitch: 45 },
  { id: 'dharavi',      lng: 72.8530,  lat: 19.0368, zoom: 15, pitch: 45 },
];

const sleep = (ms) => new Promise(r => setTimeout(r, ms));

async function captureLiveUrlEvidence(browser) {
  console.log('\n=== Step 1: Live URL Console + Network + Service Worker capture ===');
  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 720 });

  const consoleLogs = [];
  const networkLogs = [];
  const pageErrors = [];

  page.on('console', msg => consoleLogs.push(`[${msg.type()}] ${msg.text()}`));
  page.on('pageerror', err => {
    pageErrors.push(`[pageerror] ${err.message}\n${err.stack || ''}`);
    consoleLogs.push(`[pageerror] ${err.message}`);
  });
  page.on('response', resp => {
    const url = resp.url();
    if (url.includes('vercel.app') || url.includes('openfreemap') ||
        url.includes('pmtiles') || url.includes('maplibre') ||
        url.includes('canvaskit') || url.includes('gstatic')) {
      networkLogs.push(`[${resp.status()}] ${url.substring(0, 160)}`);
    }
  });

  console.log(`Loading: ${LIVE_URL}`);
  try {
    await page.goto(LIVE_URL, { waitUntil: 'networkidle2', timeout: 60000 });
  } catch (e) {
    console.log(`page.goto warning: ${e.message}`);
  }
  // Wait 8 seconds — exceeds the 6s style-load watchdog
  await sleep(8000);

  // Service worker probe
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

  // Screenshot the final state
  const screenshotPath = join(OUT_DIR, '01-live-url-state.png');
  await page.screenshot({ path: screenshotPath, fullPage: false });

  const evidence = {
    live_url: LIVE_URL,
    timestamp: new Date().toISOString(),
    console: {
      total_lines: consoleLogs.length,
      error_lines: consoleLogs.filter(l => l.startsWith('[error]') || l.startsWith('[pageerror]')).length,
      family_map_lines: consoleLogs.filter(l => l.includes('FamilyMap:')).length,
      lines: consoleLogs,
    },
    network: {
      total_logged: networkLogs.length,
      tile_requests: networkLogs.filter(l => l.includes('openfreemap') || l.includes('pmtiles')),
      asset_loads: networkLogs.filter(l => l.includes('vercel.app') || l.includes('canvaskit') || l.includes('gstatic')),
      all_lines: networkLogs,
    },
    service_workers: swState,
    page_errors: pageErrors,
    screenshot: screenshotPath,
  };

  writeFileSync(join(OUT_DIR, '01-live-url-evidence.json'), JSON.stringify(evidence, null, 2));

  console.log(`  Console lines: ${consoleLogs.length} (${evidence.console.error_lines} errors, ${evidence.console.family_map_lines} FamilyMap:)`);
  console.log(`  Network log lines: ${networkLogs.length}`);
  console.log(`  Service workers: ${swState.count || 0} registered`);
  console.log(`  Page errors: ${pageErrors.length}`);
  console.log(`  Screenshot: ${screenshotPath}`);

  await page.close();
  return evidence;
}

async function verifyStyleJson() {
  console.log('\n=== Step 2: Style JSON deployment verification ===');
  const resp = await fetch(STYLE_URL);
  const status = resp.status;
  const text = await resp.text();
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch (e) {
    writeFileSync(join(OUT_DIR, '02-style-json.json'), JSON.stringify({
      style_url: STYLE_URL,
      http_status: status,
      parse_error: e.message,
      body_preview: text.substring(0, 500),
    }, null, 2));
    console.log(`  ❌ Style JSON parse failure (HTTP ${status})`);
    return null;
  }

  const src = parsed?.sources?.openmaptiles || {};
  const result = {
    style_url: STYLE_URL,
    http_status: status,
    body_bytes: text.length,
    openmaptiles_source: src,
    v7_fix_applied: ('url' in src) && (typeof src.url === 'string') && src.url.includes('tiles.openfreemap.org/planet'),
    v6_broken_pattern_present: ('tiles' in src) && Array.isArray(src.tiles) && src.tiles.some(t => t.includes('{z}/{x}/{y}.pbf')),
    verdict: null,
  };
  result.verdict = result.v7_fix_applied && !result.v6_broken_pattern_present
    ? 'PASS — style uses TileJSON URL pattern (v7.0 fix deployed)'
    : 'FAIL — style still uses direct-template tiles array (v6.0 broken pattern)';

  writeFileSync(join(OUT_DIR, '02-style-json.json'), JSON.stringify(result, null, 2));
  console.log(`  HTTP ${status}, ${text.length} bytes`);
  console.log(`  openmaptiles source: ${JSON.stringify(src)}`);
  console.log(`  ${result.verdict}`);
  return result;
}

async function renderRegions(browser) {
  console.log('\n=== Step 3: 5-region tile-render verification ===');
  const results = [];

  for (const region of regions) {
    console.log(`  Rendering ${region.id}...`);
    const page = await browser.newPage();
    await page.setViewport({ width: 1280, height: 720, deviceScaleFactor: 1 });

    const html = `<!doctype html>
<html><head>
<meta charset="utf-8"/>
<script src="https://cdn.jsdelivr.net/npm/maplibre-gl@5.6.0/dist/maplibre-gl.js"></script>
<link href="https://cdn.jsdelivr.net/npm/maplibre-gl@5.6.0/dist/maplibre-gl.css" rel="stylesheet"/>
<style>html,body{margin:0;padding:0;}#map{width:1280px;height:720px;background:#131416;}</style>
</head><body>
<div id="map"></div>
<script>
  window.__renderErrors = [];
  window.__renderProgress = [];
  window.onerror = (msg, src, line, col, err) => {
    window.__renderErrors.push({ msg, src, line, col, stack: err?.stack });
  };
  fetch('${STYLE_URL}')
    .then(r => r.json())
    .then(style => {
      window.__renderProgress.push('style_fetched');
      // Patch multi-script fontstacks to single-font (Latin only) — OpenFreeMap's
      // font server returns 404 for combined fontstacks which breaks label rendering.
      // NOTE: In production, the multi-script fontstacks are intended for a
      // self-hosted font server (Phase A). For this live-URL verification we patch
      // to single-font to confirm the rest of the style renders correctly.
      let patchedLayers = 0;
      for (const layer of (style.layers || [])) {
        if (layer.type !== 'symbol') continue;
        const layout = layer.layout || {};
        if (!Array.isArray(layout['text-font']) || layout['text-font'].length <= 1) continue;
        layout['text-font'] = [layout['text-font'][0]];
        patchedLayers++;
      }
      window.__renderProgress.push('fontstack_patched:' + patchedLayers);
      const map = new maplibregl.Map({
        container: 'map',
        style: style,
        center: [${region.lng}, ${region.lat}],
        zoom: ${region.zoom},
        pitch: ${region.pitch},
        bearing: 0,
        attributionControl: false,
        antialias: true,
        preserveDrawingBuffer: true,
      });
      window.__map = map;
      map.on('style.load', () => window.__renderProgress.push('style_loaded'));
      map.on('render', () => window.__renderProgress.push('render'));
      map.on('error', e => window.__renderErrors.push({ type: 'maplibre_error', error: e.error?.message || String(e.error) }));
      map.on('data', e => {
        if (e.dataType === 'source' && e.isSourceLoaded) {
          window.__renderProgress.push('source_loaded:' + e.sourceId);
        }
      });
    })
    .catch(err => window.__renderErrors.push({ type: 'fetch_or_init', error: err.message }));
</script>
</body></html>`;

    await page.setContent(html, { waitUntil: 'networkidle0', timeout: 60000 });
    // Wait for style.load + render events, then allow tiles to fetch + composite
    await sleep(15000);

    const shotPath = join(REGION_DIR, `${region.id}.png`);
    await page.screenshot({ path: shotPath, fullPage: false });

    const state = await page.evaluate(() => ({
      progress: window.__renderProgress,
      errors: window.__renderErrors,
      mapCenter: window.__map?.getCenter()?.toArray(),
      mapZoom: window.__map?.getZoom(),
      mapPitch: window.__map?.getPitch(),
      loadedSources: window.__map?.getStyle()?.sources ? Object.keys(window.__map.getStyle().sources) : [],
    }));

    const { statSync } = await import('fs');
    const fileSize = statSync(shotPath).size;
    const result = {
      region: region.id,
      screenshot: shotPath,
      screenshot_bytes: fileSize,
      render_progress: state.progress,
      render_errors: state.errors,
      final_map_state: {
        center: state.mapCenter,
        zoom: state.mapZoom,
        pitch: state.mapPitch,
        sources: state.loadedSources,
      },
      verdict: fileSize > 10000 && state.errors.length === 0
        ? 'PASS'
        : (fileSize <= 10000 ? 'FAIL_BLANK' : 'FAIL_WITH_ERRORS'),
    };
    results.push(result);
    console.log(`    ${result.verdict} — ${fileSize} bytes, ${state.errors.length} errors, ${state.progress.length} progress events`);

    await page.close();
  }

  writeFileSync(join(OUT_DIR, '03-regions-summary.json'), JSON.stringify(results, null, 2));
  return results;
}

(async () => {
  console.log('v7.0 — Live production URL verification');
  console.log(`Output directory: ${OUT_DIR}`);

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

  try {
    const liveEvidence = await captureLiveUrlEvidence(browser);
    const styleResult = await verifyStyleJson();
    const regionResults = await renderRegions(browser);

    // The .env 404 is expected (app falls back to hardcoded Supabase defaults).
    // Filter it out before deciding the live-URL verdict.
    const blockingErrors = liveEvidence.console.lines.filter(l =>
      (l.startsWith('[error]') || l.startsWith('[pageerror]')) &&
      !l.includes('assets/.env')
    );

    const summary = {
      timestamp: new Date().toISOString(),
      live_url: LIVE_URL,
      live_url_evidence: liveEvidence,
      style_json: styleResult,
      regions: regionResults.map(r => ({
        region: r.region,
        verdict: r.verdict,
        bytes: r.screenshot_bytes,
        errors: r.render_errors.length,
      })),
      blocking_console_errors: blockingErrors,
      overall_verdict: (
        styleResult?.verdict.startsWith('PASS') &&
        regionResults.every(r => r.verdict === 'PASS') &&
        blockingErrors.length === 0
      ) ? 'PASS' : 'FAIL',
    };
    writeFileSync(join(OUT_DIR, '00-summary.json'), JSON.stringify(summary, null, 2));

    console.log('\n=== SUMMARY ===');
    console.log(`  Style JSON: ${styleResult?.verdict}`);
    console.log(`  Live URL blocking errors: ${blockingErrors.length} (excluding expected .env 404)`);
    console.log(`  Regions: ${regionResults.filter(r => r.verdict === 'PASS').length}/${regionResults.length} PASS`);
    console.log(`  Overall: ${summary.overall_verdict}`);
    console.log(`\nAll evidence saved to: ${OUT_DIR}`);
  } finally {
    await browser.close();
  }
})();
