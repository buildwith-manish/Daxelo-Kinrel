// scripts/v9_verify_live_render.mjs
//
// Final verification: load the LIVE production kinrel_dark_style.json
// from https://daxelo-kinrel.vercel.app/assets/assets/map_styles/kinrel_dark_style.json
// and render it with MapLibre GL JS 5.6.0 in a headless browser.
//
// Expected result: map renders with visible basemap (roads, water,
// buildings, land, labels) — NOT blank.

import puppeteer from 'puppeteer';
import fs from 'node:fs';
import path from 'node:path';

const OUT_DIR = '/home/z/my-project/download/v9-blank-investigation';
fs.mkdirSync(OUT_DIR, { recursive: true });

const LIVE_STYLE_URL = 'https://daxelo-kinrel.vercel.app/assets/assets/map_styles/kinrel_dark_style.json';

const HTML = `<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>v9 Live Render Verification</title>
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
window.__events = [];
window.__errors = [];
window.__fontReqStatuses = [];
window.__tileReqStatuses = [];

const origFetch = window.fetch;
window.fetch = async function(url, opts) {
  const r = await origFetch.call(this, url, opts);
  if (typeof url === 'string') {
    if (url.includes('openfreemap.org/fonts/')) {
      window.__fontReqStatuses.push({ url: url.substring(url.indexOf('/fonts/')), status: r.status });
    } else if (url.includes('openfreemap.org/planet/') && url.endsWith('.pbf')) {
      window.__tileReqStatuses.push({ status: r.status });
    }
  }
  return r;
};

(async () => {
  try {
    document.getElementById('status').textContent = 'fetching style...';
    const r = await fetch('${LIVE_STYLE_URL}');
    const style = await r.json();
    document.getElementById('status').textContent = 'style fetched (' + style.layers.length + ' layers)';

    const map = new maplibregl.Map({
      container: 'map',
      style: style,
      center: [72.8777, 19.0760],
      zoom: 12,
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
        message: e.error && e.error.message,
        type: e.error && e.error.type,
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
  } catch (e) {
    window.__errors.push({ message: e.message, type: e.name });
    document.getElementById('status').textContent = 'FATAL: ' + e.message;
  }
})();
</script>
</body>
</html>`;

async function main() {
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

  const page = await browser.newPage();
  await page.setViewport({ width: 1440, height: 900, deviceScaleFactor: 1 });

  const htmlPath = path.join(OUT_DIR, '_tmp_live_verify.html');
  fs.writeFileSync(htmlPath, HTML);

  console.log('[v9] Navigating to test page (fetches LIVE style from production URL)');
  await page.goto('file://' + htmlPath, { waitUntil: 'domcontentloaded', timeout: 30000 });

  console.log('[v9] Waiting 12s for map to render…');
  await new Promise((r) => setTimeout(r, 12000));

  const screenshotPath = path.join(OUT_DIR, '13_live_render_verified.png');
  await page.screenshot({ path: screenshotPath, fullPage: false });

  const diag = await page.evaluate(() => ({
    events: window.__events,
    errors: window.__errors,
    fontReqStatuses: window.__fontReqStatuses,
    fontReqCount: window.__fontReqStatuses.length,
    tileReqStatuses: window.__tileReqStatuses,
    tileReqCount: window.__tileReqStatuses.length,
    statusText: document.getElementById('status').textContent,
  }));

  const stat = fs.statSync(screenshotPath);
  fs.unlinkSync(htmlPath);

  console.log('\n[v9] === LIVE PRODUCTION RENDER RESULT ===');
  console.log('[v9] Screenshot:', screenshotPath, '(', stat.size, 'bytes )');
  console.log('[v9] Events:', diag.events);
  console.log('[v9] Errors:', diag.errors.length);
  if (diag.errors.length > 0) {
    for (const e of diag.errors.slice(0, 10)) {
      console.log('  -', e.type, ':', e.message, '| url:', e.url);
    }
  }
  console.log('[v9] Font requests:', diag.fontReqCount);
  if (diag.fontReqCount > 0) {
    const statuses = {};
    for (const r of diag.fontReqStatuses) statuses[r.status] = (statuses[r.status] || 0) + 1;
    console.log('  status breakdown:', statuses);
  }
  console.log('[v9] Tile requests:', diag.tileReqCount);
  if (diag.tileReqCount > 0) {
    const statuses = {};
    for (const r of diag.tileReqStatuses) statuses[r.status] = (statuses[r.status] || 0) + 1;
    console.log('  status breakdown:', statuses);
  }
  console.log('[v9] Status text:', diag.statusText);

  if (stat.size > 50000 && diag.errors.length === 0) {
    console.log('\n[v9] ✅ VERIFIED: Production map renders correctly (screenshot > 50KB, no errors)');
  } else if (stat.size < 15000) {
    console.log('\n[v9] ❌ STILL BLANK: Screenshot is suspiciously small (', stat.size, 'bytes )');
  } else {
    console.log('\n[v9] ⚠️ Inconclusive — examine screenshot manually');
  }

  fs.writeFileSync(
    path.join(OUT_DIR, '13_live_render_diag.json'),
    JSON.stringify({ screenshot: screenshotPath, sizeBytes: stat.size, diag }, null, 2),
  );

  await browser.close();
}

main().catch((e) => {
  console.error('[v9] FATAL:', e);
  process.exit(1);
});
