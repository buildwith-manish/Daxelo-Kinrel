// scripts/v9_fontstack_ab_test.mjs
//
// A/B test: multi-script fontstack (production) vs single-font Latin (patched)
//
// If multi-script renders BLANK and single-font renders correctly,
// we've confirmed the root cause: the production kinrel_dark_style.json
// has multi-script fontstacks that MapLibre GL JS 5.6.0 cannot render,
// causing the entire basemap to fail to draw (not just labels).

import puppeteer from 'puppeteer';
import fs from 'node:fs';
import path from 'node:path';

const OUT_DIR = '/home/z/my-project/download/v9-blank-investigation';
fs.mkdirSync(OUT_DIR, { recursive: true });

const LIVE_STYLE_URL = 'https://daxelo-kinrel.vercel.app/assets/assets/map_styles/kinrel_dark_style.json';

async function fetchStyle() {
  const r = await fetch(LIVE_STYLE_URL);
  return await r.text();
}

async function renderWithStyle(browser, label, styleText, center = [72.8777, 19.0760], zoom = 12) {
  const page = await browser.newPage();
  await page.setViewport({ width: 1440, height: 900, deviceScaleFactor: 1 });

  // Inject the style as a JSON string into the page before navigation
  await page.setContent(`<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>${label}</title>
<script src="https://cdn.jsdelivr.net/npm/maplibre-gl@5.6.0/dist/maplibre-gl.js"></script>
<link href="https://cdn.jsdelivr.net/npm/maplibre-gl@5.6.0/dist/maplibre-gl.css" rel="stylesheet" />
<style>
  html, body { margin:0; padding:0; height:100%; background:#000; }
  #map { position:absolute; top:0; left:0; right:0; bottom:0; }
  #status { position:absolute; top:8px; left:8px; right:8px; padding:8px; background:rgba(0,0,0,0.7); color:#fff; font-family:monospace; font-size:11px; border-radius:4px; pointer-events:none; z-index:10; }
</style>
</head>
<body>
<div id="map"></div>
<div id="status">init</div>
<script>
window.__styleJson = ${JSON.stringify(styleText)};
window.__events = [];
window.__errors = [];
window.__fontReqStatuses = [];
const origFetch = window.fetch;
window.fetch = async function(url, opts) {
  const r = await origFetch.call(this, url, opts);
  if (typeof url === 'string' && url.includes('openfreemap.org/fonts/')) {
    window.__fontReqStatuses.push({ url: url.substring(url.indexOf('/fonts/')), status: r.status });
  }
  return r;
};
const map = new maplibregl.Map({
  container: 'map',
  style: window.__styleJson,
  center: ${JSON.stringify(center)},
  zoom: ${zoom},
  pitch: 0,
  bearing: 0,
  hash: false,
  preserveDrawingBuffer: true,
  attributionControl: false,
});
map.on('style.load', () => {
  window.__events.push('style.load');
  document.getElementById('status').textContent = 'style.load fired';
});
map.on('error', (e) => {
  window.__errors.push({
    message: e.error?.message,
    type: e.error?.type,
    url: e.url,
  });
});
map.on('idle', () => {
  window.__events.push('idle');
  document.getElementById('status').textContent = 'idle (all tiles loaded)';
});
map.on('render', () => {
  if (!window.__firstRender) {
    window.__firstRender = Date.now();
    window.__events.push('render.first');
  }
});
</script>
</body>
</html>`, { waitUntil: 'networkidle0', timeout: 30000 });

  // Wait 12s for tiles to load
  await new Promise((r) => setTimeout(r, 12000));

  // Screenshot
  const screenshotPath = path.join(OUT_DIR, `12_${label}.png`);
  await page.screenshot({ path: screenshotPath, fullPage: false });

  // Capture diagnostics
  const diag = await page.evaluate(() => ({
    events: window.__events,
    errors: window.__errors,
    fontReqStatuses: window.__fontReqStatuses,
    statusText: document.getElementById('status').textContent,
    title: document.title,
  }));

  await page.close();

  // File size of screenshot is a proxy for "how much was rendered"
  const stat = fs.statSync(screenshotPath);

  return { label, screenshotPath, sizeBytes: stat.size, diag };
}

