// scripts/v9_fontstack_ab_test_v2.mjs
//
// A/B test v2 — fetches style from live URL inside the page (avoids inline
// JSON escaping issues that broke v1).
//
// Tests:
//   A. Production style AS-IS (multi-script fontstacks)
//   B. Patched style — every multi-font stack collapsed to single-font

import puppeteer from 'puppeteer';
import fs from 'node:fs';
import path from 'node:path';

const OUT_DIR = '/home/z/my-project/download/v9-blank-investigation';
fs.mkdirSync(OUT_DIR, { recursive: true });

const LIVE_STYLE_URL = 'https://daxelo-kinrel.vercel.app/assets/assets/map_styles/kinrel_dark_style.json';

const HTML_TEMPLATE = (label, patchFontstacks) => `<!DOCTYPE html>
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

window.__patchFontstacks = ${patchFontstacks};

(async () => {
  try {
    document.getElementById('status').textContent = 'fetching style...';
    const r = await fetch('${LIVE_STYLE_URL}');
    const style = await r.json();
    document.getElementById('status').textContent = 'style fetched (' + style.layers.length + ' layers)';

    if (window.__patchFontstacks) {
      let patched = 0;
      for (const layer of style.layers) {
        if (layer.layout && layer.layout['text-font']) {
          const stack = layer.layout['text-font'];
          if (Array.isArray(stack) && stack.length > 1) {
            layer.layout['text-font'] = [stack[0]];
            patched++;
          }
        }
      }
      document.getElementById('status').textContent = 'patched ' + patched + ' font stacks';
    }

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
    map.on('sourcedata', (e) => {
      if (e.isSourceLoaded && window.__events.indexOf('sourcedata.' + e.sourceId) === -1) {
        window.__events.push('sourcedata.' + e.sourceId);
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

async function renderWithLabel(browser, label, patchFontstacks) {
  const page = await browser.newPage();
  await page.setViewport({ width: 1440, height: 900, deviceScaleFactor: 1 });

  // Write the HTML to a temp file and navigate to it via file:// so we don't
  // trip over setContent script-tag escaping rules.
  const htmlPath = path.join(OUT_DIR, `_tmp_${label}.html`);
  fs.writeFileSync(htmlPath, HTML_TEMPLATE(label, patchFontstacks));

  await page.goto('file://' + htmlPath, { waitUntil: 'domcontentloaded', timeout: 30000 });

  // Wait for the map to fully render
  console.log('[v9] Waiting 12s for', label, '…');
  await new Promise((r) => setTimeout(r, 12000));

  const screenshotPath = path.join(OUT_DIR, `12_${label}.png`);
  await page.screenshot({ path: screenshotPath, fullPage: false });

  const diag = await page.evaluate(() => ({
    events: window.__events,
    errors: window.__errors,
    fontReqStatuses: window.__fontReqStatuses,
    fontReqCount: window.__fontReqStatuses.length,
    tileReqStatuses: window.__tileReqStatuses,
    tileReqCount: window.__tileReqStatuses.length,
    statusText: document.getElementById('status').textContent,
    title: document.title,
  }));

  await page.close();
  fs.unlinkSync(htmlPath);

  const stat = fs.statSync(screenshotPath);
  return { label, screenshotPath, sizeBytes: stat.size, diag };
}

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

  console.log('\n[v9] === TEST A: MULTI-SCRIPT fontstacks (production AS-IS) ===');
  const resultA = await renderWithLabel(browser, 'test_a_multiscript', false);
  console.log('[v9] Test A screenshot:', resultA.sizeBytes, 'bytes');
  console.log('[v9] Test A events:', resultA.diag.events);
  console.log('[v9] Test A errors:', resultA.diag.errors);
  console.log('[v9] Test A font reqs:', resultA.diag.fontReqCount);
  console.log('[v9] Test A tile reqs:', resultA.diag.tileReqCount);
  console.log('[v9] Test A status:', resultA.diag.statusText);

  console.log('\n[v9] === TEST B: SINGLE-FONT Latin (patched) ===');
  const resultB = await renderWithLabel(browser, 'test_b_singlefont', true);
  console.log('[v9] Test B screenshot:', resultB.sizeBytes, 'bytes');
  console.log('[v9] Test B events:', resultB.diag.events);
  console.log('[v9] Test B errors:', resultB.diag.errors);
  console.log('[v9] Test B font reqs:', resultB.diag.fontReqCount);
  console.log('[v9] Test B tile reqs:', resultB.diag.tileReqCount);
  console.log('[v9] Test B status:', resultB.diag.statusText);

  console.log('\n[v9] === A/B COMPARISON ===');
  console.log('[v9] Test A (multi-script):', resultA.sizeBytes, 'bytes | events:', resultA.diag.events.length);
  console.log('[v9] Test B (single-font): ', resultB.sizeBytes, 'bytes | events:', resultB.diag.events.length);
  console.log('[v9] Ratio B/A:', (resultB.sizeBytes / resultA.sizeBytes).toFixed(2) + 'x');

  if (resultA.sizeBytes < 15000 && resultB.sizeBytes > 50000) {
    console.log('\n[v9] ✅ ROOT CAUSE CONFIRMED: multi-script fontstack causes BLANK map');
    console.log('[v9]    FIX: patch kinrel_dark_style.json to use single-font stacks');
  } else if (resultA.sizeBytes > 50000 && resultB.sizeBytes > 50000) {
    console.log('\n[v9] ⚠️ Both tests render OK — fontstack is NOT the root cause');
  } else {
    console.log('\n[v9] ⚠️ Inconclusive — examine screenshots manually');
  }

  fs.writeFileSync(
    path.join(OUT_DIR, '12_ab_test_summary.json'),
    JSON.stringify({ testA: resultA, testB: resultB }, null, 2),
  );

  await browser.close();
}

main().catch((e) => {
  console.error('[v9] FATAL:', e);
  process.exit(1);
});