async function main() {
  console.log('[v9] Fetching production style:', LIVE_STYLE_URL);
  const styleText = await fetchStyle();
  console.log('[v9] Style fetched:', styleText.length, 'chars');

  const styleMulti = JSON.parse(styleText);
  const styleSingle = JSON.parse(styleText);

  // Patch single-font version: replace every multi-font stack with a single-font stack
  let patchCount = 0;
  for (const layer of styleSingle.layers) {
    if (layer.layout?.['text-font']) {
      const stack = layer.layout['text-font'];
      if (Array.isArray(stack) && stack.length > 1) {
        // Map: Noto Sans Regular|Bold|Italic → keep first entry only
        //      Noto Sans Devanagari Regular → keep, but actually first entry IS Latin
        layer.layout['text-font'] = [stack[0]];
        patchCount++;
      } else if (Array.isArray(stack) && stack.length === 1 && stack[0].includes(',')) {
        // Old-style comma-separated string (rare)
        layer.layout['text-font'] = [stack[0].split(',')[0]];
        patchCount++;
      }
    }
  }
  console.log('[v9] Patched', patchCount, 'layers to single-font stacks');

  const browser = await puppeteer.launch({
    headless: 'new',
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage',
      '--use-gl=angle',
      '--use-angle=swiftshader',
      '--enable-unsafe-swiftshader',
    ],
  });

  console.log('\n[v9] === TEST A: MULTI-SCRIPT fontstacks (production) ===');
  const resultA = await renderWithStyle(browser, 'test_a_multiscript', JSON.stringify(styleMulti));
  console.log('[v9] Test A screenshot:', resultA.screenshotPath, '(', resultA.sizeBytes, 'bytes )');
  console.log('[v9] Test A events:', resultA.diag.events);
  console.log('[v9] Test A errors:', resultA.diag.errors.length);
  console.log('[v9] Test A font req statuses:', resultA.diag.fontReqStatuses.length, 'requests');
  if (resultA.diag.fontReqStatuses.length > 0) {
    const statuses = {};
    for (const r of resultA.diag.fontReqStatuses) statuses[r.status] = (statuses[r.status] || 0) + 1;
    console.log('[v9] Test A font status breakdown:', statuses);
  }

  console.log('\n[v9] === TEST B: SINGLE-FONT Latin (patched) ===');
  const resultB = await renderWithStyle(browser, 'test_b_singlefont', JSON.stringify(styleSingle));
  console.log('[v9] Test B screenshot:', resultB.screenshotPath, '(', resultB.sizeBytes, 'bytes )');
  console.log('[v9] Test B events:', resultB.diag.events);
  console.log('[v9] Test B errors:', resultB.diag.errors.length);
  console.log('[v9] Test B font req statuses:', resultB.diag.fontReqStatuses.length, 'requests');
  if (resultB.diag.fontReqStatuses.length > 0) {
    const statuses = {};
    for (const r of resultB.diag.fontReqStatuses) statuses[r.status] = (statuses[r.status] || 0) + 1;
    console.log('[v9] Test B font status breakdown:', statuses);
  }

  // Summary
  console.log('\n[v9] === A/B COMPARISON ===');
  console.log('[v9] Test A (multi-script): ', resultA.sizeBytes, 'bytes');
  console.log('[v9] Test B (single-font):  ', resultB.sizeBytes, 'bytes');
  console.log('[v9] Ratio B/A:', (resultB.sizeBytes / resultA.sizeBytes).toFixed(2) + 'x');

  if (resultA.sizeBytes < 10000 && resultB.sizeBytes > 50000) {
    console.log('\n[v9] ✅ ROOT CAUSE CONFIRMED:');
    console.log('[v9]   Multi-script fontstack causes the basemap to render BLANK');
    console.log('[v9]   Single-font Latin stack renders the basemap correctly');
    console.log('[v9]   FIX: patch kinrel_dark_style.json to use single-font stacks');
  } else if (resultA.sizeBytes < 10000 && resultB.sizeBytes < 10000) {
    console.log('\n[v9] ⚠️ Both tests render blank — root cause is something else');
  } else if (resultA.sizeBytes > 50000 && resultB.sizeBytes > 50000) {
    console.log('\n[v9] ⚠️ Both tests render OK — multi-script fontstack is NOT the root cause');
  } else {
    console.log('\n[v9] ⚠️ Inconclusive — examine screenshots manually');
  }

  fs.writeFileSync(
    path.join(OUT_DIR, '12_ab_test_summary.json'),
    JSON.stringify({
      testA: { ...resultA, diag: resultA.diag },
      testB: { ...resultB, diag: resultB.diag },
    }, null, 2),
  );

  await browser.close();
}

main().catch((e) => {
  console.error('[v9] FATAL:', e);
  process.exit(1);
});
